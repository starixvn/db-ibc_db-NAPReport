/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductPrefix	VARCHAR(5)
	,@DepositType	TINYINT = 2
	,@Site			VARCHAR(20) = ''
AS

/*
	Created: 20200521@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pay to supplier for some products (using GMT +8)
	
	Revisions:
		- 20200521@Percy: Initiliaze SP [RedmineID: #134553]
    
	Param's Explanation:
		- @ProductPrefix: ProductPrefix on Products table
		- @DepositType:
						= 0 Credit Only
						= 1 Deposit Only
						= 2 All
		- @Site:
						= '': all site
						= '789y': 789y
*/

BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @GMTFDate DATETIME, @GMTTDate DATETIME
	SELECT  @GMTFDate = DATEADD(DAY, -1, @FromDate), @GMTTDate = DATEADD(DAY, 1, @ToDate)

	DECLARE @ProductID INT, @VendorID SMALLINT
	SELECT	@ProductID = ProductID, @VendorID = VendorID FROM dbo.Products WITH (NOLOCK) WHERE ProductPrefix = @ProductPrefix

	CREATE TABLE #tempVendorGlobalSetting (IsDeposit BIT, ChargeRate3rd DECIMAL(19, 8))
	INSERT INTO #tempVendorGlobalSetting (IsDeposit, ChargeRate3rd)
	SELECT CASE WHEN VName = '3rdCashWLShareRate' THEN 1 ELSE 0 END, NumberValue
	FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
	WHERE VendorID = @VendorID
		AND VName IN ('3rdCreditWLShareRate', '3rdCashWLShareRate')
    
	-- Region: Active licensees
	DECLARE @tmpAllParty TABLE (PartyID INT, ParentID INT, LicenseeID INT, IsDeposit BIT)
	INSERT INTO @tmpAllParty (PartyID, ParentID, LicenseeID, IsDeposit)
	SELECT PartyID, ParentID, OldRefID, IsDeposit
	FROM (
		SELECT ci.FromParty AS PartyID, ci.ToParty AS ParentID, p.OldRefID, pd.IsDeposit
			,ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE ci.ChargeType = 1
			AND p.PartyType = 1
			AND ci.ToParty IN (1, 9, 11, 98)
	) AS r
	WHERE r.RowNum = 1

	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT, LicenseeID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, ParentID, LicenseeID, IsDeposit)
	SELECT DISTINCT p.PartyID, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefID ELSE lb.LabelID END, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
		LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE p.PartyType = 1
		AND ci.ProductId = @ProductID
		AND (
			(ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty
	-- End region

	-- Region: Get charge rate
	CREATE TABLE #PartyCharge3rdInfo
	(
		LicenseeId	INT
		,IsDeposit	BIT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
	)
	INSERT INTO #PartyCharge3rdInfo (LicenseeId, IsDeposit, Rate, FromDate, ToDate)
	SELECT DISTINCT p.LicenseeId, ci.IsDeposit, ci.DI_Rate, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductPrefix, 'OA') ci
		INNER JOIN @tmpParty p ON p.ParentID = ci.PartyID
	WHERE
		(
			(@ProductID IN (11, 21) AND ci.ChargeType IN (9, 10)) -- GD & AB
			OR (@ProductID NOT IN (11, 21) AND ci.ChargeType = 1)
		)
		AND 1 = CASE WHEN @DepositType = 2 OR @DepositType = ci.IsDeposit THEN 1 ELSE 0 END
	-- End Region

	-- Region: Get Exchange
	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataGMT
	(
		rptDate			DATE
		,IsDeposit		BIT
		,CurrencyId		INT
		,PlayCurrency	INT
		,PayDaily		MONEY
	)

	CREATE TABLE #Bettype (BetType INT)
	INSERT INTO #Bettype (BetType)
	SELECT BetType FROM dbo.f_SportBettypeMatrixByProduct_Sel (@ProductID, 0)

	-- For Allbet
	CREATE TABLE #PlayCurrencySettings
	(
		SiteId          INT
		,MemberCurrency	INT
		,PlayCurrency   INT
		,FromDate       DATETIME
		,ToDate         DATETIME
	)

	DECLARE @ABCommissionRate FLOAT = 0

	IF @ProductID = 21
	BEGIN
		INSERT INTO #PlayCurrencySettings (SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate)
		SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate
		FROM OPENQUERY(DBACC, 'SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType = 211')
		
		DELETE #PlayCurrencySettings
		WHERE ToDate < @FromDate OR FromDate > @ToDate

		SELECT @ABCommissionRate = DI_Rate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'AB', 'OA')
		WHERE ChargeType = 11
	END

	INSERT INTO #tempDataGMT (rptDate, IsDeposit, CurrencyId, PlayCurrency, PayDaily)
	SELECT b.RptDate3rd, p.IsDeposit, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
		,SUM((b.Winloss + CASE WHEN p.IsDeposit = 0 AND @ProductID = 21 THEN b.ValidBetAmount * @ABCommissionRate ELSE 0 END) * ISNULL(p.Rate, v.ChargeRate3rd)) AS PayDaily
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN @tmpAllParty ap ON ap.LicenseeID = b.SiteID
		LEFT JOIN #tempVendorGlobalSetting v ON ap.IsDeposit = v.IsDeposit
		LEFT JOIN #PartyCharge3rdInfo p ON p.LicenseeID = b.SiteID AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
		INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
		LEFT JOIN #PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
	WHERE b.RptDate BETWEEN @GMTFDate AND @GMTTDate
		AND b.RptDate3rd BETWEEN @FDate AND @TDate
		AND EXISTS (SELECT 1 FROM #Bettype bt WHERE b.BetTypeId = bt.BetType)
		AND b.CurrencyID <> 20
		AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		AND (@Site = '' OR s.SiteName = @Site) 				
	GROUP BY
		b.RptDate3rd
		,p.IsDeposit
		,b.CurrencyId
		,ISNULL(pc.PlayCurrency, b.CurrencyId)

	DROP TABLE #Bettype
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PlayCurrencySettings
	DROP TABLE #tempVendorGlobalSetting

	CREATE TABLE #tempData
	(
		IsDeposit			BIT
		,rptDate			DATETIME
		,AmountDailyBased	MONEY
		,AmountDailySystem	MONEY
	)
	INSERT INTO #tempData (IsDeposit, rptDate, AmountDailyBased, AmountDailySystem)
	SELECT b.IsDeposit, b.rptDate, b.PayDaily * oe.Rate, b.PayDaily * pe.Rate
	FROM #tempDataGMT b
		INNER JOIN #ExchangeOANDA oe ON oe.ExchangeDate = b.rptDate AND oe.ExchangeID = b.CurrencyId
		INNER JOIN #ExchangeOANDA pe ON pe.ExchangeDate = b.rptDate AND pe.ExchangeID = b.PlayCurrency;
	-- End region

	DROP TABLE #ExchangeOANDA
	DROP TABLE #tempDataGMT

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	INSERT INTO #FinalResult (rptDate, PayToSupplier, CurrencyPlay)
	SELECT 'FullRange', AmountDailyBased, AmountDailySystem - AmountDailyBased
	FROM
	(
		SELECT
			SUM(CASE WHEN IsDeposit = 1 AND AmountDailyBased > 0 THEN 0 ELSE AmountDailyBased END) AS AmountDailyBased
			,SUM(CASE WHEN IsDeposit = 1 AND AmountDailySystem > 0 THEN 0 ELSE AmountDailySystem END) AS AmountDailySystem
		FROM
		(
			SELECT IsDeposit, SUM(AmountDailyBased) AS AmountDailyBased, SUM(AmountDailySystem) AS AmountDailySystem
			FROM #tempData
			GROUP BY IsDeposit
		) s
	) r

	IF @@ROWCOUNT = 0
		INSERT INTO #FinalResult (rptDate, PayToSupplier, CurrencyPlay)
		VALUES ('FullRange', 0, 0)

	;WITH CTE_rptDate AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (RptDate, PayToSupplier, CurrencyPlay)
	SELECT CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.AmountDailyBased, 0)), SUM(ISNULL(t.AmountDailySystem, 0) - ISNULL(t.AmountDailyBased, 0))
	FROM CTE_RptDate d
		LEFT JOIN #tempData t ON d.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

    DECLARE @DateList VARCHAR(200)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult
    
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +							
							'(SELECT ''' + @ProductPrefix + ''', 4, ''Pay to supplier'', PayToSupplier' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 5, ''Currency Play'', CurrencyPlay ) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'WHERE ProductCode = ''AB'' OR [Order] <> 5
					ORDER BY [Order]'

	EXEC(@SQL)
	
	DROP TABLE #FinalResult
	DROP TABLE #tempData
END
GO
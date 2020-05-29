/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_PayToSupplier]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductCodes	VARCHAR(MAX)
	,@DepositType	TINYINT = 2
	,@Site			VARCHAR(20) = ''
	,@IsOldView		BIT = 0
AS

/*
	Created: 20200521@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pay to supplier for some products (using diff GMT-4)
	
	Revisions:
		- 20200521@Percy: Initiliaze SP [RedmineID: #134553]
		- 20200529@Percy: Special members for AB [RedmineID: #134867]
    
	Param's Explanation:
		- @@ProductCodes: List of Product Code
		- @DepositType:
						= 0 Credit Only
						= 1 Deposit Only
						= 2 All
		- @Site:
						= '': all sites
						= '789y': 789y
*/

BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @GMTFDate DATETIME, @GMTTDate DATETIME
	SELECT  @GMTFDate = DATEADD(DAY, -1, @FromDate), @GMTTDate = DATEADD(DAY, 1, @ToDate)

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT, LicenseeID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, ParentID, LicenseeID, IsDeposit)
	SELECT DISTINCT p.PartyID, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefID ELSE lb.LabelID END, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.Products pro WITH (NOLOCK) ON ci.ProductID = pro.ProductID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
		LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE p.PartyType = 1
		AND ',' + @ProductCodes + ',' LIKE '%,' + pro.ProductPrefix + ',%'
		AND (
			(ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)
		AND 1 = CASE WHEN @DepositType = 2 OR @DepositType = pd.IsDeposit THEN 1 ELSE 0 END
	-- End region

	-- Region: Get charge rate
	CREATE TABLE #__PartyCharge3rdInfo
	(
		LicenseeId	INT
		,IsDeposit	BIT
		,ProductId	INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
	)
	INSERT INTO #__PartyCharge3rdInfo (LicenseeId, IsDeposit, ProductId, Rate, FromDate, ToDate)
	SELECT DISTINCT p.LicenseeId, ci.IsDeposit, ci.ProductId, ci.DI_Rate, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductCodes, 'OA') ci
		INNER JOIN @tmpParty p ON p.ParentID = ci.PartyID
	WHERE
		(
			(ci.ProductID IN (11, 21) AND ci.ChargeType IN (9, 10)) -- GD & AB
			OR (ci.ProductID NOT IN (11, 21) AND ci.ChargeType = 1)
		)
	-- End Region

	-- Region: Get Exchange
	CREATE TABLE #__ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #__ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #__tempDataGMT
	(
		rptDate			DATE
		,IsDeposit		BIT
		,ProductId		INT
		,CurrencyId		INT
		,PlayCurrency	INT
		,PayDaily		MONEY
	)

	CREATE TABLE #__Bettype (ProductId INT, BetType INT)
	INSERT INTO #__Bettype (ProductId, BetType)
	SELECT DISTINCT s.ProductId, s.BetType FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
		INNER JOIN dbo.Products p WITH (NOLOCK) ON s.ProductID = p.ProductID
	WHERE ',' + @ProductCodes + ',' LIKE '%,' + p.ProductPrefix + ',%'

	-- For Allbet
	CREATE TABLE #__PlayCurrencySettings
	(
		SiteId          INT
		,MemberCurrency	INT
		,PlayCurrency   INT
		,FromDate       DATETIME
		,ToDate         DATETIME
	)

	DECLARE @ABCommissionRate FLOAT = 0

	-- Allbet
	IF ',' + @ProductCodes + ',' LIKE '%,AB,%'
	BEGIN
		INSERT INTO #__PlayCurrencySettings (SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate)
		SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate
		FROM OPENQUERY(DBACC, 'SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType = 211')
		
		DELETE #__PlayCurrencySettings
		WHERE ToDate < @FromDate OR FromDate > @ToDate

		SELECT @ABCommissionRate = DI_Rate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'AB', 'OA')
		WHERE ChargeType = 11
	END

	INSERT INTO #__tempDataGMT (rptDate, IsDeposit, ProductID, CurrencyId, PlayCurrency, PayDaily)
	SELECT b.RptDate3rd, p.IsDeposit, p.ProductID, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
		,SUM((b.Winloss + CASE WHEN p.IsDeposit = 0 AND p.ProductID = 21 THEN b.ValidBetAmount * @ABCommissionRate ELSE 0 END) * p.Rate) AS PayDaily
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN #__Bettype bt ON b.BetTypeId = bt.BetType
		INNER JOIN #__PartyCharge3rdInfo p ON p.LicenseeID = b.SiteID AND bt.ProductId = p.ProductId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
		INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
		LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
	WHERE b.RptDate BETWEEN @GMTFDate AND @GMTTDate
		AND b.RptDate3rd BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		AND (@Site = '' OR s.SiteName = @Site)
	GROUP BY
		b.RptDate3rd
		,p.IsDeposit
		,p.ProductId
		,b.CurrencyId
		,ISNULL(pc.PlayCurrency, b.CurrencyId)

	-- Special PayToSupplier
	CREATE TABLE #__Special_PayToSupplier
	(
		rptDate			DATE
		,IsDeposit		BIT
		,ProductId		INT
		,CurrencyId		INT
		,PlayCurrency	INT
		,PayDaily		MONEY
	)

	IF @IsOldView = 0
	BEGIN
		INSERT INTO #__Special_PayToSupplier (rptDate, IsDeposit, ProductId, CurrencyId, PlayCurrency, PayDaily)
		SELECT b.RptDate3rd, p.IsDeposit, p.ProductId, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
			,SUM(b.Winloss * (1 - p.Rate)) AS PayDaily
		FROM bodb_LicenseeReport.dbo.rpt_CustomerWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #__PartyCharge3rdInfo p ON p.LicenseeID = b.SiteID AND b.ProductId = p.ProductId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
			INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
			LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
		WHERE b.RptDate BETWEEN @GMTFDate AND @GMTTDate
			AND b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY
			b.RptDate3rd
			,p.IsDeposit
			,p.ProductId
			,b.CurrencyId
			,ISNULL(pc.PlayCurrency, b.CurrencyId)

		UPDATE t
		SET t.PayDaily = t.PayDaily + s.PayDaily
		FROM #__tempDataGMT t
			INNER JOIN #__Special_PayToSupplier s
				ON t.rptDate = s.rptDate
					AND t.CurrencyId = s.CurrencyId
					AND t.ProductId = s.ProductId
					AND t.PlayCurrency = s.PlayCurrency
					AND t.IsDeposit = s.IsDeposit
	END

	DROP TABLE #__PartyCharge3rdInfo
	DROP TABLE #__PlayCurrencySettings
	DROP TABLE #__Special_PayToSupplier

	CREATE TABLE #__tempData
	(
		IsDeposit			BIT
		,ProductId			INT
		,rptDate			DATETIME
		,AmountDailyBased	MONEY
		,AmountDailySystem	MONEY
	)
	INSERT INTO #__tempData (IsDeposit, ProductId, rptDate, AmountDailyBased, AmountDailySystem)
	SELECT b.IsDeposit, b.ProductId, b.rptDate, b.PayDaily * oe.Rate, b.PayDaily * pe.Rate
	FROM #__tempDataGMT b
		INNER JOIN #__ExchangeOANDA oe ON oe.ExchangeDate = b.rptDate AND oe.ExchangeID = b.CurrencyId
		INNER JOIN #__ExchangeOANDA pe ON pe.ExchangeDate = b.rptDate AND pe.ExchangeID = b.PlayCurrency;
	-- End region

	DROP TABLE #__ExchangeOANDA
	DROP TABLE #__tempDataGMT

	CREATE TABLE #__FinalResult (ProductId INT, rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	INSERT INTO #__FinalResult (ProductId, rptDate, PayToSupplier, CurrencyPlay)
	SELECT DISTINCT ProductId, 'FullRange', 0, 0 FROM #__Bettype

	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT ProductId, @FDate AS rptDate FROM #__Bettype
		UNION ALL
		SELECT ProductId, DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #__FinalResult (ProductId, rptDate, PayToSupplier, CurrencyPlay)
	SELECT d.ProductId, CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.AmountDailyBased, 0)), SUM(ISNULL(t.AmountDailySystem, 0) - ISNULL(t.AmountDailyBased, 0))
	FROM CTE_RptDate d
		LEFT JOIN #__tempData t ON d.rptDate = t.rptDate AND d.ProductId = t.ProductId
	GROUP BY d.ProductId, CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

	SELECT p.ProductPrefix AS ProductCode, r.rptDate, r.PayToSupplier, r.CurrencyPlay
	FROM #__FinalResult r
		INNER JOIN dbo.Products p WITH (NOLOCK) ON r.ProductId = p.ProductID
	ORDER BY ProductCode, rptDate

	DROP TABLE #__Bettype
	DROP TABLE #__FinalResult
	DROP TABLE #__tempData
END
GO
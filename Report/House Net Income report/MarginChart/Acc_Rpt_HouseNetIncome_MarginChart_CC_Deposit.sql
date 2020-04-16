/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_CC_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS  
/*  
    Created:	20190819@Robert
    Task :		House month-to-date Net Income report for Card Club
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200313@Kean - Change the "Pay to supplier" formula of CC(New Bettype 1902) - #126465
		- 20200403@Percy: Integrate Xoc Dia - CC (Bettype 1903) [RedmineID: #131507]
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_CC_Deposit '20180601', '20180630'   
*/  
BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 34, @ProductPrefix VARCHAR(5) = 'CC', @VendorID SMALLINT
	SELECT	@VendorID = VendorID FROM dbo.Products WITH (NOLOCK) WHERE ProductID = @ProductID

	CREATE TABLE #tempVendorGlobalSetting (Sporttype SMALLINT, Bettype SMALLINT, ChargeRate3rd DECIMAL(19, 8))
	INSERT INTO #tempVendorGlobalSetting (Sporttype, Bettype, ChargeRate3rd)
	SELECT Sporttype, Bettype, NumberValue
	FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
	WHERE VendorID = @VendorID
		AND VName IN ('3rdCashWLShareRateTX', '3rdCashWLShareRateXD')
    
	-- Region: Active licensees
	DECLARE @tmpAllParty TABLE (PartyID INT, ParentID INT, LicenseeID INT)
	INSERT INTO @tmpAllParty (PartyID, ParentID, LicenseeID)
	SELECT PartyID, ParentID, OldRefID
	FROM (
		SELECT ci.FromParty AS PartyID, ci.ToParty AS ParentID, p.OldRefID
			,ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE ci.ChargeType = 1
			AND p.PartyType = 1
			AND pd.IsDeposit = 1
			AND ci.ToParty IN (1, 9, 11, 98)
	) AS r
	WHERE r.RowNum = 1

	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT, LicenseeID INT)
	INSERT INTO @tmpParty (PartyID, ParentID, LicenseeID)
	SELECT DISTINCT p.PartyID, ci.ToParty, p.OldRefID
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
	WHERE p.PartyType = 1
		AND pd.IsDeposit = 1
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
	CREATE TABLE #PartyChargeInfo
	(
		ChargeID	INT
		,PartyID    INT
		,LicenseeID INT
		,ParentID	INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ParentID, Rate, FromDate, ToDate)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
	WHERE ci.ChargeType = 1
		AND ci.DI_Rate > 0

	CREATE TABLE #PartyCharge3rdInfo
	(
		LicenseeID INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
	)
	INSERT INTO #PartyCharge3rdInfo (LicenseeID, Rate, FromDate, ToDate)
	SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductPrefix, 'OA') ci
		INNER JOIN #PartyChargeInfo p ON p.ParentID = ci.PartyID
	WHERE ci.ChargeType = 1
	-- End Region

	-- Region: Get Exchange
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataDW
	(
		rptDate		DATE
		,LicenseeID	INT
		,CurrencyID	INT
		,SportType	INT
		,BetType	INT
		,MemberWL	MONEY
		,HouseWL	MONEY
	)

	CREATE TABLE #Site (SiteID_DW INT, LicenseeID INT, SiteName VARCHAR(20))
	INSERT INTO #Site (SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName
	FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE isDeposit = 1

	UPDATE s
	SET s.LicenseeID = l.LicenseeID
	FROM #Site s
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName  = RTRIM(LTRIM(l.LicenseeName))

	CREATE TABLE #Bettype (BetType INT)
	INSERT INTO #Bettype (BetType)
	SELECT BetType FROM dbo.f_SportBettypeMatrixByProduct_Sel (@ProductID, 0)

	INSERT INTO #tempDataDW (rptDate, LicenseeID, CurrencyID, SportType, BetType, MemberWL, HouseWL)
	SELECT b.rptDate, s.LicenseeID, b.CurrencyID, b.SportType, b.BetType, SUM(ISNULL(b.WinlossP, 0)) AS MemberWL, SUM((b.WinlossIBC + b.CommissionS)) AS HouseWL
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN #Site s ON b.SiteID = s.SiteID_DW
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		AND EXISTS (SELECT 1 FROM #Bettype bt WITH (NOLOCK) WHERE b.BetType = bt.BetType)
	GROUP BY b.rptDate, s.LicenseeID, b.CurrencyID, b.SportType, b.BetType

	CREATE TABLE #tempData
	(
		PartyID				INT
		,rptDate			DATETIME
		,MemberWL			MONEY
		,PayToSupplier		MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #tempData (PartyID, rptDate, MemberWL, PayToSupplier, AmountToCompany)
	SELECT
		tp.PartyID
		,b.rptDate
		,SUM(ISNULL(b.MemberWL, 0) * ISNULL(oa.Rate,0))
		,SUM(ISNULL(b.MemberWL, 0) * (CASE WHEN b.Bettype IN (1902, 1903) THEN ISNULL(v.ChargeRate3rd, 0) ELSE ISNULL(rd.Rate, 0) END) * oa.Rate)
		,SUM(CASE WHEN p.LicenseeID IS NULL THEN -ISNULL(b.HouseWL, 0) ELSE -ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) END * ISNULL(e.Rate, 0))
	FROM #tempDataDW b
		INNER JOIN @tmpAllParty tp ON tp.LicenseeID = b.LicenseeID
		LEFT JOIN #PartyChargeInfo p ON p.PartyID = tp.PartyID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #PartyCharge3rdInfo rd ON rd.LicenseeID = b.LicenseeID AND b.rptDate BETWEEN rd.FromDate AND rd.ToDate
		LEFT JOIN #tempVendorGlobalSetting v ON v.Sporttype = b.SportType AND v.Bettype = b.BetType
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		LEFT JOIN #ExchangeOANDA oa ON b.rptDate = oa.ExchangeDate AND b.CurrencyId = oa.ExchangeID
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	GROUP BY tp.PartyID, b.rptDate

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyID)
    -- End region

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, SUM(PayToSupplier) AS PayToSupplier
	FROM (
		SELECT PartyId, SUM(PayToSupplier) AS PayToSupplier
		FROM #tempData
		GROUP BY PartyId
		HAVING SUM(MemberWL) <= 0
	) p

	IF @@ROWCOUNT = 0
		INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
		SELECT 'FullRange', 0, 0

	;WITH CTE_rptDate AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
	SELECT CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.AmountToCompany, 0)), SUM(ISNULL(t.PayToSupplier, 0))
	FROM CTE_RptDate d
		LEFT JOIN #tempData t ON d.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

	DECLARE @DateList VARCHAR(200)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult
    
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT  @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'
	EXEC (@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Bettype
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #Site
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	DROP TABLE #tempVendorGlobalSetting
END
GO
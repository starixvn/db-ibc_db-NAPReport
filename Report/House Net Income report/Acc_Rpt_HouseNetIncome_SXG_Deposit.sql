/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SXG_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*
	Created:	20200422@Percy
    Task:		Integrate Sexy Gaming product [RedmineID: #132792]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200422@Percy: House Net Income - Integrate Sexy Gaming product [RedmineID: #132792]

	Param's Explanation:

	EXEC Acc_Rpt_HouseNetIncome_SXG_Deposit '2020-03-01', '2020-03-31'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 45, @ProductPrefix VARCHAR(5) = 'SXG', @VendorID SMALLINT, @ChargeRate3rd DECIMAL(19, 8)
	SELECT	@VendorID = VendorID FROM dbo.Products WITH (NOLOCK) WHERE ProductID = @ProductID
	SELECT  @ChargeRate3rd = NumberValue
	FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
	WHERE VendorID = @VendorID
		AND VName = '3rdCashWLShareRate'

	SELECT  @ChargeRate3rd = ISNULL(@ChargeRate3rd, 0)

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
	-- End Region
	
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
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ParentID, Rate, Fromdate, Todate)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.Fromdate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
	WHERE ci.DI_Rate > 0

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

	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, CNY FLOAT, USD FLOAT, MYR FLOAT)
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, CNY, USD, MYR)
	SELECT ExchangeDate, ExchangeID, CompareCurrencyRate1, CompareCurrencyRate2, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailyForSpecRange(@FDate, @TDate, 'CNY', 'USD', 'MYR') -- not use USD
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataDW
	(
		rptDate		DATE
		,LicenseeID	INT
		,CurrencyID	INT
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

	INSERT INTO #tempDataDW (rptDate, LicenseeID, CurrencyID, MemberWL, HouseWL)
	SELECT b.rptDate, s.LicenseeID, b.CurrencyID, SUM(ISNULL(b.WinlossP, 0)) AS MemberWL, SUM((b.WinlossIBC + b.CommissionS)) AS HouseWL
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN #Site s ON b.SiteID = s.SiteID_DW
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		AND EXISTS (SELECT 1 FROM #Bettype bt WITH (NOLOCK) WHERE b.BetType = bt.BetType)
	GROUP BY b.rptDate, s.LicenseeID, b.CurrencyID

	CREATE TABLE #tempData
	(
		PartyID				INT
		,ParentID			INT
		,rptDate			DATETIME
		,MemberWL			MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #tempData (PartyID, ParentID, rptDate, MemberWL, AmountToCompany)
	SELECT
		tp.PartyID
		,tp.ParentID
		,b.rptDate
		,SUM(ISNULL(b.MemberWL, 0) * ISNULL(oa.Rate, 0))
		,SUM(CASE WHEN p.LicenseeID IS NULL THEN -ISNULL(b.HouseWL, 0) ELSE -ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) END * ISNULL(e.Rate, 0))
	FROM #tempDataDW b
		INNER JOIN @tmpAllParty tp ON tp.LicenseeID = b.LicenseeID
		LEFT JOIN #PartyChargeInfo p ON p.PartyID = tp.PartyID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		LEFT JOIN #ExchangeOANDA oa ON b.rptDate = oa.ExchangeDate AND b.CurrencyId = oa.ExchangeID
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	GROUP BY
		tp.PartyID
		,tp.ParentID
		,b.rptDate

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyID)
	-- End Region

	-- Region: Pay to Supplier
	DECLARE @tmpPartyGroup TABLE (ParentID INT, MemberWL MONEY)
	INSERT INTO @tmpPartyGroup (ParentID, MemberWL)
	SELECT b.ParentID, SUM(b.MemberWL)
	FROM #tempData b
	GROUP BY b.ParentID

	CREATE TABLE #DailyPayToSupplier (ParentID INT, rptDate DATE, MemberWL MONEY, PayToSupplier MONEY)
	INSERT INTO #DailyPayToSupplier (ParentID, rptDate, MemberWL, PayToSupplier)
	SELECT d.ParentID, d.rptDate, SUM(d.MemberWL), SUM(d.MemberWL * ISNULL(p.Rate, @ChargeRate3rd))
	FROM #tempData d
		INNER JOIN @tmpPartyGroup t ON t.ParentID = d.ParentID
		LEFT JOIN #PartyCharge3rdInfo p ON d.PartyID = p.PartyID AND d.rptDate BETWEEN p.FromDate AND p.ToDate
	GROUP BY d.ParentID, d.rptDate

	CREATE TABLE #FullRangePayToSupplier (ParentID INT, PayToSupplier MONEY)
	INSERT INTO #FullRangePayToSupplier (ParentID, PayToSupplier)
	SELECT ParentID, SUM(PayToSupplier)
	FROM #DailyPayToSupplier
	GROUP BY ParentID
	HAVING SUM(MemberWL) <= 0
	-- End Region

	CREATE TABLE #FeeData (PartyID INT, ProductID INT, AComm MONEY, MinFeeApplied MONEY, WLFeeApplied MONEY, AmountToCompany MONEY)
    INSERT INTO #FeeData (PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = @ProductPrefix

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', (SELECT SUM(WLFeeApplied) FROM #FeeData), (SELECT SUM(PayToSupplier) FROM #FullRangePayToSupplier)

	DECLARE @tmpDate DATETIME, @DateList VARCHAR(200)
	SELECT  @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT
			CONVERT(VARCHAR(2), @tmpDate, 106)
			,(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #tempData WHERE rptDate = @tmpDate)
			,(SELECT ISNULL(SUM(PayToSupplier), 0) FROM #DailyPayToSupplier WHERE rptDate = @tmpDate)

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT	@SQL =	'SELECT * ' + CHAR(13) +
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
	DROP TABLE #DailyPayToSupplier
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #FullRangePayToSupplier
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeInfo
	DROP TABLE #Site
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	-- End Region
END
GO
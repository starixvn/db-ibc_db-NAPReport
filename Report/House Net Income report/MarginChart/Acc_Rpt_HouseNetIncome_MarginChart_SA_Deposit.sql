/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_SA_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*
	Created:	20200324@Percy
    Task:		Integrate SA Gaming product [RedmineID: #128059]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200324@Percy: #128059 - House Net Income - Integrate SA Gaming product

	Param's Explanation:

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_SA_Deposit '2020-03-01', '2020-03-31'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @VendorID SMALLINT, @ProductID INT = 39, @ProductPrefix VARCHAR(5) = 'SA'
	SELECT  @VendorID = VendorID FROM dbo.Products WITH (NOLOCK) WHERE ProductID = @ProductID

	DECLARE @ChargeRate3rd DECIMAL(19, 8)
	SELECT  @ChargeRate3rd = NumberValue
	FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
	WHERE VName = '3rdCashWLShareRate'
		AND VendorID = @VendorID

	SELECT @ChargeRate3rd = ISNULL(@ChargeRate3rd, 0)

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT)
	INSERT INTO @tmpParty (PartyID, ParentID)
	SELECT DISTINCT ci.FromParty, ci.ToParty
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
		,ProductID  INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
		,Bettype    INT
		,ChargeType	INT
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ParentID, ProductID, Rate, Fromdate, Todate, Bettype, ChargeType)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, p.ParentID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype), ci.ChargeType
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE ci.DI_Rate > 0
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
	CREATE TABLE #TempData
	(
		PartyID				INT
		,ParentID			INT
		,rptDate			DATETIME
		,CurrencyID			INT
		,ProductID			TINYINT
		,MemberWL			MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #TempData (PartyID, ParentID, rptDate, CurrencyID, ProductID, MemberWL, AmountToCompany)
	SELECT
		p.PartyID
		,CASE WHEN p.ParentID = 98 THEN 11 ELSE p.ParentID END AS ParentID -- Group Boping & Zelianta
		,b.rptDate
		,b.CurrencyID
		,b.ProductID
		,SUM(ISNULL(b.MemberWL, 0))
		,SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate)
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		INNER JOIN #PartyChargeInfo p ON b.ProductID = p.ProductID AND p.LicenseeID = b.SiteID AND b.rptDate BETWEEN p.FromDate AND p.ToDate AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.customercategory NOT IN(27, 28)
		AND b.StatusId NOT IN (-1, 103) -- Exclude Void, Reject, Refund
		AND (
			(b.Bettype = -1 AND p.ChargeType <> 12)
			OR (b.Bettype = 3007 AND p.ChargeType = 12)
		)
	GROUP BY p.PartyID, CASE WHEN p.ParentID = 98 THEN 11 ELSE p.ParentID END, b.rptDate, b.CurrencyID, b.ProductID

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyID)
	-- End Region

	-- Region: Pay to Supplier
	DECLARE @tmpPartyGroup TABLE (ParentID INT, AmountCNY MONEY, Rate FLOAT)
	INSERT INTO @tmpPartyGroup (ParentID, AmountCNY, Rate)
	SELECT b.ParentID, SUM(-b.MemberWL * e.CNY), 0 -- Group Boping & Zelianta
	FROM #TempData b
		INNER JOIN @tmpParty t ON b.PartyId = t.PartyID
		INNER JOIN #ExchangeOANDA e ON b.CurrencyId = e.ExchangeID AND e.ExchangeDate = b.RptDate
	GROUP BY b.ParentID

	UPDATE @tmpPartyGroup
	SET Rate = CASE WHEN AmountCNY < 10000000 THEN 0.6 ELSE 0.5 END -- 10M CNY
	WHERE ParentID IN (1, 11)

	CREATE TABLE #DailyPayToSupplier (ParentID INT, rptDate DATE, MemberWLOANDA MONEY, PayToSupplier MONEY)
	INSERT INTO #DailyPayToSupplier (ParentID, rptDate, MemberWLOANDA, PayToSupplier)
	SELECT d.ParentID, d.rptDate, SUM(d.MemberWL * e.MYR), SUM(d.MemberWL * e.MYR * t.Rate)
	FROM #TempData d
		INNER JOIN @tmpPartyGroup t ON t.ParentID = d.ParentID
		INNER JOIN #ExchangeOANDA e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
	GROUP BY d.ParentID, d.rptDate

	CREATE TABLE #FullRangePayToSupplier (ParentID INT, PayToSupplier MONEY)
	INSERT INTO #FullRangePayToSupplier (ParentID, PayToSupplier)
	SELECT ParentID, SUM(PayToSupplier)
	FROM #DailyPayToSupplier
	GROUP BY ParentID
	-- End Region

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, (SELECT SUM(PayToSupplier) FROM #FullRangePayToSupplier)

	DECLARE @tmpDate DATETIME, @DateList VARCHAR(200)
	SELECT  @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT
			CONVERT(VARCHAR(2), @tmpDate, 106)
			,(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #TempData WHERE rptDate = @tmpDate)
			,(SELECT ISNULL(SUM(PayToSupplier), 0) FROM #DailyPayToSupplier WHERE rptDate = @tmpDate)

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult
	
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
	DROP TABLE #DailyPayToSupplier
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #FullRangePayToSupplier
	DROP TABLE #PartyChargeInfo
	DROP TABLE #TempData
	-- End Region
END
GO
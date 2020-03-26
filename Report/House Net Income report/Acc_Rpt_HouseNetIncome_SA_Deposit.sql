/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SA_Deposit]
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

	EXEC Acc_Rpt_HouseNetIncome_SA_Deposit '2020-03-01', '2020-03-31'
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

	CREATE TABLE #PartyCharge3rdInfo
	(
		PartyID		INT
		,ProductID	INT
		,DI_Rate	MONEY
		,Fromdate	SMALLDATETIME
		,ToDate		SMALLDATETIME
	)
	INSERT INTO #PartyCharge3rdInfo (PartyID, ProductID, DI_Rate, Fromdate, ToDate)	
	SELECT DISTINCT p.PartyID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductPrefix, 'OA') ci
		INNER JOIN @tmpParty p ON (p.PartyID = ci.PartyID OR p.ParentID = ci.PartyID)
	-- End Region
	
	-- Region: Get Exchange
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE TABLE #ExchangeOANDA (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel (@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #TempData
	(
		PartyID				INT
		,rptDate			DATETIME
		,CurrencyID			INT
		,ProductID			TINYINT
		,MemberWL			MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #TempData (PartyID, rptDate, CurrencyID, ProductID, MemberWL, AmountToCompany)
	SELECT
		p.PartyID
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
	GROUP BY p.PartyID, b.rptDate, b.CurrencyID, b.ProductID

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyID)

	CREATE TABLE #DailyPayToSupplier (ParentID INT, rptDate DATE, MemberWLOANDA MONEY, PayToSupplier MONEY)
	INSERT INTO #DailyPayToSupplier (ParentID, rptDate, MemberWLOANDA, PayToSupplier)
	SELECT t.ParentID, d.rptDate, SUM(d.MemberWL * e.Rate), SUM(d.MemberWL * e.Rate * ISNULL(p.DI_Rate, ISNULL(@ChargeRate3rd, 0)))
	FROM #TempData d
		INNER JOIN @tmpParty t ON t.PartyID = d.PartyID
		INNER JOIN #ExchangeOANDA e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		LEFT JOIN #PartyCharge3rdInfo p ON p.PartyID = d.PartyID AND d.rptDate BETWEEN p.FromDate AND p.ToDate
	GROUP BY t.ParentID, d.rptDate

	CREATE TABLE #FullRangePayToSupplier (ParentID INT, PayToSupplier MONEY)
	INSERT INTO #FullRangePayToSupplier (ParentID, PayToSupplier)
	SELECT ParentID, CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(PayToSupplier) END
	FROM #DailyPayToSupplier
	GROUP BY ParentID
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
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #FullRangePayToSupplier
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeInfo
	DROP TABLE #TempData
	-- End Region
END
GO
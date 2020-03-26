/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_I4D_Deposit]
	@FromDate    DATE
   ,@ToDate      DATE
AS

/*
	Created:	20200324@Percy
    Task:		Integrate Indo 4D product [RedmineID: #130882]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200324@Percy: #130882 - House Net Income - Integrate Indo 4D product

	Param's Explanation:

	EXEC Acc_Rpt_HouseNetIncome_I4D_Deposit '2020-03-01', '2020-03-31'
*/
BEGIN  
    SET NOCOUNT ON

    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 43, @ProductPrefix VARCHAR(5) = 'I4D'

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
		,ProductID  INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
		,Bettype    INT
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate, Bettype)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE ci.DI_Rate > 0

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
		rptDate				DATETIME
		,ProductID			TINYINT
		,AmountToCompany	MONEY
	)
	INSERT INTO #TempData (rptDate, ProductID, AmountToCompany)
	SELECT
		b.rptDate
		,b.ProductID
		,SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate)
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		INNER JOIN #PartyChargeInfo p ON b.ProductID = p.ProductID AND p.LicenseeID = b.SiteID AND b.rptDate BETWEEN p.FromDate AND p.ToDate AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.customercategory NOT IN(27, 28)
		AND b.StatusId NOT IN (-1, 103) -- Exclude Void, Reject, Refund
		AND b.Bettype = -1
	GROUP BY b.rptDate, b.ProductID
	-- End Region

	CREATE TABLE #FeeData (PartyID INT, ProductID INT, AComm MONEY, MinFeeApplied MONEY, WLFeeApplied MONEY, AmountToCompany MONEY)
    INSERT INTO #FeeData (PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = @ProductPrefix

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', ISNULL(SUM(AmountToCompany), 0), 0
	FROM #FeeData

	DECLARE @tmpDate DATETIME, @DateList VARCHAR(200)
	SELECT  @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT
			CONVERT(VARCHAR(2), @tmpDate, 106)
			,ISNULL(SUM(AmountToCompany), 0)
			,0
		FROM #TempData
		WHERE rptDate = @tmpDate

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

    -- Output data
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
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #PartyChargeInfo
	DROP TABLE #TempData
	-- End Region
END
GO
/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_HouseNetIncome_WM_Credit
	@FromDate DATE
	,@ToDate DATE 
AS
/*
	Created:	20200916@Roy
	Task : 		Get data for House Net Income report by WM Live Casino product (PayToSupplier by GTM+8)
	DB: 		DBDW.bodb_dwrs

	Revisions:
		20200916@Roy: Email/Letstalk Reports - Integrate WM Live Casino (#131593)

	Param's Explanation:

	Script:
		EXEC Acc_Rpt_HouseNetIncome_WM_Credit '20200901', '20200930'
*/
BEGIN 
	SET NOCOUNT ON

	DECLARE @FDate DATE
		,@TDate DATE
		,@ProductPrefix VARCHAR(5) = 'WM'
		,@ProductID INT = 51

	SELECT @FDate = @FromDate
		,@TDate = @ToDate

	---Region: Get exchange rate info---
	CREATE TABLE #Exchange(
		ExchangeDate DATE
		,ExchangeID INT
		,Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	OPTION(RECOMPILE)
	CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID)

	---End region---

	CREATE TABLE #FinalResult(
		RptDate VARCHAR(10)
		,HouseWL MONEY
		,ExtraPT MONEY
		,PayToSupplier MONEY)

	DECLARE @tmpDate DATE
		,@DateList VARCHAR(200) = '[FullRange]'

	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult(RptDate, HouseWL, ExtraPT, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
	FROM #FinalResult

	---Sport - Bettype Matrix---
	CREATE TABLE #SportBettypeMatrix( Bettype INT )

	INSERT INTO #SportBettypeMatrix( Bettype )
	SELECT DISTINCT BetType
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(@ProductID, 0, 0, 2, '', @ProductPrefix, 0)

	---BEGIN: GET DATA---
	CREATE TABLE #TmpHouseWL(
		rptDate DATE
		,CurrencyID INT
		,HouseWL MONEY
		,ExtraPT MONEY)

	INSERT INTO #TmpHouseWL(
		rptDate
		,HouseWL
		,ExtraPT)
	SELECT b.rptDate
		,-SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL
		,SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
		LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		AND b.BetType IN (SELECT Bettype FROM #SportBettypeMatrix )
		AND b.SiteID IN ( SELECT SiteID FROM bodb_account.dbo.tbl_site WITH(NOLOCK) WHERE isDeposit = 0 )
	GROUP BY b.rptDate
	OPTION(RECOMPILE)
	---END: GET DATA---

	---BEGIN - Calculate House Income, ExtraPT---
	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL
		,ExtraPT = f.ExtraPT + wl.ExtraPT
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON f.RptDate = CONVERT(VARCHAR(2), wl.rptDate, 106)
	
	---FullRange amount---
	INSERT INTO #FinalResult(
		RptDate
		,HouseWL
		,ExtraPT
		,PayToSupplier)
	SELECT 'FullRange'
		,SUM(f.HouseWL)
		,SUM(f.ExtraPT)
		,0
	FROM #FinalResult AS f
	---END - Calculate House Income, ExtraPT---
	
	---BEGIN - Calculate PayToSupplier (GTM+8)---
	CREATE TABLE #PayToSupplier(
		ProductCode VARCHAR(10)
		,rptDate VARCHAR(10)
		,PayToSupplier MONEY
		,CurrencyPlay MONEY)
	INSERT INTO #PayToSupplier(
		ProductCode
		,rptDate
		,PayToSupplier
		,CurrencyPlay)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier	@FromDate = @FDate
																,@ToDate = @TDate
																,@ProductCodes = @ProductPrefix
																,@DepositType = 0
																,@Site = ''
																,@IsOldView = 0

	UPDATE f
	SET f.PayToSupplier = f.PayToSupplier + p.PayToSupplier
	FROM #FinalResult f
		 INNER JOIN #PayToSupplier p ON f.rptDate = p.rptDate
	---END - Calculate PayToSupplier (GTM+8)---

	-----------------------------------------------------Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM (SELECT ProductCode, [Order], RptDate, Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
						'CROSS APPLY' + CHAR(13) +
						'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', HouseWL' + CHAR(13) +
						'UNION ALL' + CHAR(13) +
						'SELECT ''' + @ProductPrefix + ''', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
						'UNION ALL' + CHAR(13) +
						'SELECT ''' + @ProductPrefix + ''', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR RptDate in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'
	EXEC(@SQL)

	---Drop tmp table---
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #Exchange
	DROP TABLE #FinalResult
	DROP TABLE #PayToSupplier
END
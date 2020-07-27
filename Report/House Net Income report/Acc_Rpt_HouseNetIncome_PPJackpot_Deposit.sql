/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PPJackpot_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*
	Created: 20200715@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pramatic - Jackpot

	Revisions:
		- 20200715@Percy: Initialize SP [RedmineID: #137280]
*/

BEGIN
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	-- Region: Get Exchange
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataDW
	(
		rptDate				DATE
		,CurrencyID			INT
		,FullContribution	MONEY
		,JackpotPrize		MONEY
	)

	INSERT INTO #tempDataDW (rptDate, CurrencyID, FullContribution, JackpotPrize)
	SELECT b.rptDate, b.CurrencyID
		,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
		,SUM(CASE WHEN b.bettype = 4298 THEN b.WinlossP ELSE 0 END) AS JackpotPrize
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		AND b.BetType IN (4297, 4298)
	GROUP BY b.rptDate, b.CurrencyID

	CREATE TABLE #tempData
	(
		rptDate				DATETIME
		,HouseIncome		MONEY
		,FullContribution	MONEY
		,JackpotPrize		MONEY
	)
	INSERT INTO #tempData (rptDate, FullContribution, JackpotPrize)
	SELECT
		b.rptDate
		,SUM(b.FullContribution * ISNULL(e.Rate, 0))
		,SUM(b.JackpotPrize * ISNULL(e.Rate, 0))
	FROM #tempDataDW b
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
	GROUP BY b.rptDate
	-- End Region

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), FullContribution MONEY, JackpotPrize MONEY)
	INSERT INTO #FinalResult (rptDate, FullContribution, JackpotPrize)
	SELECT 'FullRange', ISNULL(SUM(FullContribution), 0), ISNULL(SUM(JackpotPrize), 0)
	FROM #tempData

	;WITH CTE_rptDate AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (RptDate, FullContribution, JackpotPrize)
	SELECT CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.FullContribution, 0)), SUM(ISNULL(t.JackpotPrize, 0))
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
							'(SELECT ''PP-JP'', 1, ''Contribution Amount'', FullContribution' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''PP-JP'', 2, ''Jackpot Prize'', JackpotPrize) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC (@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #FinalResult
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	-- End Region
END
GO
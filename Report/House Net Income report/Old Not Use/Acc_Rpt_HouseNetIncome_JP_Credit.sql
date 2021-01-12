/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_JP_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180620@Harper 
	Description: HDWL Letstalk - Implement report of RNG JP [#RedmineID: 94403]
    
    DB: DBWH/bodb_dwrs  
   
    Revisions:
		- 20180620@Harper - HDWL Letstalk - Implement report of RNG JP [#RedmineID: 94403]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_JP_Credit '2018-06-01', '2018-06-30'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate	
	-- End region

	CREATE	TABLE #TempDataJP (			
			rptDate			DATETIME,
			CurrencyId		INT,
			MegaPrize		MONEY,	
			Contribution	MONEY)

	INSERT INTO #TempDataJP (rptDate, CurrencyId, MegaPrize, Contribution)
	SELECT 		
		b.rptDate,
		b.CurrencyID,
		-SUM(CASE WHEN b.bettype IN (2199, 2399, 2999) THEN b.WinlossP ELSE 0 END * ex.Rate) AS WinningPrize,		
		SUM(CASE WHEN b.Bettype IN (2198, 2398, 2998) THEN b.WinlossIBC - b.WinlossS - b.WinlossM - b.WinlossA ELSE 0 END * ex.Rate)
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 		
		AND b.Bettype IN (2198, 2398, 2998, 2199, 2399, 2999) -- bettype of Contribution and Mega Prize
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
	GROUP BY b.rptDate, b.CurrencyID
	OPTION (RECOMPILE)

	-- Region: Result
	CREATE TABLE #FinalResult (
		RptDate			VARCHAR(10),
		MegaPrize		MONEY,	
		Contribution	MONEY
	)

	INSERT INTO #FinalResult (rptDate, MegaPrize, Contribution)
	SELECT 'FullRange', SUM(MegaPrize), SUM(Contribution)
	FROM #TempDataJP	

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, MegaPrize, Contribution)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), SUM(MegaPrize), SUM(Contribution)
		FROM #TempDataJP 
		WHERE rptDate = @tmpDate

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''JP'', 9, ''Contribution Amount'', Contribution' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''JP'', 10, ''Mega Prize'', MegaPrize) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempDataJP
	DROP TABLE #FinalResult
END
GO

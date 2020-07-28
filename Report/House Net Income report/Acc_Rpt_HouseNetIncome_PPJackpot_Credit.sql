/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

CREATE PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PPJackpot_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS

/*  	
	Created: 20200714@Ned.Le
	Description: Get data about Pragmatic Jackpot Games for House Net Income report
    
    DB: DBWH/bodb_dwrs  
   
    Revisions:
		20200714@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)
		
	Param's Explanation:   

	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_PPJackpot_Credit '20200701', '20200713'
  
*/

BEGIN
	SET NOCOUNT ON

	-- Declare variables
	DECLARE @productID INT = 32

	-- #tmpExchange
	CREATE	TABLE #tmpExchange (
		ExchangeDate		DATE,
		ExchangeID			INT,
		Rate				FLOAT
	)

	INSERT INTO #tmpExchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate >= @FromDate AND ExchangeDate <= @ToDate

	-- #tmpBettypeGroup
	CREATE TABLE #tmpBettypeGroup (
		BettypeGroupID SMALLINT,
		Bettype INT
	)

	INSERT INTO #tmpBettypeGroup (BettypeGroupID, Bettype)
	SELECT bg.BettypeGroupID, bg.Bettype
	FROM bodb_Account.dbo.BettypeGroup bg (NOLOCK)
		 LEFT JOIN bodb_Account.dbo.Product_Bettype pb (NOLOCK) ON bg.Bettype = pb.Bettype
		 LEFT JOIN bodb_Account.dbo.Bettype b (NOLOCK) ON bg.Bettype = b.typeid
	WHERE bg.BettypeGroupID IN (6, 10)
		  AND pb.ProductID = @productID
		  AND b.typenamee LIKE '%Jackpot%'

	-- #tmpDataJP
	CREATE TABLE #tmpDataJP (
			rptDate			DATETIME,
			CurrencyId		INT,
			JackpotPrize	MONEY,
			Contribution	MONEY
	)

	INSERT INTO #tmpDataJP (rptDate, CurrencyId, JackpotPrize, Contribution)
	SELECT b.rptDate rptDate,
		   b.CurrencyID CurrencyId,
		   -SUM(CASE WHEN bg.BettypeGroupID = 6 THEN b.WinlossP ELSE 0 END * ex.Rate) JackpotPrize,	
		   SUM(CASE WHEN bg.BettypeGroupID = 10 THEN b.WinlossIBC - b.WinlossS - b.WinlossM - b.WinlossA ELSE 0 END * ex.Rate) Contribution
	FROM bodb_Account.dbo.FactSiteWinloss b (NOLOCK)
		 INNER JOIN #tmpExchange ex ON b.rptdate = ex.ExchangeDate AND b.CurrencyID = ex.ExchangeID
		 INNER JOIN #tmpBettypeGroup bg ON b.BetType = bg.Bettype
	WHERE b.rptDate >= @FromDate AND b.rptDate <= @ToDate
		  AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		  AND b.SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )
	GROUP BY b.rptDate,
		     b.CurrencyID
	OPTION (RECOMPILE)

	-- #FinalResult
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		JackpotPrize		MONEY,	
		Contribution		MONEY
	)

	INSERT INTO #FinalResult (RptDate, JackpotPrize, Contribution)
	SELECT 'FullRange' RptDate,
		   SUM(JackpotPrize) JackpotPrize,
		   SUM(Contribution) Contribution
	FROM #tmpDataJP	

	DECLARE @tmpDate DATE,
		    @DateList VARCHAR(200)
	
	SELECT @tmpDate = @FromDate

	WHILE @tmpDate <= @ToDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, JackpotPrize, Contribution)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106) RptDate,
			   SUM(JackpotPrize) JackpotPrize,
			   SUM(Contribution) Contribution
		FROM #tmpDataJP 
		WHERE rptDate = @tmpDate

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	

	-- Select output
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''PP-JP'', 1, ''Contribution Amount'', Contribution' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''PP-JP'', 2, ''Jackpot Prize'', JackpotPrize) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop temp tables
	DROP TABLE #tmpExchange
	DROP TABLE #tmpBettypeGroup
	DROP TABLE #tmpDataJP
	DROP TABLE #FinalResult
END
GO

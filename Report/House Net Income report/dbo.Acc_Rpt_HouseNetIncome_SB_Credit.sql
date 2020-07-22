/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_SB_Credit 
	@FromDate    DATE
   , @ToDate      DATE
AS
/*  Created: Victor  
	Date: 2016-05-27  
    Task : House month-to-date Net Income report
    DB: DBWH/bodb_dwrs  
   
    Revisions:	
		- 20160922@Harper - #64429 - Edit status ID
		- 20190529@Dan: tuning to prevent wrong excution plan (scan all table)
		- 20200210@Robert: #126634 - DHWL Letstalk Reports - Break SB into Soccer, OS and Parlay
		- 20200202@Robert: #126634 DHWL - break OS into Basketball, E-sports, Tennis and Other Sports
		- 20200720@Kean - DHWL Email/Letstalk - Separate Saba Sports from real Sports (#137822)
	Param's Explanation:   
*/

BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- #Exchange

    CREATE TABLE #Exchange(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    INSERT INTO #Exchange(ExchangeDate
				    , ExchangeID
				    , Rate)
		 SELECT ExchangeDate
			 , Currency
			 , Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;
    -- #FinalResult

    CREATE TABLE #FinalResult(
	    RptDate               VARCHAR(10)
	  , HouseWL_Soccer        MONEY
	  , HouseWL_SabaSoccer        MONEY
	  , HouseWL_Basketball    MONEY
	  , HouseWL_SabaBasketball    MONEY
	  , HouseWL_Tennis        MONEY
	  , HouseWL_ESports       MONEY
	  , HouseWL_OS            MONEY
	  , HouseWL_Cricket       MONEY
	  , HouseWL_Parlay        MONEY
	  --
	  , ExtraPT_Soccer        MONEY
	  , ExtraPT_SabaSoccer    MONEY
	  , ExtraPT_Basketball    MONEY
	  , ExtraPT_SabaBasketball    MONEY
	  , ExtraPT_Tennis        MONEY
	  , ExtraPT_ESports       MONEY
	  , ExtraPT_OS            MONEY
	  , ExtraPT_Cricket       MONEY
	  , ExtraPT_Parlay        MONEY);

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;
	-- #tmpLeague
	CREATE TABLE #tmpLeague (LeagueID INT, LeagueGroupID INT)

	INSERT INTO #tmpLeague (LeagueID, LeagueGroupID)
	SELECT leagueID, LeagueGroupID
	FROM bodb02.dbo.League WITH(NOLOCK) 
	WHERE sporttype IN (1,2,50)
		AND LeagueGroupID IN (42,74)

    -- #SportBettypeMatrix
    CREATE TABLE #SportBettypeMatrix(
	    ProductID    INT
	  , Bettype      INT);

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype)
		 SELECT ProductID
			 , BetType
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (1, 0, 0, 2, '', 'SB', 0)
		 WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss');
    -- #TmpData

    CREATE TABLE #TmpData(
	    rptDate      DATE
	  , SportType    INT
	  , HouseWL      MONEY
	  , ExtraPT      MONEY);

    INSERT INTO #TmpData(rptDate
				   , SportType
				   , HouseWL
				   , ExtraPT)
		 SELECT b.rptDate
				 , CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END SportType
			 , ISNULL(-SUM((winlossP + winlossS + winlossM + winlossA + commissionS) * ex.rate), 0) AS HouseWL
			 , ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.Rate), 0) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN  #tmpLeague l ON l.leagueid = b.leagueID
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
		 WHERE b.rptDate BETWEEN @FDate AND @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20
			  AND SiteID IN
						 (
							SELECT siteid
							FROM bodb_Account.dbo.tbl_Site
							WHERE isDeposit = 0
						 ) -- Credit data only	    
		 GROUP BY b.rptDate
			   , CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END
				OPTION(RECOMPILE);
    -- Get DetailDaily Data & FullRange Data

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL_Soccer
							, HouseWL_SabaSoccer
							, HouseWL_Basketball
							, HouseWL_SabaBasketball
							, HouseWL_Tennis
							, HouseWL_ESports
							, HouseWL_OS
							, HouseWL_Cricket
							, HouseWL_Parlay
							--
							, ExtraPT_Soccer
							, ExtraPT_SabaSoccer
							, ExtraPT_Basketball
							, ExtraPT_SabaBasketball
							, ExtraPT_Tennis
							, ExtraPT_ESports
							, ExtraPT_OS
							, ExtraPT_Cricket
							, ExtraPT_Parlay)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 1 AND t.rptDate = @tmpDate) AS HouseWL_Soccer
				    ,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -3 AND t.rptDate = @tmpDate) AS HouseWL_SabaSoccer
					,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 2 AND t.rptDate = @tmpDate) AS HouseWL_Basketball
					,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -4 AND t.rptDate = @tmpDate) AS HouseWL_SabaBasketball
				    ,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 5 AND t.rptDate = @tmpDate ) AS HouseWL_Tennis
					,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 43 AND t.rptDate = @tmpDate) AS HouseWL_ESports
				    ,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType NOT IN (1, 2, 5, 43, -2,-3,-4,-5) AND t.rptDate = @tmpDate) AS  HouseWL_OS
					,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -5 AND t.rptDate = @tmpDate) AS  HouseWL_Cricket
					,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -2 AND t.rptDate = @tmpDate) AS  HouseWL_Parlay
					--
				    ,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = 1 AND t.rptDate = @tmpDate) AS ExtraPT_Soccer
				    ,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = -3 AND t.rptDate = @tmpDate) AS ExtraPT_SabaSoccer
					,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = 2 AND t.rptDate = @tmpDate) AS ExtraPT_Basketball
					,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = -4 AND t.rptDate = @tmpDate) AS ExtraPT_SabaBasketball
				    ,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = 5 AND t.rptDate = @tmpDate ) AS ExtraPT_Tennis
					,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = 43 AND t.rptDate = @tmpDate) AS ExtraPT_ESports
				    ,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType NOT IN (1, 2, 5, 43, -2,-3,-4,-5) AND t.rptDate = @tmpDate) AS  ExtraPT_OS
					,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = -5 AND t.rptDate = @tmpDate) AS  ExtraPT_Cricket
					,(SELECT SUM(t.ExtraPT) FROM #TmpData AS t WHERE t.SportType = -2 AND t.rptDate = @tmpDate) AS  ExtraPT_Parlay;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;

    INSERT INTO #FinalResult(RptDate
					    , HouseWL_Soccer
						, HouseWL_SabaSoccer
						, HouseWL_Basketball
						, HouseWL_SabaBasketball
						, HouseWL_Tennis
						, HouseWL_ESports
						, HouseWL_OS
						, HouseWL_Cricket
						, HouseWL_Parlay
						--
						, ExtraPT_Soccer
						, ExtraPT_SabaSoccer
						, ExtraPT_Basketball
						, ExtraPT_SabaBasketball
						, ExtraPT_Tennis
						, ExtraPT_ESports
						, ExtraPT_OS
						, ExtraPT_Cricket
						, ExtraPT_Parlay)
		 SELECT 'FullRange'
			 , SUM(HouseWL_Soccer)
			 , SUM(HouseWL_SabaSoccer)
			 , SUM(HouseWL_Basketball)
			 , SUM(HouseWL_SabaBasketball)
			 , SUM(HouseWL_Tennis)
			 , SUM(HouseWL_ESports)
			 , SUM(HouseWL_OS)
			 , SUM(HouseWL_Cricket)
			 , SUM(HouseWL_Parlay)
			 --
			 , SUM(ExtraPT_Soccer)
			 , SUM(ExtraPT_SabaSoccer)
			 , SUM(ExtraPT_Basketball)
			 , SUM(ExtraPT_SabaBasketball)
			 , SUM(ExtraPT_Tennis)
			 , SUM(ExtraPT_ESports)
			 , SUM(ExtraPT_OS)
			 , SUM(ExtraPT_Cricket)
			 , SUM(ExtraPT_Parlay)
		 FROM #FinalResult;
    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 1.1, ''House Income'', HouseWL_Soccer' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaSoccer'', 1.1, ''House Income'', HouseWL_SabaSoccer' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 1.21, ''House Income'', HouseWL_Basketball' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaBasketball'', 1.21, ''House Income'', HouseWL_SabaBasketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Tennis'', 1.22, ''House Income'', HouseWL_Tennis' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''E-Sports'', 1.23, ''House Income'', HouseWL_ESports' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''OS'', 1.24, ''House Income'', HouseWL_OS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaCricket'', 1.24, ''House Income'', HouseWL_Cricket' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Parlay'', 1.3, ''House Income'', HouseWL_Parlay' + CHAR(13)
	-- 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Soccer'', 3.1, ''Extra PT'', ExtraPT_Soccer' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaSoccer'', 3.1, ''Extra PT'', ExtraPT_SabaSoccer' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 3.21, ''Extra PT'', ExtraPT_Basketball' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaBasketball'', 3.21, ''Extra PT'', ExtraPT_SabaBasketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Tennis'', 3.22, ''Extra PT'', ExtraPT_Tennis' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''E-Sports'', 3.23, ''Extra PT'', ExtraPT_ESports' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''OS'', 3.24, ''Extra PT'', ExtraPT_OS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaCricket'', 3.24, ''Extra PT'', ExtraPT_Cricket' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Parlay'', 3.3, ''Extra PT'', ExtraPT_Parlay) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13) 
    + 'ORDER BY [Order]';

    EXEC (@SQL);
    -- Drop temp tables
    DROP TABLE #SportBettypeMatrix;
	DROP TABLE #tmpLeague;
    DROP TABLE #Exchange;
    DROP TABLE #FinalResult;
    DROP TABLE #TmpData;
END;

GO
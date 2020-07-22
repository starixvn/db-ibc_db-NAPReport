/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_ProductTurnover_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC
	DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200224@Kean - Add SG product - #123734
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200422@Kean: House Net Income - Integrate Sexy Gaming product (#132792)
		- 20200422@Kean: House Net Income - Integrate Saba.Club product (#132791)
		- 20200521@Ned.Le: Re-Integrate Fishing World product for letstalk (#134533)
		- 20200701@Kean.Nguyen - House Net Income Email/Letstalk - Change formula to Calculate Margin (#136792)
		- 20200720@Kean - DHWL Email/Letstalk - Separate Saba Sports from real Sports (#137822)
		- 20200722@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)

	EXEC Acc_Rpt_HouseNetIncome_ProductTurnover_Deposit '20180601', '20180619'
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

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
		  AND b.typenamee LIKE '%Jackpot%'

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
	    RptDate							VARCHAR(10)
	  , HouseTO_Soccer					MONEY
	  , HouseTO_SabaSoccer        MONEY
	  , HouseTO_Basketball				MONEY
	  , HouseTO_SabaBasketball    MONEY
	  , HouseTO_Tennis					MONEY
	  , HouseTO_ESports					MONEY
	  , HouseTO_OS						MONEY
	  , HouseTO_Cricket            MONEY
	  , HouseTO_Parlay					MONEY
	  --
	  , HouseTO_AGC						MONEY
	  , HouseTO_CB						MONEY
	  , HouseTO_NG						MONEY
	  , HouseTO_H5						MONEY
	  , HouseTO_VS						MONEY
	  , HouseTO_RNGKeno					MONEY
	  , HouseTO_MacauG					MONEY
	  , HouseTO_AB						MONEY
	  , HouseTO_CO						MONEY
	  , HouseTO_GD						MONEY
	  , HouseTO_LT						MONEY
	  , HouseTO_EX						MONEY
	  , HouseTO_VS2						MONEY
	  , HouseTO_1RNG					MONEY
	  , HouseTO_1RNG_JP_MegaPrize       MONEY
	  , HouseTO_1RNG_JP_Contribution    MONEY
	  , HouseTO_PP						MONEY
	  , HouseTO_PP_JP_MegaPrize			MONEY
	  , HouseTO_PP_JP_Contribution		MONEY
	  , HouseTO_CC						MONEY
	  , HouseTO_SP						MONEY
	  , HouseTO_SG						MONEY
	  , HouseTO_VG						MONEY
	  , HouseTO_SA						MONEY
	  , HouseTO_I4D						MONEY
	  , HouseTO_TG						MONEY
	  , HouseTO_SBC						MONEY
	  , HouseTO_SXG						MONEY
	  , HouseTO_FW						MONEY);

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

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype)
		SELECT DISTINCT ProductID
			 , BetType
		FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
		WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
		AND ProductID IN (1,11, 15, 34, 25, 31, 28, 32, 37, 27, 21, 6, 12, 3, 8, 22, 5, 36, 38, 39, 43, 40, 42, 45, 24)
		-- SB, AG casino,Colossus Bets,Card Club,Cash Out,Exchange,Lottery,Pragmatic,Saba Promotion,Betradar Virtual Sports(VS2),
		-- AllBet,RNG Casino,Gold Deluxe,Number Game(NG & HP5),RNG Keno,Macau Games,Virtual Sports, Spade Gaming, Virtual Games 
		-- Fishing World

		 CREATE TABLE #TmpData(
				rptDate      DATE
				, ProductID INT
				, SportType    INT
				, BetType    INT
				, HouseTO      MONEY);
	    
    INSERT INTO #TmpData(rptDate
				   , ProductID
				   , SportType
				   , BetType
				   , HouseTO)
		 SELECT b.rptDate
			 , sb.ProductID
			 , CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END SportType
			 , b.BetType
			 , SUM(CASE WHEN TurnoverIBC = 0 THEN 0
						ELSE TurnoverIBC - ExtraTO
					 END * CASE
							 WHEN VarianceVR > 0 THEN VarianceVR + 1
							 ELSE 1
						  END * ex.Rate * (CASE WHEN b.TicketStatus in (12,13) THEN 0.5 ELSE 1 END)) AS HouseTO
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN  #tmpLeague l ON l.leagueid = b.leagueID
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14, 3)
			  AND b.CurrencyID <> 20
			  AND SiteID IN
							(
							    SELECT SiteID
							    FROM bodb_Account.dbo.tbl_Site
							    WHERE isDeposit = 1
							)-- Deposit data only  
		 GROUP BY b.rptDate
			    , sb.ProductID
				, CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END
				, b.BetType OPTION(RECOMPILE);
		
		-- Get DetailDaily Data & FullRange Data

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  , HouseTO_Soccer, HouseTO_SabaSoccer
						  , HouseTO_Basketball, HouseTO_SabaBasketball
						  , HouseTO_Tennis, HouseTO_ESports
						  , HouseTO_OS, HouseTO_Cricket, HouseTO_Parlay
						  , HouseTO_AGC
						  , HouseTO_CB 
						  ,	HouseTO_NG        
						  , HouseTO_H5        
						  , HouseTO_VS        
						  , HouseTO_RNGKeno        
						  , HouseTO_MacauG        
						  , HouseTO_AB
						  , HouseTO_CO
						  , HouseTO_GD        
						  , HouseTO_LT
						  , HouseTO_EX        
						  , HouseTO_VS2        
						  , HouseTO_1RNG
						  , HouseTO_1RNG_JP_MegaPrize
						  , HouseTO_1RNG_JP_Contribution        
						  , HouseTO_PP
						  , HouseTO_PP_JP_MegaPrize
						  , HouseTO_PP_JP_Contribution
						  , HouseTO_CC
						  , HouseTO_SP
						  , HouseTO_SG
						  , HouseTO_VG
						  , HouseTO_SA        
						  , HouseTO_I4D
						  , HouseTO_TG
						  , HouseTO_SBC
						  , HouseTO_SXG
						  , HouseTO_FW
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	-- BEGIN SPORTBOOK
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 1 AND t.rptDate = @tmpDate) AS HouseTO_Soccer
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = -3 AND t.rptDate = @tmpDate) AS HouseTO_SabaSoccer
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 2 AND t.rptDate = @tmpDate) AS HouseTO_Basketball
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = -4 AND t.rptDate = @tmpDate) AS HouseTO_SabaBasketball
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 5 AND t.rptDate = @tmpDate ) AS HouseTO_Tennis
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 43 AND t.rptDate = @tmpDate) AS HouseTO_ESports
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 1 AND t.SportType NOT IN (1, 2, 5, 43, -2,-3,-4,-5) AND t.rptDate = @tmpDate) AS  HouseTO_OS
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = -5 AND t.rptDate = @tmpDate) AS  HouseTO_Cricket
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = -2 AND t.rptDate = @tmpDate) AS  HouseTO_Parlay
	-- END SPORTBOOK
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 11 AND t.rptDate = @tmpDate) AS  HouseTO_AGC
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 15 AND t.rptDate = @tmpDate) AS  HouseTO_CB
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  HouseTO_NG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS  HouseTO_H5
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate) AS  HouseTO_VS
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate) AS  HouseTO_RNGKeno
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate) AS  HouseTO_MacauG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 21 AND t.rptDate = @tmpDate) AS  HouseTO_AB
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 25 AND t.rptDate = @tmpDate) AS  HouseTO_CO
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 12 AND t.rptDate = @tmpDate) AS  HouseTO_GD
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  HouseTO_LT
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 31 AND t.rptDate = @tmpDate) AS  HouseTO_EX
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  HouseTO_VS2
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 6 AND t.rptDate = @tmpDate) AS  HouseTO_1RNG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.BetType IN (2199, 2399, 2999) AND t.rptDate = @tmpDate) AS HouseTO_1RNG_JP_MegaPrize
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.BetType IN (2198, 2398, 2998) AND t.rptDate = @tmpDate) AS HouseTO_1RNG_JP_Contribution
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 32 AND t.rptDate = @tmpDate) AS  HouseTO_PP
	,(SELECT SUM(t.HouseTO)
	  FROM #TmpData AS t
	       INNER JOIN #tmpBettypeGroup AS bg ON t.BetType = bg.Bettype
	  WHERE t.rptDate = @tmpDate
		    AND t.ProductID = 32
	        AND bg.BettypeGroupID = 6) AS  HouseTO_PP_JP_MegaPrize
	,(SELECT SUM(t.HouseTO)
	  FROM #TmpData AS t
	       INNER JOIN #tmpBettypeGroup AS bg ON t.BetType = bg.Bettype
	  WHERE t.rptDate = @tmpDate
		    AND t.ProductID = 32
	        AND bg.BettypeGroupID = 10) AS  HouseTO_PP_JP_Contribution
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 34 AND t.rptDate = @tmpDate) AS  HouseTO_CC
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 37 AND t.rptDate = @tmpDate) AS  HouseTO_SP
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 36 AND t.rptDate = @tmpDate) AS  HouseTO_SG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 38 AND t.rptDate = @tmpDate) AS  HouseTO_VG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 39 AND t.rptDate = @tmpDate) AS  HouseTO_SA
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 43 AND t.rptDate = @tmpDate) AS  HouseTO_I4D
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 40 AND t.rptDate = @tmpDate) AS  HouseTO_TG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 42 AND t.rptDate = @tmpDate) AS  HouseTO_SBC
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 45 AND t.rptDate = @tmpDate) AS  HouseTO_SXG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 24 AND t.rptDate = @tmpDate) AS  HouseTO_FW
	;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
		
INSERT INTO #FinalResult(RptDate
					, HouseTO_Soccer, HouseTO_SabaSoccer
					, HouseTO_Basketball, HouseTO_SabaBasketball
					, HouseTO_Tennis, HouseTO_ESports
					, HouseTO_OS, HouseTO_Cricket, HouseTO_Parlay
					, HouseTO_AGC
					, HouseTO_CB
					, HouseTO_NG        
					, HouseTO_H5        
					, HouseTO_VS        
					, HouseTO_RNGKeno     
					, HouseTO_MacauG        
					, HouseTO_AB
					, HouseTO_CO
					, HouseTO_GD        
					, HouseTO_LT
					, HouseTO_EX        
					, HouseTO_VS2        
					, HouseTO_1RNG
					, HouseTO_1RNG_JP_MegaPrize
					, HouseTO_1RNG_JP_Contribution        
					, HouseTO_PP
					, HouseTO_PP_JP_MegaPrize
					, HouseTO_PP_JP_Contribution
					, HouseTO_CC
					, HouseTO_SP
					, HouseTO_SG
					, HouseTO_VG
					, HouseTO_SA        
					, HouseTO_I4D
					, HouseTO_TG
					, HouseTO_SBC
					, HouseTO_SXG
					, HouseTO_FW)
		 SELECT 'FullRange'
			 , SUM(HouseTO_Soccer)
			 , SUM(HouseTO_SabaSoccer)
			 , SUM(HouseTO_Basketball)
			 , SUM(HouseTO_SabaBasketball)
			 , SUM(HouseTO_Tennis)
			 , SUM(HouseTO_ESports)
			 , SUM(HouseTO_OS)
			 , SUM(HouseTO_Cricket)
			 , SUM(HouseTO_Parlay)
			 --
			 , SUM(HouseTO_AGC)
			 , SUM(HouseTO_CB)
			 , SUM(HouseTO_NG)        
			 , SUM(HouseTO_H5)        
			 , SUM(HouseTO_VS)        
			 , SUM(HouseTO_RNGKeno)       
			 , SUM(HouseTO_MacauG)        
			, SUM(HouseTO_AB)
			, SUM(HouseTO_CO)
			, SUM(HouseTO_GD)        
			, SUM(HouseTO_LT)
			, SUM(HouseTO_EX)        
			, SUM(HouseTO_VS2)        
			, SUM(HouseTO_1RNG)
			, SUM(HouseTO_1RNG_JP_MegaPrize)
			, SUM(HouseTO_1RNG_JP_Contribution)        
			, SUM(HouseTO_PP)
			, SUM(HouseTO_PP_JP_MegaPrize)
			, SUM(HouseTO_PP_JP_Contribution)
			, SUM(HouseTO_CC)
			, SUM(HouseTO_SP)
			, SUM(HouseTO_SG)
			, SUM(HouseTO_VG)
			, SUM(HouseTO_SA)
			, SUM(HouseTO_I4D)
			, SUM(HouseTO_TG)
			, SUM(HouseTO_SBC)
			, SUM(HouseTO_SXG)
			, SUM(HouseTO_FW)
		 FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 1, ''House TurnOver'', HouseTO_Soccer' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaSoccer'', 1, ''House TurnOver'', HouseTO_SabaSoccer' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 2, ''House TurnOver'', HouseTO_Basketball' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaBasketball'', 2, ''House TurnOver'', HouseTO_SabaBasketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 2, ''House TurnOver'', HouseTO_Basketball' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaBasketball'', 2, ''House TurnOver'', HouseTO_SabaBasketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Tennis'', 3, ''House TurnOver'', HouseTO_Tennis' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''E-Sports'', 4, ''House TurnOver'', HouseTO_ESports' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''OS'', 5, ''House TurnOver'', HouseTO_OS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaCricket'', 5, ''House TurnOver'', HouseTO_Cricket' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''Parlay'', 6, ''House TurnOver'', HouseTO_Parlay' + CHAR(13)
	--
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''AGC'', 7, ''House TurnOver'', HouseTO_AGC' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CB'', 8, ''House TurnOver'', HouseTO_CB' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG'', 9, ''House TurnOver'', HouseTO_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 10, ''House TurnOver'', HouseTO_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 11, ''House TurnOver'', HouseTO_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGKeno'', 12, ''House TurnOver'', HouseTO_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''MacauG'', 13, ''House TurnOver'', HouseTO_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''AB'', 14, ''House TurnOver'', HouseTO_AB' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CO'', 15, ''House TurnOver'', HouseTO_CO' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''GD'', 16, ''House TurnOver'', HouseTO_GD' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 17, ''House TurnOver'', HouseTO_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 18, ''House TurnOver'', HouseTO_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 19, ''House TurnOver'', HouseTO_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG'', 20, ''House TurnOver'', HouseTO_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 21, ''House TurnOver'', HouseTO_1RNG_JP_MegaPrize' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 22, ''House TurnOver'', HouseTO_1RNG_JP_Contribution' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP'', 23, ''House TurnOver'', HouseTO_PP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP-JP'', 24, ''House TurnOver'', HouseTO_PP_JP_MegaPrize' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP-JP'', 25, ''House TurnOver'', HouseTO_PP_JP_Contribution' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 26, ''House TurnOver'', HouseTO_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SP'', 27, ''House TurnOver'', HouseTO_SP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SG'', 28, ''House TurnOver'', HouseTO_SG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VG'', 29, ''House TurnOver'', HouseTO_VG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SAG'', 30, ''House TurnOver'', HouseTO_SA' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''I4D'', 31, ''House TurnOver'', HouseTO_I4D' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''TG'', 32, ''House TurnOver'', HouseTO_TG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SBC'', 33, ''House TurnOver'', HouseTO_SBC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SXG'', 34, ''House TurnOver'', HouseTO_SXG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''FW'', 35, ''House TurnOver'', HouseTO_FW) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13) 
    + 'ORDER BY [Order]';

    EXEC (@SQL);
	
    -- Drop temp tables
	DROP TABLE #tmpBettypeGroup;
    DROP TABLE #SportBettypeMatrix;
	DROP TABLE #tmpLeague;
    DROP TABLE #Exchange;
    DROP TABLE #FinalResult;
    DROP TABLE #TmpData;

END
GO

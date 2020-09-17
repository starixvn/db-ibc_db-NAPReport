/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Product_BySite]
	@FromDate DATE,
	@ToDate	DATE,
	@DepositType BIT = 0,
	@Site       VARCHAR(20) = ''
AS  
/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200224@Kean - Add SG product - #123734
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200410@Kean - Email/Letstalk Reports - Integrate BBIN product [#131364]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200423@Kean - Email/Letstalk Reports - Integrate IBCBet Live Casino product (#130690)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO ION Live Casino (#132331)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO RNG War (#132019)
		- 20200521@Ned.Le - Re-Integrate Fishing World product for letstalk (#134533)
		- 20200720@Kean - DHWL Email/Letstalk - Separate Saba Sports from real Sports (#137822)
		- 20200722@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)
		- 20200813@Kean - DHWL Email/Letstalk - Change Product Name and Margin Report Format. (#139537)
		- 20200811@Kean - Email/Letstalk Reports - Integrate PG Soft (#137764)
		- 20200916@Roy: Email/Letstalk Reports - Integrate Joker Gaming (#131602)
		- 20200916@Roy: Email/Letstalk Reports - Integrate WM Live Casino (#131593)
		- 20200529@Ned.Le: Letstalk Reports - Saba - Treat Saba Futsal as Saba Soccer (#142264)
	
	Param's Explanation:   
	- DepositType  
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_Product_BySite '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_Product_BySite '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_Product_BySite '20180601', '20180619', 1, '789Y' -- 789Y site of Credit   
  
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
	DECLARE @SiteCN88    INT;

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88';

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
	  , HouseWL_Soccer					MONEY
	  , HouseWL_SabaSoccer        		MONEY
	  , HouseWL_Basketball				MONEY
	  , HouseWL_SabaBasketball    		MONEY
	  , HouseWL_Tennis					MONEY
	  , HouseWL_ESports					MONEY
	  , HouseWL_OS						MONEY
	  , HouseWL_Cricket            		MONEY
	  , HouseWL_Parlay					MONEY
	  , HouseWL_NG						MONEY
	  , HouseWL_H5						MONEY
	  , HouseWL_VS						MONEY
	  , HouseWL_RNGKeno					MONEY
	  , HouseWL_NG2						MONEY
	  , HouseWL_MacauG					MONEY
	  , HouseWL_AB						MONEY
	  , HouseWL_GD						MONEY
	  , HouseWL_LT						MONEY
	  , HouseWL_EX						MONEY
	  , HouseWL_VS2						MONEY
	  , HouseWL_1RNG					MONEY
	  , HouseWL_1RNG_JP_MegaPrize       MONEY
	  , HouseWL_1RNG_JP_Contribution    MONEY
	  , HouseWL_PP						MONEY
	  , HouseWL_PP_JP_MegaPrize			MONEY
	  , HouseWL_PP_JP_Contribution      MONEY
	  , HouseWL_CC						MONEY
	  , HouseWL_SP						MONEY
	  , HouseWL_SG						MONEY
	  , HouseWL_VG						MONEY
	  , HouseWL_SA						MONEY
	  , HouseWL_SBC						MONEY
	  , HouseWL_SXG						MONEY
	  , HouseWL_BBIN					MONEY
	  , HouseWL_TG						MONEY
	  , HouseWL_IBCLC					MONEY
	  , HouseWL_ION						MONEY
	  , HouseWL_RNGW					MONEY
	  , HouseWL_FW						MONEY
	  , HouseWL_PGS						MONEY
	  , HouseWL_JK						MONEY
	  , HouseWL_WM						MONEY);

	  DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;

	-- #tmpLeague
	CREATE TABLE #tmpLeague (LeagueID INT, LeagueGroupID INT)

	INSERT INTO #tmpLeague (LeagueID, LeagueGroupID)
	SELECT leagueID, LeagueGroupID
	FROM bodb02.dbo.League WITH(NOLOCK) 
	WHERE sporttype IN (1,2,50)
		AND LeagueGroupID IN (42,74,108)

    -- #SportBettypeMatrix
    CREATE TABLE #SportBettypeMatrix(
	    ProductID    INT
		, Bettype      INT);

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype)
	SELECT DISTINCT ProductID, BetType
	FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
		  AND ProductID IN (1, 3, 5, 8, 23, 22, 21, 12, 28, 27, 6, 32, 34, 36,38,39,42,45,47, 40, 46, 52, 50, 24, 55, 56, 51)

	CREATE TABLE #TmpData(
			rptDate      DATE
			, ProductID INT
			, SportType    INT
			, BetType    INT
			, HouseWL      MONEY
			, WinningPrize MONEY
			, Contribution MONEY);
	    
    INSERT INTO #TmpData(rptDate
				   , ProductID
				   , SportType
				   , BetType
				   , HouseWL
				   , WinningPrize
				   , Contribution)
		 SELECT b.rptDate
			 , sb.ProductID
			 , CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74,108) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END SportType
			 , b.BetType
			 , ISNULL(-SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate), 0) AS  HouseWL
			 , -SUM(CASE WHEN bg.BettypeGroupID = 6 THEN b.WinlossP ELSE 0 END * ex.Rate) AS WinningPrize		
			 , SUM(CASE WHEN bg.BettypeGroupID = 10 THEN b.WinlossIBC - b.WinlossS - b.WinlossM - b.WinlossA ELSE 0 END * ex.Rate) AS Contribution
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN  #tmpLeague l ON l.leagueid = b.leagueID
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
			LEFT JOIN #tmpBettypeGroup bg ON b.BetType = bg.Bettype
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20
			  AND SiteID IN
						 (
							SELECT siteid
							FROM bodb_Account.dbo.tbl_Site (NOLOCK)
							WHERE isDeposit = @DepositType
							AND (@Site = '' OR [site] = @Site)
							AND siteid <> @SiteCN88
						 )    
		 GROUP BY b.rptDate
			    , sb.ProductID
				, CASE WHEN b.BetType IN (9, 29) THEN -2
					WHEN l.leagueid IS NOT NULL AND b.SportType = 1 AND l.LeagueGroupID IN (42,74,108) THEN -3  -- Saba Soccer
					WHEN l.leagueid IS NOT NULL AND b.SportType = 2 AND l.LeagueGroupID IN (42) THEN -4  -- Saba Basketball
					WHEN l.leagueid IS NOT NULL AND b.SportType = 50 AND l.LeagueGroupID IN (42) THEN -5  -- Saba Cricket 
					ELSE b.SportType END
				, b.BetType OPTION(RECOMPILE);
		
		-- Get DetailDaily Data & FullRange Data

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  , HouseWL_Soccer, HouseWL_SabaSoccer
						  , HouseWL_Basketball, HouseWL_SabaBasketball 
						  , HouseWL_Tennis, HouseWL_ESports
						  , HouseWL_OS, HouseWL_Cricket, HouseWL_Parlay
						  ,	HouseWL_NG        
						  , HouseWL_H5        
						  , HouseWL_VS        
						  , HouseWL_RNGKeno        
						  , HouseWL_NG2        
						  , HouseWL_MacauG        
						  , HouseWL_AB
						  , HouseWL_GD        
						  , HouseWL_LT
						  , HouseWL_EX        
						  , HouseWL_VS2        
						  , HouseWL_1RNG
						  , HouseWL_1RNG_JP_MegaPrize
						  , HouseWL_1RNG_JP_Contribution        
						  , HouseWL_PP
						  , HouseWL_PP_JP_MegaPrize
						  , HouseWL_PP_JP_Contribution
						  , HouseWL_CC
						  , HouseWL_SP
						  , HouseWL_SG
						  , HouseWL_VG
						  , HouseWL_SA        
						  , HouseWL_SBC        
						  , HouseWL_SXG
						  , HouseWL_BBIN
						  , HouseWL_TG
						  , HouseWL_IBCLC
						  , HouseWL_ION
						  , HouseWL_RNGW
						  , HouseWL_FW
						  , HouseWL_PGS
						  , HouseWL_JK
						  , HouseWL_WM
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	-- BEGIN SPORTBOOK
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 1 AND t.rptDate = @tmpDate) AS HouseWL_Soccer
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -3 AND t.rptDate = @tmpDate) AS HouseWL_SabaSoccer
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 2 AND t.rptDate = @tmpDate) AS HouseWL_Basketball
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -4 AND t.rptDate = @tmpDate) AS HouseWL_SabaBasketball
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 5 AND t.rptDate = @tmpDate ) AS HouseWL_Tennis
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = 43 AND t.rptDate = @tmpDate) AS HouseWL_ESports
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 1 AND t.SportType NOT IN (1, 2, 5, 43, -2,-3,-4,-5) AND t.rptDate = @tmpDate) AS  HouseWL_OS
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -5 AND t.rptDate = @tmpDate) AS  HouseWL_Cricket
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.SportType = -2 AND t.rptDate = @tmpDate) AS  HouseWL_Parlay
	-- END SPORTBOOK
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  HouseWL_NG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS  HouseWL_H5
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate) AS  HouseWL_VS
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate) AS  HouseWL_RNGKeno
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 23 AND t.rptDate = @tmpDate) AS  HouseWL_NG2
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate) AS  HouseWL_MacauG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 21 AND t.rptDate = @tmpDate) AS  HouseWL_AB
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 12 AND t.rptDate = @tmpDate) AS  HouseWL_GD
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  HouseWL_LT
	, 0 HouseWL_EX
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  HouseWL_VS2
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 6 AND t.rptDate = @tmpDate) AS  HouseWL_1RNG
	,(SELECT SUM(t.WinningPrize) FROM #TmpData AS t WHERE t.BetType IN (2199, 2399, 2999) AND t.rptDate = @tmpDate) AS HouseWL_1RNG_JP_MegaPrize
	,(SELECT SUM(t.Contribution) FROM #TmpData AS t WHERE t.BetType IN (2198, 2398, 2998) AND t.rptDate = @tmpDate) AS HouseWL_1RNG_JP_Contribution
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 32 AND t.rptDate = @tmpDate) AS  HouseWL_PP
	,(SELECT SUM(t.WinningPrize)
	  FROM #TmpData AS t
		   INNER JOIN #tmpBettypeGroup AS bg ON t.BetType = bg.Bettype
	  WHERE t.rptDate = @tmpDate
		    AND t.ProductID = 32
	        AND bg.BettypeGroupID = 6) AS HouseWL_PP_JP_MegaPrize
	,(SELECT SUM(t.Contribution)
	  FROM #TmpData AS t
		   INNER JOIN #tmpBettypeGroup AS bg ON t.BetType = bg.Bettype
	  WHERE t.rptDate = @tmpDate
		    AND t.ProductID = 32
	        AND bg.BettypeGroupID = 10) AS HouseWL_PP_JP_Contribution
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 34 AND t.rptDate = @tmpDate) AS  HouseWL_CC
	, 0 HouseWL_SP
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 36 AND t.rptDate = @tmpDate) AS  HouseWL_SG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 38 AND t.rptDate = @tmpDate) AS  HouseWL_VG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 39 AND t.rptDate = @tmpDate) AS  HouseWL_SA
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 42 AND t.rptDate = @tmpDate) AS  HouseWL_SBC
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 45 AND t.rptDate = @tmpDate) AS  HouseWL_SXG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 47 AND t.rptDate = @tmpDate) AS  HouseWL_BBIN
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 40 AND t.rptDate = @tmpDate) AS  HouseWL_TG
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 46 AND t.rptDate = @tmpDate) AS  HouseWL_IBCLC
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 52 AND t.rptDate = @tmpDate) AS  HouseWL_ION
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 50 AND t.rptDate = @tmpDate) AS  HouseWL_RNGW
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 24 AND t.rptDate = @tmpDate) AS  HouseWL_FW
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 55 AND t.rptDate = @tmpDate) AS  HouseWL_PGS
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 56 AND t.rptDate = @tmpDate) AS  HouseWL_JK
	,(SELECT SUM(t.HouseWL) FROM #TmpData AS t WHERE t.ProductID = 51 AND t.rptDate = @tmpDate) AS  HouseWL_WM;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
		
INSERT INTO #FinalResult(RptDate
					, HouseWL_Soccer, HouseWL_SabaSoccer
					, HouseWL_Basketball, HouseWL_SabaBasketball
					, HouseWL_Tennis, HouseWL_ESports
					, HouseWL_OS, HouseWL_Cricket, HouseWL_Parlay
					, HouseWL_NG        
					, HouseWL_H5        
					, HouseWL_VS        
					, HouseWL_RNGKeno        
					, HouseWL_NG2        
					, HouseWL_MacauG        
					, HouseWL_AB
					, HouseWL_GD        
					, HouseWL_LT        
					, HouseWL_EX        
					, HouseWL_VS2        
					, HouseWL_1RNG
					, HouseWL_1RNG_JP_MegaPrize
					, HouseWL_1RNG_JP_Contribution        
					, HouseWL_PP
					, HouseWL_PP_JP_MegaPrize
				    , HouseWL_PP_JP_Contribution
					, HouseWL_CC
					, HouseWL_SP
					, HouseWL_SG
					, HouseWL_VG
					, HouseWL_SA        
					, HouseWL_SBC        
					, HouseWL_SXG
					, HouseWL_BBIN
					, HouseWL_TG
					, HouseWL_IBCLC
					, HouseWL_ION
					, HouseWL_RNGW
					, HouseWL_FW
					, HouseWL_PGS
					, HouseWL_JK
					, HouseWL_WM)
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
			, SUM(HouseWL_NG)        
			, SUM(HouseWL_H5)        
			, SUM(HouseWL_VS)        
			, SUM(HouseWL_RNGKeno)        
			, SUM(HouseWL_NG2)        
			, SUM(HouseWL_MacauG)        
			, SUM(HouseWL_AB)
			, SUM(HouseWL_GD)        
			, SUM(HouseWL_LT)
			, SUM(HouseWL_EX)        
			, SUM(HouseWL_VS2)        
			, SUM(HouseWL_1RNG)
			, SUM(HouseWL_1RNG_JP_MegaPrize)
			, SUM(HouseWL_1RNG_JP_Contribution)        
			, SUM(HouseWL_PP)
			, SUM(HouseWL_PP_JP_MegaPrize)
			, SUM(HouseWL_PP_JP_Contribution)
			, SUM(HouseWL_CC)
			, SUM(HouseWL_SP)
			, SUM(HouseWL_SG)
			, SUM(HouseWL_VG)
			, SUM(HouseWL_SA)
			, SUM(HouseWL_SBC)
			, SUM(HouseWL_SXG)
			, SUM(HouseWL_BBIN)
			, SUM(HouseWL_TG)
			, SUM(HouseWL_IBCLC)
			, SUM(HouseWL_ION)
			, SUM(HouseWL_RNGW)
			, SUM(HouseWL_FW)
			, SUM(HouseWL_PGS)
			, SUM(HouseWL_JK)
			, SUM(HouseWL_WM)
		 FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 1, ''House Income'', HouseWL_Soccer' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaSoccer'', 1, ''House Income'', HouseWL_SabaSoccer' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 2, ''House Income'', HouseWL_Basketball' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaBasketball'', 2, ''House Income'', HouseWL_SabaBasketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Tennis'', 3, ''House Income'', HouseWL_Tennis' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''E-Sports'', 4, ''House Income'', HouseWL_ESports' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''OS'', 5, ''House Income'', HouseWL_OS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SabaCricket'', 5, ''House Income'', HouseWL_Cricket' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''Parlay'', 6, ''House Income'', HouseWL_Parlay' + CHAR(13)

	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG'', 7, ''House Income'', HouseWL_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 8, ''House Income'', HouseWL_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 9, ''House Income'', HouseWL_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''KN'', 10, ''House Income'', HouseWL_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG2'', 11, ''House Income'', HouseWL_NG2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VB'', 12, ''House Income'', HouseWL_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''AB'', 13, ''House Income'', HouseWL_AB' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''GD'', 14, ''House Income'', HouseWL_GD' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 15, ''House Income'', HouseWL_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 16, ''House Income'', HouseWL_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 17, ''House Income'', HouseWL_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CS'', 18, ''House Income'', HouseWL_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''JP'', 19, ''House Income'', HouseWL_1RNG_JP_MegaPrize' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''JP'', 20, ''House Income'', HouseWL_1RNG_JP_Contribution' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP'', 21, ''House Income'', HouseWL_PP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP-JP'', 22, ''House Income'', HouseWL_PP_JP_MegaPrize' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP-JP'', 23, ''House Income'', HouseWL_PP_JP_Contribution' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 24, ''House Income'', HouseWL_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''NPH'', 25, ''House Income'', HouseWL_SP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SG'', 26, ''House Income'', HouseWL_SG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VG'', 27, ''House Income'', HouseWL_VG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SAG'', 28, ''House Income'', HouseWL_SA' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SBC'', 29, ''House Income'', HouseWL_SBC' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SXG'', 30, ''House Income'', HouseWL_SXG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''BBIN'', 31, ''House Income'', HouseWL_BBIN' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''TG'', 32, ''House Income'', HouseWL_TG' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''IBCLC'', 33, ''House Income'', HouseWL_IBCLC' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''ION'', 34, ''House Income'', HouseWL_ION' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGW'', 35, ''House Income'', HouseWL_RNGW' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''FW'', 36, ''House Income'', HouseWL_FW' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PGS'', 37, ''House Income'', HouseWL_PGS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''JK'', 38, ''House Income'', HouseWL_JK' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''WM'', 39, ''House Income'', HouseWL_WM) c (ProductCode, [Order], Figure, value)) a' + CHAR(13)
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

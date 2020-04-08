/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_ProductTurnover_BySite]
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
	
	Param's Explanation:   
	- DepositType  
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_ProductTurnover_BySite '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_ProductTurnover_BySite '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_ProductTurnover_BySite '20180601', '20180619', 1, '789Y' -- 789Y site of Credit   
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
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
	    RptDate               VARCHAR(10)
	  , HouseTO_Soccer        MONEY
	  , HouseTO_Basketball    MONEY
	  , HouseTO_Tennis        MONEY
	  , HouseTO_ESports       MONEY
	  , HouseTO_OS            MONEY
	  , HouseTO_Parlay        MONEY
	  , HouseTO_NG        MONEY
	  , HouseTO_H5        MONEY
	  , HouseTO_VS        MONEY
	  , HouseTO_RNGKeno        MONEY
	  , HouseTO_NG2        MONEY
	  , HouseTO_MacauG        MONEY
	  , HouseTO_AB        MONEY
	  , HouseTO_GD        MONEY
	  , HouseTO_LT        MONEY
	  , HouseTO_EX        MONEY
	  , HouseTO_VS2        MONEY
	  , HouseTO_1RNG        MONEY
	  , HouseTO_1RNG_JP_MegaPrize        MONEY
	  , HouseTO_1RNG_JP_Contribution        MONEY
	  , HouseTO_PP        MONEY
	  , HouseTO_CC        MONEY
	  , HouseTO_SP        MONEY
	  , HouseTO_SG        MONEY
	  , HouseTO_VG        MONEY
	  , HouseTO_SA        MONEY
	  , HouseTO_SBC        MONEY
	  , HouseTO_SXG        MONEY
	  , HouseTO_BBIN        MONEY)
	  , HouseTO_TG        MONEY);

	  DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;
    -- #SportBettypeMatrix

    CREATE TABLE #SportBettypeMatrix(
	    ProductID    INT
		, Bettype      INT);

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype)
		SELECT DISTINCT ProductID
			 , BetType
		FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
		WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
		 AND ProductID IN (1, 3, 5, 8, 23, 22, 21, 12, 28, 27, 6, 32, 34, 36, 38, 39, 42, 45, 47, 40)
		 AND BetType NOT IN (4299, 4300) -- PP

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
			 , CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END SportType
			 , b.BetType
			 , SUM((CASE WHEN b.TurnoverIBC=0 THEN 0 ELSE b.TurnoverIBC - b.ExtraTO END) *
							(CASE WHEN b.VarianceVR > 0 THEN (b.VarianceVR + 1) ELSE 1 END) * ex.Rate) AS  HouseTO
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
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
				, CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END
				, b.BetType OPTION(RECOMPILE);
		
		-- Get DetailDaily Data & FullRange Data

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  , HouseTO_Soccer, HouseTO_Basketball, HouseTO_Tennis, HouseTO_ESports, HouseTO_OS, HouseTO_Parlay
						  ,	HouseTO_NG        
						  , HouseTO_H5        
						  , HouseTO_VS        
						  , HouseTO_RNGKeno        
						  , HouseTO_NG2        
						  , HouseTO_MacauG        
						  , HouseTO_AB
						  , HouseTO_GD        
						  , HouseTO_LT
						  , HouseTO_EX        
						  , HouseTO_VS2        
						  , HouseTO_1RNG
						  , HouseTO_1RNG_JP_MegaPrize
						  , HouseTO_1RNG_JP_Contribution        
						  , HouseTO_PP   
						  , HouseTO_CC
						  , HouseTO_SP
						  , HouseTO_SG
						  , HouseTO_VG
						  , HouseTO_SA        
						  , HouseTO_SBC        
						  , HouseTO_SXG
						  , HouseTO_BBIN
						  , HouseTO_TG
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	-- BEGIN SPORTBOOK
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 1 AND t.rptDate = @tmpDate) AS HouseTO_Soccer
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 2 AND t.rptDate = @tmpDate) AS HouseTO_Basketball
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 5 AND t.rptDate = @tmpDate ) AS HouseTO_Tennis
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = 43 AND t.rptDate = @tmpDate) AS HouseTO_ESports
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 1 AND t.SportType NOT IN (1, 2, 5, 43, -2) AND t.rptDate = @tmpDate) AS  HouseTO_OS
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.SportType = -2 AND t.rptDate = @tmpDate) AS  HouseTO_Parlay
	-- END SPORTBOOK
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  HouseTO_NG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS  HouseTO_H5
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate) AS  HouseTO_VS
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate) AS  HouseTO_RNGKeno
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 23 AND t.rptDate = @tmpDate) AS  HouseTO_NG2
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate) AS  HouseTO_MacauG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 21 AND t.rptDate = @tmpDate) AS  HouseTO_AB
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 12 AND t.rptDate = @tmpDate) AS  HouseTO_GD
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  HouseTO_LT
	, 0 HouseTO_EX
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  HouseTO_VS2
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 6 AND t.rptDate = @tmpDate) AS  HouseTO_1RNG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.BetType IN (2199, 2399, 2999) AND t.rptDate = @tmpDate) AS HouseTO_1RNG_JP_MegaPrize
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.BetType IN (2198, 2398, 2998) AND t.rptDate = @tmpDate) AS HouseTO_1RNG_JP_Contribution
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 32 AND t.rptDate = @tmpDate) AS  HouseTO_PP
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 34 AND t.rptDate = @tmpDate) AS  HouseTO_CC
	, 0 HouseTO_SP
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 36 AND t.rptDate = @tmpDate) AS  HouseTO_SG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 38 AND t.rptDate = @tmpDate) AS  HouseTO_VG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 39 AND t.rptDate = @tmpDate) AS  HouseTO_SA
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 42 AND t.rptDate = @tmpDate) AS  HouseTO_SBC
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 45 AND t.rptDate = @tmpDate) AS  HouseTO_SXG
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 47 AND t.rptDate = @tmpDate) AS  HouseTO_BBIN
	,(SELECT SUM(t.HouseTO) FROM #TmpData AS t WHERE t.ProductID = 40 AND t.rptDate = @tmpDate) AS  HouseTO_TG;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
		
INSERT INTO #FinalResult(RptDate
					, HouseTO_Soccer, HouseTO_Basketball, HouseTO_Tennis, HouseTO_ESports, HouseTO_OS, HouseTO_Parlay
					, HouseTO_NG        
					, HouseTO_H5        
					, HouseTO_VS        
					, HouseTO_RNGKeno        
					, HouseTO_NG2        
					, HouseTO_MacauG        
					, HouseTO_AB
					, HouseTO_GD        
					, HouseTO_LT
					, HouseTO_EX        
					, HouseTO_VS2        
					, HouseTO_1RNG
					, HouseTO_1RNG_JP_MegaPrize
					, HouseTO_1RNG_JP_Contribution        
					, HouseTO_PP   
					, HouseTO_CC
					, HouseTO_SP
					, HouseTO_SG
					, HouseTO_VG
					, HouseTO_SA        
					, HouseTO_SBC        
					, HouseTO_SXG
					, HouseTO_BBIN
					, HouseTO_TG)
		 SELECT 'FullRange'
			 , SUM(HouseTO_Soccer)
			 , SUM(HouseTO_Basketball)
			 , SUM(HouseTO_Tennis)
			 , SUM(HouseTO_ESports)
			 , SUM(HouseTO_OS)
			 , SUM(HouseTO_Parlay)
			 , SUM(HouseTO_NG)        
			 , SUM(HouseTO_H5)        
			 , SUM(HouseTO_VS)        
			 , SUM(HouseTO_RNGKeno)        
			 , SUM(HouseTO_NG2)        
			 , SUM(HouseTO_MacauG)        
			, SUM(HouseTO_AB)
			, SUM(HouseTO_GD)        
			, SUM(HouseTO_LT)
			, SUM(HouseTO_EX)        
			, SUM(HouseTO_VS2)        
			, SUM(HouseTO_1RNG)
			, SUM(HouseTO_1RNG_JP_MegaPrize)
			, SUM(HouseTO_1RNG_JP_Contribution)        
			, SUM(HouseTO_PP)   
			, SUM(HouseTO_CC)
			, SUM(HouseTO_SP)
			, SUM(HouseTO_SG)
			, SUM(HouseTO_VG)
			, SUM(HouseTO_SA)
			, SUM(HouseTO_SBC)
			, SUM(HouseTO_SXG)
			, SUM(HouseTO_BBIN)
			, SUM(HouseTO_TG)
		 FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 1, ''House TurnOver'', HouseTO_Soccer' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Basketball'', 2, ''House TurnOver'', HouseTO_Basketball' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''Tennis'', 3, ''House TurnOver'', HouseTO_Tennis' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''E-Sports'', 4, ''House TurnOver'', HouseTO_ESports' + CHAR(13) 
    + 'UNION ALL' + CHAR(13) + 'SELECT ''OS'', 5, ''House TurnOver'', HouseTO_OS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''Parlay'', 6, ''House TurnOver'', HouseTO_Parlay' + CHAR(13)

	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG'', 7, ''House TurnOver'', HouseTO_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 8, ''House TurnOver'', HouseTO_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 9, ''House TurnOver'', HouseTO_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGKeno'', 10, ''House TurnOver'', HouseTO_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG2'', 11, ''House TurnOver'', HouseTO_NG2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''MacauG'', 12, ''House TurnOver'', HouseTO_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''AB'', 13, ''House TurnOver'', HouseTO_AB' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''GD'', 14, ''House TurnOver'', HouseTO_GD' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 15, ''House TurnOver'', HouseTO_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 16, ''House TurnOver'', HouseTO_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 17, ''House TurnOver'', HouseTO_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG'', 18, ''House TurnOver'', HouseTO_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 19, ''House TurnOver'', HouseTO_1RNG_JP_MegaPrize' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 20, ''House TurnOver'', HouseTO_1RNG_JP_Contribution' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP'', 21, ''House TurnOver'', HouseTO_PP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 22, ''House TurnOver'', HouseTO_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SP'', 23, ''House TurnOver'', HouseTO_SP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SG'', 24, ''House TurnOver'', HouseTO_SG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VG'', 25, ''House TurnOver'', HouseTO_VG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SAG'', 26, ''House TurnOver'', HouseTO_SA' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SBC'', 27, ''House TurnOver'', HouseTO_SBC' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SXG'', 28, ''House TurnOver'', HouseTO_SXG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''BBIN'', 29, ''House TurnOver'', HouseTO_BBIN' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''TG'', 30, ''House TurnOver'', HouseTO_TG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13)  
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13) 
    + 'ORDER BY [Order]';

    EXEC (@SQL);
	
    -- Drop temp tables
    DROP TABLE #SportBettypeMatrix;
    DROP TABLE #Exchange;
    DROP TABLE #FinalResult;
    DROP TABLE #TmpData;

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_ProductTurnover_BySite] TO [dwrs]
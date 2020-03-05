/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier_BySite]
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
	
	Param's Explanation:   
	- DepositType  
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '789Y' -- 789Y site of Credit   
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate DATE, @TDate DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- #Exchange
	DECLARE @SiteCN88    INT;

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88';

    CREATE TABLE #Exchange(ExchangeDate    DATE, ExchangeID      INT, Rate            FLOAT);
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE TABLE #tmpProduct(ProductID INT, ProductCode VARCHAR(100))

	INSERT INTO #tmpProduct(ProductID, ProductCode)
	SELECT SourceID, ProductCode
	FROM bodb_Account.dbo.DimProduct
	WHERE ProductCode IN ( 'PP', 'CC', 'SG') AND SourceInfo = 'Licensee'

    INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
		 SELECT ExchangeDate, Currency, Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

	DECLARE @OpenQuery NVARCHAR(1000)
	SELECT @OpenQuery = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBEXT, '
						+ N'''SELECT ExchangeDate, ExchangeID, BaseCurrencyRate '
						+ N'FROM bodb02.dbo.LA_f_ExchangeDailySel('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''MYR'''''			
						+ N')'')'
					
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQuery)

	CREATE TABLE #ChargeInfo3rd(
	    ProductID         INT
	  , Rate              MONEY
	  , FromDate          SMALLDATETIME
	  , ToDate            SMALLDATETIME
	  , MinAmount         MONEY
	  , MaxAmount         MONEY
	  , BaseCurrencyId    INT);
	
	DECLARE @OpenQueryCharge NVARCHAR(1000)
	SELECT @OpenQueryCharge = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''PP,CC,SG'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID
						, Rate, FromDate, ToDate
					    , MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQueryCharge);	


    -- #FinalResult
	CREATE TABLE #FinalResult(
	    RptDate               VARCHAR(10)
	  , PayToSupplier_NG        MONEY
	  , PayToSupplier_H5        MONEY
	  , PayToSupplier_VS        MONEY
	  , PayToSupplier_RNGKeno        MONEY
	  , PayToSupplier_NG2        MONEY
	  , PayToSupplier_MacauG        MONEY
	  , PayToSupplier_LT        MONEY
	  , PayToSupplier_EX        MONEY--
	  , PayToSupplier_VS2        MONEY
	  , PayToSupplier_1RNG        MONEY
	  , PayToSupplier_1RNG_JP        MONEY
	  , PayToSupplier_PP        MONEY
	  , PayToSupplier_CC        MONEY
	  , PayToSupplier_SP        MONEY
	  , PayToSupplier_SG        MONEY);

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
		WHERE ProductID IN (3, 5, 8, 23, 22, 21, 12, 28, 27, 6, 32, 34, 36)
		 AND BetType NOT IN (4299, 4300) -- PP

		 CREATE TABLE #TmpData(
				rptDate      DATE
				, ProductID INT
				, SportType    INT
				, BetType    INT
				, HouseWL      MONEY
				, MemberWLOANDA MONEY);
	    
    INSERT INTO #TmpData(rptDate
				   , ProductID
				   , SportType
				   , BetType
				   , HouseWL
				   , MemberWLOANDA)
		 SELECT b.rptDate
			 ,  sb.ProductID
			 ,  CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END SportType
			 ,  b.BetType
			 ,ISNULL(-SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate), 0) AS  HouseWL
			 ,ISNULL(SUM(b.WinlossP * oanda.Rate), 0) AS  MemberWLOANDA
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
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

	-- BEGIN - Calculate PayToSupplier for Pragmatic (PP)
	CREATE TABLE #tmpPayToSupplier_PP(
	    RptDate               VARCHAR(10),
		PayToSupplier_PP_Daily        MONEY);

	CREATE TABLE #tmpPayToSupplier_PP_MTD(
		MemberWLOANDA				MONEY,
		PayToSupplier_PP_MTD        MONEY);

	INSERT INTO #tmpPayToSupplier_PP(RptDate, PayToSupplier_PP_Daily)
	SELECT wl.RptDate, (CASE WHEN (MemberWLOANDA < 0 AND (ci.MinAmount * ex.Rate) = 0) OR (MemberWLOANDA >= (ci.MinAmount * ex.Rate)) THEN 
								CASE WHEN MemberWLOANDA > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
									 ELSE MemberWLOANDA - (ci.MinAmount * ex.Rate) END
							ELSE 0 END) * ci.Rate AS PayToSupplier_PP_Daily
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #TmpData AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'PP'
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate

	INSERT INTO #tmpPayToSupplier_PP_MTD( MemberWLOANDA, PayToSupplier_PP_MTD)
	SELECT SUM(MemberWL_MTD) MemberWLOANDA,
						SUM((CASE WHEN MemberWL_MTD >= MinAmount THEN 
								CASE WHEN MemberWL_MTD > MaxAmount THEN (MaxAmount - MinAmount)
									 ELSE MemberWL_MTD - MinAmount END
							ELSE 0 END) * Rate)  AS PayToSupplier_PP_MTD
		FROM (
		SELECT ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount * ex.Rate as MinAmount, MaxAmount * ex.Rate as MaxAmount, SUM(MemberWLOANDA)  MemberWL_MTD
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #TmpData AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'PP'
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate
			GROUP BY ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount * ex.Rate, MaxAmount * ex.Rate
					) as temp
	-- END - Calculate PayToSupplier for Pragmatic (PP)
	
	CREATE TABLE #tmpPayToSupplier_SportBook(
	    RptDate               VARCHAR(10),
		ProductName				VARCHAR(10),
		PayToSupplier        MONEY);

		
	-- Get DetailDaily Data & FullRange Data
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  ,	PayToSupplier_NG        
						  , PayToSupplier_H5        
						  , PayToSupplier_VS        
						  , PayToSupplier_RNGKeno        
						  , PayToSupplier_NG2        
						  , PayToSupplier_MacauG                
						  , PayToSupplier_LT
						  , PayToSupplier_EX        
						  , PayToSupplier_VS2        
						  , PayToSupplier_1RNG
						  , PayToSupplier_1RNG_JP        
						  , PayToSupplier_PP   
						  , PayToSupplier_CC
						  , PayToSupplier_SP
						  , PayToSupplier_SG
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  PayToSupplier_NG
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS  PayToSupplier_H5
	,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #TmpData AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate) AS  PayToSupplier_VS
	,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #TmpData AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate) AS  PayToSupplier_RNGKeno
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #TmpData AS t WHERE t.ProductID = 23 AND t.rptDate = @tmpDate) AS  PayToSupplier_NG2
	,(SELECT SUM(t.MemberWLOANDA) * 0.02 FROM #TmpData AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate) AS  PayToSupplier_MacauG
	,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #TmpData AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  PayToSupplier_LT
	, 0 PayToSupplier_EX
	,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #TmpData AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  PayToSupplier_VS2
	, 0 PayToSupplier_1RNG
	, 0 PayToSupplier_1RNG_JP
	,(SELECT -SUM(t.PayToSupplier_PP_Daily) FROM #tmpPayToSupplier_PP AS t WHERE t.rptDate = @tmpDate) AS  PayToSupplier_PP
	,(SELECT SUM(t.MemberWLOANDA * ISNULL(ci.Rate,0)) 
							FROM #TmpData AS t
							INNER JOIN #ChargeInfo3rd AS ci ON t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'CC' 
							WHERE t.ProductID = 34 AND t.rptDate = @tmpDate) AS  PayToSupplier_CC
	, 0 PayToSupplier_SP
	,(SELECT SUM(t.MemberWLOANDA * ISNULL(ci.Rate,0)) 
							FROM #TmpData AS t
							INNER JOIN #ChargeInfo3rd AS ci ON t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'SG' 
							WHERE t.ProductID = 36 AND t.rptDate = @tmpDate) AS  PayToSupplier_SG;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END; 

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
	
INSERT INTO #FinalResult(RptDate
					, PayToSupplier_NG        
					, PayToSupplier_H5        
					, PayToSupplier_VS        
					, PayToSupplier_RNGKeno        
					, PayToSupplier_NG2        
					, PayToSupplier_MacauG               
					, PayToSupplier_LT
					, PayToSupplier_EX        
					, PayToSupplier_VS2        
					, PayToSupplier_1RNG
					, PayToSupplier_1RNG_JP        
					, PayToSupplier_PP   
					, PayToSupplier_CC
					, PayToSupplier_SP
					, PayToSupplier_SG)
		 SELECT 'FullRange'
			, SUM(PayToSupplier_NG)        
			, SUM(PayToSupplier_H5)
			, 0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #TmpData AS t WHERE t.ProductID = 5)
			, 0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #TmpData AS t WHERE t.ProductID = 8)
			, SUM(PayToSupplier_NG2)
			, 0.02 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #TmpData AS t WHERE t.ProductID = 22)
			, 0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #TmpData AS t WHERE t.ProductID = 28)
			, 0
			, 0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #TmpData AS t WHERE t.ProductID = 27)               
			, 0
			, 0        
			, (SELECT CASE WHEN SUM(MemberWLOANDA) < 0 THEN 0 ELSE -SUM(PayToSupplier_PP_MTD) END FROM #tmpPayToSupplier_PP_MTD)
			, CASE WHEN SUM(PayToSupplier_CC) > 0 THEN 0 ELSE SUM(PayToSupplier_CC) END
			, 0
			, CASE WHEN SUM(PayToSupplier_SG) > 0 THEN 0 ELSE SUM(PayToSupplier_SG) END
		 FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''NG'', 1, ''PayToSupplier'', PayToSupplier_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 2, ''PayToSupplier'', PayToSupplier_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 3, ''PayToSupplier'', PayToSupplier_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGKeno'', 4, ''PayToSupplier'', PayToSupplier_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG2'', 5, ''PayToSupplier'', PayToSupplier_NG2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''MacauG'', 6, ''PayToSupplier'', PayToSupplier_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 7, ''PayToSupplier'', PayToSupplier_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 8, ''PayToSupplier'', PayToSupplier_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 9, ''PayToSupplier'', PayToSupplier_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG'', 10, ''PayToSupplier'', PayToSupplier_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 11, ''PayToSupplier'', PayToSupplier_1RNG_JP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP'', 12, ''PayToSupplier'', PayToSupplier_PP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 13, ''PayToSupplier'', PayToSupplier_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SP'', 14, ''PayToSupplier'', PayToSupplier_SP' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SG'', 15, ''PayToSupplier'', PayToSupplier_SG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13)  
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13)

    CREATE TABLE #tmpPayToSupplier_MetricGaming(
	    RptDate               VARCHAR(10),
		PayToSupplier_MG        MONEY);

	INSERT INTO #tmpPayToSupplier_MetricGaming(rptDate, PayToSupplier_MG)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming 
				@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	CREATE TABLE #tmpPayToSupplier_MuayThai(
	    RptDate               VARCHAR(10),
		PayToSupplier_MT        MONEY);

	INSERT INTO #tmpPayToSupplier_MuayThai(rptDate, PayToSupplier_MT)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMuayThai
			@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
			
	CREATE TABLE #tmpPayToSupplier_BetBuilder(
	    RptDate               VARCHAR(10),
		PayToSupplier_BB        MONEY);

	INSERT INTO #tmpPayToSupplier_BetBuilder(rptDate, PayToSupplier_BB)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder
			@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site			 

	DECLARE @SQL_MetricGaming    VARCHAR(max)
			,@SQL_MuayThai    VARCHAR(max)
			,@SQL_BetBuilder    VARCHAR(max);

    SELECT @SQL_MetricGaming = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MetricGaming' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 16, ''PayToSupplier'', PayToSupplier_MG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);
	SELECT @SQL_MuayThai = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MuayThai' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''OS'', 17, ''PayToSupplier'', PayToSupplier_MT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);
	SELECT @SQL_BetBuilder = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_BetBuilder' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 18, ''PayToSupplier'', PayToSupplier_BB) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);

	EXEC (@SQL_MetricGaming + ' UNION ALL ' + @SQL_MuayThai + ' UNION ALL ' + @SQL_BetBuilder + ' UNION ALL ' + @SQL );

	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_AB_PayToSupplier
		@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_GD_PayToSupplier
		@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site

	-- Drop temp tables
	DROP TABLE #tmpPayToSupplier_MetricGaming;
	DROP TABLE #tmpPayToSupplier_MuayThai;
	DROP TABLE #tmpPayToSupplier_BetBuilder;
    -- Drop temp tables
    DROP TABLE #SportBettypeMatrix;
    DROP TABLE #Exchange;
	DROP TABLE #ExchangeOANDA;
	DROP TABLE #tmpProduct;
	DROP TABLE #ChargeInfo3rd
    DROP TABLE #FinalResult;
    DROP TABLE #TmpData;
	DROP TABLE #tmpPayToSupplier_PP;
	DROP TABLE #tmpPayToSupplier_PP_MTD;

END
GO
GRANT EXECUTE ON [dbo].Acc_Rpt_HouseNetIncome_PayToSupplier_BySite TO [dwrs]
/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier_ByCN88]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:	20200214@Kean  
    Task :		Apply new billing terms for NG, RNG Keno, Lottery, Virtual Sport, Virtual Sport 2, Happy 5
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200214@Kean - Apply new billing terms for NG, RNG Keno, Lottery, Virtual Sport, Virtual Sport 2, Happy 5 [#128007]
	
	Param's Explanation:   
	- DepositType  
				    = 2 All
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_ByCN88 '20180601', '20180619'   
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate DATE, @TDate DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- #Exchange

    CREATE TABLE #Exchange(ExchangeDate    DATE, ExchangeID      INT, Rate            FLOAT);
	DECLARE @SiteCN88    INT;

	   SELECT TOP 1 @SiteCN88 = SiteId
	   FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	   WHERE [site] = 'CN88';

    INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
		 SELECT ExchangeDate, Currency, Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    -- #FinalResult
	CREATE TABLE #FinalResult(
	    RptDate               VARCHAR(10)
	  , PayToSupplier_NG        MONEY
	  , PayToSupplier_H5        MONEY
	  , PayToSupplier_VS        MONEY
	  , PayToSupplier_RNGKeno        MONEY
	  , PayToSupplier_LT        MONEY
	  , PayToSupplier_VS2        MONEY);

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
		WHERE ProductID IN (3, 5, 8, 28, 27)

		 CREATE TABLE #TmpData(
				rptDate      DATE
				, ProductID INT
				, SportType    INT
				, BetType    INT
				, MemberWL MONEY);
	    
    INSERT INTO #TmpData(rptDate
				   , ProductID
				   , SportType
				   , BetType
				   , MemberWL)
		 SELECT b.rptDate
			 ,  sb.ProductID
			 ,  b.SportType SportType
			 ,  b.BetType
			 ,ISNULL(SUM(b.WinlossP * ex.Rate), 0) AS  MemberWL
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20
			  AND SiteID = @SiteCN88  
		 GROUP BY b.rptDate
			    , sb.ProductID
				, b.SportType
				, b.BetType 
		OPTION(RECOMPILE);
	
		
	-- Get DetailDaily Data & FullRange Data
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  ,	PayToSupplier_NG        
						  , PayToSupplier_H5        
						  , PayToSupplier_VS        
						  , PayToSupplier_RNGKeno       
						  , PayToSupplier_LT        
						  , PayToSupplier_VS2        
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	,(SELECT SUM(t.MemberWL) * 0.015 FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  PayToSupplier_NG
	,(SELECT SUM(t.MemberWL) * 0.015 FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS  PayToSupplier_H5
	,(SELECT SUM(t.MemberWL) * 0.01 FROM #TmpData AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate) AS  PayToSupplier_VS
	,(SELECT SUM(t.MemberWL) * 0.015 FROM #TmpData AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate) AS  PayToSupplier_RNGKeno
	,(SELECT SUM(t.MemberWL) * 0.015 FROM #TmpData AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  PayToSupplier_LT
	,(SELECT SUM(t.MemberWL) * 0.01 FROM #TmpData AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  PayToSupplier_VS2;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END; 

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
	
INSERT INTO #FinalResult(RptDate
					, PayToSupplier_NG        
					, PayToSupplier_H5        
					, PayToSupplier_VS        
					, PayToSupplier_RNGKeno               
					, PayToSupplier_LT        
					, PayToSupplier_VS2)
		SELECT 'FullRange'
		, 0.015 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType <> 164)
		, 0.015 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 3 AND t.SportType = 164)
		, 0.01 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 5)
		, 0.015 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 8)
		, 0.015 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 28)
		, 0.01 * (SELECT CASE WHEN SUM(MemberWL) > 0 THEN 0 ELSE SUM(MemberWL) END FROM #TmpData AS t WHERE t.ProductID = 27)        
		FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''NG'', 1, ''PayToSupplier'', PayToSupplier_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 2, ''PayToSupplier'', PayToSupplier_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 3, ''PayToSupplier'', PayToSupplier_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''KN'', 4, ''PayToSupplier'', PayToSupplier_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 5, ''PayToSupplier'', PayToSupplier_LT' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 6, ''PayToSupplier'', PayToSupplier_VS2) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
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
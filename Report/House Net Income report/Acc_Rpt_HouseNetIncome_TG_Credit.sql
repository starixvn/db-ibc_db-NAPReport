/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_TG_Credit]
	@FromDate DATE ,
	@ToDate	DATE 
AS
  
/*  
	Created:	20200408@Kean  
    Task :		Integrate Table Games product [RedmineID: #129447] 
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
	   - 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
	   - 20201023@Roy: HNI Email/Letstalk - Adjust royalty fee term for RNG Keno, Lottery, Table Game, Number Game, NG2, Happy 5 (#143589)

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_TG_Credit '20160901', '20160930'
*/ 
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Get exchange rate info

    CREATE TABLE #Exchange(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);
	CREATE TABLE #tmpProduct(ProductID INT, ProductCode VARCHAR(100), VendorID INT)
	 
	INSERT INTO #tmpProduct(ProductID, ProductCode, VendorID)
	SELECT ProductID, ProductPrefix, VendorID
	FROM bodb02.dbo.Products WITH(NOLOCK)
	WHERE ProductPrefix IN ('TG')

    INSERT INTO #Exchange(ExchangeDate
				    , ExchangeID
				    , Rate)
		 SELECT ExchangeDate
			 , Currency
			 , Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID);
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
					
    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
    EXECUTE (@OpenQuery);
    -- End region

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , HouseWL          MONEY
	  , ExtraPT          MONEY
	  , PayToSupplier    MONEY);

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0
				    , 0
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    -- Sport - Bettype Matrix

    CREATE TABLE #SportBettypeMatrix(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype
						    , EventType
						    , SubProduct)
		 SELECT ProductID
			 , BetType
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (40, 0, 0, 2, '', 'TG', 0);
    -- Get PayToSupplier Rate
    
    -- House WL
    CREATE TABLE #TmpHouseWL(
	    rptDate          DATE
	  , CurrencyID       INT
	  , HouseWL          MONEY
	  , MemberWL         MONEY
	  , MemberWLReal     MONEY
	  , MemberWLOANDA    MONEY
	  , PayToSupplier    MONEY
	  , ExtraPT          MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , CurrencyID
					 , HouseWL
					 , MemberWLOANDA					 
					 , ExtraPT)
		 SELECT b.rptDate
			 , b.CurrencyID
			 , -SUM((b.WinlossIBC + b.CommissionS) * ex.rate) AS HouseWL			 
			 , SUM(b.WinlossP * e.Rate) AS MemberWLOANDA
			 , SUM((b.ExtraWL + b.ExtraComm) * ex.Rate) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate
								    AND e.ExchangeID = b.CurrencyID
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.BetType IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 40)
	   		  AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
		 GROUP BY b.rptDate
			   , b.CurrencyID OPTION(RECOMPILE);    
    
    -- House Winloss

    UPDATE f
		 SET
			HouseWL = f.HouseWL + house.HouseWL
		   , ExtraPT = f.ExtraPT + house.ExtraPT
		   , PayToSupplier = f.PayToSupplier + house.PayToSupplier
    FROM #FinalResult f
	   INNER JOIN
	    (
		   SELECT CONVERT(VARCHAR(2), wl.rptDate, 106) AS winlostDate
			   , SUM(wl.HouseWL) AS HouseWL
			   , SUM(wl.ExtraPT) AS ExtraPT
			   , SUM(wl.MemberWLOANDA * (CASE WHEN wl.rptDate >= '2020-07-01' THEN 0.036 ELSE 0.03 END)) AS PayToSupplier
		   FROM #TmpHouseWL AS wl
		   GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	    ) house ON house.winlostDate = f.RptDate;
    
    -- FullRange amount

    INSERT INTO #FinalResult(RptDate
					  , HouseWL
					  , ExtraPT
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , SUM(f.HouseWL)
			 , SUM(f.ExtraPT)
			 , CASE
				  WHEN SUM(PayToSupplier) > 0
				  THEN 0
				  ELSE SUM(PayToSupplier)
			   END AS PayToSupplier
		 FROM #FinalResult AS f;
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''TG'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''TG'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''TG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #tmpProduct
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
END

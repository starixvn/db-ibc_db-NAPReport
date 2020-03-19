/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CC_Credit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  	
	 Created:	20190819@Robert
    Task :		House month-to-date Net Income report for Card Club
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20200313@Kean - Change the "Pay to supplier" formula of CC(New Bettype 1902) - #126465
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_CC_Credit '20180601', '20180630'   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Get exchange rate info
	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 

	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,[VName]
		  ,[NumberValue]
		  ,[sporttype]
		  ,[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN bodb02.dbo.Products p WITH(NOLOCK) ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCreditWLShareRateTX')
	AND p.ProductPrefix IN ('CC')

    CREATE TABLE #Exchange(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

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
			 (34, 0, 0, 2, '', 'CC', 0);
    -- Get PayToSupplier Rate

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
						+ N',''''CC'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID
					    , Rate
					    , FromDate
					    , ToDate
					    , MinAmount
					    , MaxAmount
					    , BaseCurrencyId)
    EXECUTE (@OpenQueryCharge);	
    
    -- House WL
    CREATE TABLE #TmpHouseWL(
	    rptDate          DATE
	  , ProductID        INT
	  , SportType        INT
	  , BetType          INT
	  , CurrencyID       INT
	  , HouseWL          MONEY
	  , MemberWL         MONEY
	  , MemberWLReal     MONEY
	  , MemberWLOANDA    MONEY
	  , PayToSupplier    MONEY
	  , ExtraPT          MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , ProductID
					 , SportType
					 , BetType
					 , CurrencyID
					 , HouseWL
					 , MemberWLOANDA					 
					 , ExtraPT)
		 SELECT b.rptDate
			 , 34 ProductID
			 , b.SportType
			 , b.BetType
			 , b.CurrencyID
			 , ISNULL(-SUM((b.WinlossIBC + b.CommissionS) * ex.rate),0) AS HouseWL			 
			 , ISNULL(SUM(b.WinlossP * e.Rate),0) AS MemberWLOANDA
			 , ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.Rate),0) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			--INNER JOIN #SportBettypeMatrix AS sb ON sb.Bettype = b.bettype
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate
								    AND e.ExchangeID = b.CurrencyID
			
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20
	   		  AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
			  AND b.bettype IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb)
		 GROUP BY b.rptDate
			   , b.CurrencyID
			   , b.SportType
			   , b.BetType OPTION(RECOMPILE);    
    
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
			   , SUM(wl.MemberWLOANDA * (CASE WHEN wl.Bettype = 1902 THEN ISNULL(v.ChargeRate3rd,0) ELSE ISNULL(ci.Rate,0) END)) AS PayToSupplier
		   FROM #TmpHouseWL AS wl
			  INNER JOIN #ChargeInfo3rd AS ci ON wl.rptDate BETWEEN ci.FromDate AND ci.ToDate
			  LEFT JOIN #tmpVendorGlobalSetting v ON wl.ProductID = v.ProductID 
																	AND v.Sporttype = wl.SportType 
																	AND v.Bettype = wl.BetType
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
							'(SELECT ''CC'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''CC'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''CC'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpVendorGlobalSetting
END
GO

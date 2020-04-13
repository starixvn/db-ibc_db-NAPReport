/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_BBIN_Credit]
	@FromDate DATE ,
	@ToDate	DATE 
AS
  
/*  
	Created:	20200410@Kean  
    Task :		Integrate BBIN product [RedmineID: #131364] 
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200410@Kean - Email/Letstalk Reports - Integrate BBIN product (#131364)

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_BBIN_Credit '20160901', '20160930'
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
	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT)
	 
	INSERT INTO #tmpProduct(ProductID, ProductCode, VendorID)
	SELECT ProductID, ProductPrefix, VendorID
	FROM bodb02.dbo.Products WITH(NOLOCK)
	WHERE ProductPrefix IN ('BBIN')
	
	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,[VName]
		  ,[NumberValue]
		  ,[sporttype]
		  ,[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN #tmpProduct p ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCreditWLShareRate')


    INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
		 SELECT ExchangeDate, Currency, Rate
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
					
    INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
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
		  INSERT INTO #FinalResult(RptDate, HouseWL, ExtraPT, PayToSupplier)
		  SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0;

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

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype, EventType, SubProduct)
		 SELECT ProductID
			 , BetType
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (47, 0, 0, 2, '', 'BBIN', 0);
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
						+ N',''''BBIN'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQueryCharge);
	
	-- Get ChargeRate3rd from VendorGlobalSetting table IF NOT EXIST FROM LA
	INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate)
	SELECT v.ProductID, v.ChargeRate3rd, @FDate, @TDate
	FROM #tmpVendorGlobalSetting v
	WHERE v.ProductID NOT IN (SELECT ProductID FROM #ChargeInfo3rd)
	AND v.VName = '3rdCreditWLShareRate'
	
		-- Mapping Site between DW and Licensees
	CREATE TABLE #tmpSite(SiteID_DW INT,SiteID_Li INT,SiteName VARCHAR(100))

	INSERT INTO #tmpSite(SiteID_DW,SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = 0

	UPDATE tmpS
	SET tmpS.SiteID_Li = l.SiteID
	FROM #tmpSite tmpS
	INNER JOIN DBLIC.bodb_licensee.dbo.view_site_list l WITH(NOLOCK)
		ON tmpS.SiteName  = RTRIM(LTRIM(l.SiteName));		
    
	-- BEGIN: GET DATA
    CREATE TABLE #TmpHouseWL(
	    rptDate          DATE
	  , CurrencyID       INT
	  , HouseWL          MONEY
	  , MemberWL         MONEY
	  , MemberWLReal     MONEY
	  , MemberWLOANDA    MONEY
	  , PayToSupplier    MONEY
	  , ExtraPT          MONEY);

    INSERT INTO #TmpHouseWL(rptDate, CurrencyID, HouseWL, MemberWLOANDA, ExtraPT)
		 SELECT b.rptDate
			 , b.CurrencyID
			 , -SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL			 
			 , SUM(b.WinlossP * ISNULL(e.Rate,0)) AS MemberWLOANDA
			 , SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #tmpSite s ON b.SiteID = s.SiteID_DW
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate
								    AND e.ExchangeID = b.CurrencyID
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.BetType IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 47)
		 GROUP BY b.rptDate
			   , b.CurrencyID 
		OPTION(RECOMPILE);
	-- END: GET DATA

	-- BEGIN - Calculate House Income, ExtraPT, PayToSupplier

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
			   , SUM(wl.MemberWLOANDA * ci.Rate) AS PayToSupplier
		   FROM #TmpHouseWL AS wl
			  INNER JOIN #ChargeInfo3rd AS ci ON wl.rptDate BETWEEN ci.FromDate AND ci.ToDate
		   GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	    ) house ON house.winlostDate = f.RptDate;
    -- END - Calculate House Income, ExtraPT, PayToSupplier

    -- FullRange amount
    INSERT INTO #FinalResult(RptDate
					  , HouseWL
					  , ExtraPT
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , SUM(f.HouseWL)
			 , SUM(f.ExtraPT)
			 , SUM(PayToSupplier)
		 FROM #FinalResult AS f;
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''BBIN'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''BBIN'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''BBIN'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpSite
END

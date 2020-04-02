/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SBC_Credit]
	@FromDate DATE ,
	@ToDate	DATE 
AS
  
/*  
	Created:	20200324@Kean  
    Task :		Integrate Saba.club (SBC) product [RedmineID: #128059] 
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200324@Kean - Email/Letstalk Reports - Integrate Saba.club (SBC) product [#128059]

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_SBC_Credit '20160901', '20160930'
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

    INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
		 SELECT ExchangeDate, Currency, Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID);
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
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel(42, 0, 0, 2, '', 'SBC', 0);
	
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
	  , PayToSupplier    MONEY
	  , ExtraPT          MONEY);

    INSERT INTO #TmpHouseWL(rptDate, CurrencyID, HouseWL, ExtraPT)
		 SELECT b.rptDate
			 , b.CurrencyID
			 , -SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL			 
			 , SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #tmpSite s ON b.SiteID = s.SiteID_DW
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.BetType IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 42)
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
			   , 0 AS PayToSupplier
		   FROM #TmpHouseWL AS wl
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
			 , 0
		 FROM #FinalResult AS f;
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SBC'', 1, ''House Income'', HouseWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''SBC'', 2, ''Extra PT'', ExtraPT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #FinalResult
	DROP TABLE #tmpSite
END

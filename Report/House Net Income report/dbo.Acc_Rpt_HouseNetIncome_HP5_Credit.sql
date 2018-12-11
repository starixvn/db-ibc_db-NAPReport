/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_HP5_Credit]
	@FromDate DATE 
    ,@ToDate	DATE 
AS  
/*  Created: Victor  
	Date: 2016-08-08  
    Task : House month-to-date Net Income report
    DB: DBWH/bodb_dwrs  
   
    Revisions:		
		- 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
	Param's Explanation:   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    /* Region: Get exchange rate info*/

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
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    CREATE NONCLUSTERED INDEX IX_Exchange_ExchangeDate_ExchangeID ON #Exchange(ExchangeDate, ExchangeID);
    /* End region*/


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
    /* Sport - Bettype Matrix*/

    CREATE TABLE #SportBettypeMatrix(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype
						    , EventType
						    , SubProduct)
		 SELECT DISTINCT
			   ProductID
			 , Bettype
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
		 WHERE ProductID = 3
			  AND SportType = 164;

    CREATE NONCLUSTERED INDEX IX_SportBettypeMatrix_ProductID ON #SportBettypeMatrix(Bettype);
    

    CREATE TABLE #RawData(
	    SiteId     INT
	  , RptDate    DATE
	  , ExtraPT    MONEY
	  , HouseWL    MONEY);

    CREATE TABLE #TmpHouseWL(
	    rptDate    DATE
	  , ExtraPT    MONEY
	  , HouseWL    MONEY);


    INSERT INTO #RawData(SiteId
				   , rptDate
				   , ExtraPT
				   , HouseWL)
		 SELECT b.SiteID
			 , b.rptDate
			 , ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.rate), 0) AS                                  ExtraPT
			 , ISNULL(-SUM((winlossP + winlossS + winlossM + winlossA + commissionS) * ex.rate), 0) AS HouseWL
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			INNER JOIN #SportBettypeMatrix AS sb ON sb.Bettype = b.bettype
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND Sb.ProductID = 3
			  AND b.TicketStatus <> 14
		 GROUP BY b.SiteID
			   , b.rptDate OPTION(RECOMPILE);

    CREATE NONCLUSTERED INDEX IX_RawData ON #RawData(SiteId, rptDate);

    INSERT INTO #TmpHouseWL(rptDate
					 , ExtraPT
					 , HouseWL)
		 SELECT b.rptDate
			 , SUM(ExtraPT)
			 , SUM(HouseWL)
		 FROM #RawData AS b WITH (NOLOCK)
			INNER JOIN bodb_Account.dbo.tbl_Site AS s WITH (NOLOCK) ON s.siteid = b.SiteID
		 WHERE s.isDeposit = 0 /* Credit data only*/
		 GROUP BY b.rptDate OPTION(RECOMPILE);

    CREATE NONCLUSTERED INDEX IX_TmpHouseWL ON #TmpHouseWL(rptDate);

    UPDATE f
		 SET
			ExtraPT = f.ExtraPT + wl.ExtraPT
		   , HouseWL = f.HouseWL + wl.HouseWL
    FROM #FinalResult f
	   INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate;
    /* FullRange amount*/

    INSERT INTO #FinalResult(RptDate
					  , HouseWL
					  , ExtraPT
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , SUM(HouseWL)
			 , SUM(ExtraPT)
			 , 0
		 FROM #FinalResult;

    UPDATE #FinalResult
		 SET
			PayToSupplier = -(HouseWL + ExtraPT) * 0.4;

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''H5'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''H5'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''H5'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #RawData
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_HP5_Credit] TO [dwrs]
GO

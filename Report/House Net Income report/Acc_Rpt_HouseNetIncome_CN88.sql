/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_CN88 
	@FromDate    SMALLDATETIME 
   , @ToDate      SMALLDATETIME 
AS
/*
Creator: Robert
Date: 20191211
Task:  DHWL Letstalk - Add column MTD for each Product and add new CN88 House WL rows in daily and monthly reports [125175]
DB: DBWH.bodb_dwrs

Revisions:
	20191211@Robert: Initialize SP	
	20191227@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report, Need to exclude sporttype = -1 
Example:

EXEC [Acc_Rpt_HouseNetIncome_CN88] @@FromDate='20190801',@@ToDate='20190801'
*/
BEGIN

    SET NOCOUNT ON;

    DECLARE @SiteCN88    INT;

    SELECT TOP 1 @SiteCN88 = SiteId
    FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
    WHERE site = 'CN88';

    CREATE TABLE #FinalResult(
	    RptDate    VARCHAR(10)
	  , HouseWL    MONEY);

    CREATE TABLE #CurrencyDaily(
	    ExchangeDate    DATE
	  , Currency        INT
	  , Rate            FLOAT);

    INSERT INTO #CurrencyDaily
		 SELECT ExchangeDate
			 , Currency
			 , Rate
		 FROM bodb_account.dbo.tbl_currency_daily AS ex WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FromDate AND @ToDate;

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #CurrencyDaily(ExchangeDate, Currency);

    CREATE TABLE #SportBetType(
	    ProductId     INT NOT NULL
	  , BetType       SMALLINT NOT NULL
	  , EventType     INT NOT NULL
	  , SubProduct    VARCHAR(50) NOT NULL
	  , RefTable      INT
	  , CasinoType    INT);

    INSERT INTO #SportBetType
		 SELECT ProductId
			 , BetType
			 , EventType
			 , SubProduct
			 , RefTable
			 , CasinoType
		 FROM bodb02.dbo.f_SportBetTypeMatrix_Sel
			 (0, 0, 0, 2, '', '', 0) AS sb
		 WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm')		

    CREATE CLUSTERED INDEX PK_tmp_SportBetType ON #SportBetType(BetType, ProductID, SubProduct);

    CREATE TABLE #RawData(
	    rptDate    DATE
	  , SiteId     INT
	  , HouseWL    DECIMAL(18, 8));

    INSERT INTO #RawData(rptDate
				   , SiteId
				   , HouseWL)
		 SELECT sd.RptDate
			 , sd.SiteID
			 , -SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate) AS HouseWL
		 FROM bodb_Account.dbo.FactSiteWinloss AS sd WITH(NOLOCK)
			INNER JOIN #SportBetType AS sb ON sd.BetType = sb.BetType
			LEFT JOIN #CurrencyDaily AS ex WITH(NOLOCK) ON sd.rptDate = ex.ExchangeDate
												  AND sd.CurrencyID = ex.Currency
		 WHERE sd.rptdate >= CAST(@FromDate AS DATE)
			  AND rptdate <= CAST(@ToDate AS DATE)			  
			  AND sd.TicketStatus NOT IN(-1, 18, 9, 10, 14)				 
			  AND sd.CurrencyID <> 20
			  AND sd.SiteID = @SiteCN88			  
		 GROUP BY sd.RptDate
			   , sd.SiteID;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FromDate;

    WHILE @tmpDate <= @ToDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;

    UPDATE f
		 SET 
			HouseWL = f.HouseWL + house.HouseWL
    FROM #FinalResult f
	   INNER JOIN
	    (
		   SELECT CONVERT(VARCHAR(2), wl.rptDate, 106) AS winlostDate
			   , SUM(wl.HouseWL) AS HouseWL
		   FROM #RawData AS wl
		   GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	    ) house ON house.winlostDate = f.RptDate;

    INSERT INTO #FinalResult(RptDate
					  , HouseWL)
		 SELECT 'FullRange'
			 , SUM(f.HouseWL)
		 FROM #FinalResult AS f;

    DECLARE @SQL VARCHAR(1000)
    SELECT @SQL =	'SELECT * ' + CHAR(13) +
				    'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
						  'CROSS APPLY' + CHAR(13) +
						  '(SELECT ''CN88'', 1, ''House Income'', HouseWL) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +						  
				    'PIVOT' + CHAR(13) +
				    '(' + CHAR(13) +
					   'MAX(value)' + CHAR(13) +
					   'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
				    ') piv' + CHAR(13) +
				    'ORDER BY [Order]'

	EXEC(@SQL)

    DROP TABLE #CurrencyDaily;
    DROP TABLE #RawData;
    DROP TABLE #FinalResult;
    drop table #SportBetType
END;
GO
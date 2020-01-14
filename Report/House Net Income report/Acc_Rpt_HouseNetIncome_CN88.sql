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
	20200116@Cherry: Separate CN88 data into 3 groups: overall, 92%, 88% (#127003)

Example:

EXEC [Acc_Rpt_HouseNetIncome_CN88] @@FromDate='20190801',@@ToDate='20190801'
*/
BEGIN

    SET NOCOUNT ON;

    CREATE TABLE #FinalResult(
	    RptDate    VARCHAR(10)
	  , HouseWL    MONEY
	  , HouseWL_XPG    MONEY
	  , HouseWL_TPG    MONEY);

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
    
    CREATE TABLE #tmp_XPG_SuperID(SuperID INT)
		  
    INSERT INTO #tmp_XPG_SuperID(SuperID)
    SELECT SuperId
    FROM bodb02.dbo.f_GetHeadlineNoPT()

    CREATE TABLE #RawData(
	    rptDate    DATE
	  , HouseWL    DECIMAL(18, 8)
	  , HouseWL_XPG    DECIMAL(18, 8)
	  , HouseWL_TPG    DECIMAL(18, 8));

    INSERT INTO #RawData(rptDate
				   , HouseWL
				   , HouseWL_XPG
				   , HouseWL_TPG)
		 SELECT sd.RptDate
			 , -SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate) AS HouseWL
			 , -SUM(CASE WHEN s.SuperID IS NOT NULL THEN (WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate ELSE 0 END) AS HouseWL_XPG
			 , -SUM(CASE WHEN s.SuperID IS NULL THEN (WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate ELSE 0 END) AS HouseWL_TPG
		 FROM bodb_Account.dbo.FactCN88Winloss AS sd WITH(NOLOCK)
			INNER JOIN #SportBetType AS sb ON sd.BetType = sb.BetType
			LEFT JOIN #CurrencyDaily AS ex WITH(NOLOCK) ON sd.rptDate = ex.ExchangeDate
												  AND sd.CurrencyID = ex.Currency
			LEFT JOIN #tmp_XPG_SuperID s ON sd.SuperID = s.SuperID 
		 WHERE sd.rptdate >= CAST(@FromDate AS DATE)
			  AND rptdate <= CAST(@ToDate AS DATE)			  
			  AND sd.TicketStatus NOT IN(-1, 18, 9, 10, 14)				 
			  AND sd.CurrencyID <> 20		  
		 GROUP BY sd.RptDate;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FromDate;

    WHILE @tmpDate <= @ToDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, HouseWL_XPG
							, HouseWL_TPG)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0
				    , 0
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;

    UPDATE f
		 SET 
			HouseWL = f.HouseWL + house.HouseWL,
			HouseWL_XPG = f.HouseWL_XPG + house.HouseWL_XPG,
			HouseWL_TPG = f.HouseWL_TPG + house.HouseWL_TPG
    FROM #FinalResult f
	   INNER JOIN
	    (
		   SELECT CONVERT(VARCHAR(2), wl.rptDate, 106) AS winlostDate
			   , SUM(wl.HouseWL) AS HouseWL
			   , SUM(wl.HouseWL_XPG) AS HouseWL_XPG
			   , SUM(wl.HouseWL_TPG) AS HouseWL_TPG
		   FROM #RawData AS wl
		   GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	    ) house ON house.winlostDate = f.RptDate;

    INSERT INTO #FinalResult(RptDate
					  , HouseWL
					  , HouseWL_XPG
					  , HouseWL_TPG)
		 SELECT 'FullRange'
			 , SUM(f.HouseWL)
			 , SUM(f.HouseWL_XPG)
			 , SUM(f.HouseWL_TPG)
		 FROM #FinalResult AS f;

    DECLARE @SQL VARCHAR(5000)
    SELECT @SQL =	'SELECT * ' + CHAR(13) +
				    'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
						  'CROSS APPLY' + CHAR(13) +
						  '(SELECT ''CN88'', 1, ''House Income'', HouseWL) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +					  
				    'PIVOT' + CHAR(13) +
				    '(' + CHAR(13) +
					   'MAX(value)' + CHAR(13) +
					   'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
				    ') piv' + CHAR(13) +
				    'UNION SELECT * ' + CHAR(13) +
				    'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
						  'CROSS APPLY' + CHAR(13) +
						  '(SELECT ''TPG'', 2, ''House Income TPG'', HouseWL_TPG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +					  
				    'PIVOT' + CHAR(13) +
				    '(' + CHAR(13) +
					   'MAX(value)' + CHAR(13) +
					   'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
				    ') piv' + CHAR(13) +
				    'UNION SELECT * ' + CHAR(13) +
				    'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
						  'CROSS APPLY' + CHAR(13) +
						  '(SELECT ''XPG'', 3, ''House Income XPG'', HouseWL_XPG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +					  
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
    DROP TABLE #SportBetType;
    DROP TABLE #tmp_XPG_SuperID;
END;
GO
/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs,bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_SP_Deposit 
	@FromDate    DATE
   , @ToDate      DATE
AS;
/*  	
	 Created:	201901030@Robert
    Task :		NPH - House Net Income, Licensee Performance Email/Letstalk Report Integration
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 201901030@Robert - House Net Income, Licensee Performance Email/Letstalk Report Integration [122516]
		- 20191127@Robert: Rename Product from 'NPH Promotion' to 'Saba Promotion'
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_NPH_Deposit '20180601', '20180630'   
*/

BEGIN
    SET NOCOUNT ON;    

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
		 WHERE ExchangeDate BETWEEN @FromDate AND @ToDate;

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID);

    CREATE TABLE #FinalResult(
	    RptDate    VARCHAR(10)
	  , HouseWL    MONEY);

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

    CREATE TABLE #SportBettypeMatrix(
	    ProductID    INT
	  , Bettype      INT);

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype)
		 SELECT ProductID
			 , BetType
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (37, 0, 0, 2, '', '', 0);
    -- House WL
    CREATE TABLE #TmpHouseWL(
	    rptDate       DATE
	  , CurrencyID    INT
	  , HouseWL       MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , CurrencyID
					 , HouseWL)
		 SELECT b.rptDate
			 , b.CurrencyID
			 , -SUM(b.WinlossIBC * ex.rate) AS HouseWL
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
		 WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.bettype IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 37 )
			  AND SiteID IN
						 (
							SELECT SiteID
							FROM bodb_Account.dbo.tbl_Site
							WHERE isDeposit = 1
						 )
		 GROUP BY b.rptDate
			   , b.CurrencyID OPTION(RECOMPILE);

    UPDATE f
		 SET 
			HouseWL = f.HouseWL + house.HouseWL
    FROM #FinalResult f
	   INNER JOIN
	    (
		   SELECT CONVERT(VARCHAR(2), wl.rptDate, 106) AS winlostDate
			   , SUM(wl.HouseWL) AS HouseWL
		   FROM #TmpHouseWL AS wl
		   GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	    ) house ON house.winlostDate = f.RptDate;

      INSERT INTO #FinalResult(RptDate, HouseWL)
		 SELECT 'FullRange'
			 , SUM(f.HouseWL)			 			 
		 FROM #FinalResult AS f;

    DECLARE @SQL VARCHAR(1000)
    SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +							
							'(SELECT ''NPH'', 1, ''House Income'', HouseWL) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)


    DROP TABLE #Exchange;
    DROP TABLE #FinalResult;
    DROP TABLE #SportBettypeMatrix;
    DROP TABLE #TmpHouseWL;
END;

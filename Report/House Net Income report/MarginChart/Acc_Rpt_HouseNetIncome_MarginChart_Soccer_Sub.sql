/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub
	@FromDate     DATE
   , @ToDate       DATE
   , @isDeposit    BIT
AS
/*  	
    Created: 20190121@Robert
    Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBWH/bodb_dwrs  
   
    Revisions:		
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub '2018-04-01', '2018-04-30'
  
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

    INSERT INTO #Exchange(ExchangeDate
				    , ExchangeID
				    , Rate)
		 SELECT ExchangeDate
			 , Currency
			 , Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;
-- End region		

-- Region: Handle data of Soccer
    CREATE TABLE #FinalResult(
	    RptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , ExtraPT     MONEY
	  , TurnOver    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , HouseWL
					  , ExtraPT
					  , TurnOver)
		 SELECT 'FullRange'
			 , 0
			 , 0
			 , 0;
-- Date list to draw chart
    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);
    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, TurnOver)
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
			 (1, 0, 0, 2, '', 'SB', 0)
		 WHERE SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss');
-- House WL of Soccer + Parlay + Metrix Gaming
    CREATE TABLE #TmpHouseWL(
	    SiteId      INT
	  , rptDate     DATE
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);
    INSERT INTO #TmpHouseWL(SiteId
					 , rptDate
					 , HouseWL
					 , TurnOver
					 , ExtraPT)
		 SELECT b.SiteID
			 , b.rptDate
			 , ISNULL(-SUM(CASE
						    WHEN b.SiteID NOT IN(-2, -4)
						    THEN b.WinlossIBC + b.CommissionS
						    ELSE 0
						END * ex.rate), 0) AS HouseWL
			 , SUM(CASE
					 WHEN TurnoverIBC = 0
					 THEN 0
					 ELSE TurnoverIBC - ExtraTO
				  END * CASE
						  WHEN VarianceVR > 0
						  THEN VarianceVR + 1
						  ELSE 1
					   END * ex.Rate)
			 , SUM((ISNULL(b.ExtraWL, 0) + ISNULL(b.ExtraComm, 0)) * ex.Rate) AS ExtraPT
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			INNER JOIN #SportBettypeMatrix AS s ON b.bettype = s.Bettype -- Get all data of SB		
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND
				 (b.bettype IN(9, 29) -- Parlay
				  OR s.EventType IN(1, 2, 4)
				  AND s.SubProduct = 'MG-SuperLive' -- Metrix Gaming
				  OR s.EventType IN(1, 2, 4)
				  AND s.SubProduct <> 'MG-SuperLive'
				  AND EXISTS
						   (
							  SELECT 1
							  FROM bodb_Account.dbo.League AS l WITH (NOLOCK)
							  WHERE b.LeagueId = l.LeagueId
								   AND l.sportid = 1
						   ) -- Soccer
			  )
		 GROUP BY b.SiteID
			   , b.rptDate OPTION(RECOMPILE);

    SELECT CONVERT(VARCHAR(2), t.rptDate, 106) AS rptDate
	    , SUM(t.HouseWL) AS HouseWL
	    , SUM(t.ExtraPT) AS ExtraPT
	    , SUM(t.TurnOver) AS TurnOver
    FROM #TmpHouseWL AS t
	   LEFT JOIN bodb_Account.dbo.tbl_Site AS s WITH (NOLOCK) ON t.SiteId = s.siteid
    WHERE s.isDeposit = @IsDeposit
		OR @IsDeposit = 0
		AND t.SiteId = -2
		OR @IsDeposit = 1
		AND t.SiteId = -4
    GROUP BY isnull(s.isDeposit, 0)
		 , CONVERT(VARCHAR(2), t.rptDate, 106)
    ORDER BY CONVERT(VARCHAR(2), t.rptDate, 106);
-- Drop tmp table
    DROP TABLE #SportBettypeMatrix;
    DROP TABLE #TmpHouseWL;
    DROP TABLE #Exchange;
    DROP TABLE #FinalResult;
END;
GO

GRANT EXECUTE ON dbo.Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub TO [bodbAdminNet];

GRANT EXECUTE ON dbo.Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub TO [dwrs];
GO
/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_Monthly_Bet_Builder_AutoMail
	@RptDate    SMALLDATETIME = NULL
AS
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBRPT.bodb_Report
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]
		- 20200723@Jaden: Bet Builder - Remove hardcoding (soccer), add basketball [#138082]

	Param's Explanation:	 
*/

BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #HistoryData(
	    TransId           BIGINT
	  , MatchId           INT
	  , WinLostDate       SMALLDATETIME
	  , LeagueId          INT
	  , HomeId            INT
	  , AwayId            INT
	  , GlobalShowTime    DATETIME
	  , MarketId          VARCHAR(20)
	  , DateTimePlaced    DATETIME
	  , NoOfLegsPerBet    SMALLMONEY
	  , Betfrom           VARCHAR(1)
	  , Odds              SMALLMONEY
	  , Currency          INT
	  , Stake             MONEY
	  , StatusId          INT
	  , Payout            MONEY
	  , Commission        MONEY
	  , GrossRevenue      MONEY);

    CREATE TABLE #BetTransData(
	    TransId         BIGINT
	  , MatchId         INT
	  , WinLostDate     SMALLDATETIME
	  , Stake           MONEY
	  , StatusId        INT
	  , Payout          MONEY
	  , Commission      MONEY
	  , GrossRevenue    MONEY
	  , Transdate       DATETIME
	  , Betfrom         VARCHAR(1)
	  , Betcheck        VARCHAR(50)
	  , hdp2            SMALLMONEY
	  , Odds            SMALLMONEY
	  , Currency        INT);

    CREATE TABLE #Result(
	    TransId               BIGINT
	  , MatchId               INT
	  , SportType		  	  INT
	  , WinLostDate           SMALLDATETIME
	  , LeagueId              INT
	  , HomeId                INT
	  , AwayId                INT
	  , GlobalShowTime        DATETIME
	  , MarketId              VARCHAR(20)
	  , DateTimePlaced        DATETIME
	  , NoOfLegsPerBet        SMALLMONEY
	  , Betfrom               VARCHAR(1)
	  , Odds                  SMALLMONEY
	  , Currency              INT
	  , StakeBefore           MONEY
	  , StakeAfter            MONEY
	  , StatusIdBefore        INT
	  , StatusIdAfter         INT
	  , PayoutBefore          MONEY
	  , PayoutAfter           MONEY
	  , CommissionBefore      MONEY
	  , CommissionAfter       MONEY
	  , GrossRevenueBefore    MONEY
	  , GrossRevenueAfter     MONEY
	  , BetDescription        VARCHAR(MAX));

    DECLARE @movebetdate      DATETIME
		, @balanceupdate    DATETIME
		, @DateStart        SMALLDATETIME
		, @DateEnd          SMALLDATETIME
		, @WinlostDate      SMALLDATETIME;

    DECLARE @BetFrom TABLE(
	    Betfrom        VARCHAR(1)
	  , DeviceGroup    VARCHAR(20));


    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT
	  , Code            VARCHAR(5));

    SELECT @RptDate = ISNULL(@RptDate, CONVERT(VARCHAR(10), GETDATE(), 110))
	    , @DateEnd = DATEADD(DD, -DAY(@RptDate), @RptDate)
	    , @DateStart = DATEADD(DD, -DAY(@DateEnd) + 1, @DateEnd)
	    , @WinlostDate = @DateStart;

    INSERT INTO @BetFrom(Betfrom
				   , DeviceGroup)
		 (
			SELECT bf.BetFrom
				, bf.DeviceGroup
			FROM DBWH.bodb_account.dbo.tbl_Betfrom AS bf WITH (NOLOCK)
		 );

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate
					    , Code)
		 (
			SELECT ExchangeDate
				, ExchangeId
				, EUR
				, Code
			FROM bodb02.dbo.ExchangeDailyOanda AS o WITH (NOLOCK)
			WHERE ExchangeDate BETWEEN @DateStart AND @DateEnd
				 AND ExchangeId NOT IN(20, 27, 28, 72)
		 );

    CREATE CLUSTERED INDEX CIX_ExchangeOANDA ON #ExchangeOANDA(ExchangeDate ASC, ExchangeId ASC);

    SELECT TOP 1 @balanceupdate = winlostdate
    FROM bodb02.dbo.Bettrans WITH (NOLOCK)
    WHERE bettype = 20000
		AND matchid = 0
		AND custid = 3;

    SELECT @movebetdate = MAX(eventdate)
    FROM bodb02.dbo.match14 WITH (NOLOCK);

    INSERT INTO #HistoryData(TransId
					  , MatchId
					  , WinLostDate
					  , LeagueId
					  , HomeId
					  , AwayId
					  , GlobalShowTime
					  , MarketId
					  , DateTimePlaced
					  , NoOfLegsPerBet
					  , Betfrom
					  , Odds
					  , Currency
					  , Stake
					  , StatusId
					  , Payout
					  , Commission
					  , GrossRevenue)
		 (
			SELECT TransId
				, MatchId
				, b.WinlostDate
				, 0 AS LeagueId
				, 0 AS HomeId
				, 0 AS AwayId
				, NULL AS GlobalShowTime
				, Betcheck AS MarketId
				, NULL AS DateTimePlaced
				, Hdp2 AS NoOfLegsPerBet
				, '' AS Betfrom
				, Odds
				, CurrencyId AS Currency
				, Stake
				, StatusId
				, Winlost AS Payout
				, Scomm AS Commission
				, b.stake - b.winlost - b.scomm AS GrossRevenue
			FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail AS b WITH (NOLOCK)
			WHERE b.WinlostDate BETWEEN @DateStart AND @DateEnd
		 );

    CREATE CLUSTERED INDEX CIX_HistoryData_TransId ON #HistoryData(TransId ASC);

    WHILE @WinlostDate <= @DateEnd
	   BEGIN
		  IF @WinlostDate > @movebetdate --bettrans
			 BEGIN
				INSERT INTO #BetTransData(TransId
								    , MatchId
								    , WinLostDate
								    , Stake
								    , StatusId
								    , Payout
								    , Commission
								    , GrossRevenue
								    , Transdate
								    , Betfrom
								    , Betcheck
								    , hdp2
								    , Odds
								    , Currency)
					  (
						 SELECT TransId
							 , matchid
							 , WinLostDate
							 , Stake
							 , StatusId
							 , b.winlost AS Payout
							 , b.scomm AS Commission
							 , b.stake - b.winlost - b.scomm AS GrossRevenue
							 , b.transdate
							 , b.betfrom
							 , b.betcheck
							 , b.hdp2
							 , b.odds
							 , b.currency
						 FROM bodb02.dbo.bettrans AS b WITH (NOLOCK)
						 WHERE b.winlostdate = @WinlostDate
							  AND bettype = 38
							  AND b.statusID IN(112, 113, 111, 102, 103)
					  );
			 END;
		  IF @WinlostDate BETWEEN @balanceupdate AND @movebetdate --bettrans_14
			 BEGIN
				INSERT INTO #BetTransData(TransId
								    , MatchId
								    , WinLostDate
								    , Stake
								    , StatusId
								    , Payout
								    , Commission
								    , GrossRevenue
								    , Transdate
								    , Betfrom
								    , Betcheck
								    , hdp2
								    , Odds
								    , Currency)
					  (
						 SELECT TransId
							 , matchid
							 , WinLostDate
							 , Stake
							 , StatusId
							 , b.winlost AS Payout
							 , b.scomm AS Commission
							 , b.stake - b.winlost - b.scomm AS GrossRevenue
							 , b.transdate
							 , b.betfrom
							 , b.betcheck
							 , b.hdp2
							 , b.odds
							 , b.currency
						 FROM bodb02.dbo.bettrans14 AS b WITH (NOLOCK)
						 WHERE b.winlostdate = @WinlostDate
							  AND bettype = 38
					  );
			 END;
		  IF @WinlostDate < @balanceupdate --bettrans_bk
			 BEGIN
				INSERT INTO #BetTransData(TransId
								    , MatchId
								    , WinLostDate
								    , Stake
								    , StatusId
								    , Payout
								    , Commission
								    , GrossRevenue
								    , Transdate
								    , Betfrom
								    , Betcheck
								    , hdp2
								    , Odds
								    , Currency)
					  (
						 SELECT TransId
							 , matchid
							 , WinLostDate
							 , Stake
							 , StatusId
							 , b.winlost AS Payout
							 , b.scomm AS Commission
							 , b.stake - b.winlost - b.scomm AS GrossRevenue
							 , b.transdate
							 , b.betfrom
							 , b.betcheck
							 , b.hdp2
							 , b.odds
							 , b.currency
						 FROM bodb_Archive.dbo.bettrans_bk AS b WITH (NOLOCK)
						 WHERE b.winlostdate = @WinlostDate
							  AND bettype = 38
					  );
			 END;
		  SELECT @WinlostDate = DATEADD(DD, 1, @WinlostDate);
	   END;

    CREATE CLUSTERED INDEX CIX_BetTransData_TransId_StatusId ON #BetTransData(TransId ASC, StatusId ASC);
-- case 1: same ticket but difference values
    INSERT INTO #Result(TransId
				  , MatchId
				  , WinLostDate
				  , StakeBefore
				  , StakeAfter
				  , StatusIdBefore
				  , StatusIdAfter
				  , PayoutBefore
				  , PayoutAfter
				  , CommissionBefore
				  , CommissionAfter
				  , GrossRevenueBefore
				  , GrossRevenueAfter
				  , DateTimePlaced
				  , Betfrom
				  , MarketId
				  , NoOfLegsPerBet
				  , Odds
				  , Currency)
		 (
			SELECT b.TransId
				, b.MatchId
				, b.WinLostDate
				, h.Stake AS StakeBefore
				, b.Stake AS StakeAfter
				, h.StatusId AS StatusIdBefore
				, b.StatusId AS StatusIdAfter
				, h.Payout AS PayoutBefore
				, b.Payout AS PayoutAfter
				, h.Commission AS CommissionBefore
				, b.Commission AS CommissionAfter
				, h.GrossRevenue AS GrossRevenueBefore
				, b.GrossRevenue AS GrossRevenueAfter
				, b.Transdate AS DateTimePlaced
				, b.Betfrom
				, b.Betcheck AS MarketId
				, b.hdp2 AS NoOfLegsPerBet
				, b.Odds
				, b.Currency
			FROM #BetTransData AS b
			    INNER JOIN #HistoryData AS h ON b.TransId = h.TransId
			WHERE b.Stake <> h.Stake
				 OR b.StatusId <> h.StatusId
				 OR b.Payout <> h.Payout
				 OR b.Commission <> h.Commission
		 );
-- case 2: existing in #BetTransData but not in #HistoryData, just for WON, LOSE, DRAW
    INSERT INTO #Result(TransId
				  , MatchId
				  , WinLostDate
				  , StakeBefore
				  , StakeAfter
				  , StatusIdBefore
				  , StatusIdAfter
				  , PayoutBefore
				  , PayoutAfter
				  , CommissionBefore
				  , CommissionAfter
				  , GrossRevenueBefore
				  , GrossRevenueAfter
				  , DateTimePlaced
				  , Betfrom
				  , MarketId
				  , NoOfLegsPerBet
				  , Odds
				  , Currency)
		 (
			SELECT b.TransId
				, b.MatchId
				, b.WinLostDate
				, h.Stake AS StakeBefore
				, b.Stake AS StakeAfter
				, h.StatusId AS StatusIdBefore
				, b.StatusId AS StatusIdAfter
				, h.Payout AS PayoutBefore
				, b.Payout AS PayoutAfter
				, h.Commission AS CommissionBefore
				, b.Commission AS CommissionAfter
				, h.GrossRevenue AS GrossRevenueBefore
				, b.GrossRevenue AS GrossRevenueAfter
				, b.Transdate AS DateTimePlaced
				, b.Betfrom
				, b.Betcheck AS MarketId
				, b.hdp2 AS NoOfLegsPerBet
				, b.Odds
				, b.Currency
			FROM #BetTransData AS b
			    LEFT JOIN #HistoryData AS h ON b.TransId = h.TransId
			WHERE h.TransId IS NULL
				 AND b.StatusId IN(112, 113, 111)
		 );


    CREATE CLUSTERED INDEX CIX_Result_Betfrom_Currency_WinLostDate ON #Result(Betfrom ASC, Currency ASC, WinLostDate ASC, MatchId ASC);

    SELECT @WinlostDate = @DateStart;
    WHILE @WinlostDate <= @DateEnd
	   BEGIN
		  IF @WinlostDate > @movebetdate
			 BEGIN
				UPDATE d
					  SET
						 d.LeagueId = m.leagueid
					    , d.HomeId = m.homeid
					    , d.AwayId = m.awayid
						, d.SportType = m.sporttype
					    , d.GlobalShowTime = m.GlobalShowTime
					    , d.BetDescription =
						 (
							SELECT Selection
							FROM f_BetBuilder_GetSelectionName
								(d.MarketId, @WinlostDate)
						 )
				FROM #Result AS d
				    INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON m.matchid = d.matchid
				WHERE d.winlostdate = @WinlostDate;
			 END;

		  IF @WinlostDate <= @movebetdate
			 BEGIN
				UPDATE d
					  SET
						 d.LeagueId = m.leagueid
					    , d.HomeId = m.homeid
					    , d.AwayId = m.awayid
						, d.SportType = m.sporttype
					    , d.GlobalShowTime = m.GlobalShowTime
					    , d.BetDescription =
						 (
							SELECT Selection
							FROM f_BetBuilder_GetSelectionName
								(d.MarketId, @WinlostDate)
						 )
				FROM #Result AS d
				    INNER JOIN bodb02.dbo.match14 AS m WITH (NOLOCK) ON m.matchid = d.matchid
				WHERE d.winlostdate = @WinlostDate;
			 END;

		  IF @WinlostDate < @balanceupdate
			 BEGIN
				UPDATE d
					  SET
						 d.LeagueId = m.leagueid
					    , d.HomeId = m.homeid
					    , d.AwayId = m.awayid
						, d.SportType = m.sporttype
					    , d.GlobalShowTime = m.GlobalShowTime
					    , d.BetDescription =
						 (
							SELECT Selection
							FROM f_BetBuilder_GetSelectionName
								(d.MarketId, @WinlostDate)
						 )
				FROM #Result AS d
				    INNER JOIN bodb_Archive.dbo.match_bk AS m WITH (NOLOCK) ON m.matchid = d.matchid
				WHERE d.winlostdate = @WinlostDate;
			 END;
		  SELECT @WinlostDate = DATEADD(DD, 1, @WinlostDate);
	   END;


    SELECT (SELECT SportName FROM bodb02.dbo.Sports WHERE SportType = d.SportType) AS Sport
	    , d.LeagueId
	    , d.HomeId
	    , d.AwayId
	    , d.GlobalShowTime
	    , d.MarketId
	    , d.DateTimePlaced
	    , d.WinLostDate
	    , d.TransId
	    , d.BetDescription
	    , d.NoOfLegsPerBet
	    , 'Settled' AS BetStatus
	    , bf.DeviceGroup
	    , d.Odds AS BetPrice
	    , e.Code
	    , d.StakeBefore
	    , d.StakeAfter
	    , CASE
			WHEN d.StatusIdBefore = 112
			THEN 'Won'
			WHEN d.StatusIdBefore = 113
			THEN 'Lose'
			WHEN d.StatusIdBefore = 111
			THEN 'Draw'
			WHEN d.StatusIdBefore = 102
			THEN 'Void'
			WHEN d.StatusIdBefore = 103
			THEN 'Refund'
		 END AS ResultBefore
	    , CASE
			WHEN d.StatusIdAfter = 112
			THEN 'Won'
			WHEN d.StatusIdAfter = 113
			THEN 'Lose'
			WHEN d.StatusIdAfter = 111
			THEN 'Draw'
			WHEN d.StatusIdAfter = 102
			THEN 'Void'
			WHEN d.StatusIdAfter = 103
			THEN 'Refund'
		 END AS ResultAfter
	    , d.PayoutBefore
	    , d.PayoutAfter
	    , d.CommissionBefore
	    , d.CommissionAfter
	    , d.GrossRevenueBefore
	    , d.GrossRevenueAfter
    FROM #Result AS d
	   INNER JOIN @BetFrom AS bf ON d.Betfrom = bf.betfrom
	   INNER JOIN #ExchangeOANDA AS e ON d.Currency = e.ExchangeID
								  AND d.WinLostDate = e.ExchangeDate;

    DROP TABLE #HistoryData;
    DROP TABLE #BetTransData;
    DROP TABLE #Result;
    DROP TABLE #ExchangeOANDA;
END;
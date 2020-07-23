/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_Daily_Bet_Builder_AutoMail
	@WinlostDate    SMALLDATETIME = NULL
AS
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBRPT.bodb_Report
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]

	Param's Explanation:	 
*/

BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Data(
	    TransId           BIGINT
	  , MatchId           INT
	  , LeagueId          INT
	  , HomeId            INT
	  , AwayId            INT
	  , SportType		  INT
	  , GlobalShowTime    DATETIME
	  , MarketId          VARCHAR(20)
	  , DateTimePlaced    DATETIME
	  , WinLostDate       SMALLDATETIME
	  , NoOfLegsPerBet    SMALLMONEY
	  , Betfrom           VARCHAR(1)
	  , Odds              SMALLMONEY
	  , Currency          INT
	  , Stake             MONEY
	  , StatusId          INT
	  , Payout            MONEY
	  , Commission        MONEY
	  , GrossRevenue      MONEY);

    DECLARE @movebetdate      DATETIME
		, @balanceupdate    DATETIME
		, @CapturedDate DATETIME= CONVERT(VARCHAR(10), GETDATE(), 110);

    DECLARE @BetFrom TABLE(
	    Betfrom        VARCHAR(1)
	  , DeviceGroup    VARCHAR(20));

    DECLARE @ExchangeOANDA TABLE(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT
	  , Code            VARCHAR(5));

    INSERT INTO @BetFrom(Betfrom
				   , DeviceGroup)
		 (
			SELECT bf.BetFrom
				, bf.DeviceGroup
			FROM DBWH.bodb_account.dbo.tbl_Betfrom AS bf WITH (NOLOCK)
		 );

    INSERT INTO @ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate
					    , Code)
		 (
			SELECT ExchangeDate
				, ExchangeId
				, EUR
				, Code
			FROM bodb02.dbo.ExchangeDailyOanda AS o WITH (NOLOCK)
			WHERE ExchangeDate = @WinlostDate
				 AND ExchangeId NOT IN(20, 27, 28, 72)
		 );

    SELECT TOP 1 @balanceupdate = winlostdate
    FROM bodb02.dbo.Bettrans WITH (NOLOCK)
    WHERE bettype = 20000
		AND matchid = 0
		AND custid = 3;

    SELECT @movebetdate = MAX(eventdate)
    FROM bodb02.dbo.match14 WITH (NOLOCK);

    IF @WinlostDate IS NULL
	   SELECT @WinlostDate = CONVERT(VARCHAR(10), DATEADD(DAY, -1, GETDATE()), 110);

    INSERT INTO #Data(TransId
				, MatchId
				, LeagueId
				, HomeId
				, AwayId
				, SportType
				, GlobalShowTime
				, MarketId
				, DateTimePlaced
				, WinLostDate
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
				, 0 AS LeagueId
				, 0 AS HomeId
				, 0 AS AwayId
				, NULL AS SportType
				, NULL AS GlobalShowTime
				, Betcheck AS MarketId
				, Transdate AS DateTimePlaced
				, WinlostDate
				, Hdp2 AS NoOfLegsPerBet
				, Betfrom
				, Odds
				, CurrencyId AS Currency
				, Stake
				, StatusId
				, Winlost AS Payout
				, Scomm AS Commission
				, b.stake - b.winlost - b.scomm AS GrossRevenue
			FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail AS b WITH (NOLOCK)
			WHERE b.WinlostDate = @WinlostDate
		 );

    CREATE CLUSTERED INDEX CIX_MatchId ON #Data(MatchId ASC);

    IF @WinlostDate > @movebetdate
	   BEGIN
		  UPDATE d
			    SET
				   d.LeagueId = m.leagueid
				 , d.HomeId = m.homeid
				 , d.AwayId = m.awayid
				 , d.SportType = m.sporttype
				 , d.GlobalShowTime = m.GlobalShowTime
		  FROM #Data AS d
			 INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON m.matchid = d.matchid;
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
		  FROM #Data AS d
			 INNER JOIN bodb02.dbo.match14 AS m WITH (NOLOCK) ON m.matchid = d.matchid;
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
		  FROM #Data AS d
			 INNER JOIN bodb_Archive.dbo.match_bk AS m WITH (NOLOCK) ON m.matchid = d.matchid;
	   END;
    SELECT (SELECT SportName FROM bodb02.dbo.Sports WHERE SportType = d.SportType) AS Sport
	    , d.LeagueId
	    , d.HomeId
	    , d.AwayId
	    , d.GlobalShowTime
	    , d.MarketId
	    , d.DateTimePlaced
	    ,
		 (
			SELECT Selection
			FROM f_BetBuilder_GetSelectionName
				(d.MarketId, @WinlostDate)
		 ) AS BetDescription
	    , d.NoOfLegsPerBet
	    , 'Settled' AS BetStatus
	    , bf.DeviceGroup
	    , d.Odds AS BetPrice
	    , e.Code
	    , d.Stake
	    , CASE
			WHEN d.StatusId = 112
			THEN 'WON'
			WHEN d.StatusId = 113
			THEN 'LOSE'
			WHEN d.StatusId = 111
			THEN 'DRAW'
		 END AS Result
	    , d.Payout
	    , d.Commission
	    , d.GrossRevenue
    FROM #Data AS d
	   INNER JOIN @BetFrom AS bf ON d.Betfrom = bf.betfrom
	   INNER JOIN @ExchangeOANDA AS e ON d.Currency = e.ExchangeID
    UNION ALL
    SELECT '' AS Sport
	    , 0 AS LeagueId
	    , 0 AS HomeId
	    , 0 AS AwayId
	    , NULL AS GlobalShowTime
	    , '' AS MarketId
	    , NULL AS DateTimePlaced
	    , '' AS BetDescription
	    , NULL AS NoOfLegsPerBet
	    , '' AS BetStatus
	    , 'Grand Total in EUR' AS DeviceGroup
	    , NULL AS BetPrice
	    , 'EUR' AS Code
	    , SUM(d.Stake * e.Rate) AS Stake
	    , '' AS Result
	    , SUM(d.Payout * e.Rate) AS Payout
	    , SUM(d.Commission * e.Rate) AS Commission
	    , SUM(d.GrossRevenue * e.Rate) AS GrossRevenue
    FROM #Data AS d
	   INNER JOIN @ExchangeOANDA AS e ON d.Currency = e.ExchangeID;

    DROP TABLE #Data;
END;
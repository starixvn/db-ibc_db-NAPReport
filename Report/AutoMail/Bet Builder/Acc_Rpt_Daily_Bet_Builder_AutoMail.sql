/*<info serverAlias="DBRPT-bodb_Report" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_Report
GO

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
		- 20200723@Jaden: Bet Builder - Remove hardcoding (soccer), add basketball [#138082]
		- 20210504@Jaden: Use SP to get balanceup & movebets (#154116)
		- 20220110@Roy: Automail Report - Tune sp performance of Bet Builder repo (#167198)
		- 20220907@Jaden: Change betfrom datatype (#177202)
		- 20240816@Jaden: Add Live Status (#209221)
		- 20250505@Jaden: Add GrossRevenue_EUR column (#226017)

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
	  , LiveStatus        TINYINT
	  , Betfrom           NVARCHAR(5)
	  , Odds              SMALLMONEY
	  , Currency          INT
	  , Stake             MONEY
	  , StatusId          INT
	  , Payout            MONEY
	  , Commission        MONEY
	  , GrossRevenue      MONEY);
	
	CREATE TABLE #tmpBetDesc (
		MarketId VARCHAR(20)
		,SelectionName VARCHAR(210)
	)
	
    DECLARE @movebetdate      DATETIME
		, @balanceupdate    DATETIME

    DECLARE @BetFrom TABLE(
	    Betfrom        NVARCHAR(5)
	  , DeviceGroup    VARCHAR(20));

    DECLARE @ExchangeOANDA TABLE(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT
	  , Code            VARCHAR(12));

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

	SELECT @balanceupdate = BalanceUpDay, @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

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
			OPTION (RECOMPILE)

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

		  UPDATE #Data
		  SET LiveStatus = b.liveindicator
		  FROM bodb02.dbo.bettrans b WITH (NOLOCK)
		  WHERE b.TransId = #Data.TransId
	   END;

    IF @WinlostDate BETWEEN @balanceupdate AND @movebetdate
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

		  UPDATE #Data
		  SET LiveStatus = b.liveindicator
		  FROM bodb02.dbo.bettrans14 b WITH (NOLOCK)
		  WHERE b.TransId = #Data.TransId
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

		  UPDATE #Data
		  SET LiveStatus = b.liveindicator
		  FROM bodb_Archive.dbo.bettrans_bk b WITH (NOLOCK)
		  WHERE b.TransId = #Data.TransId
	   END;
	   
	--Get BetDescription - replace f_BetBuilder_GetSelectionName by temp table
	IF @WinlostDate > @movebetdate --range bettrans
	BEGIN
		;WITH CTE_Market AS (
			SELECT DISTINCT MatchId
				,MarketId
			FROM #Data
		)
		INSERT INTO #tmpBetDesc (
			MarketId
			,SelectionName
		)
		SELECT s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb02.dbo.SMP_MarketSelection AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)
	END
	
	ELSE IF @WinlostDate BETWEEN @balanceupdate AND @movebetdate --range bettrans14
	BEGIN
		;WITH CTE_Market AS (
			SELECT DISTINCT MatchId
				,MarketId
			FROM #Data
		)
		INSERT INTO #tmpBetDesc (
			MarketId
			,SelectionName
		)
		SELECT s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb02.dbo.SMP_MarketSelection14 AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)
	END
	
	ELSE --range bettrans_bk
	BEGIN
		;WITH CTE_Market AS (
			SELECT DISTINCT MatchId
				,MarketId
			FROM #Data
		)
		INSERT INTO #tmpBetDesc (
			MarketId
			,SelectionName
		)
		SELECT s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb_Archive.dbo.SMP_MarketSelection_bk AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)
	END
	
	;WITH CTE_BetDesc AS (
		SELECT MarketId
			,BetDesc = STUFF((
					SELECT '; ' + SelectionName
					FROM #tmpBetDesc AS t1 WITH (NOLOCK)
					WHERE t1.MarketId = t2.MarketId
					ORDER BY t1.SelectionName
					FOR XML PATH('')
					), 1, 2, '')
		FROM #tmpBetDesc AS t2 WITH (NOLOCK)
		GROUP BY MarketId
	)
    SELECT s.SportName AS Sport
	    , d.LeagueId
	    , d.HomeId
	    , d.AwayId
	    , d.GlobalShowTime
	    , d.MarketId
	    , d.DateTimePlaced
	    , bd.BetDesc AS BetDescription
	    , d.NoOfLegsPerBet
		, CASE d.LiveStatus WHEN 1 THEN 'Live' WHEN 0 THEN 'Non-Live' ELSE 'Mixed' END AS LiveStatus
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
		, d.GrossRevenue * e.Rate AS GrossRevenue_EUR
    FROM #Data AS d
	   INNER JOIN @BetFrom AS bf ON d.Betfrom = bf.betfrom
	   INNER JOIN @ExchangeOANDA AS e ON d.Currency = e.ExchangeID
	   LEFT JOIN bodb02.dbo.Sports AS s WITH (NOLOCK) ON s.SportType = d.SportType
	   LEFT JOIN CTE_BetDesc AS bd ON d.MarketId = bd.MarketId
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
		, NULL AS LiveStatus
	    , '' AS BetStatus
	    , 'Grand Total in EUR' AS DeviceGroup
	    , NULL AS BetPrice
	    , 'EUR' AS Code
	    , SUM(d.Stake * e.Rate) AS Stake
	    , '' AS Result
	    , SUM(d.Payout * e.Rate) AS Payout
	    , SUM(d.Commission * e.Rate) AS Commission
	    , SUM(d.GrossRevenue * e.Rate) AS GrossRevenue
	    , SUM(d.GrossRevenue * e.Rate) AS GrossRevenue_EUR
    FROM #Data AS d
	   INNER JOIN @ExchangeOANDA AS e ON d.Currency = e.ExchangeID;

    DROP TABLE #Data;
	DROP TABLE #tmpBetDesc;
END;
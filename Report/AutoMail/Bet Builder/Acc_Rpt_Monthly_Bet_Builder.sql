/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_Report
GO

ALTER PROCEDURE dbo.Acc_Rpt_Monthly_Bet_Builder
	@FromDate    SMALLDATETIME
   , @ToDate      SMALLDATETIME
AS
/*
	Creator: Cherry
	Date: 2020-02-10
	DB: DBRPT.bodb_Report
	Task: Bet Builder - Monthly Automail report 
	Revisions:		
		20200210@Cherry: Initial (#128002)
		20210504@Jaden: Use SP to get balanceup & movebets (#154116)
		20220110@Roy: Automail Report - Tune sp performance of Bet Builder repo (#167198)

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
		
		CREATE TABLE #tmpBetDesc (
			WinLostDate SMALLDATETIME
			,MarketId VARCHAR(20)
			,SelectionName VARCHAR(210)
		)

	   DECLARE @movebetdate      SMALLDATETIME
		    , @balanceupdate    SMALLDATETIME

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
			    SELECT ExchangeDate
				    , ExchangeId
				    , EUR
				    , Code
			    FROM bodb02.dbo.ExchangeDailyOanda AS o WITH (NOLOCK)
			    WHERE ExchangeDate BETWEEN @FromDate AND @ToDate
					AND ExchangeId NOT IN(20, 27, 28, 72)
				OPTION (RECOMPILE)

		SELECT @balanceupdate = BalanceUpDay, @movebetdate = MoveBetsDay
		FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	   INSERT INTO #Data(TransId
				    , MatchId
				    , LeagueId
				    , HomeId
				    , AwayId
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
			    FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail AS b WITH(NOLOCK)
			    WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
				OPTION (RECOMPILE)

	   CREATE CLUSTERED INDEX CIX_MatchId ON #Data(WinLostDate, MatchId);

		UPDATE d
		SET d.LeagueId = m.leagueid
			,d.HomeId = m.homeid
			,d.AwayId = m.awayid
			,d.GlobalShowTime = m.GlobalShowTime
		FROM #Data AS d
		INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON m.matchid = d.matchid
		WHERE d.WinLostDate > @movebetdate
		OPTION (RECOMPILE)


		UPDATE d
		SET d.LeagueId = m.leagueid
			,d.HomeId = m.homeid
			,d.AwayId = m.awayid
			,d.GlobalShowTime = m.GlobalShowTime
		FROM #Data AS d
		INNER JOIN bodb02.dbo.match14 AS m WITH (NOLOCK) ON m.matchid = d.matchid
		WHERE d.WinLostDate BETWEEN @balanceupdate AND @movebetdate
		OPTION (RECOMPILE)

		UPDATE d
		SET d.LeagueId = m.leagueid
			,d.HomeId = m.homeid
			,d.AwayId = m.awayid
			,d.GlobalShowTime = m.GlobalShowTime
		FROM #Data AS d
		INNER JOIN bodb_Archive.dbo.match_bk AS m WITH (NOLOCK) ON m.matchid = d.matchid
		WHERE d.WinLostDate < @balanceupdate
		OPTION (RECOMPILE)
	   
	   --Get BetDescription - replace f_BetBuilder_GetSelectionName by temp table
	   --range bettrans
		;WITH CTE_Market AS (
			SELECT DISTINCT WinLostDate
				,MatchId
				,MarketId
			FROM #Data
			WHERE WinLostDate > @movebetdate
		)
		INSERT INTO #tmpBetDesc (
			WinLostDate
			,MarketId
			,SelectionName
		)
		SELECT b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb02.dbo.SMP_MarketSelection AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)
		
		--range bettrans14
		;WITH CTE_Market AS (
			SELECT DISTINCT WinLostDate
				,MatchId
				,MarketId
			FROM #Data
			WHERE WinLostDate BETWEEN @balanceupdate AND @movebetdate
		)
		INSERT INTO #tmpBetDesc (
			WinLostDate
			,MarketId
			,SelectionName
		)
		SELECT b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb02.dbo.SMP_MarketSelection14 AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)
		
		--range bettrans_bk
		;WITH CTE_Market AS (
			SELECT DISTINCT WinLostDate
				,MatchId
				,MarketId
			FROM #Data
			WHERE WinLostDate < @balanceupdate
		)
		INSERT INTO #tmpBetDesc (
			WinLostDate
			,MarketId
			,SelectionName
		)
		SELECT b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		FROM CTE_Market AS b
			INNER JOIN bodb_Archive.dbo.SMP_MarketSelection_bk AS s1 WITH (NOLOCK) ON b.MatchId = s1.MatchId AND b.MarketId = s1.MarketId
			INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		GROUP BY b.WinLostDate
			,s1.MarketId
			,s2.SelectionName
		OPTION (RECOMPILE)

		;WITH CTE_BetDesc AS (
			SELECT WinLostDate
				,MarketId
				,BetDesc = STUFF((
						SELECT '; ' + SelectionName
						FROM #tmpBetDesc AS t1 WITH (NOLOCK)
						WHERE t1.WinLostDate = t2.WinLostDate
							AND t1.MarketId = t2.MarketId
						ORDER BY t1.SelectionName
						FOR XML PATH('')
						), 1, 2, '')
			FROM #tmpBetDesc AS t2 WITH (NOLOCK)
			GROUP BY WinLostDate
				,MarketId
		)
		SELECT 'Soccer' AS Sport
		   , l.leaguename
		   , h.teamname + ' vs ' + a.teamname AS Match
		   , d.GlobalShowTime
		   , d.MarketId
		   , d.DateTimePlaced
		   , bd.BetDesc AS BetDescription
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
									 AND d.WinLostDate = e.ExchangeDate
		  LEFT JOIN bodb02.dbo.league AS l WITH(NOLOCK) ON d.LeagueId = l.leagueid
		  LEFT JOIN bodb02.dbo.Team AS h WITH(NOLOCK) ON h.teamid = d.HomeId
		  LEFT JOIN bodb02.dbo.Team AS a WITH(NOLOCK) ON a.teamid = d.AwayId
		  LEFT JOIN CTE_BetDesc AS bd ON d.WinLostDate = bd.WinLostDate AND d.MarketId = bd.MarketId
		UNION ALL
		SELECT '' AS Sport
		   , '' AS leaguename
		   , '' AS Match
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
		  INNER JOIN @ExchangeOANDA AS e ON d.Currency = e.ExchangeID
									 AND d.WinLostDate = e.ExchangeDate
		OPTION (RECOMPILE)

	   DROP TABLE #Data;
	   DROP TABLE #tmpBetDesc

    END;

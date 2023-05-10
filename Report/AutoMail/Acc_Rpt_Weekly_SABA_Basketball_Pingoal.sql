/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_Weekly_SABA_Basketball_Pingoal
    @Fromdate SMALLDATETIME = '20230403'
  , @Todate   SMALLDATETIME = '20230409'
AS
    /*
	 Created: 20230411@Jaden
	 Task: #186711 - SAS - Create Auto Report - Weekly Saba Basketball PinGoal - Irene
	 DB: DB061.BODB02
	 
	 Revisions:
	 - 20230411@Jaden: Init
   - 20230510@Jaden: Add draw, non-live
	 */
BEGIN

    CREATE TABLE #BU (BalanceUpDay DATE, MovebetsDay DATE)
    INSERT INTO #bu (BalanceUpDay, MovebetsDay)
    EXEC bodb02.dbo.Age_SelBalanceUpDay


    DECLARE @MovebetsDay SMALLDATETIME
    SELECT @MovebetsDay = (SELECT MovebetsDay FROM #BU)

    CREATE TABLE #league (leagueid INT, leaguename NVARCHAR(1000))

    INSERT INTO #league
    SELECT leagueid
         , leaguename
      FROM bodb02..league WITH (nolock)
     WHERE LeagueGroupid =122 AND isTest <> 1

    CREATE TABLE #data_basketball
    (
        rptdate       DATE
      , transdate     DATETIME
      , transid       BIGINT
      , liveindicator INT
      , bettype       INT
      , betteam       NVARCHAR(10)
      , custid        BIGINT
      , sporttype     BIGINT
      , homeid        INT
      , awayid        INT
      , leagueid      BIGINT
      , betcount      INT
      , memberTO      MONEY
      , memberWL      MONEY
      , realTO        MONEY
      , realWL        MONEY
      , statusid      INT
      , odds          SMALLMONEY
      , oddstype      MONEY
      , betfrom       NVARCHAR(10)
      , currency      INT
    )


    --bettrans data-------------------------------------------------------------------------------------------------------------------------------------------------
    INSERT INTO #data_basketball
    SELECT winlostdate
         , transdate
         , transid
         , liveindicator
         , bettype
         , betteam
         , mc.custid
         , m.sporttype
         , m.homeid
         , m.awayid
         , m.leagueid
         , 1                                                                                     AS [betcount]
         , ABS(stake) * mc.actualrate
         , (winlost - actual_stake) * mc.actualrate
         , (ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking, 0))
            * CASE WHEN mc.virtualrate > actualrate THEN mc.virtualrate ELSE actualrate END)     RealTO
         , - (((winlost - actual_stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking, 0))
               + (Scomm - CASE WHEN tpositiontaking = 1 THEN 0
                               ELSE Scomm / (1 - tpositiontaking) * ISNULL(mc.epositiontaking, 0)
                          END)) * actualrate * CASE WHEN recommend IN (52466) THEN 0 ELSE 1 END) RealWL
         , mc.statusid
         , mc.odds
         , mc.oddstype
         , betfrom
         , currency
      FROM bodb02.dbo.bettrans   mc WITH (nolock)
     INNER JOIN bodb02.dbo.match m WITH (nolock)
        ON mc.matchid = m.matchid AND m.sporttype = 2
     WHERE winlostdate > @MovebetsDay
       AND winlostdate <= @Todate
       AND mc.statusid IN (111,112,113)
       AND mc.currency <> 20
       AND m.leagueid IN (SELECT leagueid FROM #league)
    OPTION (RECOMPILE)

    --Bettrans14 data-------------------------------------------------------------------------------------------------------------------------------------------------

    INSERT INTO #data_basketball
    SELECT winlostdate
         , transdate
         , transid
         , liveindicator
         , bettype
         , betteam
         , mc.custid
         , m.sporttype
         , m.homeid
         , m.awayid
         , m.leagueid
         , 1                                                                                     AS [betcount]
         , ABS(stake) * mc.actualrate
         , (winlost - actual_stake) * mc.actualrate
         , (ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking, 0))
            * CASE WHEN mc.virtualrate > actualrate THEN mc.virtualrate ELSE actualrate END)     RealTO
         , - (((winlost - actual_stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking, 0))
               + (Scomm - CASE WHEN tpositiontaking = 1 THEN 0
                               ELSE Scomm / (1 - tpositiontaking) * ISNULL(mc.epositiontaking, 0)
                          END)) * actualrate * CASE WHEN recommend IN (52466) THEN 0 ELSE 1 END) RealWL
         , mc.statusid
         , mc.odds
         , mc.oddstype
         , betfrom
         , currency
      FROM bodb02.dbo.bettrans14   mc WITH (nolock)
     INNER JOIN bodb02.dbo.match14 m WITH (nolock)
        ON mc.matchid = m.matchid AND m.sporttype = 2
     WHERE winlostdate >= @Fromdate
       AND winlostdate <= @MovebetsDay
       AND mc.statusid IN (111,112,113)
       AND mc.currency <> 20
       AND m.leagueid IN (SELECT leagueid FROM #league)
    OPTION (RECOMPILE)


    --Select data------------------------------------------------------------------------------------------------------------------------------

    SELECT cast(rptDate AS DATE)                                                                    'Winlossdate'
         , CASE
			     	WHEN liveindicator=1 THEN 'Live'
			     	WHEN liveindicator=0 THEN 'Non-Live'
			     	ELSE 'Live&Non-live' 
			     END [Live Status]
         , l.leaguename
         , ISNULL(t1.teamname + ' vs ' + t2.teamname, 'Combine Parlay Match')                       [Match]
         , bt.typenamee                                                                             'Bettype'
         , CASE WHEN b.bettype IN (1, 7, 17, 20, 21) THEN
                    CASE WHEN betteam = 'h' THEN 'Home' WHEN betteam = 'a' THEN 'Away' ELSE betteam END
                WHEN b.bettype IN (2, 12, 184) THEN
                    CASE WHEN betteam = 'h' THEN 'Odd' WHEN betteam = 'a' THEN 'Even' END
                WHEN b.bettype IN (3, 8, 18) THEN
                    CASE WHEN betteam = 'h' THEN 'Over' WHEN betteam = 'a' THEN 'Under' END
                ELSE betteam
           END                                                                                      [Bet Choice]
         , CASE WHEN b.oddstype = 1 THEN odds + 1 WHEN b.oddstype = 5 THEN odds * 100 ELSE odds END [odds]
         , CASE WHEN b.oddstype = 1 THEN 'Dec'
                WHEN b.oddstype = 2 THEN 'HK'
                WHEN b.oddstype = 3 THEN 'Indo'
                WHEN b.oddstype = 4 THEN 'MY'
                WHEN b.oddstype = 5 THEN 'US'
           END                                                                                      [Odd Type]
         , CASE WHEN statusid = 112 THEN 'Won' WHEN statusid = 113 THEN 'Lose' ELSE 'Draw' END                  [status]  
         , COUNT(transid)                                                                           [Betcount]
         , SUM(b.memberTO)                                                                          memberTO
         , SUM(b.memberWL)                                                                          memberWL
         , SUM(b.realTO)                                                                            [Company Real Turnover]
         , SUM(b.realWL)                                                                            [Company Real Winloss]
      FROM #data_basketball         b WITH (NOLOCK)
      LEFT JOIN bodb02.dbo.Sports   s WITH (nolock)
        ON s.SportType = b.sporttype
      LEFT JOIN bodb02.dbo.bettype  bt WITH (nolock)
        ON bt.typeid = b.bettype
      LEFT JOIN bodb02.dbo.exchange e WITH (nolock)
        ON b.currency = e.exchangeid
      LEFT JOIN bodb02.dbo.league   l WITH (nolock)
        ON l.leagueid = b.leagueid
      LEFT JOIN bodb02.dbo.team     t1 WITH (nolock)
        ON b.homeid = t1.teamid
      LEFT JOIN bodb02.dbo.team     t2 WITH (nolock)
        ON b.awayid = t2.teamid
     GROUP BY cast(rptDate AS DATE)
            , l.leaguename
            , ISNULL(t1.teamname + ' vs ' + t2.teamname, 'Combine Parlay Match')
            , bt.typenamee
            , CASE WHEN b.bettype IN (1, 7, 17, 20, 21) THEN
                       CASE WHEN betteam = 'h' THEN 'Home' WHEN betteam = 'a' THEN 'Away' ELSE betteam END
                   WHEN b.bettype IN (2, 12, 184) THEN
                       CASE WHEN betteam = 'h' THEN 'Odd' WHEN betteam = 'a' THEN 'Even' END
                   WHEN b.bettype IN (3, 8, 18) THEN
                       CASE WHEN betteam = 'h' THEN 'Over' WHEN betteam = 'a' THEN 'Under' END
                   ELSE betteam
              END
            , CASE WHEN b.oddstype = 1 THEN odds + 1 WHEN b.oddstype = 5 THEN odds * 100 ELSE odds END
            , CASE WHEN b.oddstype = 1 THEN 'Dec'
                   WHEN b.oddstype = 2 THEN 'HK'
                   WHEN b.oddstype = 3 THEN 'Indo'
                   WHEN b.oddstype = 4 THEN 'MY'
                   WHEN b.oddstype = 5 THEN 'US'
              END
            , CASE WHEN statusid = 112 THEN 'Won' WHEN statusid = 113 THEN 'Lose' ELSE 'Draw' END 
			      , CASE
			        	WHEN liveindicator=1 THEN 'Live'
			        	WHEN liveindicator=0 THEN 'Non-Live'
			        	ELSE 'Live&Non-live' 
			        END
     ORDER BY Winlossdate


    DROP TABLE #BU
    DROP TABLE #data_basketball
    DROP TABLE #league

END

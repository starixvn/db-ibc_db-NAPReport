/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

--Top winning members: drilldown
ALTER PROCEDURE dbo.Acc_Rpt_SBPerformanceMonitor_Member @fromDate SMALLDATETIME,
                                                        @toDate SMALLDATETIME,
                                                        @timeRange SMALLINT = -1,
                                                        @margin FLOAT = NULL,           -- Not used with "Top by" reports
                                                        @excludeDrawTickets BIT = 0,
                                                        @excludeParlay BIT = 1,
                                                        @topBy VARCHAR(20) = 'Margin',    
                                                        @custID INT,                    -- level 1
                                                        @sportID INT = NULL,	        -- level 2
                                                        @leagueID INT = NULL,	        -- level 3
                                                        @liveIndicator TINYINT = NULL,  -- level 4
                                                        @showBy VARCHAR(20) = 'Match',  -- or 'BetType', in effect when used with @liveIndicator
                                                        @matchID INT = NULL 			-- level 5
AS
/*
    Created: Jaden.Tang@20210715
    Task: Getting drilldown data from dashboard of SB Performance Monitor Report by Member
    DB: DBACC.bodb02

    Revisions:
        - 20210715@Jaden.Tang: First Commit (#158683)
		    - 20220419@Kean.Nguyen: Fix the way to determine HALF-WON|HALF_LOSE ticket (#171706)
    	  - 20220711@Jaden.Tang: Dynamic half win/lose check (#175205)

    Param's Explanation:
        - @fromDate: Range date to get data for report
        - @toDate: Range date to get data for report
        - @timeRange: Not used in DBACC, web'd switch to DW report when this is selected
        - @excludeDrawTickets: 
                         0: Include all tickets
                         1: Exclude draw tickets
        - @excludeParlay: Exclude parlay tickets, filter not in effect when using with @isShowLeague = 1

    Example:

*/

BEGIN

    SET NOCOUNT ON

    -- Declare variables
    DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME
    SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay
      FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
    -- show Parlay at top level only, always exclude when drilldown from Sport level
    DECLARE @parlayFlag BIT = CASE WHEN @sportID IS NOT NULL THEN 0
								   ELSE @excludeParlay^1 END     
    -- #tmpBettypeGroup
    BEGIN
        CREATE TABLE #tmpBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)

        INSERT INTO #tmpBettypeGroup (BettypeGroupID, Bettype)
        SELECT BettypeGroupID, Bettype 
          FROM DBWH.bodb_Account.dbo.BettypeGroup 
         WHERE BettypeGroupID = 12
    END
    
    -- #tmpSportBettypeMatrix
    BEGIN
        CREATE TABLE #tmpSportBettypeMatrix (BetType SMALLINT, IsHalfWonLoseAble BIT)

        INSERT INTO #tmpSportBettypeMatrix (BetType, IsHalfWonLoseAble)
        SELECT DISTINCT sbm.BetType,
               CASE WHEN sbm.BetType NOT IN (29, 38, 901, 902 ,903, 904, 18999) THEN 1 ELSE 0 END
          FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
         WHERE sbm.ProductID = 1
           AND sbm.SubProduct NOT LIKE 'BT%'
           AND ((sbm.BetType NOT IN (9, 29) AND @parlayFlag = 0) OR @parlayFlag = 1)
           AND sbm.BetType != 999

        CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(BetType)
    END

    -- #tmpMatch, start filter by sport & league & match
    BEGIN
        CREATE TABLE #tmpMatch (SportType INT, 
                                LeagueID INT, 
                                MatchID INT, 
                                MatchType SMALLINT, -- normal or outright
                                ChildMatchType INT, -- determine Extra Time or Penalty matches
                                IsHedge BIT,
                                HomeID INT, 
                                AwayID INT)

        ;WITH CTE_Match AS (
            SELECT MatchID AS MatchID, LeagueID, 0 AS MatchType, ChildMatchType, matchcode, HomeID, AwayID
              FROM bodb02.dbo.match WITH (NOLOCK)
             WHERE eventdate >= @fromDate AND eventdate <= @toDate
                   UNION ALL
            SELECT orid AS MatchID, LeagueID, 1 AS MatchType, 0 AS ChildMatchType, matchcode, TeamID, -1
              FROM bodb02.dbo.outright WITH (NOLOCK)
             WHERE eventdate >= @fromDate AND eventdate <= @toDate
                   UNION
            SELECT MatchID AS MatchID, LeagueID, 0 AS MatchType, ChildMatchType, matchcode, HomeID, AwayID
              FROM bodb02.dbo.match14 WITH (NOLOCK)
             WHERE @fromDate <= @MoveBetsDay
               AND eventdate >= @fromDate AND eventdate <= @MoveBetsDay
                   UNION ALL
            SELECT orid AS MatchID, LeagueID, 1 AS MatchType, 0 AS ChildMatchType, matchcode, TeamID, -1
              FROM bodb02.dbo.outright14 (NOLOCK)
             WHERE @fromDate <= @MoveBetsDay
               AND eventdate >= @fromDate AND eventdate <= @MoveBetsDay
        )
        INSERT INTO #tmpMatch (SportType, LeagueID, MatchID, MatchType, ChildMatchType, IsHedge, HomeID, AwayID)
        SELECT s.SportType,
            l.LeagueID,
            m.MatchID,
            m.MatchType,
            m.ChildMatchType,
            CASE WHEN m.matchcode LIKE '%hedge%' THEN 1 ELSE 0 END Ishedge,
            m.HomeID,
            m.AwayID
        FROM CTE_Match m
             INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.LeagueID = l.LeagueID
             INNER JOIN bodb02.dbo.Sports s WITH (NOLOCK) ON l.sporttype = s.SportType
        WHERE s.SportType = ISNULL(@sportID, s.SportType)
          AND l.LeagueID = ISNULL(@leagueID, l.LeagueID)
          AND m.MatchID = ISNULL(@matchID, m.MatchID)
              UNION ALL
        SELECT -2, -2, 9, 0, NULL, NULL, -1, -1 WHERE @parlayFlag = 1
              UNION ALL
        SELECT -2, -2, 29, 0, NULL, NULL, -1, -1 WHERE @parlayFlag = 1
        OPTION (RECOMPILE)
        
        CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(MatchID, MatchType)
    END
    
    -- #staging, group by all available dimensions, and filter by site & live indicator
    BEGIN
        CREATE TABLE #staging (SportID       INT,
                               LeagueID      INT,
                               LiveIndicator BIT,
                               MatchID       INT,
                               BetType       INT,
                               BetCount      INT,
                               RealIncome    DECIMAL(19, 4),
                               RealTurnover  DECIMAL(19, 4))
    
        INSERT INTO #staging (SportID, 
                              LeagueID, 
                              LiveIndicator, 
                              MatchID, 
                              BetType,
                              BetCount, 
                              RealIncome, 
                              RealTurnover)
        SELECT -- DIMENSION
            m.SportType,
            m.LeagueID,
            sd.liveindicator,
            sd.MatchID,
            sd.bettype,
            -- MEASURE
            COUNT(1) AS BetCount,
            SUM(CASE WHEN sd.recommend IN (52466, 5707545) THEN 0
                     ELSE (- (sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
                           - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                  ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
                              END) 
                           * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate)
                END) AS RealIncome,
            SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                          * ABS(sd.stake)
                          * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
                END 
                * 
                CASE WHEN @excludeDrawTickets = 1 
                         THEN CASE WHEN ((sd.winlostdate < '2019-10-01' AND sd.bettype IN (1, 3, 7, 8, 17, 18, 124, 125, 482, 483, 484, 485))
                                        OR (sd.winlostdate >= '2019-10-01' AND sbm.IsHalfWonLoseAble = 1))
                                    AND sd.statusID IN (112, 113)
                                    AND ABS(sd.modds) = 0.25
                                   THEN 0.5
                                   ELSE 1 END
                    ELSE 1 
                END) AS RealTurnover
          FROM (
            SELECT custid, recommend, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, tpositiontaking, epositiontaking, stake
                 , virtualrate, actualrate, bettype, statusID, modds, MatchID, currency, ruben, liveindicator, winlostdate
              FROM bodb02.dbo.bettrans WITH (NOLOCK)
             WHERE winlostdate >= @fromDate AND winlostdate <= @toDate
            UNION ALL
            SELECT custid, recommend, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, tpositiontaking, epositiontaking, stake
                 , virtualrate, actualrate, bettype, statusID, modds, MatchID, currency, ruben, liveindicator, winlostdate
              FROM bodb02.dbo.bettrans14 WITH (NOLOCK) 
             WHERE @fromDate <= @MoveBetsDay AND winlostdate > @fromDate AND winlostdate <= @MoveBetsDay
          ) sd
            INNER JOIN #tmpMatch m ON sd.MatchID = m.MatchID
                                  AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.MatchType
            LEFT JOIN #tmpSportBettypeMatrix sbm ON sd.bettype = sbm.BetType
         WHERE sd.ruben = 1
           AND sd.statusID IN (111, 112, 113)
           AND sd.currency NOT IN (20, 27, 28)
           AND sbm.BetType IS NOT NULL
           AND (@excludeDrawTickets = 0 OR (@excludeDrawTickets = 1 AND statusID NOT IN (111)))
           AND sd.liveindicator = ISNULL(@liveindicator, sd.liveindicator)
           AND sd.custid = @custID
         GROUP BY m.SportType,
                  m.LeagueID,
                  sd.liveindicator,
                  sd.MatchID,
                  sd.bettype
        OPTION (RECOMPILE)
    END

    DECLARE @orderDirection SMALLINT = -1

    CREATE TABLE #tmpFinal (ID              INT,
                            Name            VARCHAR(5000),
                            [NoMatches]     INT,
                            [NoBetTypes]    INT,
                            [BetCount]      INT,
                            [RealIncome]    DECIMAL(19, 4),
                            [RealTurnover]  DECIMAL(19, 4),
                            [RealMargin]    DECIMAL(19, 4))
    
    ;WITH CTE_Extra AS (
        SELECT SportID,
               s.LeagueID, 
               LiveIndicator,
               CASE LiveIndicator WHEN 1 THEN 'Live' ELSE 'Non-Live' END AS [LiveIndicatorDisplay], 
               home.teamname 
               + CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END MatchName,
               s.MatchID,
               CASE WHEN m.ChildMatchType IN (201, 202, 203) OR m.IsHedge = 1 THEN NULL ELSE s.MatchID END [MatchID_ForCnt], -- don't COUNT hedge, extra time, penalty matches
               s.BetType, 
               -- since we're showing one customer, this is most likely always 1
               CASE WHEN bg.Bettype IS NOT NULL OR td.[VendorID] = 14 THEN 0 ELSE BetCount END AS BetCount, 
               RealIncome, 
               RealTurnover,
               CASE WHEN s.SportID = -2 THEN 'Parlay' ELSE sp.SportName END SportName,
               l.leaguename LeagueName,
               bt.typenamee BetTypeName
          FROM #staging s
               LEFT JOIN #tmpBettypeGroup bg ON s.BetType = bg.Bettype
               LEFT JOIN bodb02.dbo.TradeCust AS td WITH (NOLOCK) ON td.custid = @custID

               LEFT JOIN bodb02.dbo.Sports sp WITH (NOLOCK) ON s.SportID = sp.SportType -- for displaying sport names, 1st level
                                                           AND @sportID IS NULL

               LEFT JOIN bodb02.dbo.league l WITH (NOLOCK) ON s.LeagueID = l.LeagueID -- for displaying league names, 2nd level
                                                          AND @sportID IS NOT NULL
                                                                                    -- 3rd level: live indicator
               LEFT JOIN #tmpMatch m ON s.MatchID = m.matchid
                                    AND ((@liveIndicator IS NULL AND @leagueID IS NOT NULL) -- for getting ChildMatchType and IsHedge columns, 3rd level
                                      OR (@liveIndicator IS NOT NULL AND @showBy = 'Match')) -- for displaying home & away teams, 4th level
                    LEFT JOIN bodb02.dbo.Team home WITH (NOLOCK) ON m.homeid = home.teamid
                    LEFT JOIN bodb02.dbo.Team away WITH (NOLOCK) ON m.awayid = away.teamid

               LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK) ON s.BetType = bt.typeid -- for displaying bet types, 4th or 5th level
                                                            AND (@matchID IS NOT NULL 
                                                             OR (@liveIndicator IS NOT NULL AND @showBy != 'Match'))
    ),
    CTE_Grouped AS (
        /*remember to order it desc by level as TSQL case when stops at first hit*/
        SELECT CASE WHEN @matchID IS NOT NULL       THEN cte.BetType        -- level 5
                    WHEN @liveIndicator IS NOT NULL THEN
                         CASE @showBy
                         WHEN 'Match'               THEN cte.MatchID        -- level 4
                         ELSE                            cte.BetType        -- level 4
                         END
                    WHEN @leagueID IS NOT NULL      THEN cte.LiveIndicator  -- level 3
                    WHEN @sportID IS NOT NULL       THEN cte.LeagueID       -- level 2
                    WHEN @sportID IS NULL           THEN cte.SportID        -- level 1
               END AS [ID], 
            MAX(
                CASE WHEN @matchID IS NOT NULL       THEN cte.BetTypeName
                    WHEN @liveIndicator IS NOT NULL  THEN
                         CASE @showBy 
                         WHEN 'Match'                THEN cte.MatchName       
                         ELSE                             cte.BetTypeName       
                         END      
                    WHEN @leagueID IS NOT NULL       THEN cte.LiveIndicatorDisplay   
                    WHEN @sportID IS NOT NULL        THEN cte.LeagueName
                    WHEN @sportID IS NULL            THEN cte.SportName                            
                END 
            )AS [Name],
            COUNT(DISTINCT MatchID_ForCnt) AS [No.Matches],
            COUNT(DISTINCT BetType)        AS [No.Bet Types],
            SUM(BetCount)                  AS [Bet Count],
            SUM(RealIncome)                AS [Real Income],
            SUM(RealTurnover)              AS [Real Turnover],
            CASE WHEN SUM(RealTurnover) != 0 THEN (SUM(RealIncome) / SUM(RealTurnover)) * 100
                 ELSE 0 END                AS [Real Margin]
        FROM CTE_Extra cte
        GROUP BY CASE WHEN @matchID IS NOT NULL       THEN cte.BetType        -- level 5
                      WHEN @liveIndicator IS NOT NULL THEN
                           CASE @showBy
                           WHEN 'Match'               THEN cte.MatchID        -- level 4
                           ELSE                            cte.BetType        -- level 4
                           END
                      WHEN @leagueID IS NOT NULL      THEN cte.LiveIndicator  -- level 3
                      WHEN @sportID IS NOT NULL       THEN cte.LeagueID       -- level 2
                      WHEN @sportID IS NULL           THEN cte.SportID        -- level 1
                 END        
    ) 
    INSERT INTO #tmpFinal
    SELECT * FROM CTE_Grouped
     ORDER BY 
           CASE @topBy 
           WHEN 'RealTurnover' THEN [Real Turnover]
           WHEN 'RealIncome' THEN [Real Income]
           WHEN 'Margin' THEN [Real Margin] END * @orderDirection

    -- Dynamic query to display additional column aliases for report view by live indicator (level 3)
    DECLARE @SQL VARCHAR(MAX)
    SET @SQL = 'SELECT ID, ' +
                    'Name AS ' + CASE WHEN @matchID IS NOT NULL       THEN '[BetType] '       -- level 5
                                      WHEN @liveIndicator IS NOT NULL THEN
                                           CASE @showBy
                                           WHEN 'Match'               THEN '[Match] '          -- level 4
                                           ELSE                            '[BetType] '       -- level 4
                                           END
                                      WHEN @leagueID IS NOT NULL      THEN '[Event] '          -- level 3
                                      WHEN @sportID IS NOT NULL       THEN '[League] '         -- level 2
                                      WHEN @sportID IS NULL           THEN '[Sport] '          -- level 1
                                      ELSE ''
                                 END + ',' +
                    CASE WHEN @leagueID IS NOT NULL AND @liveIndicator IS NULL THEN '[NoMatches], ' ELSE '' END + 
                    CASE WHEN @leagueID IS NOT NULL AND @liveIndicator IS NULL THEN '[NoBetTypes], ' ELSE '' END + 
                    '[BetCount], ' +
                    '[RealIncome], ' +
                    '[RealTurnover], ' +
                    '[RealMargin] ' +
        'FROM #tmpFinal'
    -- PRINT @SQL
    EXECUTE (@SQL)

    -- Drop temp tables
    DROP TABLE #tmpSportBettypeMatrix
    DROP TABLE #tmpMatch
    DROP TABLE #staging
    DROP TABLE #tmpFinal
    DROP TABLE #tmpBettypeGroup

END
GO

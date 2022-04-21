/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

--Margin (%) By Sport: drilldown
ALTER PROCEDURE dbo.Acc_Rpt_SBPerformanceMonitor_Sport @fromDate SMALLDATETIME,
                                                       @toDate SMALLDATETIME,
                                                       @timeRange SMALLINT = -1,
                                                       @margin FLOAT = NULL,
                                                       @excludeDrawTickets BIT = 0,
                                                       @excludeParlay BIT = 1,       -- Not used in Sport reports
                                                       @topBy VARCHAR(20) = NULL,    -- Not used with "Margin By" reports
                                                       @sportID INT, 			     -- level 1
                                                       @siteID INT = NULL, 			 -- level 2
                                                       @leagueID INT = NULL,		 -- level 3
                                                       @liveIndicator TINYINT = NULL,-- level 4, combine with below
                                                       @showBy VARCHAR(20) = 'Match',-- or 'BetType', in effect when used with @liveIndicator
                                                       @matchID INT = NULL 			 -- level 5
AS
/*
    Created: Jaden.Tang@20210715
    Task: Getting drilldown data from dashboard of SB Performance Monitor Report by Sport
    DB: DBACC.bodb02

    Revisions:
        - 20210715@Jaden.Tang: First Commit (#158683)
		- 20220419@Kean.Nguyen: Fix the way to determine HALF-WON|HALF_LOSE ticket (#171706)

    Param's Explanation:
        - @fromDate: Range date to get data for report
        - @toDate: Range date to get data for report
        - @timeRange: Not used in DBACC, web'd switch to DW report when this is selected
        - @excludeDrawTickets: 
                         0: Include all tickets
                         1: Exclude draw tickets

    Example:

*/

BEGIN

    SET NOCOUNT ON

    -- Declare variables
    DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME
    SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay
      FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
     
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
        CREATE TABLE #tmpSportBettypeMatrix (BetType SMALLINT)

        INSERT INTO #tmpSportBettypeMatrix (BetType)
        SELECT DISTINCT sbm.BetType
          FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
         WHERE sbm.ProductID = 1
           AND sbm.SubProduct NOT LIKE 'BT%'
           AND sbm.BetType NOT IN (9, 29, 999)

        CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(BetType)
    END

    -- #tmpMatch, start filter by sport & league & match
    BEGIN
        CREATE TABLE #tmpMatch (SportType INT, 
                                LeagueID INT, 
                                MatchID INT, 
                                MatchType SMALLINT, -- normal or outright
                                ChildMatchType INT, -- determine Extra Time or Penalty matches
                                HomeID INT, 
                                AwayID INT)

        ;WITH CTE_Match AS (
            SELECT MatchID AS MatchID, LeagueID, 0 AS MatchType, ChildMatchType, HomeID, AwayID
              FROM bodb02.dbo.match WITH (NOLOCK)
             WHERE eventdate >= @fromDate AND eventdate <= @toDate
                   UNION ALL
            SELECT orid AS MatchID, LeagueID, 1 AS MatchType, 0 AS ChildMatchType, TeamID, -1
              FROM bodb02.dbo.outright WITH (NOLOCK)
             WHERE eventdate >= @fromDate AND eventdate <= @toDate
                   UNION
            SELECT MatchID AS MatchID, LeagueID, 0 AS MatchType, ChildMatchType, HomeID, AwayID
              FROM bodb02.dbo.match14 WITH (NOLOCK)
             WHERE @fromDate <= @MoveBetsDay
               AND eventdate >= @fromDate AND eventdate <= @MoveBetsDay
                   UNION ALL
            SELECT orid AS MatchID, LeagueID, 1 AS MatchType, 0 AS ChildMatchType, TeamID, -1
              FROM bodb02.dbo.outright14 (NOLOCK)
             WHERE @fromDate <= @MoveBetsDay
               AND eventdate >= @fromDate AND eventdate <= @MoveBetsDay
        )
        INSERT INTO #tmpMatch (SportType, LeagueID, MatchID, MatchType, ChildMatchType, HomeID, AwayID)
        SELECT s.SportType,
            l.LeagueID,
            m.MatchID,
            m.MatchType,
            m.ChildMatchType,
            m.HomeID,
            m.AwayID
        FROM CTE_Match m
             INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.LeagueID = l.LeagueID
             INNER JOIN bodb02.dbo.Sports s WITH (NOLOCK) ON l.sporttype = s.SportType
        WHERE s.SportType = @sportID
          AND l.LeagueID = ISNULL(@leagueID, l.LeagueID)
          AND m.MatchID = ISNULL(@matchID, m.MatchID)
        OPTION (RECOMPILE)
        
        CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(MatchID, MatchType)
    END

    -- #tmpAgent, start filter by site
    BEGIN
        CREATE TABLE #tmpAgent (CustID INT, SiteID INT)
        
        INSERT INTO #tmpAgent (CustID, SiteID)
        SELECT c.CustId CustID, 
               s.siteid SiteID
          FROM bodb02.dbo.Customer c (NOLOCK)
               LEFT JOIN bodb02.dbo.Site s (NOLOCK) ON c.site = s.site
         WHERE c.RoleID = 2
           AND s.SiteID = ISNULL(@siteID, s.SiteID)
        OPTION (RECOMPILE)

        CREATE UNIQUE CLUSTERED INDEX PK_tmpAgent ON #tmpAgent(CustID)
    END
    
    -- #staging, group by all available dimensions, and filter by site & live indicator
    BEGIN
        CREATE TABLE #staging (SiteID        INT,
                               LeagueID      INT,
                               LiveIndicator BIT,
                               MatchID       INT,
                               BetType       INT,
                               CustID        INT,
                               BetCount      INT,
                               RealIncome    DECIMAL(19, 4),
                               RealTurnover  DECIMAL(19, 4))
    
        INSERT INTO #staging (SiteID, 
                              LeagueID, 
                              LiveIndicator, 
                              MatchID, 
                              BetType,
                              CustID,
                              BetCount, 
                              RealIncome, 
                              RealTurnover)
        SELECT -- DIMENSION
            a.SiteID,
            m.LeagueID,
            sd.liveindicator,
            sd.MatchID,
            sd.bettype,
            sd.custid,
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
                         THEN CASE WHEN (sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399 OR sd.bettype BETWEEN 9400 AND 9998)
                                    AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914)
                                    AND sd.bettype NOT BETWEEN 81 AND 120
                                    AND sd.statusID IN (112, 113)
                                    AND ABS(sd.modds) = 0.25
                                   THEN 0.5
                                   ELSE 1 END
                    ELSE 1 
                END) AS RealTurnover
          FROM (
            SELECT custid, recommend, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, tpositiontaking, epositiontaking, stake
                 , virtualrate, actualrate, bettype, statusID, modds, MatchID, currency, ruben, liveindicator
              FROM bodb02.dbo.bettrans WITH (NOLOCK)
             WHERE winlostdate >= @fromDate AND winlostdate <= @toDate
            UNION ALL
            SELECT custid, recommend, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, tpositiontaking, epositiontaking, stake
                 , virtualrate, actualrate, bettype, statusID, modds, MatchID, currency, ruben, liveindicator
              FROM bodb02.dbo.bettrans14 WITH (NOLOCK) 
             WHERE @fromDate <= @MoveBetsDay AND winlostdate > @fromDate AND winlostdate <= @MoveBetsDay
          ) sd
            INNER JOIN #tmpMatch m ON sd.MatchID = m.MatchID
                                  AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.MatchType
            INNER JOIN #tmpAgent a ON sd.recommend = a.CustID
         WHERE sd.ruben = 1
           AND sd.statusID IN (111, 112, 113)
           AND sd.currency NOT IN (20, 27, 28)
           AND EXISTS (SELECT 1 FROM #tmpSportBettypeMatrix sbm WHERE sd.BetType = sbm.BetType)
           AND (@excludeDrawTickets = 0 OR (@excludeDrawTickets = 1 AND statusID NOT IN (111)))
           AND sd.liveindicator = ISNULL(@liveindicator, sd.liveindicator)
         GROUP BY a.SiteID,
                  m.LeagueID,
                  sd.liveindicator,
                  sd.MatchID,
                  sd.bettype,
                  sd.custid
        OPTION (RECOMPILE)
    END

    CREATE TABLE #tmpFinal (ID              INT,
                            Name            VARCHAR(5000),
                            [NoMatches]     INT,
                            [NoBetTypes]    INT,
                            [BetCount]      INT,
                            [ActiveMembers] INT,
                            [RealIncome]    DECIMAL(19, 4),
                            [RealTurnover]  DECIMAL(19, 4),
                            [RealMargin]    DECIMAL(19, 4))
    
    ;WITH CTE_Extra AS (
        SELECT s.SiteID,
               s.LeagueID, 
               LiveIndicator,
               CASE LiveIndicator WHEN 1 THEN 'Live' ELSE 'Non-Live' END AS [LiveIndicatorDisplay], 
               home.teamname 
               + CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END MatchName,
               s.MatchID,
               CASE WHEN m.ChildMatchType IN (201, 202, 203) THEN NULL ELSE s.MatchID END [MatchID_ForCnt], -- don't COUNT extra time, penalty matches
               s.CustID, 
               s.BetType, 
               -- exclude dummy Cashout accounts when counting Active Members and Bet Count
               CASE WHEN bg.bettype IS NOT NULL OR td.[VendorID] = 14 THEN NULL ELSE s.custid END AS [CustID_ForCnt],
               CASE WHEN bg.Bettype IS NOT NULL OR td.[VendorID] = 14 THEN 0 ELSE BetCount END AS BetCount, 
               RealIncome, 
               RealTurnover,
               st.Site      SiteName,
               l.leaguename LeagueName,
               bt.typenamee BetTypeName
          FROM #staging s
               LEFT JOIN #tmpBettypeGroup bg ON s.BetType = bg.Bettype
               LEFT JOIN bodb02.dbo.TradeCust AS td WITH (NOLOCK) ON s.CustID = td.custid

               LEFT JOIN bodb02.dbo.Site st WITH (NOLOCK) ON s.SiteID = st.siteid -- for displaying site names, 1st level
                                                           AND @siteID IS NULL

               LEFT JOIN bodb02.dbo.league l WITH (NOLOCK) ON s.LeagueID = l.LeagueID -- for displaying league names, 2nd level
                                                          AND @siteID IS NOT NULL
                                                                                    -- 3rd level: live indicator
               LEFT JOIN #tmpMatch m ON s.MatchID = m.matchid -- for displaying home & away teams, 4th level
                                    AND @liveIndicator IS NOT NULL AND @showBy = 'Match'
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
                    WHEN @siteID IS NOT NULL        THEN cte.LeagueID       -- level 2
                    WHEN @siteID IS NULL            THEN cte.SiteID         -- level 1
            END AS [ID], 
            MAX(
                CASE WHEN @matchID IS NOT NULL       THEN cte.BetTypeName
                     WHEN @liveIndicator IS NOT NULL THEN
                          CASE @showBy
                          WHEN 'Match'               THEN cte.MatchName       
                          ELSE                            cte.BetTypeName       
                          END     
                     WHEN @leagueID IS NOT NULL      THEN cte.LiveIndicatorDisplay   
                     WHEN @siteID IS NOT NULL        THEN cte.LeagueName
                     WHEN @siteID IS NULL            THEN cte.SiteName                            
                END 
            )AS [Name],
            COUNT(DISTINCT MatchID_ForCnt) AS [No.Matches],
            COUNT(DISTINCT BetType)        AS [No.Bet Types],
            SUM(BetCount)                  AS [Bet Count],
            COUNT(DISTINCT CustID_ForCnt)  AS [Active Members],
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
                      WHEN @siteID IS NOT NULL        THEN cte.LeagueID       -- level 2
                      WHEN @siteID IS NULL            THEN cte.SiteID         -- level 1
                 END       
    ) 
    INSERT INTO #tmpFinal
    SELECT * FROM CTE_Grouped WHERE [Real Margin] <= ISNULL(@margin, [Real Margin])


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
                                      WHEN @siteID IS NOT NULL        THEN '[League] '         -- level 2
                                      WHEN @siteID IS NULL            THEN '[Site] '          -- level 1
                                      ELSE ''
                                 END + ',' +
                    CASE WHEN @leagueID IS NOT NULL AND @liveIndicator IS NULL THEN '[NoMatches], ' ELSE '' END + 
                    CASE WHEN @leagueID IS NOT NULL AND @liveIndicator IS NULL THEN '[NoBetTypes], ' ELSE '' END + 
                    '[BetCount], ' +
                    '[ActiveMembers], ' +
                    '[RealIncome], ' +
                    '[RealTurnover], ' +
                    '[RealMargin] ' +
        'FROM #tmpFinal ' + 
        'ORDER BY [RealMargin]'
    -- PRINT @SQL
    EXECUTE (@SQL)

    -- Drop temp tables
    DROP TABLE #tmpSportBettypeMatrix
    DROP TABLE #tmpMatch
    DROP TABLE #tmpAgent
    DROP TABLE #staging
    DROP TABLE #tmpFinal
    DROP TABLE #tmpBettypeGroup

END
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

--Top losing leagues: drilldown
ALTER PROCEDURE dbo.Acc_Rpt_SBPerformanceMonitor_League @fromDate SMALLDATETIME,
                                                        @toDate SMALLDATETIME,
                                                        @timeRange SMALLINT = -1,
                                                        @margin FLOAT = NULL,           -- Not used with "Top by" reports
                                                        @excludeDrawTickets BIT = 0,
                                                        @excludeParlay BIT = NULL,      -- Not used with "Top by losing leagues" reports
                                                        @topBy VARCHAR(20) = 'Margin',    
                                                        @leagueID INT,			        -- level 1
                                                        @siteID INT = NULL, 			-- level 2
                                                        @showBy VARCHAR(20) = 'Event',  -- or 'Match', in effect when used with @siteID
                                                        @liveIndicator TINYINT = NULL,  -- level 3
                                                        @matchID INT = NULL, 			-- level 4
                                                        @bettype INT = NULL 			-- level 5
AS
/*
    Created: Jaden.Tang@20210715
    Task: Getting drilldown data from dashboard of SB Performance Monitor Report by League
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
        - @topBy: The metric to sort descending

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
    
    -- #tmpSportBettypeMatrix, filter by bet type
    BEGIN
        CREATE TABLE #tmpSportBettypeMatrix (BetType SMALLINT, IsHalfWonLoseAble BIT)

        INSERT INTO #tmpSportBettypeMatrix (BetType, IsHalfWonLoseAble)
        SELECT DISTINCT sbm.BetType,
               CASE WHEN sbm.BetType NOT IN (38, 901, 902 ,903, 904, 18999) THEN 1 ELSE 0 END
          FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
         WHERE sbm.ProductID = 1
           AND sbm.SubProduct NOT LIKE 'BT%'
           AND sbm.BetType NOT IN (9, 29, 999)
           AND sbm.BetType = ISNULL(@betType, sbm.BetType)

        CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(BetType)
    END

    -- #tmpMatch, start filter by league & match
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
        WHERE l.LeagueID = ISNULL(@leagueID, l.LeagueID)
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
                               LiveIndicator BIT,
                               MatchID       INT,
                               BetType       INT,
                               CustID        INT,
                               BetCount      INT,
                               RealIncome    DECIMAL(19, 4),
                               RealTurnover  DECIMAL(19, 4))
    
        INSERT INTO #staging (SiteID, 
                              LiveIndicator, 
                              MatchID, 
                              BetType,
                              CustID,
                              BetCount, 
                              RealIncome, 
                              RealTurnover)
        SELECT -- DIMENSION
            a.SiteID,
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
            LEFT JOIN #tmpSportBettypeMatrix sbm ON sd.bettype = sbm.BetType
         WHERE sd.ruben = 1
           AND sd.statusID IN (111, 112, 113)
           AND sd.currency NOT IN (20, 27, 28)
           AND sbm.BetType IS NOT NULL
           AND (@excludeDrawTickets = 0 OR (@excludeDrawTickets = 1 AND statusID NOT IN (111)))
           AND sd.liveindicator = ISNULL(@liveindicator, sd.liveindicator)
           AND sd.bettype = ISNULL(@bettype, sd.bettype)
         GROUP BY a.SiteID,
                  sd.liveindicator,
                  sd.MatchID,
                  sd.bettype,
                  sd.custid
        OPTION (RECOMPILE)
    END

    -- 1 = ASC; -1 = DESC
    DECLARE @orderDirection SMALLINT = CASE @topBy
                                            WHEN 'RealTurnover' THEN -1
                                            ELSE 1
                                       END

    CREATE TABLE #tmpFinal (ID              INT,
                            Name            VARCHAR(5000),
                            [NoMatches]     INT,
                            [BetCount]      INT,
                            [ActiveMembers] INT,
                            [RealIncome]    DECIMAL(19, 4),
                            [RealTurnover]  DECIMAL(19, 4),
                            [RealMargin]    DECIMAL(19, 4))
    
    ;WITH CTE_Extra AS (
        SELECT s.SiteID, 
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
               c.username CustName,
               st.site SiteName,
               bt.typenamee BetTypeName
          FROM #staging s
               LEFT JOIN #tmpBettypeGroup bg ON s.BetType = bg.Bettype
               LEFT JOIN bodb02.dbo.TradeCust AS td WITH (NOLOCK) ON s.CustID = td.custid

               LEFT JOIN bodb02.dbo.Site st WITH (NOLOCK) ON s.SiteID = st.siteid -- for displaying site names, 1st level
                                                         AND @siteID IS NULL

               LEFT JOIN #tmpMatch m ON s.MatchID = m.matchid -- for displaying match names, 2nd or 3rd level
                                    AND @siteID IS NOT NULL
                                    AND @matchID IS NULL 
                                    AND (@liveIndicator IS NOT NULL OR @showBy = 'Match')
                    LEFT JOIN bodb02.dbo.Team home WITH (NOLOCK) ON m.homeid = home.teamid
                    LEFT JOIN bodb02.dbo.Team away WITH (NOLOCK) ON m.awayid = away.teamid

               LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK) ON s.BetType = bt.typeid  -- for display bet names, 4th level
                                                            AND @matchID IS NOT NULL 
                                                            AND @liveIndicator IS NOT NULL

               LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON s.CustID = c.custid -- for display customers, 5th level
                                                            AND @bettype IS NOT NULL
    ),
    CTE_Grouped AS (
        /*remember to order it desc by level as TSQL case when stops at first hit*/
        SELECT CASE WHEN @bettype IS NOT NULL                          THEN cte.CustID               -- level 5
                    WHEN @liveIndicator IS NOT NULL            
                    AND @matchID IS NOT NULL                           THEN cte.BetType              -- level 4
                    WHEN @liveIndicator IS NOT NULL            
                    AND @matchID IS NULL                               THEN cte.MatchID              -- level 3
                    WHEN @liveIndicator IS NULL 
                    AND @matchID IS NOT NULL                           THEN cte.LiveIndicator        -- level 3
                    WHEN @siteID IS NOT NULL                           THEN 
                        CASE @showBy
                            WHEN 'Match'                               THEN cte.MatchID              -- level 2
                            ELSE                                            cte.LiveIndicator        -- level 2
                            END
                    WHEN @siteID IS NULL                               THEN cte.SiteID               -- level 1
               END AS [ID], 
            MAX(
                CASE WHEN @bettype IS NOT NULL                          THEN cte.CustName              
                     WHEN @liveIndicator IS NOT NULL            
                     AND @matchID IS NOT NULL                           THEN cte.BetTypeName            
                     WHEN @liveIndicator IS NOT NULL            
                     AND @matchID IS NULL                               THEN cte.MatchName           
                     WHEN @liveIndicator IS NULL 
                     AND @matchID IS NOT NULL                           THEN cte.LiveIndicatorDisplay
                     WHEN @siteID IS  NOT NULL                          THEN
                         CASE @showBy
                             WHEN 'Match'                               THEN cte.MatchName             
                             ELSE                                            cte.LiveIndicatorDisplay       
                             END
                     WHEN @siteID IS NULL                               THEN cte.SiteName              
                END
            )AS [Name],
            COUNT(DISTINCT MatchID_ForCnt) AS [No.Matches],
            SUM(BetCount)                  AS [Bet Count],
            COUNT(DISTINCT CustID_ForCnt)  AS [Active Members],
            SUM(RealIncome)                AS [Real Income],
            SUM(RealTurnover)              AS [Real Turnover],
            CASE WHEN SUM(RealTurnover) != 0 THEN (SUM(RealIncome) / SUM(RealTurnover)) * 100
                 ELSE 0 END                AS [Real Margin]
        FROM CTE_Extra cte
        GROUP BY CASE WHEN @bettype IS NOT NULL                        THEN cte.CustID      
                    WHEN @liveIndicator IS NOT NULL            
                    AND @matchID IS NOT NULL                           THEN cte.BetType      
                    WHEN @liveIndicator IS NOT NULL            
                    AND @matchID IS NULL                               THEN cte.MatchID      
                    WHEN @liveIndicator IS NULL 
                    AND @matchID IS NOT NULL                           THEN cte.LiveIndicator
                    WHEN @siteID IS  NOT NULL                          THEN
                        CASE @showBy
                            WHEN 'Match'                               THEN cte.MatchID      
                            ELSE                                            cte.LiveIndicator
                            END
                    WHEN @siteID IS NULL                               THEN cte.SiteID       
                END
    ) 
    INSERT INTO #tmpFinal
    SELECT * FROM CTE_Grouped
     ORDER BY 
           CASE @topBy 
           WHEN 'RealTurnover' THEN [Real Turnover]
           WHEN 'RealIncome' THEN [Real Income]
           WHEN 'Margin' THEN [Real Margin] END * @orderDirection

    DECLARE @SQL VARCHAR(MAX)
    SET @SQL = 'SELECT ID, ' +
                    'Name AS ' + CASE WHEN @bettype IS NOT NULL                           THEN '[Username]'     
                                      WHEN @liveIndicator IS NOT NULL            
                                       AND @matchID IS NOT NULL                           THEN '[BetType]'      
                                      WHEN @liveIndicator IS NOT NULL            
                                       AND @matchID IS NULL                               THEN '[Match]'      
                                      WHEN @liveIndicator IS NULL 
                                       AND @matchID IS NOT NULL                           THEN '[Event]'
                                      WHEN @siteID IS  NOT NULL                           THEN
                                           CASE @showBy
                                                WHEN 'Match'                              THEN '[Match]'      
                                                ELSE                                           '[Event]'
                                                END
                                      WHEN @siteID IS NULL                                THEN '[Site]'       
                                 END + ',' +
                    CASE WHEN @siteID IS NULL THEN '[NoMatches], ' ELSE '' END + 
                    '[BetCount], ' +
                    '[ActiveMembers], ' +
                    '[RealIncome], ' +
                    '[RealTurnover], ' +
                    '[RealMargin] ' +
        'FROM #tmpFinal'
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

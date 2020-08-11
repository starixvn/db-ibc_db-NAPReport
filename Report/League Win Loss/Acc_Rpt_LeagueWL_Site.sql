/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Site @StartDate SMALLDATETIME,
                                          @EndDate SMALLDATETIME,
                                          @SportType INT,
										  @LeagueName VARCHAR(500),
                                          @MatchID INT,
                                          @LiveIndicator TINYINT,
										  @BetType INT,
                                          @SiteType VARCHAR(20),
										  @IsNoDraw BIT = 0
AS
/*
	Created: Jaden.Tang@20200810
	Task: View by Site (4th level drill down) in League Win Loss report
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Jaden.Tang: NAP Report - New drilldown level for League Win Loss (#138955)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportType: The sporttype to view on report
		- @LeagueName: The leaguename to view on report
        - @MatchID: The specific match to view on report
        - @LiveIndicator: To indicate the live status to view on report
		- @BetType: The bettype to view on report
		- @SiteType: Credit/Deposit/CN88
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
        EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Site @StartDate='20200620', @EndDate='20200630'
                    , @SportType=1, @LeagueName='DENMARK SUPER LEAGUE (PLAY OFF)', @MatchID=36693927, @LiveIndicator=0, @SiteType='Credit'
                    , @BetType=1, @IsNoDraw=0
*/

BEGIN
	SET NOCOUNT ON
	
    BEGIN /*gather match & outright data based on @StartDate*/
        CREATE TABLE #tmpMatch (matchid      INT,
                                matchcode    VARCHAR(500),
                                matchtype    TINYINT,
                                homeid       INT,
                                hometeamname VARCHAR(100),
                                awayid       INT,
                                awayteamname VARCHAR(100))

            ;WITH CTE_all_matches AS (
                SELECT m.matchid,
                    m.matchcode,
                    0 matchtype,
                    m.homeid,
                    m.awayid,
                    m.leagueid
                FROM [bodb02].[dbo].[match] m (NOLOCK)
                WHERE m.eventdate = @StartDate
                    AND m.matchid = @MatchID
                UNION ALL
                SELECT m.orid matchid,
                    m.matchcode,
                    1 matchtype,
                    m.teamid homeid,
                    -1 awayid,
                    m.leagueid
                FROM bodb02.dbo.outright m (NOLOCK)
                WHERE m.eventdate = @StartDate
                    AND m.orid = @MatchID
            )
        INSERT INTO #tmpMatch(matchid, matchcode, matchtype, homeid, hometeamname, awayid, awayteamname)
            SELECT matchid,
                matchcode,
                matchtype,
                homeid,
                ISNULL(home.teamname, '') hometeamname,
                awayid,
                ISNULL(away.teamname, '') awayteamname
            FROM CTE_all_matches m
            INNER JOIN [bodb02].[dbo].[league] l (NOLOCK)
                ON m.leagueid = l.leagueid
            LEFT JOIN bodb02.dbo.Team home (NOLOCK) 
                ON m.homeid = home.teamid
            LEFT JOIN bodb02.dbo.Team away (NOLOCK) 
                ON m.awayid = away.teamid
            WHERE l.leaguename = @LeagueName
                AND l.sporttype = @SportType
                AND l.isTest = 0
    END

    BEGIN /*gather agent-site data depending on @SiteType*/
        CREATE TABLE #agent (agentId INT PRIMARY KEY, 
                             site    VARCHAR(50))

        IF @SiteType = 'CN88'
            BEGIN
                INSERT INTO #Agent
                    SELECT c.CustId, c.Site
                    FROM bodb02..Customer AS c WITH(NOLOCK)
                    INNER JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
                        ON c.srecommend = cn88.CustId
                    WHERE c.RoleID = 2
            END
        ELSE
            IF @SiteType = 'Deposit'
                BEGIN
                    INSERT INTO #Agent
                        SELECT c.CustId, c.Site
                        FROM bodb02..Customer AS c WITH(NOLOCK)
                        INNER JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
                            ON c.srecommend = dep.CustId
                        WHERE c.RoleID = 2
                            AND c.CustId NOT IN (52466, 5707545);
                   
                    INSERT INTO #Agent SELECT 5707545, 'BEST-ODDS'
                END
            ELSE
                BEGIN
                    INSERT INTO #Agent
                        SELECT c.CustId, c.Site
                        FROM bodb02..Customer AS c WITH(NOLOCK)
                        LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
                            ON c.srecommend = dep.CustId
                        LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
                            ON c.srecommend = cn88.CustId
                        WHERE c.RoleID = 2
                            AND c.CustId NOT IN (52466, 5707545)
                            AND dep.CustId IS NULL
                            AND cn88.CustId IS NULL;
                    
                    INSERT INTO #Agent SELECT 52466, 'XYZBET'
                END
    END

	BEGIN /*staging data*/
        CREATE TABLE #tmpData (AgentId         INT,
                               Site			   VARCHAR(50),
                               MemberWinLoss   MONEY,
                               SMAWinLoss	   MONEY,
                               ExtraPT		   MONEY,
                               Commission	   MONEY,
                               RealIncome	   MONEY,
                               VirtualIncome   MONEY,
                               VarianceIncome  MONEY,
                               RealTurnover	   MONEY,
                               VirtualTurnover MONEY)
        
        --+ soccer, other sports
        INSERT INTO #tmpData (AgentId,
                            Site,
                            MemberWinLoss,
                            SMAWinLoss,
                            ExtraPT,
                            Commission,
                            RealIncome,
                            VirtualIncome,
                            VarianceIncome,
                            RealTurnover,
                            VirtualTurnover)
            SELECT  a.agentId,
                    a.site Site,
                    SUM((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
                    SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
                    SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                            ELSE (sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking) END) 
                        * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) 
                        * sd.actualrate
                        ) AS ExtraPT,
                    SUM(sd.scomm * sd.actualrate) AS Commission,
                    SUM((
                            sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
                            - CASE WHEN sd.tpositiontaking = 1 THEN 0
                                ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking) END 
                            * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
                        ) 
                        * sd.actualrate
                        ) AS RealIncome,
                    SUM((
                            sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost 
                            - CASE WHEN sd.tpositiontaking = 1 THEN 0
                                ELSE (sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) END
                        ) * sd.virtualrate 
                        + (
                            sd.scomm 
                            - CASE WHEN sd.tpositiontaking = 1 THEN 0
                                ELSE sd.scomm / (1 - sd.tpositiontaking) END 
                            * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
                        ) 
                        * sd.actualrate 
                        * (CASE WHEN sd.virtualrate < sd.actualrate THEN sd.virtualrate / sd.actualrate ELSE 1 END)
                        ) AS VirtualIncome,
                    SUM((
                            sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost -
                            CASE WHEN sd.tpositiontaking = 1 THEN 0
                                ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
                            END 
                            + CASE WHEN sd.virtualrate < sd.actualrate 
                                    THEN (sd.scomm - 
                                            (CASE WHEN tpositiontaking = 1 THEN 0 ELSE sd.scomm / (1 - sd.tpositiontaking) END) 
                                            * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                                ELSE 0
                            END
                        ) 
                        * (sd.actualrate - sd.virtualrate)) AS VarianceIncome,
                    SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                            ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                                * ABS(sd.stake)
                                * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
                                * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN  (sd.bettype < 999 
                                                                                OR sd.bettype BETWEEN 1301 AND 1399 
                                                                                OR sd.bettype BETWEEN 9001 AND 9399) 
                                                                            AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914)
                                                                            AND sd.bettype NOT BETWEEN 81 AND 120
                                                                            AND ABS(sd.modds) = 0.25
                                                                            AND sd.statusID IN (112, 113)
                                                                    THEN 0.5
                                                                    ELSE 1 END
                                        ELSE 1 END
                        END) AS RealTurnover, 
                    SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                            ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                                * ABS(sd.stake)
                                * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(sd.bettype < 999 
                                                                                OR sd.bettype BETWEEN 1301 AND 1399 
                                                                                OR sd.bettype BETWEEN 9001 AND 9399) 
                                                                            AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
                                                                            AND sd.bettype NOT BETWEEN 81 AND 120
                                                                            AND ABS(sd.modds) = 0.25
                                                                            AND sd.statusID IN (112, 113)
                                                                    THEN 0.5
                                                                    ELSE 1 END
                                        ELSE 1 END
                                * sd.virtualrate
                        END) AS VirtualTurnover
            FROM bodb02.dbo.bettrans sd (NOLOCK)
            INNER JOIN #tmpMatch m 
                ON sd.matchid = m.matchid
                    AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype --extra predicate to prevent dupplicated matchids
            INNER JOIN #agent a
                ON sd.recommend = a.agentId
            WHERE sd.winlostdate = @StartDate
                AND sd.ruben = 1
                AND sd.statusID IN (111, 112, 113)
                AND sd.currency NOT IN (20, 27, 28)
                AND sd.liveindicator = @LiveIndicator
                AND sd.bettype = @BetType
                AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
            GROUP BY a.agentId, a.site
            OPTION (RECOMPILE)

        --+ RM summary
        INSERT INTO #tmpData (AgentId,
                            Site,
                            MemberWinLoss,
                            SMAWinLoss,
                            ExtraPT,
                            Commission,
                            RealIncome,
                            VirtualIncome,
                            VarianceIncome,
                            RealTurnover,
                            VirtualTurnover)
            SELECT  '' AS AgentId,
                    CASE    WHEN @SportType = 1 AND t.AgentId = 52466   THEN 'Soccer 8RM'
                            WHEN @SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
                            WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 'Soccer BARM'
                            WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
                            ELSE '' END AS Site,
                    - SUM(MemberWinLoss) AS MemberWinLoss,
                    - SUM(SMAWinLoss) AS SMAWinLoss,
                    SUM(ExtraPT) AS ExtraPT,
                    SUM(Commission) AS Commission,
                    - SUM(RealIncome) AS RealIncome,
                    - SUM(VirtualIncome) AS VirtualIncome,
                    - SUM(VarianceIncome) AS VarianceIncome,
                    SUM(RealTurnover) AS RealTurnover, 
                    SUM(VirtualTurnover) AS VirtualTurnover
            FROM #tmpData t
            WHERE t.AgentId IN (52466, 5707545)
            GROUP BY CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 'Soccer 8RM'
                          WHEN @SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
                          WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 'Soccer BARM'
                          WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
                          ELSE '' END
    END
	
    -- final aggregation by Site, display report
	SELECT  Site,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #tmpData
    GROUP BY Site
    ORDER BY CASE WHEN Site = 'Soccer 8RM'        THEN 1
                  WHEN Site = 'Other Sports 8RM'  THEN 2
                  WHEN Site = 'Soccer BARM'       THEN 3
                  WHEN Site = 'Other Sports BARM' THEN 4
                  ELSE 0 END

	/*
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData
    DROP TABLE #agent
    */
END
GO

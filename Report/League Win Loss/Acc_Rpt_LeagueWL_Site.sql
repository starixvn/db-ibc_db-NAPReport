/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Site @StartDate SMALLDATETIME,
                                          @EndDate SMALLDATETIME,
                                          @SiteName VARCHAR(MAX) = 'ALL',
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
        - 20201016@Jaden.Tang: Refactor for code readability & new drilldowns (#144387)
        - 20212203@Jaden: Support SABA789 (#151326)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
        - @SiteName: Filter by list of site names (delimited by commas)
        - @MatchID: The specific match to view on report
        - @LiveIndicator: To indicate the live status to view on report
		- @BetType: The bettype to view on report
		- @SiteType: Credit/Deposit/CN88
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
        EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Site_xtest @StartDate='2020-09-06', @EndDate='2020-09-06'
                , @MatchID=38236262, @LiveIndicator=1, @SiteType='Credit', @BetType=2, @IsNoDraw=0
                , @SiteName = 'XYZBET,BEST-ODDS,611111'
*/

BEGIN
	SET NOCOUNT ON

    DECLARE @SportType INT
    BEGIN /*get sport type from league*/
        SELECT @SportType = sporttype 
        FROM (
            SELECT l.sporttype
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.match m WITH (NOLOCK)
                ON l.leagueid = m.leagueid
            WHERE m.matchid = @MatchID AND m.eventdate = @StartDate
            UNION ALL 
            SELECT l.sporttype
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.outright o WITH (NOLOCK)
                ON l.leagueid = o.leagueid
            WHERE o.orid = @MatchID AND o.eventdate = @StartDate
        ) t
        OPTION (RECOMPILE)
    END

    BEGIN /*filter by input site list*/
		CREATE TABLE #inputSites (SiteName NVARCHAR(100))
		IF @SiteName <> 'ALL' BEGIN
            INSERT INTO #inputSites
			    SELECT val SiteName
				FROM bodb02.dbo.strSplit(@SiteName, ',')
				WHERE LEN(val) > 0
		END
	END

    BEGIN /*gather agent-site data depending on @SiteType & @SiteName*/
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
                        AND (@SiteName = 'ALL' OR c.site IN (SELECT SiteName FROM #inputSites))
            END
        ELSE
            IF @SiteType = 'Deposit'
                BEGIN
                    ;WITH CTE_Dep AS (
                        SELECT c.CustId, c.Site
                        FROM bodb02..Customer AS c WITH(NOLOCK)
                        INNER JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
                            ON c.srecommend = dep.CustId
                            AND dep.site <> 'Saba789'
                        WHERE c.RoleID = 2
                            AND c.CustId NOT IN (52466, 5707545)
                                    UNION
                        SELECT 5707545, 'BEST-ODDS'
                    )
                    INSERT INTO #Agent
                        SELECT CustId, Site
                        FROM CTE_Dep
                        WHERE (@SiteName = 'ALL' OR Site IN (SELECT SiteName FROM #inputSites))
                END
            ELSE
                BEGIN
                    ;WITH CTE_Cre AS (
                        SELECT c.CustId, c.Site
                        FROM bodb02..Customer AS c WITH(NOLOCK)
                        LEFT JOIN DBWH.bodb_Account.dbo.vw_Dep_CustSuper dep WITH (NOLOCK)
                            ON c.srecommend = dep.CustId
                        LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
                            ON c.srecommend = cn88.CustId
                        WHERE c.RoleID = 2
                            AND c.CustId NOT IN (52466, 5707545)
                            AND dep.CustId IS NULL
                            AND cn88.CustId IS NULL
                                    UNION
                        SELECT 52466, 'XYZBET'
                    )
                    INSERT INTO #Agent
                        SELECT CustId, Site
                        FROM CTE_Cre
                        WHERE (@SiteName = 'ALL' OR Site IN (SELECT SiteName FROM #inputSites))
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
					SUM(sd.MemberWinLoss)			AS MemberWinLoss,
					SUM(sd.SMAWinLoss)				AS SMAWinLoss,
					SUM(sd.[Extra's Amount]) 		AS ExtraPT,
					SUM(sd.CommissionS) 			AS Commission,
					SUM(sd.RealHouseIncome) 		AS RealIncome,
					SUM(sd.VirtualHouseIncome) 		AS VirtualIncome,
					SUM(sd.VarianceHouseIncome) 	AS VarianceIncome,
					SUM(sd.RealHouseTurnover) 		AS RealTurnover, 
					SUM(sd.VirtualHouseTurnover) 	AS VirtualTurnover
            FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) sd
            INNER JOIN #agent a
                ON sd.recommend = a.agentId
            WHERE sd.winlostdate = @StartDate
                AND sd.matchid = @MatchID
                AND sd.ruben = 1
                AND sd.statusID IN (111, 112, 113)
                AND sd.currency NOT IN (20, 27, 28)
                AND sd.liveindicator = @LiveIndicator
                AND sd.bettype = @BetType
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
	SELECT  s.siteid SiteID,
            MAX(t.Site) SiteName,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            - SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #tmpData t
    LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK)
        ON t.Site = s.site
    GROUP BY s.siteid
    ORDER BY CASE WHEN MAX(t.Site) = 'Soccer 8RM'        THEN 2
                  WHEN MAX(t.Site) = 'Other Sports 8RM'  THEN 3
                  WHEN MAX(t.Site) = 'Soccer BARM'       THEN 4
                  WHEN MAX(t.Site) = 'Other Sports BARM' THEN 5
                  ELSE 1 END, SiteName

	DROP TABLE #tmpData
    DROP TABLE #agent
    DROP TABLE #inputSites
END
GO

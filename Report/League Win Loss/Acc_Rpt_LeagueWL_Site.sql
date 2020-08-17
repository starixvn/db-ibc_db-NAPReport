/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Site @StartDate SMALLDATETIME,
                                          @EndDate SMALLDATETIME,
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
        - @MatchID: The specific match to view on report
        - @LiveIndicator: To indicate the live status to view on report
		- @BetType: The bettype to view on report
		- @SiteType: Credit/Deposit/CN88
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
        EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Site @StartDate='20200809', @EndDate='20200630'
                    , @MatchID=36693927, @LiveIndicator=0, @SiteType='Credit', @BetType=1, @IsNoDraw=0
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

    BEGIN /*gather super-site data depending on @SiteType*/
        CREATE TABLE #super (SuperID INT PRIMARY KEY, 
                             Site    VARCHAR(50))

        IF @SiteType = 'CN88'
            INSERT INTO #super
                SELECT c.CustId AS SuperID, c.Site
                FROM bodb02..Customer AS c WITH(NOLOCK)
                INNER JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
                    ON c.srecommend = cn88.CustId
                WHERE c.RoleID = 4
        ELSE
            IF @SiteType = 'Deposit'
                INSERT INTO #super
                    SELECT CustId AS SuperID, Site
                    FROM bodb02..Dep_CustSuper WITH(NOLOCK)
            ELSE
                INSERT INTO #super
                    SELECT s.CustId AS SuperID, s.Site
                    FROM bodb02..Customer AS s WITH(NOLOCK)
                    LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
                        ON s.custid = dep.CustId
                    LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
                        ON s.srecommend = cn88.CustId
                    WHERE s.RoleID = 4
                        AND dep.CustId IS NULL
                        AND cn88.CustId IS NULL
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
            SELECT  sd.recommend AgentID,
                    s.site Site,
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
            FROM bodb02.dbo.bettrans sd WITH (NOLOCK)
            INNER JOIN #super s
                ON sd.srecommend = s.SuperID
            WHERE sd.winlostdate = @StartDate
                AND sd.matchid = @MatchID
                AND sd.ruben = 1
                AND sd.statusID IN (111, 112, 113)
                AND sd.currency NOT IN (20, 27, 28)
                AND sd.liveindicator = @LiveIndicator
                AND sd.bettype = @BetType
                AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
            GROUP BY sd.recommend, s.site
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
                  ELSE 1 END

	DROP TABLE #tmpData
    DROP TABLE #super
END
GO

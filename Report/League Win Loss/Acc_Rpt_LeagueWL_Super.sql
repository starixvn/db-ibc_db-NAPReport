/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Super @StartDate SMALLDATETIME,
                                           @EndDate SMALLDATETIME,
                                           @SiteID INT,
                                           @SportName NVARCHAR(100) = 'Soccer',
                                           @MatchID INT,
                                           @LiveIndicator TINYINT,
										   @BetType INT,
										   @IsNoDraw BIT = 0
AS
/*
	Created: Jaden.Tang@20200812
	Task: View by Super (5th level drill down) in League Win Loss report
	DB: DBACC.bodb02

	Revisions:
		- 20200812@Jaden.Tang: NAP Report - New drilldown level for League Win Loss (#138955)
        - 20201016@Jaden.Tang: Refactor for code readability & new drilldowns (#144387)
        - 20210520@Jaden.Tang: SABA Soccer Pin Goal (#155447)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
        - @SiteID: The site id of data to view on report (coming from 4th level drill)
        - @SportName: The user selected sport coming from SportType report
        - @MatchID: The specific match to view on report
        - @LiveIndicator: To indicate the live status to view on report
		- @BetType: The bettype to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
       EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Super_xtest @StartDate='20200620', @EndDate='20200630'
                , @MatchID=36693927, @SiteID = 3, @LiveIndicator=0, @BetType=1, @IsNoDraw=0
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

    BEGIN /*gather agent-super data depending on @SiteID*/
        CREATE TABLE #agentSuper (AgentID   INT PRIMARY KEY, 
                                  SuperID   INT,
                                  SuperName VARCHAR(30))

        INSERT INTO #agentSuper
        SELECT agent.custid Agent, super.custid SuperID, super.username SuperName
        FROM bodb02.dbo.Customer agent WITH (NOLOCK)
        INNER JOIN bodb02.dbo.Customer super WITH (NOLOCK)
            ON agent.srecommend = super.custid
                AND super.roleid = 4
        INNER JOIN bodb02.dbo.Site s WITH (NOLOCK)
            ON agent.site = s.site -->>filter by agent to get "current" snapsnot of working agents from a site
        WHERE s.siteid = @SiteID
            AND agent.roleid = 2
        OPTION (RECOMPILE)
    END

	BEGIN /*staging data*/
        CREATE TABLE #tmpData (AgentID         INT,
                               SuperID         INT,
                               SuperName	   VARCHAR(50),
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
        INSERT INTO #tmpData (AgentID,
                              SuperID,
                              SuperName,
                              MemberWinLoss,
                              SMAWinLoss,
                              ExtraPT,
                              Commission,
                              RealIncome,
                              VirtualIncome,
                              VarianceIncome,
                              RealTurnover,
                              VirtualTurnover)
            SELECT  s.AgentID,
                    MAX(s.SuperID),
                    MAX(s.SuperName),
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
            INNER JOIN #agentSuper s
                ON sd.recommend = s.AgentID
            WHERE sd.winlostdate = @StartDate
                AND sd.matchid = @MatchID
                AND sd.ruben = 1
                AND sd.statusID IN (111, 112, 113)
                AND sd.currency NOT IN (20, 27, 28)
                AND sd.liveindicator = @LiveIndicator
                AND sd.bettype = @BetType
            GROUP BY s.AgentId
            OPTION (RECOMPILE)

        --+ RM summary
        INSERT INTO #tmpData (SuperName,
                            MemberWinLoss,
                            SMAWinLoss,
                            ExtraPT,
                            Commission,
                            RealIncome,
                            VirtualIncome,
                            VarianceIncome,
                            RealTurnover,
                            VirtualTurnover)
            SELECT  CASE    WHEN @SportType = 1 AND t.AgentId = 52466   THEN @SportName + ' 8RM'
                            WHEN @SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
                            WHEN @SportType = 1 AND t.AgentId = 5707545 THEN @SportName + ' BARM'
                            WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
                            ELSE '' END AS SuperName, --place holder
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
            GROUP BY CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN @SportName + ' 8RM'
                          WHEN @SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
                          WHEN @SportType = 1 AND t.AgentId = 5707545 THEN @SportName + ' BARM'
                          WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
                          ELSE '' END
    END
	
    -- final aggregation by SuperID, display report
    -- check if this master has VR settings (core logic extracted from Acc_Rpt_LeagueWL_CustVirtualMultiplierSel)
    ;WITH CTE_currVirtualRate AS (
		SELECT custid, 
            CASE WHEN ISNULL(VirtualMultiplier, 0) <> 0 THEN 1 ELSE 0 END HasVR
		FROM bodb02.dbo.custInfo WITH (NOLOCK)
	)
	SELECT  t.SuperID SuperID,
            t.SuperName SuperName,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            - SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover,
            CAST(CASE WHEN EXISTS (SELECT 1 FROM CTE_currVirtualRate cte WHERE cte.custid = t.SuperID AND cte.HasVR = 1) 
                      THEN 1
                      ELSE 0 END 
                 AS BIT) HasVR
	FROM #tmpData t
    GROUP BY t.SuperID, t.SuperName
    ORDER BY CASE WHEN t.SuperName = @SportName + ' 8RM' THEN 2
                  WHEN t.SuperName = 'Other Sports 8RM'  THEN 3
                  WHEN t.SuperName = @SportName + ' BARM' THEN 4
                  WHEN t.SuperName = 'Other Sports BARM' THEN 5
                  ELSE 1 END, SuperName

	DROP TABLE #tmpData
    DROP TABLE #agentSuper
END
GO

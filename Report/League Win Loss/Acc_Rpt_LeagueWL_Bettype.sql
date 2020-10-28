/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Bettype @StartDate SMALLDATETIME,
											 @EndDate SMALLDATETIME,
											 @SportBettype VARCHAR(MAX),
											 @SiteName VARCHAR(MAX) = 'ALL',
											 @MatchID INT,
											 @LiveIndicator BIT,
											 @IsNoDraw BIT = 0,
											 @IsIncludeSiteType BIT = 1
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by bettypes
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200626@Ned.Le: NAP Report - Enhancement for searching a league info on Punter Analysis and League Win Loss Report (#136277)
		- 20200814@Jaden.Tang: NAP Report - Enhancement for League Win Loss (#138955) - New dimensions
								+ Moved one level down (drill down: League > Match > **Bet Type** > ... )
								+ Add filter by SiteName
		- 20201016@Jaden.Tang: Refactor for code readability & new drilldowns (#144387)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @SiteName: Filter by list of site names (delimited by commas)
		- @MatchID: The specific match to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report
		- @IsIncludeSiteType: Include site info (credit/deposit/cn88) in report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Bettype_xtest @StartDate='2020-09-06', @EndDate='2020-09-06', 
			@MatchID=38236262, @LiveIndicator=1, @IsNoDraw=0, 
			@SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1',
			@SiteName = '12Bet,755555,INDO,789y,IBCIndo,BEST-ODDS,722222,733333,XYZBET,asiabet88'
*/

BEGIN

	SET NOCOUNT ON

	BEGIN /*split the array @SportBettype into a temp table*/
		CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
											 BetType SMALLINT)

		;WITH CTE_SportBettypeMatrix AS (
			SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
				   CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
			FROM bodb02.dbo.strSplit(@SportBettype, ',')
			WHERE LEN(val) > 0
		)
		INSERT INTO #tmpSportBettypeMatrix (SportType, BetType)
		SELECT cte.SportType, cte.BetType
		FROM CTE_SportBettypeMatrix cte
	END

	DECLARE @SportType INT
    BEGIN /*get sport type from @MatchID*/
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

	BEGIN /*get a list of Supers by site type*/
		CREATE TABLE #super (SuperID   INT PRIMARY KEY, 
                             SiteType  VARCHAR(7))

		INSERT INTO #super
			SELECT DISTINCT 
				   s.srecommend AS SuperID,
				   CASE WHEN cn88.CustId IS NOT NULL THEN 'CN88'
				 		WHEN dep.custid  IS NOT NULL THEN 'Deposit'
						ELSE 'Credit' END AS SiteType
			FROM bodb02..Customer AS s WITH(NOLOCK)
			LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
				ON s.srecommend = dep.CustId
			LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
				ON s.srecommend = cn88.CustId
			WHERE s.RoleID = 2 -- always get Site info from Agent
	END

	BEGIN -- #tmpAgentBySite: list of active agents in the list input @SiteName
		CREATE TABLE #tmpAgentBySite (AgentID INT)
		IF @SiteName <> 'ALL' BEGIN
			;WITH CTE_Sites AS (
				SELECT val SiteName
				FROM bodb02.dbo.strSplit(@SiteName, ',')
				WHERE LEN(val) > 0
			)
			INSERT INTO #tmpAgentBySite
				SELECT custid AgentID
				FROM bodb02.dbo.Customer
				WHERE roleid = 2
					AND site IN (SELECT SiteName FROM CTE_Sites)
		END
	END

	BEGIN /*build staging data by agent-super-bettype dimension*/
		CREATE TABLE #agentSuperBettype (AgentID				INT,
							   			 SuperID				INT,
							   			 Bettype				INT,
							   			 MemberWinLoss			MONEY,
							   			 SMAWinLoss				MONEY,
							   			 ExtraPT				MONEY,
							   			 Commission				MONEY,
							   			 RealIncome				MONEY,
							   			 VirtualIncome			MONEY,
							   			 VarianceIncome			MONEY,
							   			 RealTurnover			MONEY,
							   			 VirtualTurnover		MONEY,
							   			 SummaryLineIdentifier  TINYINT)
		
		--+ Soccer, Other Sports
		INSERT INTO #agentSuperBettype (AgentID,
							  			SuperID,
							  			Bettype,
							  			MemberWinLoss,
							  			SMAWinLoss,
							  			ExtraPT,
							  			Commission,
							  			RealIncome,
							  			VirtualIncome,
							  			VarianceIncome,
							  			RealTurnover,
							  			VirtualTurnover)
			SELECT  sd.recommend  					AS AgentID,
					sd.srecommend 					AS SuperID,
					sd.BetType 	  					AS BetType,
					SUM(sd.MemberWinLoss)			AS MemberWinLoss,
					SUM(sd.SMAWinLoss)				AS SMAWinLoss,
					SUM(sd.[Extra's Amount]) 		AS ExtraPT,
					SUM(sd.TreeCommission) 			AS Commission,
					SUM(sd.RealHouseIncome) 		AS RealIncome,
					SUM(sd.VirtualHouseIncome) 		AS VirtualIncome,
					SUM(sd.VarianceHouseIncome) 	AS VarianceIncome,
					SUM(sd.RealHouseTurnover) 		AS RealTurnover, 
					SUM(sd.VirtualHouseTurnover) 	AS VirtualTurnover
			FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) sd
			INNER JOIN #tmpSportBettypeMatrix mtrix
				ON mtrix.BetType = sd.bettype AND mtrix.SportType = @SportType
			WHERE sd.winlostdate = @StartDate
				AND sd.matchid = @MatchID
				AND sd.liveindicator = @LiveIndicator
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND (@SiteName = 'ALL' OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
			GROUP BY sd.recommend, sd.srecommend, sd.BetType
			OPTION (RECOMPILE)
	
        --+ RM summary
        INSERT INTO #agentSuperBettype (SummaryLineIdentifier,
                              			MemberWinLoss,
                              			SMAWinLoss,
                              			ExtraPT,
                              			Commission,
                              			RealIncome,
                              			VirtualIncome,
                              			VarianceIncome,
                              			RealTurnover,
                              			VirtualTurnover)
            SELECT  CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 1 -- dummy for 'Soccer 8RM'
                         WHEN @SportType > 1 AND t.AgentId = 52466   THEN 2 -- dummy for 'Other Sports 8RM'
                         WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 3 -- dummy for 'Soccer BARM'
                         WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 4 -- dummy for 'Other Sports BARM'
                         ELSE 0 END AS SummaryLineIdentifier,
                    - SUM(MemberWinLoss) AS MemberWinLoss,
                    - SUM(SMAWinLoss) AS SMAWinLoss,
                    SUM(ExtraPT) AS ExtraPT,
                    SUM(Commission) AS Commission,
                    - SUM(RealIncome) AS RealIncome,
                    - SUM(VirtualIncome) AS VirtualIncome,
                    - SUM(VarianceIncome) AS VarianceIncome,
                    SUM(RealTurnover) AS RealTurnover, 
                    SUM(VirtualTurnover) AS VirtualTurnover
            FROM #agentSuperBettype t
            WHERE t.AgentId IN (52466, 5707545)
            GROUP BY CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 1
                          WHEN @SportType > 1 AND t.AgentId = 52466   THEN 2
                          WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 3
                          WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 4
                          ELSE 0 END
	END

	/* final aggregation by: 
		- if @IsIncludeSiteType = 1: bet type and site types
		- if @IsIncludeSiteType = 0: bet type only */
	SELECT  Bettype AS BetTypeID,
			MAX(bt.typenamee) AS BetTypeName,
			CASE WHEN t.SummaryLineIdentifier = 1 THEN 'Soccer 8RM'
				 WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				 WHEN t.SummaryLineIdentifier = 3 THEN 'Soccer BARM'
				 WHEN t.SummaryLineIdentifier = 4 THEN 'Other Sports BARM'
				 ELSE CASE WHEN @IsIncludeSiteType = 1 THEN super.SiteType END
			END AS SiteType,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            - SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #agentSuperBettype t
	LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK)
		ON t.Bettype = bt.typeid
	LEFT JOIN #super AS super
		ON t.SuperID = super.SuperID
	GROUP BY Bettype, t.SummaryLineIdentifier
			,CASE WHEN t.SummaryLineIdentifier = 1 THEN 'Soccer 8RM'
				  WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				  WHEN t.SummaryLineIdentifier = 3 THEN 'Soccer BARM'
				  WHEN t.SummaryLineIdentifier = 4 THEN 'Other Sports BARM'
				  ELSE CASE WHEN @IsIncludeSiteType = 1 THEN super.SiteType END
			 END
	ORDER BY CASE WHEN BetType = 1		THEN 1		--Handicap
				  WHEN BetType = 301	THEN 2		--% Handicap
				  WHEN BetType = 3		THEN 3		--Over/Under
				  WHEN BetType = 302	THEN 4		--% Over/Under
				  WHEN BetType = 7		THEN 5		--1st Half Handicap
				  WHEN BetType = 303	THEN 6		--1H % Handicap
				  WHEN BetType = 8		THEN 7		--1st Half Over/Under
				  WHEN BetType = 304	THEN 8		--1H % Over/Under
				  WHEN BetType = 2		THEN 9		--Odd/Even
				  WHEN BetType = 5		THEN 10		--1X2
				  WHEN BetType = 4		THEN 11		--Correct Score
				  WHEN BetType = 6		THEN 12		--Total Goal
				  WHEN BetType = 10		THEN 13		--Outright
				  ELSE 
				  	CASE WHEN t.SummaryLineIdentifier > 0 THEN 99 ELSE 14 END
			 END -- first priority bet type group
			 , BetTypeName --then order by name
			 , 3 ASC -- then order "SiteType" NULL first
			 , t.SummaryLineIdentifier

	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #super
	DROP TABLE #agentSuperBettype
	DROP TABLE #tmpAgentBySite
END
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Bettype @StartDate SMALLDATETIME,
											 @EndDate SMALLDATETIME,
											 @SportBettype VARCHAR(MAX),
											 @SiteName VARCHAR(MAX) = 'ALL',
											 @GlobalShowTime VARCHAR(MAX) = '0',
											 @SportType INT,
											 @SportName NVARCHAR(100) = 'Soccer', /*Not related to @SportType above*/
											 @LeagueName VARCHAR(500) = '', /*1st report flow*/
											 @MatchID INT = -1,				/*2nd report flow*/
											 @IsNoDraw BIT = 0,
											 @LiveIndicator TINYINT = 2,		/*for 2nd report flow, this SP would be called 2 times*/
											 @IsIncludeSiteType BIT = 1,	/*1st report flow = 1; 2nd report flow = 0*/
											 @IsIncludeHedge BIT = 0		/*1st report flow = 0; 2nd report flow = 1*/
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
		- 20210126@Jaden.Tang: global show time filter (#147450)
		- 20210208@Jaden.Tang: Hotfix - change LiveIndicator type to TINYINT (#150190)
		- 20212203@Jaden: Support SABA789 (#151326)
		- 20210520@Jaden.Tang: SABA Soccer Pin Goal (#155447)
		- 20210824@Jaden.Tang: Hotfix #160586 - incorrect bet type when drilldown from leagues with same name across different sports

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @SiteName: Filter by list of site names (delimited by commas)
		- @MatchID: The specific match to view on report
		- @LeagueName: The specific league to view on report, can be used without matchid
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report
		- @IsIncludeSiteType: Include site info (credit/deposit/cn88) in report
			Example (web view):
			- @IsIncludeSiteType = 0
				Bet type		 |	Member Winloss
				----------------------------------
				Handicap		 |	10,000
			
			- @IsIncludeHedge = 1
				Bet type		 |	Member Winloss
				----------------------------------
				Handicap		 |	10,000
					Credit		 |	 5,000
					Deposit		 |   4,000
					CN88		 |   1,000
		- @IsIncludeHedge: Further groups by hedge matches / bettypes
			Example (web view):
			- @IsIncludeHedge = 0	
				Bet type		 |	Member Winloss
				----------------------------------
				Handicap		 |	10,000
			
			- @IsIncludeHedge = 1
				Bet type		 |	Member Winloss
				----------------------------------
				Handicap		 |	8,000
				Handicap (hedge) |	2,000
		- @GlobalShowTime: refer to to [Acc_Rpt_LeagueWL_Sporttype.sql]
		- @SportType: the selected sport ID from SportType report result set
		- @SportName: The user selected sport group coming from SportType report
			Example: Soccer, SABA Soccer, SABA Soccer PinGoal, Basketball...

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Bettype_xtest @StartDate='2020-09-06', @EndDate='2020-09-06', 
			@MatchID=38236262, @LiveIndicator=1, @IsNoDraw=0, 
			@SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1',
			@SportType = 1,
			@SiteName = '12Bet,755555,INDO,789y,IBCIndo,BEST-ODDS,722222,733333,XYZBET,asiabet88'
*/

BEGIN

	SET NOCOUNT ON

	-- web can't send NULLs
	IF @LeagueName = '' SET @LeagueName = NULL
	IF @MatchID = -1 SET @MatchID = NULL

	DECLARE @IsLive BIT = NULL
	IF @LiveIndicator IN (0, 1) SET @IsLive = @LiveIndicator

	IF REPLACE(@GlobalShowTime, ' ', '') = '1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24'
		SET @GlobalShowTime = '0'

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

	BEGIN --#tmpGlobalShowTime
		CREATE TABLE #tmpGlobalShowTime (ID TINYINT, [From] TIME, [To] TIME)

		;WITH CTE_EnumDict AS (
			SELECT *
			FROM (
			VALUES
				(0,  '00:00:00', '23:59:59'),
				(1,  '00:00:00', '00:59:59'),
				(2,  '01:00:00', '01:59:59'),
				(3,  '02:00:00', '02:59:59'),
				(4,  '03:00:00', '03:59:59'),
				(5,  '04:00:00', '04:59:59'),
				(6,  '05:00:00', '05:59:59'),
				(7,  '06:00:00', '06:59:59'),
				(8,  '07:00:00', '07:59:59'),
				(9,  '08:00:00', '08:59:59'),
				(10, '09:00:00', '09:59:59'),
				(11, '10:00:00', '10:59:59'),
				(12, '11:00:00', '11:59:59'),
				(13, '12:00:00', '12:59:59'),
				(14, '13:00:00', '13:59:59'),
				(15, '14:00:00', '14:59:59'),
				(16, '15:00:00', '15:59:59'),
				(17, '16:00:00', '16:59:59'),
				(18, '17:00:00', '17:59:59'),
				(19, '18:00:00', '18:59:59'),
				(20, '19:00:00', '19:59:59'),
				(21, '20:00:00', '20:59:59'),
				(22, '21:00:00', '21:59:59'),
				(23, '22:00:00', '22:59:59'),
				(24, '23:00:00', '23:59:59')
			)sub (ID, [From], [To])
		)
		INSERT INTO #tmpGlobalShowTime
			SELECT CTE_EnumDict.ID, [From], [To]
			FROM CTE_EnumDict
			INNER JOIN bodb02.dbo.strSplit(@GlobalShowTime, ',') s
			ON CTE_EnumDict.ID = s.val
	END

    BEGIN
		CREATE TABLE #tmpMatch (SportType INT, MatchID INT, MatchCode NVARCHAR(100), IsOutright BIT)

		INSERT INTO #tmpMatch
		SELECT sporttype, matchid, matchcode, IsOutright
        FROM (
            SELECT l.sporttype, m.matchid, m.matchcode, 0 AS IsOutright, GlobalShowTime
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.match m WITH (NOLOCK)
                ON l.leagueid = m.leagueid
            WHERE (m.matchid = ISNULL(@MatchID, m.matchid) AND l.leaguename = ISNULL(@LeagueName, l.leaguename))
				AND l.sporttype = @SportType
				AND m.eventdate = @StartDate
            UNION ALL 
            SELECT l.sporttype, o.orid, o.matchcode, 1 AS IsOutright, NULL
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.outright o WITH (NOLOCK)
                ON l.leagueid = o.leagueid
            WHERE (o.orid = ISNULL(@MatchID, o.orid) AND l.leaguename = ISNULL(@LeagueName, l.leaguename))
				AND l.sporttype = @SportType
				AND o.eventdate = @StartDate
				AND @GlobalShowTime = '0' /* if user filters by GlobalShowTime, then ignore outright data*/
        ) t
		, #tmpGlobalShowTime gst
		WHERE @GlobalShowTime = '0'
		   OR (@GlobalShowTime != '0' AND CONVERT(TIME, t.GlobalShowTime) BETWEEN gst.[From] AND gst.[To])
        OPTION (RECOMPILE)
    END

	BEGIN /*get a list of Supers by site type*/
	    CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
		INSERT INTO #DepositSuper
			SELECT CustId
			FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);

		CREATE TABLE #super (SuperID   INT PRIMARY KEY, 
                             SiteType  VARCHAR(7))

		INSERT INTO #super
			SELECT DISTINCT 
				   s.srecommend AS SuperID,
				   CASE WHEN cn88.CustId IS NOT NULL THEN 'CN88'
				 		WHEN dep.custid  IS NOT NULL THEN 'Deposit'
						ELSE 'Credit' END AS SiteType
			FROM bodb02..Customer AS s WITH(NOLOCK)
			LEFT JOIN #DepositSuper dep WITH (NOLOCK)
				ON s.srecommend = dep.CustId
			LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
				ON s.srecommend = cn88.CustId
			WHERE s.RoleID = 2 -- always get Site info from Agent

		DROP TABLE #DepositSuper
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
										 MatchCode				NVARCHAR(100),
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
										MatchCode,
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
					sd.matchid						AS MatchCode,
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
			INNER JOIN #tmpSportBettypeMatrix mtrix
				ON mtrix.BetType = sd.bettype AND mtrix.SportType = @SportType
			WHERE sd.winlostdate = @StartDate
				AND sd.matchid IN (SELECT MatchID FROM #tmpMatch UNION ALL SELECT 29)
				AND sd.liveindicator = ISNULL(@IsLive, sd.liveindicator)
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND (@SiteName = 'ALL' OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
			GROUP BY sd.recommend, sd.srecommend, sd.BetType, sd.matchid
			OPTION (RECOMPILE)
		
		DELETE FROM #agentSuperBettype WHERE MatchCode = '29' --a trick to improve optimizer estimation, making match data less skewed

		UPDATE sd
			SET sd.MatchCode = m.MatchCode
			FROM #agentSuperBettype sd
			INNER JOIN #tmpMatch m 
				ON sd.MatchCode = m.matchid 
				AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.IsOutright

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
            SELECT  CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 1 -- dummy for @SportName + ' 8RM'
                         WHEN @SportType > 1 AND t.AgentId = 52466   THEN 2 -- dummy for 'Other Sports 8RM'
                         WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 3 -- dummy for @SportName + ' BARM'
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
		- if @IsIncludeSiteType = 0: bet type only 
		- if @IsIncludeHedge = 1: also group by hedge matches or non-hedge matches*/
	SELECT  Bettype AS BetTypeID,
			MAX(bt.typenamee) AS BetTypeName,
			CASE WHEN @IsIncludeHedge = 1 THEN 
				CASE WHEN t.MatchCode NOT LIKE '%hedge%' THEN 0 
					 WHEN t.MatchCode     LIKE '%hedge%' THEN 1
				END 
			 END AS IsHedge,
			CASE WHEN t.SummaryLineIdentifier = 1 THEN @SportName + ' 8RM'
				 WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				 WHEN t.SummaryLineIdentifier = 3 THEN @SportName + ' BARM'
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
	GROUP BY Bettype
			,CASE WHEN @IsIncludeHedge = 1 THEN 
				CASE WHEN t.MatchCode NOT LIKE '%hedge%' THEN 0 
					 WHEN t.MatchCode     LIKE '%hedge%' THEN 1
				END 
			 END
			, t.SummaryLineIdentifier
			,CASE WHEN t.SummaryLineIdentifier = 1 THEN @SportName + ' 8RM'
				  WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				  WHEN t.SummaryLineIdentifier = 3 THEN @SportName + ' BARM'
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
			 , 4 ASC -- then order "SiteType" NULL first
			 , 3
			 , t.SummaryLineIdentifier

	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #super
	DROP TABLE #agentSuperBettype
	DROP TABLE #tmpAgentBySite
END
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Match @StartDate SMALLDATETIME,
                                           @EndDate SMALLDATETIME,
                                           @SportBettype VARCHAR(MAX),
										   @BetType	INT = -1,					/*1st report flow = -1; 2nd report flow = input from Bet type report*/	
										   @SiteName VARCHAR(MAX) = 'ALL',
										   @GlobalShowTime VARCHAR(MAX) = '0',
										   @SportType INT,
										   @SportName NVARCHAR(100) = 'Soccer', /*Not related to @SportType above*/
										   @LeagueID VARCHAR(MAX),
										   @IsNoDraw BIT = 0,
										   @LiveIndicator TINYINT = 2,			/*1st report flow = 2; 2nd report flow = 0 or 1*/
										   @ShowHedgeMatchOnly BIT = 0			/*1st report flow = 0; 2nd report flow = input from Bet type report*/
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by match information
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200626@Ned.Le: NAP Report - Enhancement for searching a league info on Punter Analysis and League Win Loss Report (#136277)
		- 20200813@Jaden.Tang: NAP Report - Enhancement for League Win Loss (#138955) - New dimensions
								+ Changed name from Acc_Rpt_LeagueWL_Details to Acc_Rpt_LeagueWL_Match
								+ Moved one level up (drill down: League > **Match** > Bet Type > ... )
								+ Add filter by SiteName
		- 20201016@Jaden.Tang: Refactor for code readability & performance & new drilldowns (#144387)
		- 20210126@Jaden.Tang: global show time filter (#147450)
		- 20210224@Jaden.Tang: Integrate Cricket AIO (#148454)
		- 20210520@Jaden.Tang: SABA Soccer Pin Goal (#155447)
		- 20210824@Jaden.Tang: Hotfix #160586 - incorrect bet type when drilldown from leagues with same name across different sports
		- 20210910@Jaden.Tang: Split match code into separate column (#160196)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportName: The user selected sport coming from SportType report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other, this list is build from the drop-down list of
						 front-end website, correspond to selections of user
		                 Example '1_1,1_3' --> 'Soccer_Handicap,Soccer_Over/Under...'
		- @BetType: The specific bet type to view, included in new drilldown flow from #144387
		- @SiteName: Filter by list of site names (delimited by commas)
		- @LeagueID: The specific leagues to view on report, a list delimited by comma, can be used without matchid
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report
		- @LiveIndicator: Include live indicators (live/non-live) in report
			- 0: filter bettrans by liveindicator = 0, result LiveIndicator column = null
			- 1: filter bettrans by liveindicator = 1, result LiveIndicator column = null
			- 2: no filter
		- @ShowHedgeMatchOnly: Only show hedge matches
		- @GlobalShowTime: refer to to [Acc_Rpt_LeagueWL_Sporttype.sql]
		- @SportType: the selected sport ID from SportType report result set
		- @SportName: The user selected sport group coming from SportType report
			Example: Soccer, SABA Soccer, SABA Soccer PinGoal, Basketball...

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match @StartDate='2021-02-21', @EndDate='2021-02-28',
			@LeagueID='3,4,5', @IsNoDraw=0,
			@SportBettype='10000_9,10000_29,50_3',
			@SportType = 1
*/

BEGIN

	SET NOCOUNT ON

	-- web can't send NULLs
	IF @BetType = -1 SET @BetType = NULL

	DECLARE @IsLive BIT = NULL
	IF @LiveIndicator IN (0, 1) SET @IsLive = @LiveIndicator

	IF REPLACE(@GlobalShowTime, ' ', '') = '1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24'
		SET @GlobalShowTime = '0'

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

	BEGIN /*get match data from @LeagueID by @StartDate*/
		CREATE TABLE #tmpMatch (matchid 	 INT,
								matchcode 	 NVARCHAR(100),
								matchtype 	 TINYINT,
								homeid 		 INT,
								awayid 		 INT)

		;WITH CTE_all_matches_by_day AS (
			SELECT  matchid,
					matchcode,
					0 matchtype,
					homeid,
					awayid,
					leagueid,
					GlobalShowTime
			FROM bodb02.dbo.match WITH (NOLOCK)
			WHERE eventdate = @StartDate
			UNION ALL
			SELECT  orid matchid,
					matchcode,
					1 matchtype,
					teamid homeid,
					-1 awayid, --'outright' matches do not have 'away' team 
					leagueid,
					NULL
			FROM bodb02.dbo.outright WITH (NOLOCK)
			WHERE eventdate = @StartDate
				AND @GlobalShowTime = '0' /* if user filters by GlobalShowTime, then ignore outright data*/
		),
		CTE_Param AS (
			SELECT val LeagueID FROM bodb02.dbo.strSplit(@LeagueID, ',')
		)
		INSERT INTO #tmpMatch (matchid, matchcode, matchtype, homeid, awayid)
			SELECT  matchid,
					matchcode,
					matchtype,
					homeid,
					awayid
			FROM CTE_all_matches_by_day m
			INNER JOIN CTE_Param l
			ON m.leagueid = l.LeagueID
			, #tmpGlobalShowTime gst
			WHERE @GlobalShowTime = '0'
			   OR (@GlobalShowTime != '0' AND CONVERT(TIME, m.GlobalShowTime) BETWEEN gst.[From] AND gst.[To])
			OPTION (RECOMPILE)
	END

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
			WHERE cte.SportType = @SportType
				AND cte.BetType = ISNULL(@BetType, cte.BetType)
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
				FROM bodb02.dbo.Customer WITH (NOLOCK)
				WHERE roleid = 2
					AND site IN (SELECT SiteName FROM CTE_Sites)
		END
	END

	BEGIN -- #matchBettypeTmp: staging table for performance enhancement
		-- Join directly with bettrans table on match, sporttype, bettype for reports that 
		-- include sport book data will cause estimation problem.
		CREATE TABLE #matchLiveIndTmp (MatchID			INT, 
									   BetType			INT,
									   LiveIndicator	BIT,
								  	   MemberWinLoss	MONEY,
								  	   SMAWinLoss		MONEY,
								  	   ExtraPT			MONEY,
								  	   Commission		MONEY,
								  	   RealIncome		MONEY,
								  	   VirtualIncome	MONEY,
								  	   VarianceIncome	MONEY,
								  	   RealTurnover		MONEY,
								  	   VirtualTurnover	MONEY)
		
		INSERT INTO #matchLiveIndTmp
			SELECT 
				sd.matchid,
				sd.bettype,
				sd.liveindicator,
				SUM(sd.MemberWinLoss),
				SUM(sd.SMAWinLoss),
				SUM(sd.[Extra's Amount]) 		AS ExtraPT,
				SUM(sd.CommissionS) 			AS Commission,
				SUM(sd.RealHouseIncome) 		AS RealIncome,
				SUM(sd.VirtualHouseIncome) 		AS VirtualIncome,
				SUM(sd.VarianceHouseIncome) 	AS VarianceIncome,
				SUM(sd.RealHouseTurnover) 		AS RealTurnover, 
				SUM(sd.VirtualHouseTurnover) 	AS VirtualTurnover
			FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) sd
			WHERE sd.winlostdate = @StartDate
					AND sd.ruben = 1
					AND sd.statusID IN (111, 112, 113)
					AND sd.currency NOT IN (20, 27, 28)
					AND ('ALL' = @SiteName OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
					AND sd.bettype IN (SELECT BetType FROM #tmpSportBettypeMatrix)
					AND sd.liveindicator = ISNULL(@IsLive, sd.liveindicator)
			GROUP BY sd.matchid, sd.bettype, sd.liveindicator
			OPTION (RECOMPILE)
	END

	CREATE TABLE #tmpDataFiltered ( MatchID				INT,
									HomeID				INT,
									AwayID				INT,
									MatchCode			NVARCHAR(100),
									LiveIndicator		BIT,
									MemberWinLoss		MONEY,
									SMAWinLoss			MONEY,
									ExtraPT				MONEY,
									Commission			MONEY,
									RealIncome			MONEY,
									VirtualIncome		MONEY,
									VarianceIncome		MONEY,
									RealTurnover		MONEY,
									VirtualTurnover		MONEY)
	BEGIN /* further filter by match */
		-- + Soccer, Other Sports
		INSERT INTO #tmpDataFiltered
			SELECT  m.matchid,
					MAX(m.homeid),		    -- 1 matchid : 1 homeid
					MAX(m.awayid),		    -- 1 matchid : 1 awayid
					MAX(m.matchcode),     	-- 1 matchid : 1 matchcode
					sd.liveindicator,
					SUM(sd.MemberWinLoss),
					SUM(sd.SMAWinLoss),
					SUM(sd.ExtraPT),
					SUM(sd.Commission),
					SUM(sd.RealIncome),
					SUM(sd.VirtualIncome),
					SUM(sd.VarianceIncome),
					SUM(sd.RealTurnover), 
					SUM(sd.VirtualTurnover)
			FROM #matchLiveIndTmp sd
			INNER JOIN #tmpMatch m 
				ON sd.matchid = m.matchid
					AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype --prevent matchid dupplicates in *match* and *outright*
			WHERE CASE WHEN @ShowHedgeMatchOnly = 1 THEN CHARINDEX('hedge', m.matchcode) ELSE 1 END > 0
			GROUP BY m.matchid, sd.liveindicator
			OPTION (RECOMPILE)

		--+ RM summary
        INSERT INTO #tmpDataFiltered (MatchCode,
									  MemberWinLoss,
									  SMAWinLoss,
									  ExtraPT,
									  Commission,
									  RealIncome,
									  VirtualIncome,
									  VarianceIncome,
									  RealTurnover,
									  VirtualTurnover)
            SELECT  CASE WHEN @SportType = 1 AND recommend = 52466   THEN @SportName + ' 8RM'
                         WHEN @SportType > 1 AND recommend = 52466   THEN 'Other Sports 8RM'
                         WHEN @SportType = 1 AND recommend = 5707545 THEN @SportName + ' BARM'
                         WHEN @SportType > 1 AND recommend = 5707545 THEN 'Other Sports BARM'
                         ELSE '' END AS MatchCode, --place holder
                    - SUM(MemberWinLoss) AS MemberWinLoss,
                    - SUM(SMAWinLoss) AS SMAWinLoss,
                    SUM([Extra's Amount]) AS ExtraPT,
                    SUM(CommissionS) AS Commission,
                    - SUM(RealHouseIncome) AS RealIncome,
                    - SUM(VirtualHouseIncome) AS VirtualIncome,
                    - SUM(VarianceHouseIncome) AS VarianceIncome,
                    SUM(RealHouseTurnover) AS RealTurnover, 
                    SUM(VirtualHouseTurnover) AS VirtualTurnover
            FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) t
				INNER JOIN #tmpMatch m 
					ON t.matchid = m.MatchID AND CASE WHEN t.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
				INNER JOIN #tmpSportBettypeMatrix sbm 
					ON sbm.SportType = @SportType AND t.BetType = sbm.BetType
            WHERE winlostdate = @StartDate
				AND recommend IN (52466, 5707545)
				AND ruben = 1
				AND statusID IN (111, 112, 113)
				AND currency NOT IN (20, 27, 28)
				AND t.bettype NOT IN (9, 29)
				AND CASE WHEN @ShowHedgeMatchOnly = 1 THEN CHARINDEX('hedge', m.matchcode) ELSE 1 END > 0
            GROUP BY CASE WHEN @SportType = 1 AND recommend = 52466   THEN @SportName + ' 8RM'
                          WHEN @SportType > 1 AND recommend = 52466   THEN 'Other Sports 8RM'
                          WHEN @SportType = 1 AND recommend = 5707545 THEN @SportName + ' BARM'
                          WHEN @SportType > 1 AND recommend = 5707545 THEN 'Other Sports BARM'
                          ELSE '' END
			OPTION (RECOMPILE)
		
	END

	/* final aggregation by:
		- match event name & live indicator if @LiveIndicatorVarchar = 'none'
		- match event name if @LiveIndicatorVarchar is 'true' or 'false' */
	SELECT  t.MatchID,
			COALESCE(
				MAX(home.teamname 
					+ CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END
					+ CASE WHEN t.MatchCode LIKE '%hedge%' THEN ' (hedge)' ELSE '' END
				) --for Soccer hedge matches, append "(hedge)" to match name
				, t.MatchCode --summary RM line
			) AS MatchEvent,
			t.MatchCode,
			CASE WHEN t.MatchCode LIKE '%hedge%' THEN 1 ELSE 0 END IsHedge,
            CASE WHEN @IsLive IS NULL THEN t.LiveIndicator ELSE @IsLive END AS LiveIndicator,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            - SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #tmpDataFiltered t
	LEFT JOIN bodb02.dbo.Team home WITH (NOLOCK) 
		ON t.homeid = home.teamid
	LEFT JOIN bodb02.dbo.Team away WITH (NOLOCK) 
		ON t.awayid = away.teamid
	GROUP BY t.MatchID
		, CASE WHEN @IsLive IS NULL THEN t.LiveIndicator ELSE @IsLive END
		, t.MatchCode
	ORDER BY CASE WHEN t.MatchCode = @SportName + ' 8RM' THEN 2
				  WHEN t.MatchCode = 'Other Sports 8RM'  THEN 3
				  WHEN t.MatchCode = @SportName + ' BARM' THEN 4
				  WHEN t.MatchCode = 'Other Sports BARM' THEN 5
				  ELSE 1 END
			, MatchID DESC, MatchEvent, LiveIndicator ASC

	DROP TABLE #tmpMatch
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpDataFiltered
	DROP TABLE #matchLiveIndTmp
	DROP TABLE #tmpAgentBySite
	DROP TABLE #tmpGlobalShowTime
END
GO

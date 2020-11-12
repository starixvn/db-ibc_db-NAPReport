/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Match @StartDate SMALLDATETIME,
                                           @EndDate SMALLDATETIME,
                                           @SportBettype VARCHAR(MAX),
										   @BetType	INT = NULL,
										   @SiteName VARCHAR(MAX) = 'ALL',
										   @LeagueName VARCHAR(500),
										   @IsNoDraw BIT = 0,
										   @IsIncludeLiveIndicator BIT = 1,
										   @ShowHedgeMatchOnly BIT = 0
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

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other, this list is build from the drop-down list of
						 front-end website, correspond to selections of user
		                 Example '1_1,1_3' --> 'Soccer_Handicap,Soccer_Over/Under...'
		- @BetType: The specific bet type to view, included in new drilldown flow from #144387
		- @SiteName: Filter by list of site names (delimited by commas)
		- @LeagueName: The leaguename to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report
		- @IsIncludeLiveIndicator: Include live indicators (live/non-live) in report
		- @ShowHedgeMatchOnly: Only show hedge matches

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match_xtest @StartDate='2020-09-06', @EndDate='2020-09-06',
			@LeagueName='UEFA NATIONS LEAGUE A', @IsNoDraw=0,
			@SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1',
			@SiteName = '12Bet,755555,INDO,789y,IBCIndo,BEST-ODDS,722222,733333,XYZBET,asiabet88'
*/

BEGIN

	SET NOCOUNT ON

	BEGIN /*get match data from @LeagueName by @StartDate*/
		CREATE TABLE #tmpMatch (matchid 	 INT,
								matchcode 	 NVARCHAR(100),
								matchtype 	 TINYINT,
								homeid 		 INT,
								awayid 		 INT,
								sporttype	 INT)

		;WITH CTE_all_matches_by_day AS (
			SELECT  matchid,
					matchcode,
					0 matchtype,
					homeid,
					awayid,
					leagueid
			FROM bodb02.dbo.match WITH (NOLOCK)
			WHERE eventdate = @StartDate
			UNION ALL
			SELECT  orid matchid,
					matchcode,
					1 matchtype,
					teamid homeid,
					-1 awayid, --'outright' matches do not have 'away' team 
					leagueid
			FROM bodb02.dbo.outright WITH (NOLOCK)
			WHERE eventdate = @StartDate
		),
		CTE_league_ids AS (
			SELECT leagueid, sporttype
			FROM bodb02.dbo.league WITH (NOLOCK)
			WHERE leaguename = @LeagueName COLLATE SQL_Latin1_General_CP1_CS_AS -- case sensitive search
				AND isTest = 0
		)
		INSERT INTO #tmpMatch (matchid, matchcode, matchtype, homeid, awayid, sporttype)
			SELECT  matchid,
					matchcode,
					matchtype,
					homeid,
					awayid,
					sporttype
			FROM CTE_all_matches_by_day m
			INNER JOIN CTE_league_ids l
			ON m.leagueid = l.leagueid
			OPTION (RECOMPILE)
	END

	DECLARE @SportType INT 
	BEGIN /*as the @SportBetType array passed from the WEB does not get filtered by the 2nd drilldown
		(always same as the parameter from first report), using data from that parameter is not the correct way to retrieve sport*/
		SELECT TOP 1 @SportType = SportType FROM #tmpMatch
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
				SUM(sd.TreeCommission) 			AS Commission,
				SUM(sd.RealHouseIncome) 		AS RealIncome,
				SUM(sd.VirtualHouseIncome) 		AS VirtualIncome,
				SUM(sd.VarianceHouseIncome) 	AS VarianceIncome,
				SUM(sd.RealHouseTurnover) 		AS RealTurnover, 
				SUM(sd.VirtualHouseTurnover) 	AS VirtualTurnover
			FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) sd
			WHERE sd.winlostdate = @StartDate
					/* -- hint use statistics: IX_bettype -- */
					AND sd.ruben = 1
					AND sd.statusID IN (111, 112, 113)
					AND sd.currency NOT IN (20, 27, 28)
					/* -------------------------------------------- */
					AND ('ALL' = @SiteName OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
					AND sd.bettype IN (SELECT BetType FROM #tmpSportBettypeMatrix)
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
            SELECT  CASE WHEN @SportType = 1 AND recommend = 52466   THEN 'Soccer 8RM'
                         WHEN @SportType > 1 AND recommend = 52466   THEN 'Other Sports 8RM'
                         WHEN @SportType = 1 AND recommend = 5707545 THEN 'Soccer BARM'
                         WHEN @SportType > 1 AND recommend = 5707545 THEN 'Other Sports BARM'
                         ELSE '' END AS MatchCode, --place holder
                    - SUM(MemberWinLoss) AS MemberWinLoss,
                    - SUM(SMAWinLoss) AS SMAWinLoss,
                    SUM([Extra's Amount]) AS ExtraPT,
                    SUM(TreeCommission) AS Commission,
                    - SUM(RealHouseIncome) AS RealIncome,
                    - SUM(VirtualHouseIncome) AS VirtualIncome,
                    - SUM(VarianceHouseIncome) AS VarianceIncome,
                    SUM(RealHouseTurnover) AS RealTurnover, 
                    SUM(VirtualHouseTurnover) AS VirtualTurnover
            FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) t
				INNER JOIN #tmpMatch m 
					ON t.matchid = m.MatchID AND CASE WHEN t.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
				INNER JOIN #tmpSportBettypeMatrix sbm 
					ON m.SportType = sbm.SportType AND t.BetType = sbm.BetType
            WHERE winlostdate = @StartDate
				AND recommend IN (52466, 5707545)
				AND ruben = 1
				AND statusID IN (111, 112, 113)
				AND currency NOT IN (20, 27, 28)
				AND t.bettype NOT IN (9, 29)
				AND CASE WHEN @ShowHedgeMatchOnly = 1 THEN CHARINDEX('hedge', m.matchcode) ELSE 1 END > 0
            GROUP BY CASE WHEN @SportType = 1 AND recommend = 52466   THEN 'Soccer 8RM'
                          WHEN @SportType > 1 AND recommend = 52466   THEN 'Other Sports 8RM'
                          WHEN @SportType = 1 AND recommend = 5707545 THEN 'Soccer BARM'
                          WHEN @SportType > 1 AND recommend = 5707545 THEN 'Other Sports BARM'
                          ELSE '' END
			OPTION (RECOMPILE)
		
	END

	/* final aggregation by:
		- match event name & live indicator if @IsIncludeLiveIndicator = 1
		- match event name if @IsIncludeLiveIndicator = 0 */
	SELECT  t.MatchID,
			COALESCE(
				MAX(home.teamname 
					+ CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END
					+ CASE WHEN t.MatchCode LIKE '%hedge%' THEN ' (hedge)' ELSE '' END) --for Soccer hedge matches, append "(hedge)" to match name
				, t.MatchCode --summary RM line
			) AS MatchEvent,
			CASE WHEN t.MatchCode LIKE '%hedge%' THEN 1 ELSE 0 END IsHedge,
            CASE WHEN @IsIncludeLiveIndicator = 1 THEN t.LiveIndicator END AS LiveIndicator,
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
		, CASE WHEN @IsIncludeLiveIndicator = 1 THEN t.LiveIndicator END
		, t.MatchCode
	ORDER BY CASE WHEN t.MatchCode = 'Soccer 8RM'        THEN 2
				  WHEN t.MatchCode = 'Other Sports 8RM'  THEN 3
				  WHEN t.MatchCode = 'Soccer BARM'       THEN 4
				  WHEN t.MatchCode = 'Other Sports BARM' THEN 5
				  ELSE 1 END
			, MatchID DESC, MatchEvent, LiveIndicator ASC

	DROP TABLE #tmpMatch
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpDataFiltered
	DROP TABLE #matchLiveIndTmp
	DROP TABLE #tmpAgentBySite
END
GO

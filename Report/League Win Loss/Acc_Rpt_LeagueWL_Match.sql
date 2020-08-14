/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Match @StartDate SMALLDATETIME,
                                           @EndDate SMALLDATETIME,
                                           @SportType INT,
										   @LeagueName VARCHAR(500),
										   @IsNoDraw BIT = 0
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

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportType: The sporttype to view on report
		- @LeagueName: The leaguename to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match @StartDate='20200620', @EndDate='20200706'
				, @LeagueName='*ENGLISH PREMIER LEAGUE', @SportType = 1, @IsNoDraw=0

		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match @StartDate='20200622', @EndDate='20200630'
				, @LeagueName='SABA ELITE FRIENDLY Virtual PES 20 - 5 Mins Play'
				, @SportType = 1, @IsNoDraw=0
*/

BEGIN

	SET NOCOUNT ON

	BEGIN /*get match data from @LeagueName by @StartDate*/
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
		CTE_all_league_ids AS (
			SELECT leagueid
			FROM bodb02.dbo.league WITH (NOLOCK)
			WHERE leaguename = @LeagueName
				AND sporttype = @SportType AND isTest = 0
		)
		INSERT INTO #tmpMatch (matchid, matchcode, matchtype, homeid, awayid)
			SELECT  matchid,
					matchcode,
					matchtype,
					homeid,
					awayid
			FROM CTE_all_matches_by_day m
			INNER JOIN CTE_all_league_ids l
			ON m.leagueid = l.leagueid
			OPTION (RECOMPILE)
	END

	BEGIN /*build staging data by agent-match-live/nonlive dimension*/
		CREATE TABLE #tmpData ( AgentID				INT,
								MatchID				INT,
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
		
		-- + Soccer, Other Sports
		INSERT INTO #tmpData (AgentID,
							MatchID,
							HomeID,
							AwayID,
							MatchCode,
							LiveIndicator,
							MemberWinLoss,
							SMAWinLoss,
							ExtraPT,
							Commission,
							RealIncome,
							VirtualIncome,
							VarianceIncome,
							RealTurnover,
							VirtualTurnover)
			SELECT  sd.recommend AS AgentID,
					m.matchid AS MatchID,
					MAX(m.homeid) AS HomeID,		    -- 1 matchid : 1 homeid
					MAX(m.awayid) AS AwayID,		    -- 1 matchid : 1 awayid
					MAX(m.matchcode) AS MatchName,     	-- 1 matchid : 1 matchcode
					sd.liveindicator LiveIndicator,
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
					AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype --prevent matchid dupplicates in *match* and *outright*
			WHERE sd.winlostdate = @StartDate
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
			GROUP BY sd.recommend, m.matchid, sd.liveindicator
			OPTION (RECOMPILE)

		--+ RM summary
        INSERT INTO #tmpData (MatchCode,
                              MemberWinLoss,
                              SMAWinLoss,
                              ExtraPT,
                              Commission,
                              RealIncome,
                              VirtualIncome,
                              VarianceIncome,
                              RealTurnover,
                              VirtualTurnover)
            SELECT  CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 'Soccer 8RM'
                         WHEN @SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
                         WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 'Soccer BARM'
                         WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
                         ELSE '' END AS MatchCode, --place holder
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

	-- final aggregation by match event name & live indicator, display report
	SELECT  t.MatchID,
			COALESCE(
				MAX(home.teamname 
					+ CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END
					+ CASE WHEN t.MatchCode LIKE '%hedge%' THEN ' (hedge)' ELSE '' END) --for Soccer hedge matches, append "(hedge)" to match name
				, t.MatchCode --summary RM line
			) AS MatchEvent,
            t.LiveIndicator LiveIndicator,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #tmpData t
	LEFT JOIN bodb02.dbo.Team home WITH (NOLOCK) 
		ON t.homeid = home.teamid
	LEFT JOIN bodb02.dbo.Team away WITH (NOLOCK) 
		ON t.awayid = away.teamid
	GROUP BY GROUPING SETS (
		(t.MatchID, t.LiveIndicator, t.MatchCode),
		(t.MatchID)
	) --add summary records displaying the totals of each match
	HAVING COALESCE(
				MAX(home.teamname 
					+ CASE WHEN away.teamname IS NOT NULL THEN ' -vs- ' + away.teamname ELSE '' END
					+ CASE WHEN t.MatchCode LIKE '%hedge%' THEN ' (hedge)' ELSE '' END)
				, t.MatchCode
			) IS NOT NULL --exclude the summary record (from group set) for RM lines such as 'Soccer 8RM'
	ORDER BY CASE WHEN t.MatchCode = 'Soccer 8RM'        THEN 2
				  WHEN t.MatchCode = 'Other Sports 8RM'  THEN 3
				  WHEN t.MatchCode = 'Soccer BARM'       THEN 4
				  WHEN t.MatchCode = 'Other Sports BARM' THEN 5
				  ELSE 1 END
			, MatchID DESC, MatchEvent, LiveIndicator ASC

	DROP TABLE #tmpMatch
	DROP TABLE #tmpData
END
GO

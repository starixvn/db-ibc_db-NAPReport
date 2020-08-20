/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Match @StartDate SMALLDATETIME,
                                           @EndDate SMALLDATETIME,
                                           @SportBettype VARCHAR(MAX),
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
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,1_3' --> 'Soccer_Handicap,Soccer_Over/Under...'
		- @LeagueName: The leaguename to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match @StartDate='20200809', @EndDate='20200706'
				, @LeagueName='AUSTRALIA BRISBANE PREMIER LEAGUE RESERVE', @IsNoDraw=0
				, @SportBettype='1_301,1_302,1_303,1_304,1_15,1_125,1_453,1_476,1_459,1_466,1_205,1_201,1_138,1_404,1_464,1_485,1_215,1_188,1_427,1_456,1_457,1_478,1_203,1_471,1_487,1_494,1_30,1_414,1_151,1_410,1_191,1_411,1_182,1_181,1_207,1_489,1_127,1_7,1_204,1_200,1_136,1_403,1_463,1_484,1_213,1_209,1_492,1_180,1_12,1_8,1_211,1_143,1_202,1_474,1_126,1_426,1_177,1_430,1_146,1_433,1_472,1_495,1_405,1_186,1_431,1_185,1_432,1_490,1_17,1_183,1_184,1_428,1_18,1_178,1_28,1_475,1_458,1_465,1_447,1_122,1_381,1_388,1_386,1_196,1_139,1_402,1_462,1_483,1_214,1_198,1_132,1_421,1_148,1_437,1_134,1_439,1_150,1_441,1_189,1_434,1_190,1_435,1_145,1_445,1_451,1_417,1_418,1_26,1_13,1_477,1_496,1_497,1_194,1_470,1_486,1_4,1_413,1_24,1_454,1_449,1_25,1_123,1_804,1_129,1_412,1_179,1_429,1_187,1_162,1_409,1_130,1_161,1_407,1_159,1_406,1_167,1_165,1_174,1_166,1_399,1_398,1_164,1_396,1_395,1_400,1_397,1_173,1_206,1_488,1_806,1_424,1_192,1_193,1_14,1_422,1_423,1_176,1_5,1_124,1_216,1_217,1_801,1_152,1_416,1_467,1_493,1_1,1_140,1_452,1_442,1_142,1_444,1_141,1_443,1_446,1_121,1_382,1_389,1_387,1_195,1_137,1_401,1_461,1_482,1_212,1_197,1_131,1_420,1_147,1_436,1_133,1_438,1_149,1_440,1_16,1_128,1_208,1_491,1_448,1_175,1_221,1_225,1_222,1_22,1_160,1_169,1_803,1_450,1_2,1_157,1_10,1_3,1_135,1_385,1_384,1_376,1_392,1_391,1_394,1_393,1_390,1_383,1_210,1_172,1_415,1_144,1_163,1_468,1_469,1_38,1_170,1_481,1_479,1_455,1_805,1_425,1_27,1_473,1_199,1_6,1_223,1_224,1_226,1_227,1_419,1_460,1_168,1_171,1_408'
*/

BEGIN

	SET NOCOUNT ON

	BEGIN /*split the array @SportBettype into a temp table*/
		CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
											 BetType SMALLINT)

		;WITH CTE_SportBettypeMatrix AS (
			SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
				   CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
			FROM bodb02.dbo.strSplit_str(@SportBettype, ',')
			WHERE LEN(val) > 0
		)
		INSERT INTO #tmpSportBettypeMatrix (SportType, BetType)
		SELECT cte.SportType, cte.BetType
		FROM CTE_SportBettypeMatrix cte
	END

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
			WHERE leaguename = @LeagueName
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
			INNER JOIN #tmpSportBettypeMatrix sbm
				ON sbm.BetType = sd.bettype 
			INNER JOIN #tmpMatch m 
				ON sd.matchid = m.matchid AND m.sporttype = sbm.SportType
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
            - SUM(ExtraPT) AS ExtraPT,
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
	GROUP BY t.MatchID, t.LiveIndicator, t.MatchCode
	ORDER BY CASE WHEN t.MatchCode = 'Soccer 8RM'        THEN 2
				  WHEN t.MatchCode = 'Other Sports 8RM'  THEN 3
				  WHEN t.MatchCode = 'Soccer BARM'       THEN 4
				  WHEN t.MatchCode = 'Other Sports BARM' THEN 5
				  ELSE 1 END
			, MatchID DESC, MatchEvent, LiveIndicator ASC

	DROP TABLE #tmpMatch
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpData
END
GO

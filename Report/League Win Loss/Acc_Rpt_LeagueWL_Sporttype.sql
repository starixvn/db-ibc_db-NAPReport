/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate SMALLDATETIME,
                                               @EndDate SMALLDATETIME,
                                               @SportBettype VARCHAR(MAX),
											   @LeagueName VARCHAR(500) = '',
										       @IsNoDraw BIT = 0
AS
/*
	Created: Ned.Le@20200422
	Task: View all measures by sporttypes and leagues
	DB: DBACC.bodb02

	Revisions:
		- 20200422@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200626@Ned.Le: NAP Report - Enhancement for searching a league info on Punter Analysis and League Win Loss Report (#136277)
		- 20200819@Jaden.Tang: NAP Report - Refactor for performance (#138955)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @LeagueName: The leaguename to view on report
		               If value is '', it means that no filter by LeagueName
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate='20200809', @EndDate='20200407', 
				@SportBettype='10000_9,10000_29,1_1,1_3', @LeagueName='', @IsNoDraw=0
*/

BEGIN

	SET NOCOUNT ON

	--convert empty string to null for easier calculations
	IF @LeagueName = '' SET @LeagueName = NULL

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
								matchtype 	 TINYINT,
								sporttype	 INT,
								leaguename	 VARCHAR(500))

		;WITH CTE_all_matches_by_day AS (
			SELECT  matchid,
					0 matchtype,
					leagueid
			FROM bodb02.dbo.match WITH (NOLOCK)
			WHERE eventdate = @StartDate
			UNION ALL
			SELECT  orid matchid,
					1 matchtype,
					leagueid
			FROM bodb02.dbo.outright WITH (NOLOCK)
			WHERE eventdate = @StartDate
		),
		CTE_league_ids AS (
			SELECT leagueid, sporttype, leaguename
			FROM bodb02.dbo.league WITH (NOLOCK)
			WHERE leaguename = ISNULL(@LeagueName, leaguename)
				AND isTest = 0
		)
		INSERT INTO #tmpMatch (matchid,matchtype, sporttype, leaguename)
			SELECT  matchid,
					matchtype,
					sporttype,
					leaguename
			FROM CTE_all_matches_by_day m
			INNER JOIN CTE_league_ids l
				ON m.leagueid = l.leagueid
			OPTION (RECOMPILE)
	END

	BEGIN /*build staging data by agent-league-sport*/
		CREATE TABLE #tmpData (AgentID			INT,
							   LeagueName		VARCHAR(500), --note that 1 LeagueName may include multiple LeagueIDs
							   SportType		SMALLINT,
							   MemberWinLoss	MONEY,
							   SMAWinLoss		MONEY,
							   ExtraPT			MONEY,
							   Commission		MONEY,
							   RealIncome		MONEY,
							   VirtualIncome	MONEY,
							   VarianceIncome	MONEY,
							   RealTurnover		MONEY,
							   VirtualTurnover	MONEY)
		
		-- Soccer, Other Sports & Parlay
		;WITH CTE AS (
			SELECT 	sd.recommend AS AgentID,
					sd.matchid   AS MatchID,
					sd.bettype   AS BetType,
					((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
					((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
					((CASE WHEN sd.tpositiontaking = 1 THEN 0
							ELSE (sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking) END) 
						* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) 
						* sd.actualrate
						) AS ExtraPT,
					(sd.scomm * sd.actualrate) AS Commission,
					((
						sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
						- CASE WHEN sd.tpositiontaking = 1 THEN 0
							ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking) END 
						* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
					) 
					* sd.actualrate
					) AS RealIncome,
					((
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
					((
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
					(CASE WHEN sd.tpositiontaking = 1 THEN 0
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
					(CASE WHEN sd.tpositiontaking = 1 THEN 0
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
			WHERE sd.winlostdate = @StartDate
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
		)
		INSERT INTO #tmpData (AgentID,
							  LeagueName,
							  SportType,
							  MemberWinLoss,
							  SMAWinLoss,
							  ExtraPT,
							  Commission,
							  RealIncome,
							  VirtualIncome,
							  VarianceIncome,
							  RealTurnover,
							  VirtualTurnover)
			SELECT  CTE.AgentID,
					m.LeagueName,
					m.SportType,
					SUM(MemberWinLoss) AS MemberWinLoss,
					SUM(SMAWinLoss) AS SMAWinLoss,
					SUM(ExtraPT) AS ExtraPT,
					SUM(Commission) AS Commission,
					SUM(RealIncome) AS RealIncome,
					SUM(VirtualIncome) AS VirtualIncome,
					SUM(VarianceIncome) AS VarianceIncome,
					SUM(RealTurnover) AS RealTurnover, 
					SUM(VirtualTurnover) AS VirtualTurnover
			FROM CTE
			INNER JOIN #tmpMatch m 
				ON CTE.matchid = m.matchid
					AND CASE WHEN CTE.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
			INNER JOIN #tmpSportBettypeMatrix sbm 
				ON m.sporttype = sbm.SportType
					AND CTE.BetType = sbm.BetType AND CTE.BetType NOT IN (9, 29)
			GROUP BY CTE.AgentID, m.SportType, m.leaguename
		UNION ALL
			SELECT  CTE.AgentID,
					'' LeagueName,
					10000 SportType,
					SUM(MemberWinLoss) AS MemberWinLoss,
					SUM(SMAWinLoss) AS SMAWinLoss,
					SUM(ExtraPT) AS ExtraPT,
					SUM(Commission) AS Commission,
					SUM(RealIncome) AS RealIncome,
					SUM(VirtualIncome) AS VirtualIncome,
					SUM(VarianceIncome) AS VarianceIncome,
					SUM(RealTurnover) AS RealTurnover, 
					SUM(VirtualTurnover) AS VirtualTurnover
			FROM CTE
			INNER JOIN #tmpSportBettypeMatrix sbm 
				ON sbm.SportType = 10000 -- 10000 is the hard-coded "sport type" passed from Web, to identify Parlay category
					AND CTE.BetType = sbm.BetType -- (9, 29)
			GROUP BY CTE.AgentID
			OPTION (RECOMPILE)

		-- RM summary lines
		INSERT INTO #tmpData (LeagueName,
							  SportType,
							  MemberWinLoss,
							  SMAWinLoss,
							  ExtraPT,
							  Commission,
							  RealIncome,
							  VirtualIncome,
							  VarianceIncome,
							  RealTurnover,
							  VirtualTurnover)
			SELECT  MAX(CASE WHEN SportType = 1 AND t.AgentId = 52466   THEN 'Soccer 8RM'
							 WHEN SportType > 1 AND t.AgentId = 52466   THEN 'Other Sports 8RM'
							 WHEN SportType = 1 AND t.AgentId = 5707545 THEN 'Soccer BARM'
							 WHEN SportType > 1 AND t.AgentId = 5707545 THEN 'Other Sports BARM'
							 ELSE '' END) AS LeagueName, --place holder
					CASE WHEN SportType = 1 AND t.AgentId = 52466   THEN 10001 -- 'Soccer 8RM'
                         WHEN SportType > 1 AND t.AgentId = 52466   THEN 10002 -- 'Other Sports 8RM'
                         WHEN SportType = 1 AND t.AgentId = 5707545 THEN 10003 -- 'Soccer BARM'
                         WHEN SportType > 1 AND t.AgentId = 5707545 THEN 10004 -- 'Other Sports BARM'
                         ELSE '' END AS SportType,
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
				AND SportType != 10000 -- exclude parlay
            GROUP BY CASE WHEN SportType = 1 AND t.AgentId = 52466   THEN 10001
                          WHEN SportType > 1 AND t.AgentId = 52466   THEN 10002
                          WHEN SportType = 1 AND t.AgentId = 5707545 THEN 10003
                          WHEN SportType > 1 AND t.AgentId = 5707545 THEN 10004
                          ELSE '' END
	END

    -- final aggregation by SportType & League Name, display report
	SELECT  t.SportType SportType,
			CASE WHEN t.SportType = 10000 THEN 'Parlay'
				 ELSE ISNULL(MAX(s.SportName), t.LeagueName) END Sport,
            t.LeagueName LeagueName,
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
	LEFT JOIN bodb02.dbo.Sports s
		ON t.SportType = s.SportType
	WHERE MemberWinLoss IS NOT NULL
    GROUP BY t.SportType, t.LeagueName
    ORDER BY RealTurnover DESC

	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData
END
GO

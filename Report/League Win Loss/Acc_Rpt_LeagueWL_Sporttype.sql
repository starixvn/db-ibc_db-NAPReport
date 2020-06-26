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
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate='20200407', @EndDate='20200407', @SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1', @LeagueName='', @IsNoDraw=0
*/

BEGIN

	SET NOCOUNT ON

	-- #tmpSportBettypeMatrix
	CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
									     Sport VARCHAR(50),
										 BetType SMALLINT)

	;WITH CTE_SportBettypeMatrix AS (
		SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
			   CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
		FROM bodb02.dbo.strSplit_str(@SportBettype, ',')
		WHERE LEN(val) > 0
	)
	INSERT INTO #tmpSportBettypeMatrix (SportType, Sport, BetType)
	SELECT cte.SportType,
		   CASE WHEN cte.SportType = 10000 THEN 'Parlay' ELSE s.SportName END Sport,
		   cte.BetType
	FROM CTE_SportBettypeMatrix cte
		 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON cte.SportType = s.SportType

	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(SportType, BetType)

	-- #tmpLeague
	CREATE TABLE #tmpLeague (LeagueId INT)

	INSERT INTO #tmpLeague (LeagueId)
	SELECT leagueid
	FROM bodb02.dbo.league (NOLOCK)
	WHERE leaguename = @LeagueName
		  AND isTest = 0

	CREATE UNIQUE CLUSTERED INDEX PK_tmpLeague ON #tmpLeague(LeagueId)

	-- #tmpMatch
	CREATE TABLE #tmpMatch (matchid INT,
							sporttype SMALLINT,
							leagueid INT,
							leaguename VARCHAR(500),
							matchtype TINYINT)

	;WITH CTE_Match AS (
		SELECT matchid AS matchid, leagueid, 0 AS matchtype  FROM [bodb02].[dbo].[match] (NOLOCK) WHERE eventdate = @StartDate
		UNION ALL
		SELECT orid AS matchid, leagueid, 1 AS matchtype FROM bodb02.dbo.outright (NOLOCK) WHERE eventdate = @StartDate
	)
	INSERT INTO #tmpMatch(matchid, sporttype, leagueid, leaguename, matchtype)
	SELECT m.matchid,
		   l.sporttype,
		   l.leagueid,
		   l.leaguename,
		   m.matchtype
	FROM CTE_Match m
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE ('' = @LeagueName OR m.leagueid IN (SELECT LeagueId FROM #tmpLeague))
		  AND EXISTS (SELECT TOP 1 1
		              FROM #tmpSportBettypeMatrix sbm
					  WHERE l.sporttype = sbm.SportType)
	OPTION (RECOMPILE)
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpData
	CREATE TABLE #tmpData (SportType		SMALLINT,
						   Sport			VARCHAR(50),
						   LeagueName		VARCHAR(150),
						   MemberWinLoss	MONEY,
						   SMAWinLoss		MONEY,
						   ExtraPT			MONEY,
						   Commission		MONEY,
						   RealIncome		MONEY,
						   VirtualIncome	MONEY,
						   VarianceIncome	MONEY,
						   RealTurnover		MONEY,
						   VirtualTurnover	MONEY)
	
	-- + Soccer, Other Sports
	INSERT INTO #tmpData (SportType,
						  Sport,
						  LeagueName,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT sbm.SportType AS SportType,
		   sbm.Sport AS Sport,
		   m.leaguename AS LeagueName,
		   SUM((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
           SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
		   SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking)
			    END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) * sd.actualrate) AS ExtraPT,
		   SUM(sd.scomm * sd.actualrate) AS Commission,
		   SUM((sd.winlost - sd.actual_stake +
			    sd.awinlost + sd.mwinlost + sd.swinlost +
				sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
								 ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
							END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate) AS RealIncome,
		   SUM((sd.winlost - sd.actual_stake +
			    sd.awinlost + sd.mwinlost + sd.swinlost -
				CASE WHEN tpositiontaking = 1 THEN 0
					 ELSE(winlost - actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				END) * sd.virtualrate + (sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                                          ELSE sd.scomm / (1 - sd.tpositiontaking)
													 END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate * CASE WHEN sd.virtualrate < sd.actualrate THEN sd.virtualrate / sd.actualrate
                                                                                                                                         ELSE 1
                                                                                                                                    END) AS VirtualIncome,
           SUM((sd.winlost - sd.actual_stake +
				sd.awinlost + sd.mwinlost + sd.swinlost -
				CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				END +
				CASE WHEN sd.virtualrate < sd.actualrate THEN (sd.scomm - (CASE WHEN tpositiontaking = 1 THEN 0
                                                                                ELSE sd.scomm / (1 - sd.tpositiontaking)
				  													       END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                     ELSE 0
				END) * (sd.actualrate - sd.virtualrate)) AS VarianceIncome,
           SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					     * ABS(sd.stake)
						 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
						 * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(
																		(
																			(sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
																			AND sd.bettype NOT BETWEEN 81 AND 120
																		)
																		AND ABS(sd.modds) = 0.25
																		AND sd.statusID IN (112, 113)
																	) THEN 0.5
															 ELSE 1 END
								ELSE 1 END
			   END) AS RealTurnover, 
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					     * ABS(sd.stake)
					     * sd.virtualrate
						 * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(
																		(
																			(sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
																			AND sd.bettype NOT BETWEEN 81 AND 120
																		)
																		AND ABS(sd.modds) = 0.25
																		AND sd.statusID IN (112, 113)
																	) THEN 0.5
															 ELSE 1 END
								ELSE 1 END
			   END) AS VirtualTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
		 INNER JOIN #tmpMatch m ON sd.matchid = m.matchid
								   AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.sporttype = sbm.SportType
			                                      AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype NOT IN (9, 29)
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
	GROUP BY sbm.SportType,
			 sbm.Sport,
		     m.leaguename
	OPTION (RECOMPILE)
	
	-- + Parlay
	INSERT INTO #tmpData (SportType,
						  Sport,
						  LeagueName,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT 10000 AS SportType,
		   'Parlay' AS Sport,
		   '' AS LeagueName,
		   SUM((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
           SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
		   SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking)
			    END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) * sd.actualrate) AS ExtraPT,
		   SUM(sd.scomm * sd.actualrate) AS Commission,
		   SUM((sd.winlost - sd.actual_stake +
			    sd.awinlost + sd.mwinlost + sd.swinlost +
				sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
								 ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
							END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate) AS RealIncome,
		   SUM((sd.winlost - sd.actual_stake +
			    sd.awinlost + sd.mwinlost + sd.swinlost -
				CASE WHEN tpositiontaking = 1 THEN 0
					 ELSE(winlost - actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				END) * sd.virtualrate + (sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                                          ELSE sd.scomm / (1 - sd.tpositiontaking)
													 END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate * CASE WHEN sd.virtualrate < sd.actualrate THEN sd.virtualrate / sd.actualrate
                                                                                                                                         ELSE 1
                                                                                                                                    END) AS VirtualIncome,
           SUM((sd.winlost - sd.actual_stake +
				sd.awinlost + sd.mwinlost + sd.swinlost -
				CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				END +
				CASE WHEN sd.virtualrate < sd.actualrate THEN (sd.scomm - (CASE WHEN tpositiontaking = 1 THEN 0
                                                                                ELSE sd.scomm / (1 - sd.tpositiontaking)
				  													       END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                     ELSE 0
				END) * (sd.actualrate - sd.virtualrate)) AS VarianceIncome,
           SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					     * ABS(sd.stake)
						 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
			   END) AS RealTurnover, 
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					* ABS(sd.stake)
					* sd.virtualrate
			   END) AS VirtualTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype IN (SELECT BetType FROM #tmpSportBettypeMatrix WHERE SportType = 10000)
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
	OPTION (RECOMPILE)

	-- + RM
	INSERT INTO #tmpData (SportType,
						  Sport,
						  LeagueName,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	  THEN 10001
				WHEN sbm.SportType > 1 AND sd.recommend = 52466	  THEN 10002
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 10003
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 10004
				ELSE -10000 END AS SportType,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS Sport,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS LeagueName,
		   -SUM((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
           -SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss, 
           -SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                      ELSE(sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking)
                 END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) * sd.actualrate) AS ExtraPT,
		   SUM(sd.scomm * sd.actualrate) AS Commission,
           -SUM((sd.winlost - sd.actual_stake +
		         sd.awinlost + sd.mwinlost + sd.swinlost +
				 sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                  ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
							 END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate) AS RealIncome,
		   -SUM((sd.winlost - sd.actual_stake +
			     sd.awinlost + sd.mwinlost + sd.swinlost -
				 CASE WHEN sd.tpositiontaking = 1 THEN 0
					  ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				 END) * sd.virtualrate + (sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                                           ELSE sd.scomm / (1 - sd.tpositiontaking)
                                                      END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate * CASE WHEN sd.virtualrate < sd.actualrate THEN sd.virtualrate / sd.actualrate
                                                                                                                                          ELSE 1
                                                                                                                                     END) AS VirtualIncome,
		   -SUM((sd.winlost - sd.actual_stake +
			     sd.awinlost + sd.mwinlost + sd.swinlost -
				 CASE WHEN sd.tpositiontaking = 1 THEN 0
                      ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
                 END +
				 CASE WHEN sd.virtualrate < sd.actualrate THEN(sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                                                                ELSE sd.scomm / (1 - sd.tpositiontaking)
                                                                           END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					  ELSE 0
                 END) * (sd.actualrate - sd.virtualrate)) AS VarianceIncome,
           SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					     * ABS(sd.stake)
						 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
						 * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(
																		(
																			(sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
																			AND sd.bettype NOT BETWEEN 81 AND 120
																		)
																		AND ABS(sd.modds) = 0.25
																		AND sd.statusID IN (112, 113)
																	) THEN 0.5
															 ELSE 1 END
								ELSE 1 END
			   END) AS RealTurnover, 
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					     * ABS(sd.stake)
					     * sd.virtualrate
						 * CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(
																		(
																			(sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
																			AND sd.bettype NOT BETWEEN 81 AND 120
																		)
																		AND ABS(sd.modds) = 0.25
																		AND sd.statusID IN (112, 113)
																	) THEN 0.5
															 ELSE 1 END
								ELSE 1 END
			   END) AS VirtualTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
		 INNER JOIN #tmpMatch m ON sd.matchid = m.matchid
								   AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.SportType = sbm.SportType
												  AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype NOT IN (9, 29)
		  AND sd.recommend IN (52466, 5707545)
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
	GROUP BY CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	THEN 10001
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466	THEN 10002
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 10003
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 10004
				  ELSE -10000 END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END
	OPTION (RECOMPILE)

	-- Get Data
	SELECT SportType,
		   Sport,
		   LeagueName,
		   MemberWinLoss,
		   SMAWinLoss,
		   (-ExtraPT) ExtraPT,
		   Commission,
		   RealIncome,
		   VirtualIncome,
		   VarianceIncome,
		   RealTurnover,
		   VirtualTurnover
	FROM #tmpData
	WHERE MemberWinLoss IS NOT NULL
	ORDER BY RealTurnover DESC

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpLeague
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData

END
GO

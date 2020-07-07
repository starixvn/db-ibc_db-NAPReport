/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Bettype @StartDate SMALLDATETIME,
											 @EndDate SMALLDATETIME,
											 @SportBettype VARCHAR(MAX),
											 @SportType INT,
											 @LeagueName VARCHAR(500),
											 @IsNoDraw BIT = 0
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by bettypes
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200626@Ned.Le: NAP Report - Enhancement for searching a league info on Punter Analysis and League Win Loss Report (#136277)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @SportType: The sporttype to view on report
		- @LeagueName: The leaguename to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Bettype @StartDate='20200421', @EndDate='20200421', @SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1', @SportType = 1, @LeagueName='*GERMANY-BUNDESLIGA I', @IsNoDraw=0
*/

BEGIN

	SET NOCOUNT ON

	-- #tmpSportBettypeMatrix
	CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
									     Sport VARCHAR(50),
										 BetType SMALLINT,
										 BetTypeName VARCHAR(128),
										 BettypeDisplayOrder SMALLINT)

	;WITH
	CTE_SportBettypeMatrixRaw AS (
		SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
			   CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
		FROM bodb02.dbo.strSplit_str(@SportBettype, ',')
		WHERE LEN(val) > 0
	),
	CTE_SportBettypeMatrixFinal AS (
		SELECT cte.SportType,
			   CASE WHEN cte.SportType = 10000 THEN 'Parlay' ELSE s.SportName END Sport,
			   cte.BetType,
			   b.typenamee BetTypeName
		FROM CTE_SportBettypeMatrixRaw cte
			 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON cte.SportType = s.SportType
			 LEFT JOIN bodb02.dbo.bettype b (NOLOCK) ON cte.BetType = b.typeid
	),
	CTE_DisplayOrder AS (
		SELECT SportType,
			   Sport,
			   BetType,
			   BetTypeName,
			   (RANK() OVER (ORDER BY BetTypeName) + 100) BettypeDisplayOrder
		FROM CTE_SportBettypeMatrixFinal
	),
	CTE_FinalResult AS (
		SELECT SportType,
			   Sport,
			   BetType,
			   BetTypeName,
			   CASE WHEN BetType = 1	THEN 1		--Handicap
					WHEN BetType = 301	THEN 2		--% Handicap
					WHEN BetType = 3	THEN 3		--Over/Under
					WHEN BetType = 302	THEN 4		--% Over/Under
					WHEN BetType = 7	THEN 5		--1st Half Handicap
					WHEN BetType = 303	THEN 6		--1H % Handicap
					WHEN BetType = 8	THEN 7		--1st Half Over/Under
					WHEN BetType = 304	THEN 8		--1H % Over/Under
					WHEN BetType = 2	THEN 9		--Odd/Even
					WHEN BetType = 5	THEN 10		--1X2
					WHEN BetType = 4	THEN 11		--Correct Score
					WHEN BetType = 6	THEN 12		--Total Goal
					WHEN BetType = 10	THEN 13		--Outright
					ELSE BettypeDisplayOrder
			   END BettypeDisplayOrder
		FROM CTE_DisplayOrder
	)
	INSERT INTO #tmpSportBettypeMatrix (SportType, Sport, BetType, BetTypeName, BettypeDisplayOrder)
	SELECT SportType,
		   Sport,
		   BetType,
		   BetTypeName,
		   BettypeDisplayOrder
	FROM CTE_FinalResult
	OPTION (RECOMPILE)
	
	DELETE t
	FROM #tmpSportBettypeMatrix t
	WHERE t.BetType IN (9, 29)
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(SportType, BetType)

	-- #tmpLeague
	CREATE TABLE #tmpLeague (LeagueId INT)

	INSERT INTO #tmpLeague (LeagueId)
	SELECT leagueid
	FROM bodb02.dbo.league (NOLOCK)
	WHERE leaguename = @LeagueName
		  AND sporttype = @SportType
		  AND isTest = 0

	CREATE UNIQUE CLUSTERED INDEX PK_tmpLeague ON #tmpLeague(LeagueId)

	-- #tmpMatch
	CREATE TABLE #tmpMatch (matchid INT,
							matchcode NVARCHAR(50),
							sporttype SMALLINT,
							leagueid INT,
							matchtype TINYINT)

	;WITH CTE_Match AS (
		SELECT matchid AS matchid, matchcode, leagueid, 0 AS matchtype  FROM [bodb02].[dbo].[match] (NOLOCK) WHERE eventdate = @StartDate
		UNION ALL
		SELECT orid AS matchid, matchcode, leagueid, 1 AS matchtype FROM bodb02.dbo.outright (NOLOCK) WHERE eventdate = @StartDate
	)
	INSERT INTO #tmpMatch(matchid, matchcode, sporttype, leagueid, matchtype)
	SELECT m.matchid,
		   m.matchcode,
		   l.sporttype,
		   l.leagueid,
		   m.matchtype
	FROM CTE_Match m
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE m.leagueid IN (SELECT LeagueId FROM #tmpLeague)
	OPTION (RECOMPILE)
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpData
	CREATE TABLE #tmpData (LiveIndicator		TINYINT,
						   Bettype				SMALLINT,
						   BettypeName			VARCHAR(128),
						   BettypeDisplayOrder	SMALLINT,
						   IsHedge				SMALLINT,
						   MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover			MONEY,
						   VirtualTurnover		MONEY)
	
	-- + Soccer, Other Sports
	INSERT INTO #tmpData (LiveIndicator,
						  Bettype,
						  BettypeName,
						  BettypeDisplayOrder,
						  IsHedge,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT sd.liveindicator AS LiveIndicator,
		   sbm.BetType AS BetType,
		   sbm.BetTypeName AS BetTypeName,
		   sbm.BettypeDisplayOrder AS BettypeDisplayOrder,
		   CASE WHEN m.matchcode like '%hedge%' THEN 1 ELSE 0 END AS IsHedge,
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
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
	GROUP BY sd.liveindicator,
		     sbm.BetType,
		     sbm.BetTypeName,
		     sbm.BettypeDisplayOrder,
			 CASE WHEN m.matchcode like '%hedge%' THEN 1 ELSE 0 END
	OPTION (RECOMPILE)
	
	-- + RM
	INSERT INTO #tmpData (LiveIndicator,
						  Bettype,
						  BettypeName,
						  BettypeDisplayOrder,
						  IsHedge,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT sd.liveindicator AS LiveIndicator,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 30001
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 30002
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				ELSE -1 END AS Bettype,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS BettypeName,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 30001
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 30002
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				ELSE -1 END AS BettypeDisplayOrder,
		   -1 AS IsHedge,
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
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.sporttype = sbm.SportType
												  AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.recommend IN (52466, 5707545)
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
	GROUP BY sd.liveindicator,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 30001
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 30002
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				  ELSE -1 END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 30001
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 30002
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				  ELSE -1 END
	OPTION (RECOMPILE)

	-- Get Data
	SELECT LiveIndicator,
		   Bettype,
		   CASE WHEN IsHedge = 1 THEN BettypeName + ' (hedge)' ELSE BettypeName END BettypeName,
		   IsHedge,
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
	ORDER BY LiveIndicator DESC,
			 BettypeDisplayOrder ASC

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpLeague
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData

END
GO

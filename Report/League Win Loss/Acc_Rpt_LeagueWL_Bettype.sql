/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Bettype @StartDate SMALLDATETIME,
											 @EndDate SMALLDATETIME,
											 @SportType INT,
											 @LeagueID INT
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by bettypes
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportType: The sporttype to view on report
		- @LeagueID: The leagueid to view on report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Bettype @StartDate='20200421', @EndDate='20200421', @SportType=1, @LeagueID=143
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
	CTE_SportBettypeMatrix AS (
		SELECT DISTINCT
			   sbm.SportType,
			   s.SportName Sport,
			   sbm.BetType,
			   b.typenamee BetTypeName
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
			 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON sbm.SportType = s.SportType
			 LEFT JOIN bodb02.dbo.bettype b (NOLOCK) ON sbm.BetType = b.typeid
		WHERE sbm.ProductID = 1
			  AND sbm.SportType = @SportType
			  AND sbm.SubProduct NOT LIKE 'BT%'
			  AND sbm.BetType NOT IN (9, 29)
	),
	CTE_DisplayOrder AS (
		SELECT SportType,
			   Sport,
			   BetType,
			   BetTypeName,
			   (RANK() OVER (ORDER BY BetTypeName) + 100) BettypeDisplayOrder
		FROM CTE_SportBettypeMatrix
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

	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(SportType, BetType)

	-- #tmpMatch
	CREATE TABLE #tmpMatch (matchid INT,
							sporttype SMALLINT,
							leagueid INT,
							matchtype TINYINT)

	;WITH CTE_Match AS (
		SELECT matchid AS matchid, leagueid, 0 AS matchtype  FROM [bodb02].[dbo].[match] (NOLOCK) WHERE eventdate = @StartDate
		UNION ALL
		SELECT orid AS matchid, leagueid, 1 AS matchtype FROM bodb02.dbo.outright (NOLOCK) WHERE eventdate = @StartDate
	)
	INSERT INTO #tmpMatch(matchid, sporttype, leagueid, matchtype)
	SELECT m.matchid,
		   l.sporttype,
		   l.leagueid,
		   m.matchtype
	FROM CTE_Match m
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON l.sporttype = @SportType
														 AND l.leagueid = @LeagueID
														 AND m.leagueid = l.leagueid
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpData
	CREATE TABLE #tmpData (LiveIndicator		TINYINT,
						   Bettype				SMALLINT,
						   BettypeName			VARCHAR(128),
						   BettypeDisplayOrder	SMALLINT,
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
		   SUM((sd.winlost - sd.actual_stake) * sd.actualrate) MemberWinLoss,
           SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
		   SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking)
			    END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) * sd.actualrate) AS ExtraPT,
		   SUM(sd.scomm * sd.actualrate) Commission,
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
                                                                                                                                    END) VirtualIncome,
           SUM((sd.winlost - sd.actual_stake +
				sd.awinlost + sd.mwinlost + sd.swinlost -
				CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
				END +
				CASE WHEN sd.virtualrate < sd.actualrate THEN (sd.scomm - (CASE WHEN tpositiontaking = 1 THEN 0
                                                                                ELSE sd.scomm / (1 - sd.tpositiontaking)
				  													       END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                     ELSE 0
				END) * (sd.actualrate - sd.virtualrate)) VarianceIncome,
           SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE(1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(sd.stake) * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate
																															   ELSE sd.actualrate END END) AS RealTurnover, 
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE(1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(sd.stake) * sd.virtualrate END) AS VirtualTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
		 INNER JOIN #tmpMatch m ON sd.matchid = m.matchid
								   AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.sporttype = sbm.SportType
												  AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
	GROUP BY sd.liveindicator,
		     sbm.BetType,
		     sbm.BetTypeName,
		     sbm.BettypeDisplayOrder
	OPTION (RECOMPILE)
	
	-- + RM
	INSERT INTO #tmpData (LiveIndicator,
						  Bettype,
						  BettypeName,
						  BettypeDisplayOrder,
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
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 30001
				WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 30002
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				ELSE -1 END AS Bettype,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 'Soccer 8RM'
				WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 'Other Sports 8RM'
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS BettypeName,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 30001
				WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 30002
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				ELSE -1 END AS BettypeDisplayOrder,
		   -SUM((sd.winlost - sd.actual_stake) * sd.actualrate) MemberWinLoss,
           -SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss, 
           -SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
                      ELSE(sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking)
                 END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) * sd.actualrate) AS ExtraPT,
		   SUM(sd.scomm * sd.actualrate) Commission,
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
                                                                                                                                     END) VirtualIncome,
		   -SUM((sd.winlost - sd.actual_stake +
			     sd.awinlost + sd.mwinlost + sd.swinlost -
				 CASE WHEN sd.tpositiontaking = 1 THEN 0
                      ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
                 END +
				 CASE WHEN sd.virtualrate < sd.actualrate THEN(sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                                                                                ELSE sd.scomm / (1 - sd.tpositiontaking)
                                                                           END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
					  ELSE 0
                 END) * (sd.actualrate - sd.virtualrate)) VarianceIncome,
           SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE(1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(sd.stake) * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate
																															   ELSE sd.actualrate END END) AS RealTurnover, 
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
                    ELSE(1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(sd.stake) * sd.virtualrate END) AS VirtualTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
		 INNER JOIN #tmpMatch m ON sd.matchid = m.matchid
								   AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.sporttype = sbm.SportType
												  AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.recommend IN (52466, 5707545)
	GROUP BY sd.liveindicator,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 30001
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 30002
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				  ELSE -1 END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 'Soccer 8RM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 'Other Sports 8RM'
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466 THEN 30001
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466 THEN 30002
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 30003
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 30004
				  ELSE -1 END
	OPTION (RECOMPILE)

	-- Get Data
	SELECT LiveIndicator,
		   Bettype,
		   BettypeName,
		   MemberWinLoss,
		   SMAWinLoss,
		   ExtraPT,
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
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData

END
GO

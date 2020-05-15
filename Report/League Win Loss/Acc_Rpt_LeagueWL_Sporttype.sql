/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate SMALLDATETIME,
                                               @EndDate SMALLDATETIME,
                                               @SportTypeList VARCHAR(MAX)
AS
/*
	Created: Ned.Le@20200422
	Task: View all measures by sporttypes and leagues
	DB: DBACC.bodb02

	Revisions:
		- 20200422@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportTypeList: Set of sporttypes, seperate by ','

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate='20200407', @EndDate='20200407', @SportTypeList='1,10000,2,3,4'
*/

BEGIN

	SET NOCOUNT ON

	-- #tmpSportBettypeMatrix
	CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
									     Sport VARCHAR(50),
										 BetType SMALLINT)

	;WITH CTE_SportBettypeMatrix AS (
		SELECT DISTINCT
			   sbm.SportType,
			   s.SportName Sport,
			   sbm.BetType
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
			 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON sbm.SportType = s.SportType
		WHERE sbm.ProductID = 1
			  AND sbm.SportType <> 27
			  AND sbm.SubProduct NOT LIKE 'BT%'
			  AND sbm.BetType NOT IN (9, 29)
		UNION ALL
		SELECT DISTINCT
			   10000 SportType,
			   'Parlay' Sport,
			   sbm.BetType
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
		WHERE sbm.ProductID = 1
			  AND sbm.BetType IN (9, 29)
	)
	INSERT INTO #tmpSportBettypeMatrix (SportType, Sport, BetType)
	SELECT SportType, Sport, BetType
	FROM CTE_SportBettypeMatrix
	OPTION (RECOMPILE)

	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(SportType, BetType)

	DELETE sbm
	FROM #tmpSportBettypeMatrix sbm
	WHERE sbm.SportType NOT IN (SELECT val FROM bodb02.dbo.strSplit_str(@SportTypeList, ','))

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
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
	OPTION (RECOMPILE)
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpData
	CREATE TABLE #tmpData (SportType		SMALLINT,
						   Sport			VARCHAR(50),
						   LeagueID			INT,
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
						  LeagueID,
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
		   l.leagueid AS LeagueID,
		   l.leaguename AS LeagueName,
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
		 INNER JOIN bodb02.dbo.league l (NOLOCK) ON m.leagueid = l.leagueid
		 INNER JOIN #tmpSportBettypeMatrix sbm ON m.sporttype = sbm.SportType
			                                      AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype NOT IN (9, 29)
	GROUP BY sbm.SportType,
			 sbm.Sport,
			 l.leagueid,
		     l.leaguename
	OPTION (RECOMPILE)
	
	-- + Parlay
	IF EXISTS (SELECT TOP 1 1 FROM #tmpSportBettypeMatrix WHERE SportType = 10000)
	BEGIN
	INSERT INTO #tmpData (SportType,
						  Sport,
						  LeagueID,
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
		   -1 AS LeagueID,
		   '' AS LeagueName,
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
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype IN (9, 29)
	OPTION (RECOMPILE)
	END

	-- + RM
	INSERT INTO #tmpData (SportType,
						  Sport,
						  LeagueID,
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
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	  THEN -2
				WHEN sbm.SportType > 1 AND sd.recommend = 52466	  THEN -3
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN -4
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN -5
				ELSE -10000 END AS LeagueID,
		   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS LeagueName,
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
		 INNER JOIN bodb02.dbo.league l (NOLOCK) ON m.leagueid = l.leagueid
		 INNER JOIN #tmpSportBettypeMatrix sbm ON sbm.BetType NOT IN (9, 29)
			                                      AND m.SportType = sbm.SportType
												  AND sd.BetType = sbm.BetType
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.recommend IN (52466, 5707545)
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
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	THEN -2
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466	THEN -3
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN -4
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN -5
				  ELSE -10000 END,
		     CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
				  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END
	OPTION (RECOMPILE)

	-- Get Data
	SELECT SportType,
		   Sport,
		   LeagueID,
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
	ORDER BY SportType,
		     LeagueName

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData

END
GO

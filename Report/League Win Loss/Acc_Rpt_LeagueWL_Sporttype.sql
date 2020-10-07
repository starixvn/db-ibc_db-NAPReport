/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate SMALLDATETIME,
                                               @EndDate SMALLDATETIME,
                                               @SportBettype VARCHAR(MAX),
											   @LeagueName VARCHAR(500) = '',
											   @SiteName VARCHAR(MAX) = 'ALL',
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
		- 20200923@Jaden.Tang: NAP Report - Add filter by SiteName (#138955)
		- 20200930@Jaden.Tang: Odds Spread Adjustment (#141750)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @LeagueName: The leaguename to view on report
		               If value is '', it means that no filter by LeagueName
		- @SiteName: Filter by list of site names (delimited by commas)
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype @StartDate='2020-09-06', @EndDate='2020-09-06', 
			@SportBettype='1_1,1_2,10000_9,10000_29,2_1,3_1,4_1,5_1,6_1,7_1,8_1,9_1', @LeagueName='', @IsNoDraw=0, 
			@SiteName = '12Bet,755555,INDO,789y,IBCIndo,BEST-ODDS,722222,733333,XYZBET,asiabet88'
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
		FROM bodb02.dbo.strSplit(@SportBettype, ',')
		WHERE LEN(val) > 0
	)
	INSERT INTO #tmpSportBettypeMatrix (SportType, Sport, BetType)
	SELECT cte.SportType,
		   CASE WHEN cte.SportType = 10000 THEN 'Parlay' 
		    	WHEN cte.SportType = 10001 THEN 'SB Adjustment' 
				ELSE s.SportName END Sport,
		   cte.BetType
	FROM CTE_SportBettypeMatrix cte
		 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON cte.SportType = s.SportType

	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(SportType, BetType)

	-- #tmpLeague
	CREATE TABLE #tmpLeague (LeagueId INT)

	INSERT INTO #tmpLeague (LeagueId)
	SELECT leagueid
	FROM bodb02.dbo.league (NOLOCK)
	WHERE leaguename LIKE '%' + @LeagueName + '%'
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

	-- #tmpAgentBySite: list of active agents in the list input @SiteName
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

	--staging table for performance enhancement
	CREATE TABLE #transLeague(LeagueID			INT, 
						      BetType 			INT,
						      LeagueName		VARCHAR(150),
						      MemberWinLoss		MONEY,
						      SMAWinLoss		MONEY,
						      ExtraPT			MONEY,
						      Commission		MONEY,
						      RealIncome		MONEY,
						      VirtualIncome		MONEY,
						      VarianceIncome	MONEY,
						      RealTurnover		MONEY,
						      VirtualTurnover	MONEY)
	
	INSERT INTO #transLeague(LeagueID,
						     BetType,
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
	SELECT m.leagueid,
		   sd.bettype,
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
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND sd.bettype NOT IN (9, 29, 999) --exclude Parlay (9, 29) & SB Odds Spread Adjustment (999)
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
		  AND (@SiteName = 'ALL' OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
		  AND sd.bettype IN (SELECT s.BetType FROM #tmpSportBettypeMatrix s )
	GROUP BY m.leagueid, sd.bettype, m.leaguename
	OPTION (RECOMPILE)

	-- #tmpData
	-- + Soccer, Other Sports
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
	   SELECT l.sporttype,
	   		  sbm.Sport,
		      l.leaguename AS LeagueName,
		      SUM(MemberWinLoss) AS MemberWinLoss,
              SUM(SMAWinLoss) AS SMAWinLoss,
		      SUM(ExtraPT) AS ExtraPT,
		      SUM(Commission) AS Commission,
		      SUM(RealIncome) AS RealIncome,
		      SUM(VirtualIncome) AS VirtualIncome,
              SUM(VarianceIncome) AS VarianceIncome,
              SUM(RealTurnover) AS RealTurnover, 
		      SUM(VirtualTurnover) AS VirtualTurnover
		FROM #transLeague sd 
		INNER JOIN bodb02.dbo.League l WITH (NOLOCK) ON sd.leagueid = l.leagueid	
		INNER JOIN #tmpSportBettypeMatrix sbm ON l.sporttype = sbm.SportType AND sd.BetType = sbm.BetType
		GROUP BY  l.sporttype, sbm.Sport, l.leaguename
		OPTION (RECOMPILE)
	
	-- + Parlay, Odds Spread Adjustment (#141750)
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
	SELECT CASE WHEN sd.bettype IN (9, 29) THEN 10000
				WHEN sd.bettype = 999 	   THEN 10001
		   END AS SportType,
		   CASE WHEN sd.bettype IN (9, 29) THEN 'Parlay'
				WHEN sd.bettype = 999 	   THEN 'SB Adjustment'
		   END AS Sport,
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
		  AND sd.bettype IN (SELECT BetType FROM #tmpSportBettypeMatrix WHERE SportType IN (10000, 10001))
		  --10000, 10001 are custom sport ids defined from SporttypeSel to identify if Parlay/OddsSpread checkbox is selected
		  AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
		  AND (@SiteName = 'ALL' OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
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
		  AND (@SiteName = 'ALL' OR sd.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
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
	ORDER BY CASE WHEN Sport = 'Soccer' 	THEN 1
				  WHEN Sport = 'Parlay' 	THEN 2
				  WHEN Sport = 'Basketball' THEN 3
				  WHEN Sport = 'Tennis'		THEN 4
				  WHEN Sport = 'E-Sports'	THEN 5 
				  ELSE 
				  	CASE WHEN SportType > 10000 THEN 99 ELSE 6 END
				  END, Sport, LeagueName --fix some sports at top, then sort by league name

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpLeague
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData
	DROP TABLE #tmpAgentBySite
	DROP TABLE #transLeague

END
GO

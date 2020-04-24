/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Details @StartDate SMALLDATETIME,
                                             @EndDate SMALLDATETIME,
                                             @SportType INT,
											 @LeagueID INT,
											 @LiveIndicator TINYINT,
											 @BetType SMALLINT
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by match information
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportType: The sporttype to view on report
		- @LeagueID: The leagueid to view on report
		- @BetType: The bettype to view on report
		- @LiveIndicator: To indicate the live status to view on report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Details @StartDate='20200421', @EndDate='20200421', @SportType=1, @LeagueID=143, @LiveIndicator=1, @BetType=1
*/

BEGIN

	SET NOCOUNT ON

	-- #tmpMatch
	CREATE TABLE #tmpMatch (matchid INT,
						    matchcode VARCHAR(500),
							matchtype TINYINT,
							homeid INT,
							hometeamname VARCHAR(100),
							awayid INT,
							awayteamname VARCHAR(100))
	INSERT INTO #tmpMatch(matchid, matchcode, matchtype, homeid, hometeamname, awayid, awayteamname)
	SELECT m.matchid,
		   m.matchcode,
		   0 matchtype,
		   m.homeid,
		   ISNULL(home.teamname, '') hometeamname,
		   m.awayid,
		   ISNULL(away.teamname,'') awayteamname
	FROM [bodb02].[dbo].[match] m (NOLOCK)
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON l.sporttype = @SportType
														 AND l.leagueid = @LeagueID
														 AND m.leagueid = l.leagueid
	     LEFT JOIN bodb02.dbo.Team home (NOLOCK) ON m.homeid = home.teamid
		 LEFT JOIN bodb02.dbo.Team away (NOLOCK) ON m.awayid = away.teamid
	WHERE m.eventdate = @StartDate
	UNION ALL
	SELECT m.orid matchid,
		   m.matchcode,
		   1 matchtype,
		   m.teamid homeid,
		   ISNULL(team.teamname, '') hometeamname,
		   -1 awayid,
		   '' awayteamname
	FROM bodb02.dbo.outright m (NOLOCK)
		 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON l.sporttype = @SportType
														 AND l.leagueid = @LeagueID
														 AND m.leagueid = l.leagueid
		 LEFT JOIN bodb02.dbo.Team team (NOLOCK) ON m.teamid = team.teamid
	WHERE m.eventdate = @StartDate
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpData
	CREATE TABLE #tmpData (MatchCode			VARCHAR(50),
						   HomeID				INT,
						   AwayID				INT,
						   MatchEvent			VARCHAR(500),
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
	INSERT INTO #tmpData (MatchCode,
						  HomeID,
						  AwayID,
						  MatchEvent,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT m.matchcode AS MatchCode,
		   m.homeid AS HomeID,
		   m.awayid AS AwayID,
		   CASE WHEN sd.BetType = 10 THEN m.hometeamname
				ELSE m.hometeamname + ' -vs- ' + m.awayteamname END MatchEvent,
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
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.liveindicator = @LiveIndicator
		  AND sd.bettype = @BetType
	GROUP BY m.matchcode,
		     m.homeid,
		     m.awayid,
		     CASE WHEN sd.BetType = 10 THEN m.hometeamname
				  ELSE m.hometeamname + ' -vs- ' + m.awayteamname END
	OPTION (RECOMPILE)
	
	-- + RM
	INSERT INTO #tmpData (MatchCode,
						  HomeID,
						  AwayID,
						  MatchEvent,
						  MemberWinLoss,
						  SMAWinLoss,
						  ExtraPT,
						  Commission,
						  RealIncome,
						  VirtualIncome,
						  VarianceIncome,
						  RealTurnover,
						  VirtualTurnover)
	SELECT '' AS MatchCode,
		   -1 AS HomeID,
		   -1 AS AwayID,
		   CASE WHEN @SportType = 1 AND sd.recommend = 52466 THEN 'Soccer 8RM'
				WHEN @SportType > 1 AND sd.recommend = 52466 THEN 'Other Sports 8RM'
				WHEN @SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				WHEN @SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				ELSE '' END AS MatchEvent,
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
	WHERE sd.winlostdate = @StartDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.recommend IN (52466, 5707545)
		  AND sd.liveindicator = @LiveIndicator
		  AND sd.bettype = @BetType
	GROUP BY CASE WHEN @SportType = 1 AND sd.recommend = 52466 THEN 'Soccer 8RM'
				  WHEN @SportType > 1 AND sd.recommend = 52466 THEN 'Other Sports 8RM'
				  WHEN @SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
				  WHEN @SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
				  ELSE '' END
	OPTION (RECOMPILE)

	-- Get Data
	SELECT MatchCode,
		   HomeID,
		   AwayID,
		   MatchEvent,
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
	ORDER BY MatchEvent

	-- Drop temp tables
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData

END
GO

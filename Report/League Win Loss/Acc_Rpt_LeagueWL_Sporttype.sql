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
		- 20201016@Jaden.Tang: Refactor for code readability & performance

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

	BEGIN -- #tmpSportBettypeMatrix
		CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT, BetType SMALLINT)
		
		;WITH CTE_SportBettypeMatrix AS (
			SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
				CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
			FROM bodb02.dbo.strSplit(@SportBettype, ',')
			WHERE LEN(val) > 0
		)
		INSERT INTO #tmpSportBettypeMatrix (SportType, BetType)
			SELECT cte.SportType, cte.BetType
			FROM CTE_SportBettypeMatrix cte
		OPTION (RECOMPILE)
	END

	BEGIN -- #tmpMatch
		CREATE TABLE #tmpMatch (MatchID 	INT,
								SportType 	SMALLINT,
								LeagueID 	INT,
								LeagueName 	VARCHAR(500),
								MatchType 	TINYINT)

		;WITH CTE_Match AS (
			SELECT matchid, leagueid, 0 AS matchtype FROM match WITH (NOLOCK) WHERE eventdate = @StartDate
			UNION ALL
			SELECT orid AS matchid, leagueid, 1 AS matchtype FROM outright WITH (NOLOCK) WHERE eventdate = @StartDate
		)
		INSERT INTO #tmpMatch(MatchID, SportType, LeagueID, LeagueName, MatchType)
			SELECT m.matchid, l.sporttype, l.leagueid, l.leaguename, m.matchtype
			FROM CTE_Match m
			INNER JOIN bodb02.dbo.league l WITH (NOLOCK) 
				ON m.leagueid = l.leagueid
				AND ('' = @LeagueName OR leaguename LIKE '%' + @LeagueName + '%' AND isTest = 0)
			WHERE 
				EXISTS (SELECT 1 FROM #tmpSportBettypeMatrix sbm WHERE l.sporttype = sbm.SportType)
			OPTION (RECOMPILE)

		CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)
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
			OPTION (RECOMPILE)
		END
	END 

	BEGIN -- #matchBettypeTmp: staging table for performance enhancement
		-- Join directly with bettrans table on match, sporttype, bettype for reports that 
		-- include sport book data will cause estimation problem.
		CREATE TABLE #matchBettypeTmp (MatchID			INT, 
								  	   BetType 			INT,
								  	   MemberWinLoss	MONEY,
								  	   SMAWinLoss		MONEY,
								  	   ExtraPT			MONEY,
								  	   Commission		MONEY,
								  	   RealIncome		MONEY,
								  	   VirtualIncome	MONEY,
								  	   VarianceIncome	MONEY,
								  	   RealTurnover		MONEY,
								  	   VirtualTurnover	MONEY)
		
		INSERT INTO #matchBettypeTmp
			SELECT 
				sd.matchid,
				sd.bettype,
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
			GROUP BY sd.matchid, sd.bettype
			OPTION (RECOMPILE)
	END

	-- #tmpData: display tmp (sport / league)
	CREATE TABLE #tmpData ( SportType		SMALLINT,
							LeagueName		VARCHAR(150),
							MemberWinLoss	MONEY,
							SMAWinLoss		MONEY,
							ExtraPT			MONEY,
							Commission		MONEY,
							RealIncome		MONEY,
							VirtualIncome	MONEY,
							VarianceIncome	MONEY,
							RealTurnover	MONEY,
							VirtualTurnover	MONEY)
	BEGIN
		-- + Soccer, Other Sports
		INSERT INTO #tmpData
			SELECT  m.SportType,
					m.LeagueName,
					SUM(MemberWinLoss), 
					SUM(SMAWinLoss), 
					SUM(ExtraPT),
					SUM(Commission),
					SUM(RealIncome),
					SUM(VirtualIncome),
					SUM(VarianceIncome),
					SUM(RealTurnover), 
					SUM(VirtualTurnover)
				FROM #matchBettypeTmp sd
				INNER JOIN #tmpMatch m /*filtering with matchid eliminates parlay & odds spread data*/
					ON sd.matchid = m.matchid
					AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
				GROUP BY  m.SportType,
						  m.LeagueName
				OPTION (RECOMPILE)
		
		-- + Parlay, Odds Spread
		INSERT INTO #tmpData
			SELECT CASE WHEN sd.bettype IN (9, 29) THEN 10000
						WHEN sd.bettype = 999 	   THEN 10001
					END AS SportType,
					CASE WHEN sd.bettype IN (9, 29) THEN 'Parlay'
						 WHEN sd.bettype = 999 	    THEN 'SB Adjustment'
					END AS Sport,
				   '' 	AS LeagueName,
				   SUM(MemberWinLoss), 
				   SUM(SMAWinLoss), 
				   SUM(ExtraPT),
				   SUM(Commission),
				   SUM(RealIncome),
				   SUM(VirtualIncome),
				   SUM(VarianceIncome),
				   SUM(RealTurnover), 
				   SUM(VirtualTurnover)
			FROM #matchBettypeTmp sd
			WHERE BetType IN (9, 29, 999)
			OPTION (RECOMPILE)

		-- + RM
		INSERT INTO #tmpData
			SELECT CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	  THEN 100001
						WHEN sbm.SportType > 1 AND sd.recommend = 52466	  THEN 100002
						WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 100003
						WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 100004
						ELSE -10000 END 												AS SportType,
				   CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
						WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
						WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
						WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
						ELSE '' END 													AS LeagueName,
				   - SUM(sd.MemberWinLoss),
				   - SUM(sd.SMAWinLoss),
				   - SUM(sd.[Extra's Amount]) 											AS ExtraPT,
				   SUM(sd.TreeCommission) 												AS Commission,
				   - SUM(sd.RealHouseIncome) 											AS RealIncome,
				   - SUM(sd.VirtualHouseIncome) 										AS VirtualIncome,
				   - SUM(sd.VarianceHouseIncome) 										AS VarianceIncome,
				   SUM(sd.RealHouseTurnover) 											AS RealTurnover, 
				   SUM(sd.VirtualHouseTurnover) 										AS VirtualTurnover
			FROM bodb02.dbo.f_bettrans_measures(@IsNoDraw) sd
				INNER JOIN #tmpMatch m 
					ON sd.matchid = m.MatchID AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
				INNER JOIN #tmpSportBettypeMatrix sbm 
					ON m.SportType = sbm.SportType AND sd.BetType = sbm.BetType
			WHERE sd.winlostdate = @StartDate
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND sd.bettype NOT IN (9, 29)
				AND sd.recommend IN (52466, 5707545)
				AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
			GROUP BY CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466	THEN 100001
						  WHEN sbm.SportType > 1 AND sd.recommend = 52466	THEN 100002
						  WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 100003
						  WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 100004
						  ELSE -10000 END,
					CASE WHEN sbm.SportType = 1 AND sd.recommend = 52466   THEN 'Soccer 8RM'
						 WHEN sbm.SportType > 1 AND sd.recommend = 52466   THEN 'Other Sports 8RM'
						 WHEN sbm.SportType = 1 AND sd.recommend = 5707545 THEN 'Soccer BARM'
						 WHEN sbm.SportType > 1 AND sd.recommend = 5707545 THEN 'Other Sports BARM'
						 ELSE '' END
			OPTION (RECOMPILE)
	END

	-- Get Data
	SELECT * 
	FROM 
	(
		SELECT t.SportType,
			CASE WHEN t.SportType = 10000 THEN 'Parlay'
				 WHEN t.SportType = 10001 THEN 'SB Adjustment'
				 WHEN t.SportType BETWEEN 100001 AND 100004 THEN LeagueName
				 ELSE SportName END AS Sport,
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
		FROM #tmpData t
		LEFT JOIN bodb02.dbo.Sports 
			ON Sports.SportType = t.SportType
		WHERE MemberWinLoss IS NOT NULL
	) AS s
	ORDER BY CASE WHEN Sport = 'Soccer' 		THEN 1
				  WHEN Sport = 'Parlay' 		THEN 2
				  WHEN Sport = 'SB Adjustment'  THEN 3
				  WHEN Sport = 'Basketball' 	THEN 4
				  WHEN Sport = 'Tennis'			THEN 5
				  WHEN Sport = 'E-Sports'		THEN 6 
				  ELSE 
				  	CASE WHEN SportType > 100000 THEN 99 ELSE 7 END
				  END, Sport, LeagueName --fix some sports at top, then sort by league name

	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpMatch
	DROP TABLE #tmpData
	DROP TABLE #tmpAgentBySite
	DROP TABLE #matchBettypeTmp
END
GO

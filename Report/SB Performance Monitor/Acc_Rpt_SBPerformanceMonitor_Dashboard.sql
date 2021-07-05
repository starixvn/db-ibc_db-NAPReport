/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate SMALLDATETIME,
														    @toDate SMALLDATETIME,
															@timeRange SMALLINT = -1,
														    @isShowSite BIT,
														    @isShowSport BIT,
															@isShowLeague BIT,
														    @isShowCust BIT,
															@margin FLOAT = NULL,
															@top BIGINT = 50,
															@topBy VARCHAR(20) = 'RealTurnover',
															@excludeDrawTickets BIT = 0,
															@excludeParlay BIT = 1
AS
/*
	Created: Ned.Le@20200526
	Task: Getting data for dashboard of SB Performance Monitor Report
	DB: DBACC.bodb02

	Revisions:
		- 20200526@Ned.Le: [SB R&C] Implement Performance Monitor report (#134119)
		- 20200930@Ned.Le: NAP Reports - Licensee Odds Spread (#141750)
		- 20210504@Kean.Nguyen: NAP Reports - Allow more time for transfer - Movebet&BalanceUp (#154116)
		- 20210705@Jaden.Tang: Enhance SB Performance, add more options (#157997)

	Param's Explanation:
		- @fromDate: Range date to get data for report
		- @toDate: Range date to get data for report
		- @isShowSite:   0: Columns related to Site have NULL value
					     1: Columns related to Site have SPECIFIC value
		- @isShowSport:  0: Columns related to Sport have NULL value
					     1: Columns related to Sport have SPECIFIC value
		- @isShowLeague: 0: Columns related to League have NULL value
						 1: Columns related to League have SPECIFIC value
		- @isShowCust:   0: Columns related to Cust have NULL value
					     1: Columns related to Cust have SPECIFIC value
		- @margin: Value for filter data in the situation of site or sport
						 NULL: Get ALL
		- @top: Value for filter data in the situation of league or cust
		- @topBy: The metric to order by, depends on display type (@isShowSite, @isShowCust...), see spec for details
				  Select from 3 options: "RealTurnover", "RealIncome", "Margin"
		- @excludeDrawTickets: 
						 0: Include all tickets
						 1: Exclude draw tickets
		- @excludeParlay: Exclude parlay tickets, filter not in effect when using with @isShowLeague = 1

	Example:
		EXEC bodb02.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate='20200520', @toDate='20200520',
																  @isShowSite=1, @isShowSport=0, @isShowLeague=0, @isShowCust=0,
																  @margin = 3, @top = 50
		EXEC bodb02.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate=CAST(GETDATE() AS DATE), @toDate=CAST(GETDATE() AS DATE),
																  @isShowSite=1, @isShowSport=0, @isShowLeague=0, @isShowCust=0,
																  @margin = 3, @top = 50
		EXEC bodb02.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate='20200520', @toDate='20200520',
																  @isShowSite=0, @isShowSport=0, @isShowLeague=1, @isShowCust=0,
																  @margin = 3, @top = 50
		EXEC bodb02.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate=CAST(GETDATE() AS DATE), @toDate=CAST(GETDATE() AS DATE),
																  @isShowSite=0, @isShowSport=0, @isShowLeague=1, @isShowCust=0,
																  @margin = 3, @top = 50
*/

BEGIN

	SET NOCOUNT ON

	-- Declare variables
	DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME
	SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
 
	IF @isShowLeague = 1 SET @excludeParlay = 1
	
	-- #tmpBettypeGroup
	CREATE TABLE #tmpBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)
	
	INSERT INTO #tmpBettypeGroup (BettypeGroupID, Bettype)
	SELECT BettypeGroupID, Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup
	WHERE BettypeGroupID = 12
	
	-- #tmpSportBettypeMatrix
	CREATE TABLE #tmpSportBettypeMatrix (BetType SMALLINT)

	INSERT INTO #tmpSportBettypeMatrix (BetType)
	SELECT DISTINCT sbm.BetType
	FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
	WHERE sbm.ProductID = 1
		  AND sbm.SubProduct NOT LIKE 'BT%'
		  AND ((sbm.BetType NOT IN (9, 29, 999) AND @excludeParlay = 1)
		   OR @excludeParlay = 0)

	CREATE UNIQUE CLUSTERED INDEX PK_tmpSportBettypeMatrix ON #tmpSportBettypeMatrix(BetType)

	-- #tmpMatch
	CREATE TABLE #tmpMatch (SportType INT,
							leagueid INT,
							matchid INT,
							matchtype SMALLINT)

	;WITH
	CTE_Match AS (
		SELECT matchid AS matchid, leagueid, 0 AS matchtype
		FROM [bodb02].[dbo].[match] (NOLOCK)
		WHERE eventdate >= @fromDate AND eventdate <= @toDate
		UNION ALL
		SELECT orid AS matchid, leagueid, 1 AS matchtype
		FROM bodb02.dbo.outright (NOLOCK)
		WHERE eventdate >= @fromDate AND eventdate <= @toDate
	)
	INSERT INTO #tmpMatch (SportType, leagueid, matchid, matchtype)
	SELECT s.SportType,
		   l.leagueid,
		   m.matchid,
		   m.matchtype
	FROM CTE_Match m
		 INNER JOIN bodb02.dbo.league l (NOLOCK) ON m.leagueid = l.leagueid
		 INNER JOIN bodb02.dbo.Sports s (NOLOCK) ON l.sporttype = s.SportType
	OPTION (RECOMPILE)

	IF (@fromDate <= @MoveBetsDay)
	BEGIN
		;WITH
		CTE_Match AS (
			SELECT matchid AS matchid, leagueid, 0 AS matchtype
			FROM [bodb02].[dbo].[match14] (NOLOCK)
			WHERE eventdate >=@fromDate AND eventdate <= @MoveBetsDay
			UNION ALL
			SELECT orid AS matchid, leagueid, 1 AS matchtype
			FROM bodb02.dbo.outright14 (NOLOCK)
			WHERE eventdate >=@fromDate AND eventdate <= @MoveBetsDay
		)
		INSERT INTO #tmpMatch (SportType, leagueid, matchid, matchtype)
		SELECT s.SportType,
			   l.leagueid,
			   m.matchid,
			   m.matchtype
		FROM CTE_Match m
			 INNER JOIN bodb02.dbo.league l (NOLOCK) ON m.leagueid = l.leagueid
			 INNER JOIN bodb02.dbo.Sports s (NOLOCK) ON l.sporttype = s.SportType
		OPTION (RECOMPILE)
	END
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)

	-- #tmpAgent
	CREATE TABLE #tmpAgent (CustID INT,
							SiteID INT)
	
	INSERT INTO #tmpAgent (CustID, SiteID)
	SELECT c.CustId CustID, 
		   s.siteid SiteID
	FROM bodb02.dbo.Customer c (NOLOCK)
		 LEFT JOIN bodb02.dbo.Site s (NOLOCK) ON c.site = s.site
	WHERE c.RoleID = 2
	OPTION (RECOMPILE)

	CREATE UNIQUE CLUSTERED INDEX PK_tmpAgent ON #tmpAgent(CustID)
	
	-- #tmpData
	CREATE TABLE #tmpData (SiteID INT,
						   SportID INT,
						   LeagueID INT,
						   CustID INT,
						   BetCount INT,
						   RealIncome DECIMAL(19, 4),
						   RealTurnover DECIMAL(19, 4))
	
	INSERT INTO #tmpData (SiteID, SportID, LeagueID, CustID, BetCount, RealIncome, RealTurnover)
	SELECT -- DIMENSION
		   CASE WHEN @isShowSite = 0 THEN NULL ELSE a.SiteID END AS SiteID,
		   CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END AS SportID,
		   CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END AS LeagueID,
		   CASE WHEN @isShowCust = 0 THEN NULL ELSE sd.custid END AS CustID,
		   -- MEASURE
		   SUM(CASE WHEN bg.Bettype IS NOT NULL OR td.[VendorID] = 14 THEN 0 
					ELSE 1 END) AS BetCount,
		   SUM(CASE WHEN sd.recommend IN (52466, 5707545) THEN 0
			        ELSE (-(sd.winlost - sd.actual_stake +
			              sd.awinlost + sd.mwinlost + sd.swinlost +
			              sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
								           ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
						              END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate)
			   END) AS RealIncome,
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
					ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
						 * ABS(sd.stake)
						 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
			   END * 
			   CASE WHEN @excludeDrawTickets = 1 
                 THEN CASE WHEN (sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399)
                                 AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914)
                                 AND sd.bettype NOT BETWEEN 81 AND 120
                                 AND sd.statusID IN (112, 113)
                                 AND ABS(sd.modds) = 0.25
                           THEN 0.5
                      ELSE 1 END
                 ELSE 1 END)
			   AS RealTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK) /*TODO: use with f_bettrans_measures */
		 LEFT JOIN #tmpAgent a ON sd.recommend = a.CustID
		 LEFT JOIN #tmpMatch m ON sd.matchid = m.matchid
								  AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
		 LEFT JOIN bodb02.dbo.TradeCust AS td WITH (NOLOCK) ON sd.custid = td.custid
		 LEFT JOIN #tmpBettypeGroup bg ON sd.bettype = bg.Bettype
	WHERE sd.winlostdate >= @fromDate AND sd.winlostdate <= @toDate
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND EXISTS (SELECT TOP 1 1
					  FROM #tmpSportBettypeMatrix sbm
					  WHERE sd.BetType = sbm.BetType)
          AND (@excludeDrawTickets = 0 OR (@excludeDrawTickets = 1 AND statusID NOT IN (111))) -- exclude draw tickets if flag is turned on
	GROUP BY CASE WHEN @isShowSite = 0 THEN NULL ELSE a.SiteID END,
		     CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END,
			 CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END,
		     CASE WHEN @isShowCust = 0 THEN NULL ELSE sd.custid END
	OPTION (RECOMPILE)

	IF (@fromDate <= @MoveBetsDay)
	BEGIN
		INSERT INTO #tmpData (SiteID, SportID, LeagueID, CustID, BetCount, RealIncome, RealTurnover)
		SELECT -- DIMENSION
			   CASE WHEN @isShowSite = 0 THEN NULL ELSE a.SiteID END AS SiteID,
			   CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END AS SportID,
			   CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END AS LeagueID,
			   CASE WHEN @isShowCust = 0 THEN NULL ELSE sd.custid END AS CustID,
			   -- MEASURE
			   SUM(CASE WHEN bg.Bettype IS NOT NULL OR td.[VendorID] = 14 THEN 0 
						ELSE 1 END) AS BetCount,
			   SUM(CASE WHEN sd.recommend IN (52466, 5707545) THEN 0
			            ELSE (-(sd.winlost - sd.actual_stake +
			                  sd.awinlost + sd.mwinlost + sd.swinlost +
			                  sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
								               ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
						                  END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate)
			       END) AS RealIncome,
			   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
						ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
							 * ABS(sd.stake)
							 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
				   END * 
				   CASE WHEN @excludeDrawTickets = 1 
						THEN CASE WHEN (sd.bettype < 999 OR sd.bettype BETWEEN 1301 AND 1399 OR sd.bettype BETWEEN 9001 AND 9399)
										AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914)
										AND sd.bettype NOT BETWEEN 81 AND 120
										AND sd.statusID IN (112, 113)
										AND ABS(sd.modds) = 0.25
								THEN 0.5
							ELSE 1 END
						ELSE 1 END)
				   AS RealTurnover
		FROM bodb02.dbo.bettrans14 sd (NOLOCK)
			 LEFT JOIN #tmpAgent a ON sd.recommend = a.CustID
			 LEFT JOIN #tmpMatch m ON sd.matchid = m.matchid
									  AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
			 LEFT JOIN bodb02.dbo.TradeCust AS td WITH (NOLOCK) ON sd.custid = td.custid
			 LEFT JOIN #tmpBettypeGroup bg ON sd.bettype = bg.Bettype
		WHERE sd.winlostdate >= @fromDate AND sd.winlostdate <= @MoveBetsDay
			  AND sd.ruben = 1
			  AND sd.statusID IN (111, 112, 113)
			  AND sd.currency NOT IN (20, 27, 28)
			  AND EXISTS (SELECT TOP 1 1
						  FROM #tmpSportBettypeMatrix sbm
						  WHERE sd.BetType = sbm.BetType)
          	  AND (@excludeDrawTickets = 0 OR (@excludeDrawTickets = 1 AND statusID NOT IN (111)))
		GROUP BY CASE WHEN @isShowSite = 0 THEN NULL ELSE a.SiteID END,
				 CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END,
				 CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END,
				 CASE WHEN @isShowCust = 0 THEN NULL ELSE sd.custid END
		OPTION (RECOMPILE)
	END

	-- #tmpFinal
	CREATE TABLE #tmpFinal (SiteID INT,
							SiteName VARCHAR(50),
						    SportID INT,
							SportName VARCHAR(50),
						    LeagueID INT,
							LeagueName VARCHAR(500),
						    CustID INT,
							CustName VARCHAR(30),
						    BetCount INT,
						    RealIncome DECIMAL(19, 4),
						    RealTurnover DECIMAL(19, 4),
							RealMargin DECIMAL(19, 4))
	
	;WITH
	CTE_Aggregate AS (
		SELECT SiteID,
			   SportID,
			   LeagueID,
			   CustID,
			   SUM(BetCount) BetCount,
			   SUM(RealIncome) RealIncome,
			   SUM(RealTurnover) RealTurnover
		FROM #tmpData
		GROUP BY SiteID,
			     SportID,
			     LeagueID,
			     CustID
	),
	CTE_Margin AS (
		SELECT SiteID,
			   SportID,
			   LeagueID,
			   CustID,
			   BetCount,
			   RealIncome,
			   RealTurnover,
			   CASE WHEN RealTurnover = 0 THEN 0 ELSE ((RealIncome / RealTurnover) * 100) END RealMargin
		FROM CTE_Aggregate
	)
	INSERT INTO #tmpFinal (SiteID, SiteName, SportID, SportName, LeagueID, LeagueName, CustID, CustName, BetCount, RealIncome, RealTurnover, RealMargin)
	SELECT cte.SiteID,
		   si.site SiteName,
		   cte.SportID,
		   sp.SportName SportName,
		   cte.LeagueID,
		   l.leaguename LeagueName,
		   cte.CustID,
		   c.username CustName,
		   cte.BetCount,
		   cte.RealIncome,
		   cte.RealTurnover,
		   cte.RealMargin
	FROM CTE_Margin cte
		 LEFT JOIN bodb02.dbo.Site si (NOLOCK) ON cte.SiteID = si.siteid
		 LEFT JOIN bodb02.dbo.Sports sp (NOLOCK) ON cte.SportID = sp.SportType
		 LEFT JOIN bodb02.dbo.league l (NOLOCK) ON cte.LeagueID = l.leagueid
		 LEFT JOIN bodb02.dbo.Customer c (NOLOCK) ON cte.CustID = c.custid
	
	-- 1 = ASC; -1 = DESC
	DECLARE @orderDirection SMALLINT = 
		CASE WHEN @isShowLeague = 1 THEN
				CASE @topBy
					WHEN 'RealTurnover' THEN -1
					ELSE 1
				END
			 WHEN @isShowCust = 1 THEN -1
			 ELSE NULL
		END

	-- Return data
	SELECT TOP (CASE WHEN @isShowLeague = 1 OR @isShowCust = 1 THEN @top ELSE 0x7fffffffffffffff END)
		CASE WHEN @isShowSite = 1 THEN SiteID
			 WHEN @isShowSport = 1 THEN SportID
			 WHEN @isShowLeague = 1 THEN LeagueID
			 WHEN @isShowCust = 1 THEN CustID END AS [ID],
		CASE WHEN @isShowSite = 1 THEN SiteName
			 WHEN @isShowSport = 1 THEN SportName
			 WHEN @isShowLeague = 1 THEN LeagueName
			 WHEN @isShowCust = 1 THEN CustName END AS [Name],
		BetCount, RealIncome, RealTurnover, RealMargin
	FROM #tmpFinal
	WHERE (@isShowLeague = 1 OR @isShowCust = 1 AND RealMargin <= ISNULL(@margin, RealMargin))
	   OR (@isShowLeague = 0 AND @isShowCust = 0) -- @margin filter is not applied on top league & top member reports
	ORDER BY 
		CASE WHEN @isShowLeague = 1 OR @isShowCust = 1 THEN 
				CASE @topBy 
					WHEN 'RealTurnover' THEN RealTurnover
				 	WHEN 'RealIncome' THEN RealIncome
					WHEN 'Margin' THEN RealMargin END
		END * @orderDirection
	OPTION (RECOMPILE)

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpMatch
	DROP TABLE #tmpAgent
	DROP TABLE #tmpData
	DROP TABLE #tmpFinal
	DROP TABLE #tmpBettypeGroup

END
GO

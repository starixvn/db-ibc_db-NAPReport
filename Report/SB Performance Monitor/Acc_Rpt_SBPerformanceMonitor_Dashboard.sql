/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

CREATE PROCEDURE dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate DATE,
														    @toDate DATE,
														    @isShowSite BIT,
														    @isShowSport BIT,
															@isShowLeague BIT,
														    @isShowCust BIT
AS
/*
	Created: Ned.Le@20200526
	Task: Getting data for dashboard of SB Performance Monitor Report
	DB: DBACC.bodb02

	Revisions:
		- 20200526@Ned.Le: [SB R&C] Implement Performance Monitor report (#134119)

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

	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate='20200520', @toDate='20200520',
																  @isShowSite=1, @isShowSport=0, @isShowLeague=0, @isShowCust=0
		EXEC bodb_dwrs.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate=CAST(GETDATE() AS DATE), @toDate=CAST(GETDATE() AS DATE),
																  @isShowSite=1, @isShowSport=0, @isShowLeague=0, @isShowCust=0
		EXEC bodb_dwrs.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate='20200520', @toDate='20200520',
																  @isShowSite=0, @isShowSport=0, @isShowLeague=1, @isShowCust=0
		EXEC bodb_dwrs.dbo.Acc_Rpt_SBPerformanceMonitor_Dashboard @fromDate=CAST(GETDATE() AS DATE), @toDate=CAST(GETDATE() AS DATE),
																  @isShowSite=0, @isShowSport=0, @isShowLeague=1, @isShowCust=0
*/

BEGIN

	SET NOCOUNT ON

	-- #tmpSportBettypeMatrix
	CREATE TABLE #tmpSportBettypeMatrix (BetType SMALLINT)

	INSERT INTO #tmpSportBettypeMatrix (BetType)
	SELECT DISTINCT sbm.BetType
	FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
	WHERE sbm.ProductID = 1
		  AND sbm.SubProduct NOT LIKE 'BT%'
		  AND sbm.BetType NOT IN (9, 29)

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
		WHERE eventdate >= CAST(@fromDate AS DATETIME) AND eventdate <= CAST(@toDate AS DATETIME)
		UNION ALL
		SELECT orid AS matchid, leagueid, 1 AS matchtype
		FROM bodb02.dbo.outright (NOLOCK)
		WHERE eventdate >= CAST(@fromDate AS DATETIME) AND eventdate <= CAST(@toDate AS DATETIME)
	)
	INSERT INTO #tmpMatch (SportType, leagueid, matchid, matchtype)
	SELECT s.SportType,
		   l.leagueid,
		   m.matchid,
		   m.matchtype
	FROM CTE_Match m
		 INNER JOIN bodb02.dbo.league l (NOLOCK) ON m.leagueid = l.leagueid
		 INNER JOIN bodb02.dbo.Sports s (NOLOCK) ON l.sporttype = s.SportType
	
	CREATE UNIQUE CLUSTERED INDEX PK_tmpMatch ON #tmpMatch(matchid, matchtype)
	
	-- Return data
	SELECT -- DIMENSION
		   CASE WHEN @isShowSite = 0 THEN NULL ELSE si.siteid END SiteID,
		   CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END SportID,
		   CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END LeagueID,
		   CASE WHEN @isShowCust = 0 THEN NULL ELSE c.custid END CustID,
		   -- MEASURE
		   COUNT(1) AS BetCount,
		   SUM(-(sd.winlost - sd.actual_stake +
			     sd.awinlost + sd.mwinlost + sd.swinlost +
			     sd.scomm - (CASE WHEN sd.tpositiontaking = 1 THEN 0
								  ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
						     END) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) * sd.actualrate) AS HouseIncome,
		   SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
					ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
						 * ABS(sd.stake)
						 * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
			   END) AS HouseTurnover
	FROM bodb02.dbo.bettrans sd (NOLOCK)
		 LEFT JOIN bodb02.dbo.Customer c (NOLOCK) ON sd.custid = c.custid
		 LEFT JOIN bodb02.dbo.Site si (NOLOCK) ON c.site = si.site
		 LEFT JOIN #tmpMatch m ON sd.matchid = m.matchid
								  AND CASE WHEN sd.bettype = 10 THEN 1 ELSE 0 END = m.matchtype
	WHERE sd.winlostdate >= CAST(@fromDate AS SMALLDATETIME) AND sd.winlostdate <= CAST(@toDate AS SMALLDATETIME)
		  AND sd.ruben = 1
		  AND sd.statusID IN (111, 112, 113)
		  AND sd.currency NOT IN (20, 27, 28)
		  AND EXISTS (SELECT TOP 1 1
					  FROM #tmpSportBettypeMatrix sbm
					  WHERE sd.BetType = sbm.BetType)
	GROUP BY CASE WHEN @isShowSite = 0 THEN NULL ELSE si.siteid END,
		     CASE WHEN @isShowSport = 0 THEN NULL ELSE m.SportType END,
			 CASE WHEN @isShowLeague = 0 THEN NULL ELSE m.leagueid END,
		     CASE WHEN @isShowCust = 0 THEN NULL ELSE c.custid END
	OPTION (RECOMPILE)

	-- Drop temp tables
	DROP TABLE #tmpSportBettypeMatrix
	DROP TABLE #tmpMatch

END
GO

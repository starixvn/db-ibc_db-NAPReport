/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceSumBK]   
	@FromDate	DATETIME,  
	@ToDate		DATETIME,  
	@IsSoccer	BIT = 1   
AS

/*
	Creator: Percy
	Date: 2017-03-13
	DB: DBACC.bodb02
	Task: Trader Performance Report - Sum - bettrans_bk

	Revisions:
		@20171229: Adhoc Trader Performance
		20180328@Kean: Apply new concept of Commission to Trader Performance Report (#111015)
		20190709@Kean: Add new Bettype - Total Bookings 15 mins HDP (#116435)
		20191010@Cherry: Apply new table for Trader (#120746)

	Param's Explanation:
		@IsSoccer:
			0: Others
			1: Soccer
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @countMajorOrphan INT, @countMinor1Orphan INT, @countMinor2Orphan INT, @countMinor3Orphan INT, @countOthersOrphan INT
	
	DECLARE @CutoffDay DATETIME = CAST ('20190901' AS DATETIME)
	
	CREATE TABLE #tmpDot_Admin_Assignment_Trader (
			ID INT PRIMARY KEY,
			eventdate DATE,
			matchid INT,
			bettype SMALLINT,
			liveindicator TINYINT,
			Detail_X SMALLINT,
			Detail_Y SMALLINT,
			Detail_Z SMALLINT,
			TraderID INT,
			UpdatedTime DATETIME
		)

	CREATE TABLE #tmpTraderAssignment (
		eventdate DATE,
		matchid INT,
		bettype SMALLINT,
		livestatus TINYINT,
		TraderID INT
	)
	
	CREATE TABLE #tmpBettype (
		typeid INT,
		HasExtraDimXYZ TINYINT
	)
  
	CREATE TABLE #tmpData
	(  
		custid		INT,
		username	VARCHAR(50),
		matchid		INT,
		bettype		SMALLINT,
		OUtype		TINYINT,
		category	VARCHAR(10)
	)

	CREATE TABLE #bettrans
	(
		matchid					INT,
		bettype					SMALLINT,
		stake					MONEY,
		winlost					MONEY,
		comm					MONEY,
		stake_AfterExtraPT		MONEY,
		memberwinlost_ExtraPT	MONEY,
		bet						INT
	)

	CREATE TABLE #ExtraPTSportbook
	(
		superId		INT,
		ExtraPT		MONEY,
		FromDate	DATETIME,
		ToDate		DATETIME
	)

	CREATE TABLE #userMatch
	(  
		custid INT PRIMARY KEY,  
		nMatch INT,  
		Major INT,
		Minor1 INT,
		Minor2 INT,
		Minor3 INT,
		Others INT
	)

	INSERT INTO #ExtraPTSportbook
	SELECT SuperId, SUM(ExtraPT) AS ExtraPT, FromDate, ToDate
	FROM
	(
		SELECT SuperId, ExtraPT, FromDate, ToDate
		FROM bodb02.dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE
			(
				@FromDate BETWEEN FromDate AND ToDate
				OR @ToDate BETWEEN FromDate AND ToDate
			)
			AND ProductId = 1 AND Sporttype = 0 AND SubProduct = ''
	) A
	GROUP BY SuperId, FromDate, ToDate
	
	IF @FromDate >= @CutoffDay
	BEGIN
		INSERT INTO #tmpBettype (typeid, HasExtraDimXYZ)
		SELECT typeid, HasExtraDimXYZ
		FROM DBWH.bodb_Account.dbo.Bettype 
		
		-- Insert data to #tmpDot_Admin_Assignment_Trader
		INSERT INTO #tmpDot_Admin_Assignment_Trader(ID,EventDate,matchid,bettype,liveindicator,Detail_X,Detail_Y,Detail_Z,TraderID,UpdatedTime)
		SELECT t.ID
			   ,m.eventdate
			   ,t.matchid
			   ,t.bettype
			   ,t.liveindicator
			   ,t.Detail_X
			   ,t.Detail_Y
			   ,t.Detail_Z
			   ,t.TraderID
			   ,t.UpdatedTime
		FROM bodb_Archive.dbo.Dot_Admin_Assignment_Trader_bk t (NOLOCK)
			 LEFT JOIN bodb_Archive.dbo.match_bk m (NOLOCK) ON t.matchid = m.matchid 
		WHERE m.eventdate BETWEEN @FromDate AND @ToDate;

		-- Insert data to #tmpFactTraderAssignment - Group1_matchid|bettype|livestatus
		WITH
		CTE_Group1 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 0			
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,liveindicator livestatus,t.TraderID
		FROM CTE_Group1 t
		WHERE t.Rank_ = 1;

		-- Insert data to #tmpFactTraderAssignment - Group2_matchid|bettype|livestatus|Detail_X
		WITH
		CTE_Group2 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 1
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group2 t
		WHERE t.Rank_ = 1;

		-- Insert data to #tmpFactTraderAssignment - Group3_matchid|bettype|livestatus|Detail_X|Detail_Y
		WITH
		CTE_Group3 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X,t.Detail_Y ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 2
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group3 t
		WHERE t.Rank_ = 1;
		
		-- Insert data to #tmpFactTraderAssignment - Group4_matchid|bettype|livestatus|Detail_X|Detail_Y|Detail_Z
		WITH
		CTE_Group4 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X,t.Detail_Y,t.Detail_Z ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 3
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group4 t
		WHERE t.Rank_ = 1;
		
		IF @IsSoccer = 1
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				a.bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
				ELSE 0 END OUType,
				l.category
			FROM #tmpTraderAssignment a 
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.TraderID = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0 bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5 
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
					ELSE 0 END OUType,
				l.category
			FROM #tmpTraderAssignment a 
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid   
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				a.bettype,
				0 AS OUType,
				l.category
			FROM #tmpTraderAssignment a
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.TraderID = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0, 0, l.category
			FROM #tmpTraderAssignment a 
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
	END

	IF @FromDate < @CutoffDay AND @ToDate < @CutoffDay 
	BEGIN
		IF @IsSoccer = 1
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				CASE
					WHEN (a.bettype = 1 OR a.bettype = 5) AND a.operatortype = 1 THEN 1
					WHEN (a.bettype = 1 AND a.operatortype = 2) THEN 7
					WHEN (a.bettype = 2 AND a.operatortype = 1) THEN 3
					WHEN (a.bettype = 2 AND a.operatortype = 2) THEN 8
					WHEN (a.bettype = 3 AND a.operatortype = 1) THEN 5
					WHEN (a.bettype = 3 AND a.operatortype = 2) THEN 15    
				END bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
				ELSE 0 END OUType,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.operatortype < 3

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0 bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5 
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
					ELSE 0 END OUType,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid   
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				CASE
					WHEN (a.bettype = 1 OR a.bettype = 5) AND a.operatortype = 1 THEN 1
					WHEN (a.bettype = 1 AND a.operatortype = 2) THEN 7
					WHEN (a.bettype = 2 AND a.operatortype = 1) THEN 3
					WHEN (a.bettype = 2 AND a.operatortype = 2) THEN 8
					WHEN (a.bettype = 3 AND a.operatortype = 1) THEN 5
					WHEN (a.bettype = 3 AND a.operatortype = 2) THEN 15
					WHEN (a.bettype = 4 AND a.operatortype = 1) THEN 2
					WHEN (a.bettype = 4 AND a.operatortype = 2) THEN 12        
				END,
				0,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.operatortype < 3

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0, 0, l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
	END
	
	IF @FromDate < @CutoffDay AND @ToDate >= @CutoffDay
	BEGIN
		-- FromDate -> CutoffDay-1
		IF @IsSoccer = 1
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				CASE
					WHEN (a.bettype = 1 OR a.bettype = 5) AND a.operatortype = 1 THEN 1
					WHEN (a.bettype = 1 AND a.operatortype = 2) THEN 7
					WHEN (a.bettype = 2 AND a.operatortype = 1) THEN 3
					WHEN (a.bettype = 2 AND a.operatortype = 2) THEN 8
					WHEN (a.bettype = 3 AND a.operatortype = 1) THEN 5
					WHEN (a.bettype = 3 AND a.operatortype = 2) THEN 15    
				END bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
				ELSE 0 END OUType,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate >= @FromDate AND m.eventdate < @CutoffDay
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.operatortype < 3

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0 bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5 
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
					ELSE 0 END OUType,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid   
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate >= @FromDate AND m.eventdate < @CutoffDay
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				CASE
					WHEN (a.bettype = 1 OR a.bettype = 5) AND a.operatortype = 1 THEN 1
					WHEN (a.bettype = 1 AND a.operatortype = 2) THEN 7
					WHEN (a.bettype = 2 AND a.operatortype = 1) THEN 3
					WHEN (a.bettype = 2 AND a.operatortype = 2) THEN 8
					WHEN (a.bettype = 3 AND a.operatortype = 1) THEN 5
					WHEN (a.bettype = 3 AND a.operatortype = 2) THEN 15
					WHEN (a.bettype = 4 AND a.operatortype = 1) THEN 2
					WHEN (a.bettype = 4 AND a.operatortype = 2) THEN 12        
				END,
				0,
				l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate >= @FromDate AND m.eventdate < @CutoffDay
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.operatortype < 3

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0, 0, l.category
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate >= @FromDate AND m.eventdate < @CutoffDay
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
		
		-- CutoffDay -> ToDate
		INSERT INTO #tmpBettype (typeid, HasExtraDimXYZ)
		SELECT typeid, HasExtraDimXYZ
		FROM DBWH.bodb_Account.dbo.Bettype 
		
		-- Insert data to #tmpDot_Admin_Assignment_Trader
		INSERT INTO #tmpDot_Admin_Assignment_Trader(ID,EventDate,matchid,bettype,liveindicator,Detail_X,Detail_Y,Detail_Z,TraderID,UpdatedTime)
		SELECT t.ID
			   ,m.eventdate
			   ,t.matchid
			   ,t.bettype
			   ,t.liveindicator
			   ,t.Detail_X
			   ,t.Detail_Y
			   ,t.Detail_Z
			   ,t.TraderID
			   ,t.UpdatedTime
		FROM bodb_Archive.dbo.Dot_Admin_Assignment_Trader_bk t (NOLOCK)
			 LEFT JOIN bodb_Archive.dbo.match_bk m (NOLOCK) ON t.matchid = m.matchid 
		WHERE m.eventdate BETWEEN @CutoffDay AND @ToDate;

		-- Insert data to #tmpFactTraderAssignment - Group1_matchid|bettype|livestatus
		WITH
		CTE_Group1 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 0			
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,liveindicator livestatus,t.TraderID
		FROM CTE_Group1 t
		WHERE t.Rank_ = 1;

		-- Insert data to #tmpFactTraderAssignment - Group2_matchid|bettype|livestatus|Detail_X
		WITH
		CTE_Group2 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 1
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group2 t
		WHERE t.Rank_ = 1;

		-- Insert data to #tmpFactTraderAssignment - Group3_matchid|bettype|livestatus|Detail_X|Detail_Y
		WITH
		CTE_Group3 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X,t.Detail_Y ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 2
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group3 t
		WHERE t.Rank_ = 1;
		
		-- Insert data to #tmpFactTraderAssignment - Group4_matchid|bettype|livestatus|Detail_X|Detail_Y|Detail_Z
		WITH
		CTE_Group4 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator,t.Detail_X,t.Detail_Y,t.Detail_Z ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)
				 INNER JOIN #tmpBettype b ON t.bettype = b.typeid and b.HasExtraDimXYZ = 3
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,livestatus,TraderID)
		SELECT t.eventdate,t.matchid,t.bettype,t.liveindicator livestatus,t.TraderID
		FROM CTE_Group4 t
		WHERE t.Rank_ = 1;
		
		IF @IsSoccer = 1
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				a.bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
				ELSE 0 END OUType,
				l.category
			FROM #tmpTraderAssignment a 
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.TraderID = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @CutoffDay AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0 bettype,
				CASE
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
					WHEN t.teamname LIKE '%No.of Corners%' THEN 1
					WHEN t.teamname LIKE '%Total Bookings' THEN 3
					WHEN t.teamname LIKE '%Booking' THEN 5 
					WHEN t.teamname LIKE '%Corner%' THEN 4
					WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
					WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
					WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
					WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
					ELSE 0 END OUType,
				l.category
			FROM #tmpTraderAssignment a 
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid   
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @CutoffDay AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype = 1
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData
			SELECT DISTINCT a.operatorid, username, m.matchID,  
				a.bettype,
				0 AS OUType,
				l.category
			FROM #tmpTraderAssignment a
				INNER JOIN dbo.customer c WITH (NOLOCK) ON a.TraderID = c.custid
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			WHERE  
				m.eventdate BETWEEN @CutoffDay AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'

			INSERT INTO #tmpData
			SELECT NULL, NULL, m.matchID, 0, 0, l.category
			FROM #tmpTraderAssignment a 
				RIGHT JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
				INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
			WHERE  
				m.eventdate BETWEEN @CutoffDay AND @ToDate
				AND m.eventstatus = 'completed'
				AND m.sporttype NOT IN (1, 161)
				AND m.matchcode NOT LIKE '%hedge%'
				AND a.matchid IS NULL
		END
	END
	
	INSERT INTO #tmpData (custid, username, matchid, bettype, OUtype, category)
	SELECT DISTINCT custid, username, matchid, 124 bettype, OUtype, category
	FROM #tmpData
	WHERE bettype = 5
	
	INSERT INTO #tmpData (custid, username, matchid, bettype, OUtype, category)
	SELECT DISTINCT custid, username, matchid, 125 bettype, OUtype, category
	FROM #tmpData
	WHERE bettype = 15
	
	INSERT INTO #bettrans
	SELECT
		matchid,
		bettype,
		SUM(CASE 
				WHEN bettype IN (5, 15) THEN ABS(stake) * (1 - tpositiontaking) * virtualrate
				WHEN bettype IN (1, 2, 3, 7, 8, 12, 124, 125)
					THEN (CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking) * virtualrate
				ELSE 0 END) AS stake,
		-SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate
				+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) AS winlost,
		SUM(scomm * CASE
                                      WHEN b.virtualrate < b.actualrate
                                      THEN b.virtualrate
                                      ELSE b.actualrate
                                  END) AS comm,
		SUM(CASE 
				WHEN bettype IN (5, 15) THEN ABS(stake) * (CASE WHEN tpositiontaking = 1 THEN 0 ELSE 1 - tpositiontaking - ISNULL(ExtraPT, 0) END) * virtualrate 
				WHEN bettype IN (1, 2, 3, 7, 8, 12, 124, 125)
					THEN (CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (CASE WHEN tpositiontaking = 1 THEN 0 ELSE 1 - tpositiontaking - ISNULL(ExtraPT, 0) END) * virtualrate
				ELSE 0 END) AS stake_AfterExtraPT,
		-SUM(CASE WHEN tpositiontaking = 1 THEN 0 ELSE ((winlost - actual_stake) * virtualrate 
														+ CASE WHEN tpositiontaking = 1 THEN 0 
														ELSE (scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END)/(1 - tpositiontaking) 
														END) * ISNULL(e.ExtraPT, 0) END) AS memberwinlost_ExtraPT,
		SUM(CASE WHEN td.[VendorID] IN (14) THEN 0 
				   ELSE 1 END) AS bet
	FROM bodb_Archive.dbo.bettrans_bk b WITH (NOLOCK)
		LEFT JOIN #ExtraPTSportbook e ON b.srecommend = e.superId AND b.winlostdate BETWEEN e.FromDate AND e.ToDate
		LEFT JOIN dbo.TradeCust AS td WITH (NOLOCK) ON b.custid = td.custid 
	WHERE
		statusID NOT IN (101, 102, 103, 121, 111)
		AND ruben = 1
		AND ((@IsSoccer = 1 AND bettype IN (1, 3, 7, 8, 5, 15, 124, 125)
				AND EXISTS(SELECT 1 FROM bodb_Archive.dbo.match_bk m WHERE m.matchid = b.matchid AND m.sporttype = 1))
			OR (@IsSoccer = 0 AND bettype IN (1, 3, 7, 8, 5, 15, 2, 12, 124, 125)
				AND EXISTS(SELECT 1 FROM bodb_Archive.dbo.match_bk m WHERE m.matchid = b.matchid AND m.sporttype NOT IN (1, 161)))
			)
		AND winlostdate BETWEEN @FromDate AND @ToDate
		AND liveindicator = 1
		AND currency <> 20
	GROUP BY matchid, bettype

	INSERT INTO #tmpData (custid, username, matchid, bettype, OUtype, category)
	SELECT DISTINCT NULL, NULL, m.matchID, a.bettype,
		CASE
			WHEN leaguename LIKE '%SPECIFIC 15 MINS%' AND t.teamname LIKE '%No.of Corners%' THEN 6
			WHEN t.teamname LIKE '%No.of Corners%' THEN 1
			WHEN t.teamname LIKE '%Total Bookings' THEN 3
			WHEN t.teamname LIKE '%Booking' THEN 5 
			WHEN t.teamname LIKE '%Corner%' THEN 4
			WHEN leaguename LIKE '%SPECIFIC 15 MINS TOTAL BOOKINGS%' THEN 7
			WHEN leaguename LIKE '%SPECIFIC 15 MINS%' THEN 2
			WHEN leaguename LIKE '%SPECIFIC 10 MINS%' THEN 8
			WHEN leaguename LIKE '%SINGLE TEAM OVER/UNDER%' AND (t.teamname LIKE '%Over' OR t.teamname LIKE '%Under') THEN 9
			ELSE 0 END,
		l.category
	FROM #bettrans a WITH (NOLOCK)
		LEFT JOIN #tmpData d ON a.matchid = d.matchid AND (a.bettype = d.bettype OR d.bettype = 0)
		INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid  
		LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid   
		INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid  
	WHERE  
		m.eventdate BETWEEN @FromDate AND @ToDate
		AND m.eventstatus = 'completed'
		AND ((@IsSoccer = 1 AND m.sporttype = 1)
			OR (@IsSoccer = 0 AND m.sporttype NOT IN (1, 161)))
		AND m.matchcode NOT LIKE '%hedge%'
		AND d.bettype IS NULL

	INSERT INTO #userMatch (custid, nMatch, Major, Minor1, Minor2, Minor3, Others) 
	SELECT
		ISNULL(custid,0),
		ISNULL(Major, 0) + ISNULL(Minor1, 0) + ISNULL(Minor2, 0) + ISNULL(Minor3, 0) + ISNULL(Others, 0) AS nMatch,
		ISNULL(Major, 0), ISNULL(Minor1, 0), ISNULL(Minor2, 0), ISNULL(Minor3, 0) ,ISNULL(Others, 0)
	FROM
	(
		SELECT t.custid, ISNULL(t.category, 'Others') AS category, COUNT(DISTINCT t.matchID) AS cntMatch
		FROM #tmpData t  
			INNER JOIN #bettrans b WITH (NOLOCK) ON b.matchid = t.matchid AND b.bettype = t.bettype AND t.custid IS NOT NULL
		GROUP BY t.custid, ISNULL(t.category,'Others')
	) AS s
	PIVOT
	(
		SUM(s.cntMatch) FOR category IN (Major, Minor1, Minor2, Minor3, Others)
	) p
	
	;WITH CTE AS
	(  
		SELECT ISNULL(t.category, 'Others') AS category, COUNT(DISTINCT t.matchID) AS countOrphan
		FROM #tmpData t
			INNER JOIN #bettrans b ON b.matchid = t.matchid AND t.custid IS NULL
		GROUP BY ISNULL(t.category, 'Others')
	)
	SELECT
		@countMajorOrphan = ISNULL(@countMajorOrphan, 0) + ISNULL(SUM(CASE WHEN category = 'Major' THEN countOrphan ELSE 0 END), 0),
		@countMinor1Orphan = ISNULL(@countMinor1Orphan, 0) + ISNULL(SUM(CASE WHEN category = 'Minor1' THEN countOrphan ELSE 0 END), 0),
		@countMinor2Orphan = ISNULL(@countMinor2Orphan, 0) + ISNULL(SUM(CASE WHEN category = 'Minor2' THEN countOrphan ELSE 0 END), 0),
		@countMinor3Orphan = ISNULL(@countMinor3Orphan, 0) + ISNULL(SUM(CASE WHEN category = 'Minor3' THEN countOrphan ELSE 0 END), 0),
		@countOthersOrphan = ISNULL(@countOthersOrphan, 0) + ISNULL(SUM(CASE WHEN category = 'Others' THEN countOrphan ELSE 0 END), 0)
	FROM CTE
	
	-- Return Data
	SELECT  
		custid, username, matchno, Major, Minor1, Minor2, Minor3, Others,
		-- turnover
		stake_hdp, stake_ou, stake_1sthdp, stake_1stou, stake_1x2, stake_1st1x2, stake_oe, stake_1stoe, stake_1stNoOfCorners, stake_NoOfCorners, stake_15minhdp, stake_15minOU, stake_15min1x2, stake_1stTotalBookings,stake_TotalBookings,stake_NextCorner,  
		stake_NextBooking, stake_15minCorners, stake_15minTotalBookings, stake_15minTotalBookingsHdp, stake_10minHdp, stake_10minOU, stake_10min1x2, stake_SingleTeamOU,
		-- winloss
		winlost_hdp, winlost_ou, winlost_1sthdp, winlost_1stou, winlost_1x2, winlost_1st1x2, winlost_oe, winlost_1stoe, winlost_1stNoOfCorners, winlost_NoOfCorners, winlost_15minhdp, winlost_15minOU, winlost_15min1x2,
		winlost_1stTotalBookings, winlost_TotalBookings, winlost_NextCorner, winlost_NextBooking, winlost_15minCorners, winlost_15minTotalBookings, winlost_15minTotalBookingsHdp, winlost_10minHdp, winlost_10minOU, winlost_10min1x2, winlost_SingleTeamOU,
		-- commission
		comm_hdp, comm_ou, comm_1sthdp, comm_1stou, comm_1x2, comm_1st1x2, comm_oe, comm_1stoe, comm_1stNoOfCorners,comm_NoOfCorners, comm_15minhdp, comm_15minOU, comm_15min1x2, comm_1stTotalBookings,comm_TotalBookings,comm_NextCorner,  
		comm_NextBooking, comm_15minCorners, comm_15minTotalBookings, comm_15minTotalBookingsHdp, comm_10minHdp, comm_10minOU, comm_10min1x2, comm_SingleTeamOU,
		
		stake_1sthdp + stake_hdp + stake_1stou + stake_ou + stake_1x2 + stake_1st1x2 + stake_oe + stake_1stoe + stake_1stNoOfCorners + stake_NoOfCorners + stake_15minhdp + stake_15minOU + stake_15min1x2 + stake_1stTotalBookings + stake_TotalBookings+ stake_NextCorner 
		+ stake_NextBooking + stake_15minCorners + stake_15minTotalBookings + stake_15minTotalBookingsHdp + stake_10minHdp + stake_10minOU + stake_10min1x2 + stake_SingleTeamOU AS overall_st,  
   
		winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou +  winlost_1x2 + winlost_1st1x2 + winlost_oe + winlost_1stoe + winlost_1stNoOfCorners +winlost_NoOfCorners + winlost_15minhdp + winlost_15minOU + winlost_15min1x2 + winlost_1stTotalBookings + winlost_TotalBookings+ winlost_NextCorner
		+ winlost_NextBooking + winlost_15minCorners + winlost_15minTotalBookings + winlost_15minTotalBookingsHdp + winlost_10minHdp + winlost_10minOU + winlost_10min1x2 + winlost_SingleTeamOU AS overall_wl,  
     
		comm_1sthdp + comm_hdp + comm_1stou + comm_ou + comm_1x2 + comm_1st1x2 + comm_oe + comm_1stoe + comm_1stNoOfCorners +comm_NoOfCorners + comm_15minhdp + comm_15minOU + comm_15min1x2 + comm_1stTotalBookings + comm_TotalBookings + comm_NextCorner
		+ comm_NextBooking + comm_15minCorners + comm_15minTotalBookings + comm_15minTotalBookingsHdp + comm_10minHdp + comm_10minOU + comm_10min1x2 + comm_SingleTeamOU AS overall_com,  
   
		CASE WHEN ISNULL(ROUND(stake_1sthdp,4),0) = 0 THEN 0 ELSE winlost_1sthdp/stake_1sthdp END AS margin_1sthdp,  
		CASE WHEN ISNULL(ROUND(stake_hdp,4),0) = 0 THEN 0 ELSE winlost_hdp/stake_hdp END AS margin_hdp,  
		CASE WHEN ISNULL(ROUND(stake_1stou,4),0) = 0 THEN 0 ELSE winlost_1stou/stake_1stou END AS margin_1stou,  
		CASE WHEN ISNULL(ROUND(stake_ou,4),0) = 0 THEN 0 ELSE winlost_ou/stake_ou END AS margin_ou,  
		CASE WHEN ISNULL(ROUND(stake_1x2,4),0) = 0 THEN 0 ELSE winlost_1x2/stake_1x2 END AS margin_1x2,  
		CASE WHEN ISNULL(ROUND(stake_1st1x2,4),0) = 0 THEN 0 ELSE winlost_1st1x2/stake_1st1x2 END AS margin_1st1x2,  
		CASE WHEN ISNULL(ROUND(stake_oe,4),0) = 0 THEN 0 ELSE winlost_oe/stake_oe END AS margin_oe,  
		CASE WHEN ISNULL(ROUND(stake_1stoe,4),0) = 0 THEN 0 ELSE winlost_1stoe/stake_1stoe END AS margin_1stoe,  
		CASE WHEN ISNULL(ROUND(stake_1stNoOfCorners,4),0) = 0 THEN 0 ELSE winlost_1stNoOfCorners/stake_1stNoOfCorners END AS margin_1stNoOfCorners,  
		CASE WHEN ISNULL(ROUND(stake_NoOfCorners,4),0) = 0 THEN 0 ELSE winlost_NoOfCorners/stake_NoOfCorners END AS margin_NoOfCorners,  
		CASE WHEN ISNULL(ROUND(stake_15minhdp,4),0) = 0 THEN 0 ELSE winlost_15minhdp/stake_15minhdp END AS margin_15minhdp,  
		CASE WHEN ISNULL(ROUND(stake_15minOU,4),0) = 0 THEN 0 ELSE winlost_15minOU/stake_15minOU END AS margin_15minOU,  
		CASE WHEN ISNULL(ROUND(stake_15min1x2,4),0) = 0 THEN 0 ELSE winlost_15min1x2/stake_15min1x2 END AS margin_15min1x2,  
		CASE WHEN ISNULL(ROUND(stake_1stTotalBookings,4),0) = 0 THEN 0 ELSE winlost_1stTotalBookings/stake_1stTotalBookings END AS margin_1stTotalBookings,  
		CASE WHEN ISNULL(ROUND(stake_TotalBookings,4),0) = 0 THEN 0 ELSE winlost_TotalBookings/stake_TotalBookings END AS margin_TotalBookings,  
		CASE WHEN ISNULL(ROUND(stake_NextCorner,4),0) = 0 THEN 0 ELSE winlost_NextCorner/stake_NextCorner END AS margin_NextCorner,  
		CASE WHEN ISNULL(ROUND(stake_NextBooking,4),0) = 0 THEN 0 ELSE winlost_NextBooking/stake_NextBooking END AS margin_NextBooking,  
		CASE WHEN ISNULL(ROUND(stake_15minCorners,4),0) = 0 THEN 0 ELSE winlost_15minCorners/stake_15minCorners END AS margin_15minCorners, 
		CASE WHEN ISNULL(ROUND(stake_15minTotalBookings,4),0) = 0 THEN 0 ELSE winlost_15minTotalBookings/stake_15minTotalBookings END AS margin_15minTotalBookings,
		CASE WHEN ISNULL(ROUND(stake_15minTotalBookingsHdp,4),0) = 0 THEN 0 ELSE winlost_15minTotalBookingsHdp/stake_15minTotalBookingsHdp END AS margin_15minTotalBookingsHdp,  
		CASE WHEN ISNULL(ROUND(stake_10minHdp,4),0) = 0 THEN 0 ELSE winlost_10minHdp/stake_10minHdp END AS margin_10minHdp,
		CASE WHEN ISNULL(ROUND(stake_10minOU,4),0) = 0 THEN 0 ELSE winlost_10minOU/stake_10minOU END AS margin_10minOU,
		CASE WHEN ISNULL(ROUND(stake_10min1x2,4),0) = 0 THEN 0 ELSE winlost_10min1x2/stake_10min1x2 END AS margin_10min1x2,
		CASE WHEN ISNULL(ROUND(stake_SingleTeamOU,4),0) = 0 THEN 0 ELSE winlost_SingleTeamOU/stake_SingleTeamOU END AS margin_SingleTeamOU,
		CASE WHEN ROUND((ISNULL(stake_1sthdp,0) + ISNULL(stake_hdp,0) + ISNULL(stake_1stou,0) + ISNULL(stake_ou,0) + ISNULL(stake_1x2,0) + ISNULL(stake_1st1x2,0) + ISNULL(stake_oe,0) + ISNULL(stake_1stoe,0) + ISNULL(stake_1stNoOfCorners,0) + ISNULL(stake_NoOfCorners,0) + ISNULL(stake_15minhdp,0) + ISNULL(stake_15minOU,0) + ISNULL(stake_15min1x2,0) + ISNULL(stake_1stTotalBookings,0) + ISNULL(stake_TotalBookings,0)+ ISNULL(stake_NextCorner,0)
										+ ISNULL(stake_NextBooking,0) + ISNULL(stake_15minCorners,0) + ISNULL(stake_15minTotalBookings,0) + ISNULL(stake_15minTotalBookingsHdp,0) + ISNULL(stake_10minHdp,0) + ISNULL(stake_10minOU,0) + ISNULL(stake_10min1x2,0) + ISNULL(stake_SingleTeamOU,0)),4) = 0 THEN 0   
		ELSE (winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou + winlost_1x2 + winlost_1st1x2 + winlost_oe + winlost_1stoe + winlost_1stNoOfCorners + winlost_NoOfCorners + winlost_15minhdp + winlost_15minOU + winlost_15min1x2 + winlost_1stTotalBookings + winlost_TotalBookings + winlost_NextCorner) 
		/((ISNULL(stake_1sthdp,0) + ISNULL(stake_hdp,0) + ISNULL(stake_1stou,0) +ISNULL(stake_ou,0) + ISNULL(stake_1x2,0) + ISNULL(stake_1st1x2,0) + ISNULL(stake_oe,0)+ ISNULL(stake_1stoe,0)+ ISNULL(stake_1stNoOfCorners,0) +ISNULL(stake_NoOfCorners,0)+ ISNULL(stake_15minhdp,0) + ISNULL(stake_15minOU,0) + ISNULL(stake_15min1x2,0)  + ISNULL(stake_1stTotalBookings,0) + ISNULL(stake_TotalBookings,0) + ISNULL(stake_NextCorner,0) 
										+ ISNULL(stake_NextBooking,0) + ISNULL(stake_15minCorners,0) + ISNULL(stake_15minTotalBookings,0) + ISNULL(stake_15minTotalBookingsHdp,0) + ISNULL(stake_10minHdp,0) + ISNULL(stake_10minOU,0) + ISNULL(stake_10min1x2,0) + ISNULL(stake_SingleTeamOU,0))) END AS overall_margin ,  
     
		bet_hdp, bet_ou, bet_1sthdp, bet_1stou, bet_1x2, bet_1st1x2, bet_oe, bet_1stoe, bet_1stNoOfCorners, bet_NoOfCorners, bet_15minhdp, bet_15minOU, bet_15min1x2, bet_1stTotalBookings, bet_TotalBookings, bet_NextCorner,
		bet_NextBooking, bet_15minCorners, bet_15minTotalBookings, bet_15minTotalBookingsHdp, bet_10minHdp, bet_10minOU, bet_10min1x2, bet_SingleTeamOU,  
		bet_hdp + bet_ou + bet_1x2 + bet_oe + bet_1sthdp + bet_1stou + bet_1st1x2 + bet_1stoe +  bet_NoOfCorners + bet_1stNoOfCorners + bet_15minhdp + bet_15minOU + bet_15min1x2 + bet_1stTotalBookings + bet_TotalBookings + bet_NextCorner 
		+ bet_NextBooking + bet_15minCorners + bet_15minTotalBookings + bet_15minTotalBookingsHdp + bet_10minHdp + bet_10minOU + bet_10min1x2 + bet_SingleTeamOU AS overall_livebet  
	FROM
	(
		SELECT t.custid, t.username, nMatch AS matchno, Major, Minor1, Minor2, Minor3, Others,
			-- turn over
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_hdp,
			SUM(CASE WHEN b.bettype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_oe,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_ou,
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1x2,
			SUM(CASE WHEN b.bettype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1sthdp,
			SUM(CASE WHEN b.bettype = 12 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stoe,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stou,
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1st1x2,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stNoOfCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15min1x2,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stTotalBookings,        
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3 THEN stake_AfterExtraPT ELSE 0 END) AS stake_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NextBooking,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN stake_AfterExtraPT ELSE 0 END) AS stake_SingleTeamOU,
			-- winloss
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_oe,  
			SUM(CASE WHEN b.bettype = 3  AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_ou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1x2,  
			SUM(CASE WHEN b.bettype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stou,  
			SUM(CASE WHEN b.bettype = 12 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NextCorner,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NextBooking,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minTotalBookingsHdp,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10minHdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10min1x2,  
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_SingleTeamOU,
			-- commission  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN comm ELSE 0 END) AS comm_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN comm ELSE 0 END) AS comm_oe,  
			SUM(CASE WHEN b.bettype = 3  AND OUtype = 0 THEN comm ELSE 0 END) AS comm_ou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1x2,  
			SUM(CASE WHEN b.bettype = 7 THEN comm ELSE 0 END) AS comm_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1stou,  
			SUM(CASE WHEN b.bettype = 12 THEN comm ELSE 0 END) AS comm_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1  THEN comm ELSE 0 END) AS comm_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1  THEN comm ELSE 0 END) AS comm_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN comm ELSE 0 END) AS comm_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3  THEN comm ELSE 0 END) AS comm_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4  THEN comm ELSE 0 END) AS comm_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5  THEN comm ELSE 0 END) AS comm_NextBooking,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6  THEN comm ELSE 0 END) AS comm_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7  THEN comm ELSE 0 END) AS comm_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7  THEN comm ELSE 0 END) AS comm_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN comm ELSE 0 END) AS comm_SingleTeamOU,
			-- betcount      
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN bet ELSE 0 END) AS bet_oe,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_ou,  
			SUM(CASE WHEN b.bettype = 7 THEN bet ELSE 0 END) AS bet_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1stou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1x2,  
			SUM(CASE WHEN b.bettype = 12 THEN bet ELSE 0 END) AS bet_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN bet ELSE 0 END) AS bet_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 1 THEN bet ELSE 0 END) AS bet_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUType = 3 THEN bet ELSE 0 END) AS bet_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 3 THEN bet ELSE 0 END) AS bet_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN bet ELSE 0 END) AS bet_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN bet ELSE 0 END) AS bet_NextBooking,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN bet ELSE 0 END) AS bet_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN bet ELSE 0 END) AS bet_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN bet ELSE 0 END) AS bet_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN bet ELSE 0 END) AS bet_SingleTeamOU
		FROM #bettrans b
			INNER JOIN #tmpData t ON b.matchid = t.matchid AND b.bettype = t.bettype AND t.custid IS NOT NULL	
			INNER JOIN #userMatch um ON um.custid = t.custid
		GROUP BY t.custid, t.username, um.nMatch, Major, Minor1, Minor2, Minor3, Others
		
		UNION ALL  
		SELECT 0, '(unassigned)', ISNULL(@countMajorOrphan, 0) + ISNULL(@countMinor1Orphan, 0) + ISNULL(@countMinor2Orphan, 0) + ISNULL(@countMinor3Orphan, 0) + ISNULL(@countOthersOrphan, 0) AS matchno, ISNULL(@countMajorOrphan, 0) Major, ISNULL(@countMinor1Orphan, 0), ISNULL(@countMinor2Orphan, 0), ISNULL(@countMinor3Orphan, 0), ISNULL(@countOthersOrphan, 0),
			-- turn over
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_hdp,
			SUM(CASE WHEN b.bettype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_oe,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_ou,
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1x2,
			SUM(CASE WHEN b.bettype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1sthdp,
			SUM(CASE WHEN b.bettype = 12 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stoe,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stou,
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1st1x2,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stNoOfCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15min1x2,
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN stake_AfterExtraPT ELSE 0 END) AS stake_1stTotalBookings,        
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3 THEN stake_AfterExtraPT ELSE 0 END) AS stake_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN stake_AfterExtraPT ELSE 0 END) AS stake_NextBooking,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN stake_AfterExtraPT ELSE 0 END) AS stake_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN stake_AfterExtraPT ELSE 0 END) AS stake_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN stake_AfterExtraPT ELSE 0 END) AS stake_SingleTeamOU,
			-- winloss
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_oe,  
			SUM(CASE WHEN b.bettype = 3  AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_ou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1x2,  
			SUM(CASE WHEN b.bettype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stou,  
			SUM(CASE WHEN b.bettype = 12 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NextCorner,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_NextBooking,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_15minTotalBookingsHdp,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10minHdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_10min1x2,  
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN winlost - memberwinlost_ExtraPT ELSE 0 END) AS winlost_SingleTeamOU,
			-- commission  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN comm ELSE 0 END) AS comm_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN comm ELSE 0 END) AS comm_oe,  
			SUM(CASE WHEN b.bettype = 3  AND OUtype = 0 THEN comm ELSE 0 END) AS comm_ou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1x2,  
			SUM(CASE WHEN b.bettype = 7 THEN comm ELSE 0 END) AS comm_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1stou,  
			SUM(CASE WHEN b.bettype = 12 THEN comm ELSE 0 END) AS comm_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN comm ELSE 0 END) AS comm_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1  THEN comm ELSE 0 END) AS comm_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 1  THEN comm ELSE 0 END) AS comm_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 2 THEN comm ELSE 0 END) AS comm_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 3 THEN comm ELSE 0 END) AS comm_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 3  THEN comm ELSE 0 END) AS comm_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4  THEN comm ELSE 0 END) AS comm_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5  THEN comm ELSE 0 END) AS comm_NextBooking,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6  THEN comm ELSE 0 END) AS comm_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7  THEN comm ELSE 0 END) AS comm_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7  THEN comm ELSE 0 END) AS comm_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8  THEN comm ELSE 0 END) AS comm_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN comm ELSE 0 END) AS comm_SingleTeamOU,
			-- betcount      
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_hdp,  
			SUM(CASE WHEN b.bettype = 2 THEN bet ELSE 0 END) AS bet_oe,  
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_ou,  
			SUM(CASE WHEN b.bettype = 7 THEN bet ELSE 0 END) AS bet_1sthdp,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1stou,  
			SUM(CASE WHEN b.bettype IN (5, 124) AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1x2,  
			SUM(CASE WHEN b.bettype = 12 THEN bet ELSE 0 END) AS bet_1stoe,  
			SUM(CASE WHEN b.bettype IN (15, 125) AND OUtype = 0 THEN bet ELSE 0 END) AS bet_1st1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUtype = 1 THEN bet ELSE 0 END) AS bet_1stNoOfCorners,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 1 THEN bet ELSE 0 END) AS bet_NoOfCorners,  
			SUM(CASE WHEN b.bettype = 1 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15minhdp,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15minOU,  
			SUM(CASE WHEN b.bettype = 5 AND OUType = 2 THEN bet ELSE 0 END) AS bet_15min1x2,  
			SUM(CASE WHEN b.bettype = 8 AND OUType = 3 THEN bet ELSE 0 END) AS bet_1stTotalBookings,  
			SUM(CASE WHEN b.bettype = 3 AND OUType = 3 THEN bet ELSE 0 END) AS bet_TotalBookings,  
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 4 THEN bet ELSE 0 END) AS bet_NextCorner,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 5 THEN bet ELSE 0 END) AS bet_NextBooking,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 6 THEN bet ELSE 0 END) AS bet_15minCorners,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 7 THEN bet ELSE 0 END) AS bet_15minTotalBookings,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 7 THEN bet ELSE 0 END) AS bet_15minTotalBookingsHdp,
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN bet ELSE 0 END) AS bet_SingleTeamOU
		FROM #bettrans b      
			INNER JOIN #tmpData t ON b.matchid = t.matchid AND (b.bettype = t.bettype OR t.bettype = 0) AND t.custid IS NULL		 
	) AS A
	ORDER BY username
    
	DROP TABLE #bettrans
	DROP TABLE #tmpData
	DROP TABLE #userMatch
	DROP TABLE #ExtraPTSportbook
	DROP TABLE #tmpDot_Admin_Assignment_Trader
	DROP TABLE #tmpTraderAssignment
	DROP TABLE #tmpBettype
END

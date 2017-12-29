USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceDetail_14]   
	@FromDate	DATETIME,  
	@ToDate		DATETIME,  
	@IsSoccer	BIT = 1   
AS

/*
	Creator: Percy
	Date: 2017-03-13
	DB: DBACC.bodb02
	Task: Trader Performance Report - Detail - bettrans14

	Revisions:

	Param's Explanation:
		@IsSoccer:
			0: Others
			1: Soccer
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #tmpData
	(  
		custid		INT,
		username	VARCHAR(50),
		leagueid	INT,
		matchid		INT,
		homeid		INT,
		awayid		INT,
		eventdate	DATETIME,
		hthomescore	INT,
		htawayscore	INT,
		fthomescore	INT,
		ftawayscore	INT,
		bettype		SMALLINT,
		IsNeutral	BIT,
		OUtype		TINYINT
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

	DECLARE @temp_maxbet TABLE
	(
		matchid INT,
		custid	INT,
		maxbet	MONEY
	) 

	DECLARE @bettype TABLE
	(
		bettype		INT,
		priority	INT
	)

	INSERT INTO @bettype 
			SELECT 	1, 1
	UNION SELECT 	7, 2
	UNION SELECT 	3, 3
	UNION SELECT 	8, 4
	UNION SELECT 	5, 5
	UNION SELECT 	15, 6
	UNION SELECT 	2, 7
	UNION SELECT 	12, 8

	INSERT INTO #ExtraPTSportbook
	SELECT SuperId, SUM(ExtraPT) AS ExtraPT, FromDate, ToDate
	FROM
	(
		SELECT DISTINCT SuperId, ExtraPT, FromDate, ToDate
		FROM bodb_ACC.dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE
			(
				@FromDate BETWEEN FromDate AND ToDate
				OR @ToDate BETWEEN FromDate AND ToDate
			)
			AND ProductId = 1 AND Sporttype = 0 AND SubProduct = ''
	) A
	GROUP BY SuperId, FromDate, ToDate

	IF @IsSoccer = 1
	BEGIN
		INSERT INTO #tmpData
		SELECT DISTINCT
			c.custid,
			c.username,
			m.leagueid,
			m.matchid,
			m.homeid,
			m.awayid,
			m.eventdate,
			m.hthomescore,
			m.htawayscore,
			m.finalhomescore,
			m.finalawayscore,
			CASE 
				WHEN (operatortype = 1) AND (bettype = 1 OR bettype = 5) THEN 1
				WHEN operatortype = 1 AND bettype = 4 THEN 2
				WHEN operatortype = 1 AND bettype = 2 THEN 3
				WHEN operatortype = 1 AND bettype = 3 THEN 5
				WHEN operatortype = 2 AND bettype = 1 THEN 7
				WHEN operatortype = 2 AND bettype = 2 THEN 8
				WHEN operatortype = 2 AND bettype = 4 THEN 12
				WHEN operatortype = 2 AND bettype = 3 THEN 15
				ELSE 0 END bettype,
			m.isNeutral,
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
				ELSE 0 END
		FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
			INNER JOIN dbo.match14 m WITH (NOLOCK) ON a.matchid = m.matchid
			LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
			INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
			INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE
			m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'
			AND m.sporttype = 1
			AND a.operatortype < 3
			AND m.matchcode NOT LIKE '%hedge%'

		INSERT INTO #tmpData
		SELECT
			NULL,
			NULL,
			m.leagueid,
			m.matchid,
			m.homeid,
			m.awayid,
			m.eventdate,
			m.hthomescore,
			m.htawayscore,
			m.finalhomescore,
			m.finalawayscore,
			0,
			m.isNeutral,
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
				ELSE 0 END
		FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
			RIGHT JOIN dbo.match14 m WITH (NOLOCK) ON a.matchid = m.matchid
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
		SELECT DISTINCT
			c.custid,
			c.username,
			m.leagueid,
			m.matchid,
			m.homeid,
			m.awayid,
			m.eventdate,
			m.hthomescore,
			m.htawayscore,
			m.finalhomescore,
			m.finalawayscore,
			CASE 
				WHEN operatortype = 1 AND (bettype = 1 OR bettype = 5) THEN 1
				WHEN operatortype = 1 AND bettype = 4 THEN 2
				WHEN operatortype = 1 AND bettype = 2 THEN 3
				WHEN operatortype = 1 AND bettype = 3 THEN 5
				WHEN operatortype = 2 AND bettype = 1 THEN 7
				WHEN operatortype = 2 AND bettype = 2 THEN 8
				WHEN operatortype = 2 AND bettype = 4 THEN 12
				WHEN operatortype = 2 AND bettype = 3 THEN 15
				ELSE 0 END bettype
			,m.isNeutral
			,0
		FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
			INNER JOIN dbo.match14 m WITH (NOLOCK) ON a.matchid = m.matchid
			INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
			INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE
			m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'
			AND m.sporttype NOT IN (1, 161) -- exclude number game  
			AND a.operatortype < 3
			AND m.matchcode NOT LIKE '%hedge%'

		INSERT INTO #tmpData
		SELECT
			NULL,
			NULL,
			m.leagueid,
			m.matchid,
			m.homeid,
			m.awayid,
			m.eventdate,
			m.hthomescore,
			m.htawayscore,
			m.finalhomescore,
			m.finalawayscore,
			0,
			m.isNeutral,
			0
		FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
			RIGHT JOIN dbo.match14 m WITH (NOLOCK) ON a.matchid = m.matchid
			INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE
			m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'
			AND m.sporttype NOT IN (1, 161)
			AND m.matchcode NOT LIKE '%hedge%'
			AND a.matchid IS NULL
	END

	INSERT INTO @temp_maxbet(matchid, custid, maxbet)
	SELECT t.matchid, t.custid, MAX(maxbet)
	FROM dbo.MatchMaxbet14 m WITH(NOLOCK)
		INNER JOIN (
			SELECT matchid, t.custid, MIN(b.priority) AS priority
			FROM #tmpData t
				INNER JOIN @bettype b ON t.bettype = b.bettype
			GROUP BY t.matchid, t.custid
		) t ON m.matchid = t.matchid 
		INNER JOIN @bettype b ON b.priority = t.priority AND m.bettype = b.bettype
	GROUP BY t.matchid, t.custid
		
	INSERT INTO #bettrans
	SELECT
		matchid,
		bettype,
		SUM(CASE 
				WHEN bettype IN (5, 15) THEN ABS(stake) * (1 - tpositiontaking) * virtualrate
				WHEN bettype IN (1, 2, 3, 7, 8, 12, 124, 125)
					THEN (CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking) * virtualrate
				ELSE 0 END) AS stake,
		-SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS winlost,
		SUM(scomm * actualrate) AS comm,
		SUM(CASE 
				WHEN bettype IN (5, 15) THEN ABS(stake) * (1 - tpositiontaking - ISNULL(ExtraPT, 0)) * virtualrate
				WHEN bettype IN (1, 2, 3, 7, 8, 12, 124, 125)
					THEN (CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking- ISNULL(ExtraPT, 0)) * virtualrate
				ELSE 0 END) AS stake_AfterExtraPT,
		-SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0 ELSE scomm/(1 - tpositiontaking) END) * virtualrate * ISNULL(e.ExtraPT, 0)) AS memberwinlost_ExtraPT,
		COUNT(1) AS bet
	FROM dbo.bettrans14 b WITH (NOLOCK)
		LEFT JOIN #ExtraPTSportbook e ON b.srecommend = e.superId AND b.winlostdate BETWEEN e.FromDate AND e.ToDate
	WHERE
		statusID NOT IN (101, 102, 103, 121, 111)
		AND ruben = 1
		AND bettype IN (1, 3, 7, 8, 5, 15, 2, 12, 124, 125)
		AND winlostdate BETWEEN @FromDate AND @ToDate
		AND liveindicator = 1
		AND currency <> 20
	GROUP BY matchid, bettype

	-- Return Data
	SELECT
		a.custid, username, eventdate, leagueid, a.matchid, ISNULL(t.maxbet, 0) AS maxbet, homeid, awayid, IsNeutral, hthomescore, htawayscore, fthomescore, ftawayscore,
		-- turnover
		stake_hdp, stake_ou, stake_1sthdp, stake_1stou, stake_1x2, stake_1st1x2, stake_oe, stake_1stoe, stake_1stNoOfCorners, stake_NoOfCorners, stake_15minhdp, stake_15minOU, stake_15min1x2, stake_1stTotalBookings,stake_TotalBookings,stake_NextCorner,  
		stake_NextBooking, stake_15minCorners, stake_15minTotalBookings, stake_10minHdp, stake_10minOU, stake_10min1x2, stake_SingleTeamOU,
		-- winloss
		winlost_hdp, winlost_ou, winlost_1sthdp, winlost_1stou, winlost_1x2, winlost_1st1x2, winlost_oe, winlost_1stoe, winlost_1stNoOfCorners, winlost_NoOfCorners, winlost_15minhdp, winlost_15minOU,
		winlost_15min1x2, winlost_1stTotalBookings, winlost_TotalBookings, winlost_NextCorner, winlost_NextBooking, winlost_15minCorners, winlost_15minTotalBookings, winlost_10minHdp, winlost_10minOU, winlost_10min1x2, winlost_SingleTeamOU,
		-- commission
		comm_hdp, comm_ou, comm_1sthdp, comm_1stou, comm_1x2, comm_1st1x2, comm_oe, comm_1stoe, comm_1stNoOfCorners,comm_NoOfCorners, comm_15minhdp, comm_15minOU, comm_15min1x2, comm_1stTotalBookings,comm_TotalBookings,comm_NextCorner,  
		comm_NextBooking, comm_15minCorners, comm_15minTotalBookings, comm_10minHdp, comm_10minOU, comm_10min1x2, comm_SingleTeamOU,
		
		stake_1sthdp + stake_hdp + stake_1stou + stake_ou + stake_1x2 + stake_1st1x2 + stake_oe + stake_1stoe + stake_1stNoOfCorners + stake_NoOfCorners + stake_15minhdp + stake_15minOU + stake_15min1x2 + stake_1stTotalBookings + stake_TotalBookings+ stake_NextCorner 
		+ stake_NextBooking + stake_15minCorners + stake_15minTotalBookings + stake_10minHdp + stake_10minOU + stake_10min1x2 + stake_SingleTeamOU AS overall_st,  
   
		winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou +  winlost_1x2 + winlost_1st1x2 + winlost_oe + winlost_1stoe + winlost_1stNoOfCorners + winlost_NoOfCorners + winlost_15minhdp + winlost_15minOU + winlost_15min1x2 + winlost_1stTotalBookings + winlost_TotalBookings+ winlost_NextCorner
		+ winlost_NextBooking + winlost_15minCorners + winlost_15minTotalBookings + winlost_10minHdp + winlost_10minOU + winlost_10min1x2 + winlost_SingleTeamOU AS overall_wl,  
     
		comm_1sthdp + comm_hdp + comm_1stou + comm_ou + comm_1x2 + comm_1st1x2 + comm_oe + comm_1stoe + comm_1stNoOfCorners +comm_NoOfCorners + comm_15minhdp + comm_15minOU + comm_15min1x2 + comm_1stTotalBookings + comm_TotalBookings + comm_NextCorner
		+ comm_NextBooking + comm_15minCorners + comm_15minTotalBookings + comm_10minHdp + comm_10minOU + comm_10min1x2 + comm_SingleTeamOU AS overall_com,  
   
		(winlost_1sthdp)/(CASE WHEN ISNULL(ROUND(stake_1sthdp,4),0) = 0 THEN 1 ELSE stake_1sthdp END) AS margin_1sthdp,  
		(winlost_hdp)/(CASE WHEN ISNULL(ROUND(stake_hdp,4),0) = 0 THEN 1 ELSE stake_hdp END) AS margin_hdp,  
		(winlost_1stou)/(CASE WHEN ISNULL(ROUND(stake_1stou,4),0) = 0 THEN 1 ELSE stake_1stou END) AS margin_1stou,  
		(winlost_ou)/(CASE WHEN ISNULL(ROUND(stake_ou,4),0) = 0 THEN 1 ELSE stake_ou END) AS margin_ou,  
		(winlost_1x2)/(CASE WHEN ISNULL(ROUND(stake_1x2,4),0) = 0 THEN 1 ELSE stake_1x2 END) AS margin_1x2,  
		(winlost_1st1x2)/(CASE WHEN ISNULL(ROUND(stake_1st1x2,4),0) = 0 THEN 1 ELSE stake_1st1x2 END) AS margin_1st1x2,  
		(winlost_oe)/(CASE WHEN ISNULL(ROUND(stake_oe,4),0) = 0 THEN 1 ELSE stake_oe END) AS margin_oe,  
		(winlost_1stoe)/(CASE WHEN ISNULL(ROUND(stake_1stoe,4),0) = 0 THEN 1 ELSE stake_1stoe END) AS margin_1stoe,  
		(winlost_1stNoOfCorners)/(CASE WHEN ISNULL(ROUND(stake_1stNoOfCorners,4),0) = 0 THEN 1 ELSE stake_1stNoOfCorners END) AS margin_1stNoOfCorners,  
		(winlost_NoOfCorners)/(CASE WHEN ISNULL(ROUND(stake_NoOfCorners,4),0) = 0 THEN 1 ELSE stake_NoOfCorners END) AS margin_NoOfCorners,  
		(winlost_15minhdp)/(CASE WHEN ISNULL(ROUND(stake_15minhdp,4),0) = 0 THEN 1 ELSE stake_15minhdp END) AS margin_15minhdp,  
		(winlost_15minOU)/(CASE WHEN ISNULL(ROUND(stake_15minOU,4),0) = 0 THEN 1 ELSE stake_15minOU END) AS margin_15minOU,  
		(winlost_15min1x2)/(CASE WHEN ISNULL(ROUND(stake_15min1x2,4),0) = 0 THEN 1 ELSE stake_15min1x2 END) AS margin_15min1x2,  
		(winlost_1stTotalBookings)/(CASE WHEN ISNULL(ROUND(stake_1stTotalBookings,4),0) = 0 THEN 1 ELSE stake_1stTotalBookings END) AS margin_1stTotalBookings,  
		(winlost_TotalBookings)/(CASE WHEN ISNULL(ROUND(stake_TotalBookings,4),0) = 0 THEN 1 ELSE stake_TotalBookings END) AS margin_TotalBookings,  
		(winlost_NextCorner)/(CASE WHEN ISNULL(ROUND(stake_NextCorner,4),0) = 0 THEN 1 ELSE stake_NextCorner END) AS margin_NextCorner,  
		(winlost_NextBooking)/(CASE WHEN ISNULL(ROUND(stake_NextBooking,4),0) = 0 THEN 1 ELSE stake_NextBooking END) AS margin_NextBooking,  
		(winlost_15minCorners)/(CASE WHEN ISNULL(ROUND(stake_15minCorners,4),0) = 0 THEN 1 ELSE stake_15minCorners END) AS margin_15minCorners, 
		(winlost_15minTotalBookings)/(CASE WHEN ISNULL(ROUND(stake_15minTotalBookings,4),0) = 0 THEN 1 ELSE stake_15minTotalBookings END) AS margin_15minTotalBookings,  
		(winlost_10minHdp)/(CASE WHEN ISNULL(ROUND(stake_10minHdp,4),0) = 0 THEN 1 ELSE stake_10minHdp END) AS margin_10minHdp,
		(winlost_10minOU)/(CASE WHEN ISNULL(ROUND(stake_10minOU,4),0) = 0 THEN 1 ELSE stake_10minOU END) AS margin_10minOU,
		(winlost_10min1x2)/(CASE WHEN ISNULL(ROUND(stake_10min1x2,4),0) = 0 THEN 1 ELSE stake_10min1x2 END) AS margin_10min1x2,
		(winlost_SingleTeamOU)/(CASE WHEN ISNULL(ROUND(stake_SingleTeamOU,4),0) = 0 THEN 1 ELSE stake_SingleTeamOU END) AS margin_SingleTeamOU,
   
		(winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou + winlost_1x2 + winlost_1st1x2 + winlost_oe + winlost_1stoe + winlost_1stNoOfCorners + winlost_NoOfCorners + winlost_15minhdp + winlost_15minOU + winlost_15min1x2 + winlost_1stTotalBookings + winlost_TotalBookings + winlost_NextCorner
		+ winlost_NextBooking + winlost_15minCorners + winlost_15minTotalBookings + winlost_10minHdp + winlost_10minOU + winlost_10min1x2 + winlost_SingleTeamOU)
		/(CASE WHEN ROUND((ISNULL(stake_1sthdp,0) + ISNULL(stake_hdp,0) + ISNULL(stake_1stou,0) + ISNULL(stake_ou,0) + ISNULL(stake_1x2,0) + ISNULL(stake_1st1x2,0) + ISNULL(stake_oe,0) + ISNULL(stake_1stoe,0) + ISNULL(stake_1stNoOfCorners,0) + ISNULL(stake_NoOfCorners,0) + ISNULL(stake_15minhdp,0) + ISNULL(stake_15minOU,0) + ISNULL(stake_15min1x2,0) + ISNULL(stake_1stTotalBookings,0) + ISNULL(stake_TotalBookings,0)+ ISNULL(stake_NextCorner,0)
										+ ISNULL(stake_NextBooking,0) + ISNULL(stake_15minCorners,0) + ISNULL(stake_15minTotalBookings,0) + ISNULL(stake_10minHdp,0) + ISNULL(stake_10minOU,0) + ISNULL(stake_10min1x2,0) + ISNULL(stake_SingleTeamOU,0)),4) = 0 THEN 1   
		ELSE (ISNULL(stake_1sthdp,0) + ISNULL(stake_hdp,0) + ISNULL(stake_1stou,0) +ISNULL(stake_ou,0) + ISNULL(stake_1x2,0) + ISNULL(stake_1st1x2,0) + ISNULL(stake_oe,0)+ ISNULL(stake_1stoe,0)+ ISNULL(stake_1stNoOfCorners,0) +ISNULL(stake_NoOfCorners,0)+ ISNULL(stake_15minhdp,0) + ISNULL(stake_15minOU,0) + ISNULL(stake_15min1x2,0)  + ISNULL(stake_1stTotalBookings,0) + ISNULL(stake_TotalBookings,0) + ISNULL(stake_NextCorner,0) 
										+ ISNULL(stake_NextBooking,0) + ISNULL(stake_15minCorners,0) + ISNULL(stake_15minTotalBookings,0) + ISNULL(stake_10minHdp,0) + ISNULL(stake_10minOU,0) + ISNULL(stake_10min1x2,0) + ISNULL(stake_SingleTeamOU,0)) END) AS overall_margin,  
     
		bet_hdp, bet_ou, bet_1sthdp, bet_1stou, bet_1x2, bet_1st1x2, bet_oe, bet_1stoe, bet_1stNoOfCorners, bet_NoOfCorners, bet_15minhdp, bet_15minOU, bet_15min1x2, bet_1stTotalBookings, bet_TotalBookings, bet_NextCorner,
		bet_NextBooking, bet_15minCorners, bet_15minTotalBookings, bet_10minHdp, bet_10minOU, bet_10min1x2, bet_SingleTeamOU,  
		bet_hdp + bet_ou + bet_1x2 + bet_oe + bet_1sthdp + bet_1stou + bet_1st1x2 + bet_1stoe +  bet_NoOfCorners + bet_1stNoOfCorners + bet_15minhdp + bet_15minOU + bet_15min1x2 + bet_1stTotalBookings + bet_TotalBookings + bet_NextCorner 
		+ bet_NextBooking + bet_15minCorners + bet_15minTotalBookings + bet_10minHdp + bet_10minOU + bet_10min1x2 + bet_SingleTeamOU AS overall_livebet  
	FROM
	(
		SELECT t.custid, t.username, t.eventdate, t.leagueid, t.matchid,t.homeid, t.awayid, t.hthomescore, t.htawayscore, t.fthomescore, t.ftawayscore, t.IsNeutral,
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
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN bet ELSE 0 END) AS bet_SingleTeamOU
		FROM #bettrans b
			INNER JOIN #tmpData t ON b.matchid = t.matchid AND (b.bettype = t.bettype OR (b.bettype = 124 AND t.bettype = 5) OR (b.bettype = 125 AND t.bettype = 15))
		GROUP BY t.custid, t.username, t.eventdate, t.leagueid, t.matchid, t.homeid, t.awayid, t.hthomescore, t.htawayscore, t.fthomescore, t.ftawayscore, t.IsNeutral
		
		UNION ALL  
		SELECT 0, '(unassigned)', t.eventdate, t.leagueid, t.matchid, t.homeid, t.awayid, t.hthomescore, t.htawayscore, t.fthomescore, t.ftawayscore, t.IsNeutral,
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
			SUM(CASE WHEN b.bettype = 1 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minHdp,
			SUM(CASE WHEN b.bettype = 3 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10minOU,
			SUM(CASE WHEN b.bettype = 5 AND OUtype = 8 THEN bet ELSE 0 END) AS bet_10min1x2,
			SUM(CASE WHEN b.bettype IN (3, 8) AND OUtype = 9 THEN bet ELSE 0 END) AS bet_SingleTeamOU
		FROM #bettrans b      
			INNER JOIN #tmpData t ON b.matchid = t.matchid AND t.bettype = 0     
		GROUP BY t.eventdate, t.leagueid, t.matchid, t.homeid, t.awayid, t.hthomescore, t.htawayscore, t.fthomescore, t.ftawayscore, t.IsNeutral
	) AS A
		LEFT JOIN @temp_maxbet t ON a.matchid = t.matchid AND a.custid = t.custid
	ORDER BY username, eventdate, leagueid, matchid

	DROP TABLE #bettrans
	DROP TABLE #tmpData
	DROP TABLE #ExtraPTSportbook
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TraderPerformanceDetail_14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TraderPerformanceDetail_14] TO [vnteam]
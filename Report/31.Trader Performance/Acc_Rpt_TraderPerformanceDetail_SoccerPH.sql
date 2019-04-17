/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceDetail_SoccerPH]   
	@FromDate	DATETIME,  
	@ToDate		DATETIME
AS

/*
	Creator: Cherry
	Date: 2017-08-18
	DB: DBACC.bodb02
	Task: Trader Performance Report - Detail - SoccerPH - bettrans

	Revisions:
		-20170925@Kean: Update formula of ExtraPT
		- 20180328@Kean: Apply new concept of Commission to Trader Performance Report (#111015)

	Param's Explanation:
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
		IsNeutral	BIT
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
	
	CREATE TABLE #BettypeMapping(
		OperatorType INT,
		TradingBettype INT,
		TicketBettype INT
	)
	
	CREATE TABLE #Result (
		custid		INT,
		username	VARCHAR(50),
		eventdate	DATETIME, 
		leagueid	INT,
		matchid		INT,
		homeid		INT,
		awayid		INT,
		IsNeutral	BIT,
		hthomescore	INT,
		htawayscore	INT,
		fthomescore	INT,
		ftawayscore	INT,		
		Bettype     INT,
		BettypeName	NVARCHAR(128),
		Winlost		MONEY,		
		Stake		MONEY,
		BetCount	INT,
		Margin		MONEY,
		Commission	MONEY
	)	
	
	CREATE TABLE #MatchDetail (
		custid		INT,
		username	VARCHAR(50),
		eventdate	DATETIME, 
		leagueid	INT,
		matchid		INT,
		homeid		INT,
		awayid		INT,
		IsNeutral	BIT,
		hthomescore	INT,
		htawayscore	INT,
		fthomescore	INT,
		ftawayscore	INT
	)
	
	INSERT INTO #BettypeMapping 
	SELECT 	OperatorType, TradingBettype, TicketBettype
	FROM DBDW.bodb_Account.dbo.TradingBettypeMapping WITH (NOLOCK)
	WHERE OperatorType = 1 AND TradingBettype = 37
	
	DELETE m
	FROM #BettypeMapping m
	WHERE m.TicketBettype NOT IN (SELECT typeid FROM bodb02.dbo.bettype WITH (NOLOCK))	

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
			ISNULL(bm.TicketBettype,0) AS bettype,
			m.isNeutral
		FROM dbo.Dot_admin_Assignment_Operator a WITH (NOLOCK)
			INNER JOIN #BettypeMapping bm ON bm.OperatorType = a.OperatorType AND bm.TradingBettype = a.bettype
			INNER JOIN dbo.match m WITH (NOLOCK) ON a.matchid = m.matchid
			LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
			INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
			INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE
			m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'
			AND m.sporttype = 1
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
			0 AS bettype,
			m.isNeutral
		FROM dbo.Dot_admin_Assignment_Operator a WITH (NOLOCK)
			RIGHT JOIN dbo.match m WITH (NOLOCK) ON a.matchid = m.matchid
			LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
			INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE
			m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'
			AND m.sporttype = 1
			AND m.matchcode NOT LIKE '%hedge%'
			AND a.matchid IS NULL
	END		
		
	INSERT INTO #bettrans
	SELECT
		b.matchid,
		bettype,
		SUM((CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking) * virtualrate) AS stake,
		-SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate 
								+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END
								  ) AS winlost,
		SUM(scomm * CASE
                                      WHEN b.virtualrate < b.actualrate
                                      THEN b.virtualrate
                                      ELSE b.actualrate
                                  END) AS comm,
		--SUM((CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking- ISNULL(ExtraPT, 0)) * virtualrate) AS stake_AfterExtraPT,
		---SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0 ELSE scomm/(1 - tpositiontaking) END) * virtualrate * ISNULL(e.ExtraPT, 0)) AS memberwinlost_ExtraPT,
		SUM((CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (CASE WHEN tpositiontaking = 1 THEN 0 ELSE 1 - tpositiontaking- ISNULL(ExtraPT, 0) END) * virtualrate) AS stake_AfterExtraPT,
		-SUM(CASE WHEN tpositiontaking = 1 THEN 0 ELSE ((winlost - actual_stake) * virtualrate 
														+ CASE WHEN tpositiontaking = 1 THEN 0 
														ELSE (scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END)/(1 - tpositiontaking) 
														END) * ISNULL(e.ExtraPT, 0) END) AS memberwinlost_ExtraPT,
		SUM(CASE WHEN td.[VendorID] IN (14) THEN 0 
				   ELSE 1 END) AS bet
	FROM dbo.bettrans b WITH (NOLOCK)
		INNER JOIN dbo.match m WITH (NOLOCK) ON b.matchid = m.matchid 
		INNER JOIN #BettypeMapping bm ON b.bettype = bm.TicketBettype
		LEFT JOIN #ExtraPTSportbook e ON b.srecommend = e.superId AND b.winlostdate BETWEEN e.FromDate AND e.ToDate
		LEFT JOIN dbo.TradeCust AS td WITH (NOLOCK) ON b.custid = td.custid
	WHERE
		statusID NOT IN (101, 102, 103, 121, 111)
		AND b.ruben = 1
		AND winlostdate BETWEEN @FromDate AND @ToDate
		AND liveindicator = 1
		AND currency <> 20
		AND m.eventdate BETWEEN @FromDate AND @ToDate
		AND m.eventstatus = 'completed'
		AND m.sporttype = 1
		AND m.matchcode NOT LIKE '%hedge%'
	GROUP BY b.matchid, bettype

	-- Return Data
	INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, 
						homeid, awayid, IsNeutral, 
						hthomescore, htawayscore, 
						fthomescore, ftawayscore, 
						Bettype, BettypeName, 
						Winlost, Stake, BetCount, Commission)	
	SELECT t.custid, t.username, t.eventdate, t.leagueid, t.matchid, 
			t.homeid, t.awayid, t.IsNeutral,
			t.hthomescore, t.htawayscore, 
			t.fthomescore, t.ftawayscore, 
			bt.typeid AS Bettype, bt.typenamee AS BettypeName,
			SUM(ISNULL(winlost - memberwinlost_ExtraPT,0)) AS Winlost,  
			SUM(ISNULL(stake_AfterExtraPT,0)) AS Stake,		
			SUM(ISNULL(bet,0)) AS BetCount,							
			SUM(ISNULL(comm,0)) AS Commission  			    						
	FROM #bettrans b  
		INNER JOIN #tmpData t  ON b.matchid = t.matchid AND b.bettype = t.bettype 
		INNER JOIN dbo.bettype bt WITH (NOLOCK) ON t.bettype = bt.typeid 		
	GROUP BY t.custid, t.username, t.eventdate, t.leagueid, t.matchid, t.homeid, t.awayid, t.hthomescore, t.htawayscore, 
			t.fthomescore, t.ftawayscore, t.IsNeutral, bt.typeid, bt.typenamee		
			
	IF (SELECT COUNT(*) FROM #Result WHERE custid <> 0) > 0
	BEGIN
		INSERT INTO #MatchDetail (custid, username, eventdate, leagueid, matchid, 
						homeid, awayid, IsNeutral, hthomescore, htawayscore, fthomescore, ftawayscore)
		SELECT DISTINCT custid, username, eventdate, leagueid, matchid, 
				homeid, awayid, IsNeutral, hthomescore, htawayscore, fthomescore, ftawayscore
		FROM #Result
		WHERE custid <> 0
						
		INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, 
						homeid, awayid, IsNeutral, 
						hthomescore, htawayscore, 
						fthomescore, ftawayscore, 
						Bettype, BettypeName, 
						Winlost, Stake, BetCount, Commission)	
		SELECT t.custid, t.username, t.eventdate, t.leagueid, t.matchid, 
				t.homeid, t.awayid, t.IsNeutral,
				t.hthomescore, t.htawayscore, 
				t.fthomescore, t.ftawayscore, 
				bt.typeid AS Bettype, bt.typenamee AS BettypeName,
				0 AS Winlost,  
				0 AS Stake,		
				0 AS BetCount,							
				0 AS Commission  			    						
		FROM #BettypeMapping bm  
			INNER JOIN dbo.bettype bt WITH (NOLOCK) ON bm.TicketBettype = bt.typeid 
			INNER JOIN #MatchDetail t ON t.custid <> 0	
			LEFT JOIN #Result r ON bt.typeid = r.Bettype AND t.custid = r.custid AND t.matchid = r.matchid 
		WHERE r.Bettype IS NULL 
	END				
			
	INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, 
						homeid, awayid, IsNeutral, 
						hthomescore, htawayscore, 
						fthomescore, ftawayscore, 
						Bettype, BettypeName, 
						Winlost, Stake, BetCount, Commission)
	SELECT 0, '(unassigned)', t.eventdate, t.leagueid, t.matchid, 
			t.homeid, t.awayid, t.IsNeutral,
			t.hthomescore, t.htawayscore, 
			t.fthomescore, t.ftawayscore, 
			bt.typeid AS Bettype, bt.typenamee AS BettypeName,
			SUM(ISNULL(winlost - memberwinlost_ExtraPT,0)) AS Winlost,  
			SUM(ISNULL(stake_AfterExtraPT,0)) AS Stake,		
			SUM(ISNULL(bet,0)) AS BetCount,							
			SUM(ISNULL(comm,0)) AS Commission  
	FROM #bettrans b 
		INNER JOIN dbo.bettype bt WITH (NOLOCK) ON b.bettype = bt.typeid      
		LEFT JOIN #tmpData t ON b.matchid = t.matchid AND (b.bettype = t.bettype OR t.bettype = 0)
	WHERE (t.bettype IS NULL OR t.bettype = 0) AND t.matchid IS NOT NULL
	GROUP BY t.eventdate, t.leagueid, t.matchid, t.homeid, t.awayid, t.hthomescore, t.htawayscore, t.fthomescore, t.ftawayscore, t.IsNeutral, bt.typeid, bt.typenamee		
			
	IF (SELECT COUNT(*) FROM #Result WHERE custid = 0) > 0
	BEGIN
		INSERT INTO #MatchDetail (custid, username, eventdate, leagueid, matchid, 
						homeid, awayid, IsNeutral, hthomescore, htawayscore, fthomescore, ftawayscore)
		SELECT DISTINCT custid, username, eventdate, leagueid, matchid, 
				homeid, awayid, IsNeutral, hthomescore, htawayscore, fthomescore, ftawayscore
		FROM #Result
		WHERE custid = 0
		
		INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, 
							homeid, awayid, IsNeutral, 
							hthomescore, htawayscore, 
							fthomescore, ftawayscore, 
							Bettype, BettypeName, 
							Winlost, Stake, BetCount, Commission)
		SELECT 0, '(unassigned)', t.eventdate, t.leagueid, t.matchid, 
				t.homeid, t.awayid, t.IsNeutral,
				t.hthomescore, t.htawayscore, 
				t.fthomescore, t.ftawayscore, 
				bt.typeid AS Bettype, 
				bt.typenamee AS	BettypeName,
				0 AS Winlost,			
				0 AS Stake,  			
				0 AS BetCount,  			    
				0 AS Commission 
		FROM #BettypeMapping bm
			INNER JOIN dbo.bettype bt ON bm.TicketBettype = bt.typeid 		
			INNER JOIN #MatchDetail t ON t.custid = 0	
			LEFT JOIN #Result s ON s.custid = 0 AND s.matchid = t.matchid AND s.Bettype = bt.typeid 
		WHERE s.Bettype IS NULL 
	END
	
	IF (SELECT COUNT(*) FROM #Result) = 0
	BEGIN
		INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, 
							homeid, awayid, IsNeutral, 
							hthomescore, htawayscore, 
							fthomescore, ftawayscore, 
							Bettype, BettypeName, 
							Winlost, Stake, BetCount, Commission)
		SELECT 0, '(unassigned)', NULL AS eventdate, NULL AS leagueid, NULL AS matchid, 
				NULL AS homeid, NULL AS awayid, NULL AS IsNeutral,
				NULL AS hthomescore, NULL AS htawayscore, 
				NULL AS fthomescore, NULL AS ftawayscore, 
				bt.typeid AS Bettype, 
				bt.typenamee AS	BettypeName,
				0 AS Winlost,			
				0 AS Stake,  			
				0 AS BetCount,  			    
				0 AS Commission
		FROM #BettypeMapping bm
			INNER JOIN dbo.bettype bt ON bm.TicketBettype = bt.typeid 				
	END
				
	UPDATE #Result
	SET Margin = CASE WHEN ISNULL(ROUND(Stake,4),0) = 0 THEN 0 ELSE Winlost/Stake END 
	
	INSERT INTO #Result (custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
						hthomescore, htawayscore, fthomescore, ftawayscore, 
						Bettype, BettypeName, 
						Winlost, Stake, BetCount, Margin, Commission)			
	SELECT custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
						hthomescore, htawayscore, fthomescore, ftawayscore, 
						Bettype, BettypeName, 
						Winlost, Stake, BetCount, Margin, Commission
	FROM (
		SELECT custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore, 100000 AS Bettype, 'Overall_Win Loss' AS BettypeName, 
				SUM(Winlost) AS Winlost, 0 AS Stake, 0 AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore
		UNION ALL
		SELECT custid, username, eventdate, leagueid, matchid,  homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore, 200000 AS Bettype, 'Overall_Turnover' AS BettypeName, 
				0 AS Winlost, SUM(Stake) AS Stake, 0 AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore
		UNION ALL
		SELECT custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore, 300000 AS Bettype, 'Overall_Live BetCount' AS BettypeName, 
				0 AS Winlost, 0 AS Stake, SUM(BetCount) AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore
		UNION ALL
		SELECT custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore, 400000 AS Bettype, 'Overall_Margin %' AS BettypeName, 
				0 AS Winlost, 0 AS Stake, 0 AS BetCount, CASE WHEN SUM(Stake) = 0 THEN 0 ELSE SUM(Winlost)/SUM(Stake) END AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore
		UNION ALL
		SELECT custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore, 500000 AS Bettype, 'Overall_Commission' AS BettypeName, 
				0 AS Winlost, 0 AS Stake, 0 AS BetCount, 0 AS Margin, SUM(Commission) AS Commission
		FROM #Result 
		GROUP BY custid, username, eventdate, leagueid, matchid, homeid, awayid, IsNeutral, 
				hthomescore, htawayscore, fthomescore, ftawayscore
	) AS A		
	
	SELECT r.custid, username AS Trader, eventdate AS [Date], l.leaguename AS [League], 
			ht.teamname + '-' + at.teamname AS [Match], 
			CONVERT(VARCHAR(5), r.hthomescore) + '--' + CONVERT(VARCHAR(5), r.htawayscore) AS [Score_HT], 
			CONVERT(VARCHAR(5), r.fthomescore) + '--' + CONVERT(VARCHAR(5), ftawayscore) AS [Score_FT], BettypeName, 
			Winlost AS [Win Loss], Stake AS [Turnover], BetCount AS [Live BetCount], Margin AS [Margin %], Commission
	FROM #Result r
		LEFT JOIN dbo.league l WITH (NOLOCK) ON r.leagueid = l.leagueid
		LEFT JOIN dbo.team ht WITH (NOLOCK) ON r.homeid = ht.teamid
		LEFT JOIN dbo.team at WITH (NOLOCK) ON r.awayid = at.teamid	
	ORDER BY username, r.leagueid, r.matchid, Bettype

	DROP TABLE #bettrans
	DROP TABLE #tmpData
	DROP TABLE #ExtraPTSportbook
	DROP TABLE #BettypeMapping 
	DROP TABLE #Result 
	DROP TABLE #MatchDetail
	
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TraderPerformanceDetail_SoccerPH] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TraderPerformanceDetail_SoccerPH] TO [vnteam]
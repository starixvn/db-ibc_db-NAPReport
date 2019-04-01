/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceSum_SoccerPH]   
	@FromDate	DATETIME,  
	@ToDate		DATETIME  
AS

/*
	Creator: Cherry
	Date: 2017-08-18
	DB: DBACC.bodb02
	Task: Trader Performance Report - Sum - SoccerPH - bettrans

	Revisions:
		- 20170925@Kean: Update formula of ExtraPT
		- 20180328@Kean: Apply new concept of Commission to Trader Performance Report (#111015)

	Param's Explanation:

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @countMajorOrphan INT, @countMinor1Orphan INT, @countMinor2Orphan INT, @countMinor3Orphan INT, @countOthersOrphan INT
  
	CREATE TABLE #tmpData
	(  
		custid		INT,
		username	VARCHAR(50),
		matchid		INT,
		bettype		SMALLINT,
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
	
	CREATE TABLE #BettypeMapping(
		OperatorType INT,
		TradingBettype INT,
		TicketBettype INT
	)
	
	CREATE TABLE #Result (
		custid		INT,
		username	VARCHAR(50),
		matchno		INT,  
		Major		INT,
		Minor1		INT,
		Minor2		INT,
		Minor3		INT,
		Others		INT,
		Bettype     INT,
		BettypeName	NVARCHAR(128),
		Winlost		MONEY,		
		Stake		MONEY,
		BetCount	INT,
		Margin		MONEY,
		Commission	MONEY
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
		FROM bodb_ACC.dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE
			(
				@FromDate BETWEEN FromDate AND ToDate
				OR @ToDate BETWEEN FromDate AND ToDate
			)
			AND ProductId = 1 AND Sporttype = 0 AND SubProduct = ''
	) A
	GROUP BY SuperId, FromDate, ToDate

	INSERT INTO #tmpData
	SELECT DISTINCT a.operatorid, username, m.matchID,  
		bm.TicketBettype,
		l.category
	FROM dbo.Dot_admin_Assignment_Operator a WITH (NOLOCK)
		INNER JOIN #BettypeMapping bm ON bm.OperatorType = a.OperatorType AND bm.TradingBettype = a.bettype
		INNER JOIN dbo.customer c WITH (NOLOCK) ON a.operatorid = c.custid
		INNER JOIN dbo.match m WITH (NOLOCK) ON a.matchid = m.matchid
		LEFT JOIN dbo.team t WITH (NOLOCK) ON m.homeid = t.teamid
		INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE  
		m.eventdate BETWEEN @FromDate AND @ToDate
		AND m.eventstatus = 'completed'
		AND m.sporttype = 1
		AND m.matchcode NOT LIKE '%hedge%'

	INSERT INTO #tmpData
	SELECT NULL, NULL, m.matchID, 0,
		l.category
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
		
	INSERT INTO #bettrans
	SELECT
		b.matchid,
		bettype,
		SUM((CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (1 - tpositiontaking) * virtualrate) AS stake,
		-SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS winlost,
		SUM(scomm * CASE
                                      WHEN b.virtualrate < b.actualrate
                                      THEN b.virtualrate
                                      ELSE b.actualrate
                                  END) AS comm,
		SUM((CASE WHEN modds = 0.25 OR modds = - 0.25 THEN stake/2 ELSE stake END) * (CASE WHEN tpositiontaking = 1 THEN 0 ELSE 1 - tpositiontaking- ISNULL(ExtraPT, 0) END) * virtualrate) AS stake_AfterExtraPT,
		-SUM(CASE WHEN tpositiontaking = 1 THEN 0 ELSE (winlost - actual_stake + scomm/(1 - tpositiontaking)) * virtualrate * ISNULL(e.ExtraPT, 0) END) AS memberwinlost_ExtraPT,
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

	INSERT INTO #userMatch (custid, nMatch, Major, Minor1, Minor2, Minor3, Others) 
	SELECT
		ISNULL(custid,0),
		ISNULL(Major, 0) + ISNULL(Minor1, 0) + ISNULL(Minor2, 0) + ISNULL(Minor3, 0) + ISNULL(Others, 0) AS nMatch,
		ISNULL(Major, 0), ISNULL(Minor1, 0), ISNULL(Minor2, 0), ISNULL(Minor3, 0) ,ISNULL(Others, 0)
	FROM
	(
		SELECT t.custid, ISNULL(t.category, 'Others') AS category, COUNT(DISTINCT t.matchID) AS cntMatch
		FROM #tmpData t  
			INNER JOIN #bettrans b ON b.matchid = t.matchid AND b.bettype = t.bettype AND t.custid IS NOT NULL
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
	INSERT INTO #Result (custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Commission)
	SELECT t.custid, t.username, nMatch AS matchno, um.Major, um.Minor1, um.Minor2, um.Minor3, um.Others,
			bt.typeid AS Bettype, bt.typenamee AS BettypeName,
			SUM(ISNULL(winlost - memberwinlost_ExtraPT,0)) AS Winlost,  		
			SUM(ISNULL(stake_AfterExtraPT,0)) AS Stake,			
			SUM(ISNULL(bet,0)) AS BetCount, 
			SUM(ISNULL(comm,0)) AS Commission  			    			  			
	FROM #tmpData t  
		LEFT JOIN #bettrans b ON b.matchid = t.matchid AND b.bettype = t.bettype 
		INNER JOIN dbo.bettype bt WITH (NOLOCK) ON t.bettype = bt.typeid 
		INNER JOIN #userMatch um ON um.custid = t.custid			
	GROUP BY t.custid, t.username, um.nMatch, um.Major, um.Minor1, um.Minor2, um.Minor3, um.Others, bt.typeid, bt.typenamee				
	
	INSERT INTO #Result (custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Commission)
	SELECT 0, '(unassigned)', ISNULL(@countMajorOrphan, 0) + ISNULL(@countMinor1Orphan, 0) + ISNULL(@countMinor2Orphan, 0) + ISNULL(@countMinor3Orphan, 0) + ISNULL(@countOthersOrphan, 0) AS matchno, ISNULL(@countMajorOrphan, 0) Major, ISNULL(@countMinor1Orphan, 0), ISNULL(@countMinor2Orphan, 0), ISNULL(@countMinor3Orphan, 0), ISNULL(@countOthersOrphan, 0),
			bt.typeid AS Bettype, bt.typenamee AS BettypeName,
			SUM(winlost - memberwinlost_ExtraPT) AS Winlost,  		
			SUM(stake_AfterExtraPT) AS Stake,	
			SUM(bet) AS BetCount,						 
			SUM(comm) AS Commission  			    						
	FROM #bettrans b 
		INNER JOIN dbo.bettype bt WITH (NOLOCK) ON b.bettype = bt.typeid      
		LEFT JOIN #tmpData t ON b.matchid = t.matchid AND (b.bettype = t.bettype OR t.bettype = 0)
	WHERE (t.bettype IS NULL OR t.bettype = 0) AND t.matchid IS NOT NULL	
	GROUP BY bt.typeid, bt.typenamee
	
	IF (SELECT COUNT(*) FROM #Result WHERE custid = 0) > 0
	BEGIN
		INSERT INTO #Result (custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Commission)
		SELECT 0, '(unassigned)', ISNULL(@countMajorOrphan, 0) + ISNULL(@countMinor1Orphan, 0) + ISNULL(@countMinor2Orphan, 0) + ISNULL(@countMinor3Orphan, 0) + ISNULL(@countOthersOrphan, 0) AS matchno, ISNULL(@countMajorOrphan, 0) Major, ISNULL(@countMinor1Orphan, 0), ISNULL(@countMinor2Orphan, 0), ISNULL(@countMinor3Orphan, 0), ISNULL(@countOthersOrphan, 0),
				bt.typeid, bt.typenamee AS BettypeName,
				0 AS Winlost, 
				0 AS Stake,	
				0 AS BetCount,					 			 
				0 AS Commission			    			 			
		FROM #BettypeMapping bm
			INNER JOIN dbo.bettype bt WITH (NOLOCK) ON bm.TicketBettype = bt.typeid 
			LEFT JOIN #Result s ON s.custid = 0 AND bt.typeid = s.Bettype      
		WHERE s.Bettype IS NULL
		GROUP BY bt.typeid, bt.typenamee
	END
	
	IF (SELECT COUNT(*) FROM #Result) = 0
	BEGIN
		INSERT INTO #Result (custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Commission)
		SELECT 0, '(unassigned)', ISNULL(@countMajorOrphan, 0) + ISNULL(@countMinor1Orphan, 0) + ISNULL(@countMinor2Orphan, 0) + ISNULL(@countMinor3Orphan, 0) + ISNULL(@countOthersOrphan, 0) AS matchno, ISNULL(@countMajorOrphan, 0) Major, ISNULL(@countMinor1Orphan, 0), ISNULL(@countMinor2Orphan, 0), ISNULL(@countMinor3Orphan, 0), ISNULL(@countOthersOrphan, 0),
				bt.typeid, bt.typenamee AS BettypeName,
				0 AS Winlost, 
				0 AS Stake,	
				0 AS BetCount,					 			 
				0 AS Commission			    			 			
		FROM #BettypeMapping bm
			INNER JOIN dbo.bettype bt WITH (NOLOCK) ON bm.TicketBettype = bt.typeid 
	END
	
	UPDATE #Result
	SET Margin = CASE WHEN ISNULL(ROUND(Stake,4),0) = 0 THEN 0 ELSE Winlost/Stake END
	
	INSERT INTO #Result (custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Margin, Commission)			
	SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, Bettype, BettypeName, Winlost, Stake, BetCount, Margin, Commission
	FROM (
		SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, 100000 AS Bettype, 'Overall_Win Loss' AS BettypeName, 
			SUM(Winlost) AS Winlost, 0 AS Stake, 0 AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, matchno, Major, Minor1, Minor2, Minor3, Others
		UNION ALL
		SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, 200000 AS Bettype, 'Overall_Turnover' AS BettypeName, 
			0 AS Winlost, SUM(Stake) AS Stake, 0 AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, matchno, Major, Minor1, Minor2, Minor3, Others
		UNION ALL
		SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, 300000 AS Bettype, 'Overall_Live BetCount' AS BettypeName, 
			0 AS Winlost, 0 AS Stake, SUM(BetCount) AS BetCount, 0 AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, matchno, Major, Minor1, Minor2, Minor3, Others
		UNION ALL
		SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, 400000 AS Bettype, 'Overall_Margin %' AS BettypeName, 
			0 AS Winlost, 0 AS Stake, 0 AS BetCount, CASE WHEN SUM(Stake) = 0 THEN 0 ELSE SUM(Winlost)/SUM(Stake) END AS Margin, 0 AS Commission
		FROM #Result 
		GROUP BY custid, username, matchno, Major, Minor1, Minor2, Minor3, Others
		UNION ALL
		SELECT custid, username, matchno, Major, Minor1, Minor2, Minor3, Others, 500000 AS Bettype, 'Overall_Commission' AS BettypeName, 
			0 AS Winlost, 0 AS Stake, 0 AS BetCount, 0 AS Margin, SUM(Commission) AS Commission
		FROM #Result 
		GROUP BY custid, username, matchno, Major, Minor1, Minor2, Minor3, Others
	) AS A
	
	SELECT custid, username AS Trader, matchno AS Match, Major, Minor1, Minor2, Minor3, Others, BettypeName, 
			Winlost AS [Win Loss], Stake AS [Turnover], BetCount AS [Live BetCount], Margin AS [Margin %], Commission
	FROM #Result 
	ORDER BY username, Bettype
	
    
	DROP TABLE #bettrans
	DROP TABLE #tmpData
	DROP TABLE #userMatch
	DROP TABLE #ExtraPTSportbook
	DROP TABLE #BettypeMapping 
	DROP TABLE #Result 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TraderPerformanceSum_SoccerPH] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TraderPerformanceSum_SoccerPH] TO [vnteam]
GO
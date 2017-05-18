USE [bodb_report] 
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DuplicatedTicketsSel]
	@Date DATETIME,
	@CheckTime SMALLINT = 1
AS
/*
Created: 20150212@Sophia
Task :	Get Duplicated ticket report
DB:		DBRPT/bodb_report
Original: [Acc_CheckDuplicateTickets]

Revisions:
	- 20150402@Sophia: Add more test currency (20, 27, 28)
	- 20150723@Sophia: Exclude data of Bettrade [#38815]
	- 20151009@Sophia: Group by IP [#45176]
	- 20151021@Sophia: Modify the SPs to only cover the tickets of the following products [#45898] 
						1	Sportsbook [inclusive of : Metric Gaming - Superlive and BetTrade tickets (check the refno)]
						3	Number Game
						4	SLI - Live Casino
						5	Virtual Sports
	- 20160119@Robert: Modify SP covered bettype 501. Need to exclude bettype 500 from this report. [#50274]
	- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
	- 20170323@Sophia: Fix Parlay issue ( can't detect Parlay ticket if checking RefNo) [Redmine: #73884]
						1	Sportsbook
						2	Number Game
						3	SLI - Live Casino
						4	Virtual Sports
						5   Metric Gaming - Superlive
						6   BetTrade (check the refno)
	- 20170424@Percy: Don't check dummy account of Cash Out [RedmineID: #73419]
Param's Explanation:
	- @CheckTime : The time we consider how long the job fails (Compared the last run with the current time).
				   Because job recurs every 30s, so we set @CheckTime = 1 minute as default


*/
BEGIN
	SET NOCOUNT ON

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype (ProductID  , Bettype  ,EventType  ,SubProduct)
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5

	DELETE  @SportBettype 
	WHERE	ProductID NOT IN (1, 3, 4, 5) 
			OR bettype IN (500) ----, 901, 902, 903, 904)

	---- ** 1. Check the transdate of LastTransID and current time  ** ----
	DECLARE @LastTransDate DATETIME	
	SELECT @LastTransDate = CONVERT(DATETIME, VValue) FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastDate'
	
		----> If it's more than 1 minute then the job fails and call the code of the old report (SP: Acc_CheckDuplicateTickets)
	IF DATEDIFF(MINUTE, @LastTransDate, CURRENT_TIMESTAMP) > @CheckTime
	BEGIN 
			;WITH _match AS (
			SELECT matchid as mID from bodb02.dbo.match WITH(NOLOCK) WHERE eventdate >= @date
			UNION ALL
			SELECT orid FROM bodb02.dbo.outright WITH(NOLOCK) WHERE eventdate >= @date
			UNION ALL
			SELECT DISTINCT eventid FROM bodb02.dbo.VSOutright WITH(NOLOCK) WHERE EventDate >= @date
			UNION ALL
			SELECT DISTINCT eventid FROM bodb02.dbo.translog WITH(NOLOCK) WHERE transdate BETWEEN @date AND DATEADD(dd, 1, @date)
			UNION ALL
			SELECT 9 -- mix parlay
			UNION ALL
			SELECT 29 -- system parlay
			)
			SELECT  b.custid, 
					b.odds, 
					b.stake, 
					b.balance, 
					CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
					WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
					ELSE b.bettype END bettype,
					b.winlostdate, 
					b.matchid,
					b.ip,
					CASE WHEN b.Bettype IN (901,902,903,904) THEN b.RefNo ELSE 0 END as RefNo	
			INTO #TempData
			FROM bodb02.dbo.bettrans b WITH(NOLOCK)
				INNER JOIN @SportBettype s ON s.bettype = b.bettype
				INNER JOIN _match m ON b.matchid = m.mID
			WHERE b.bettype < 19000							
				and custid not in (50057,879241,103873, 851668, 878902) --betdaq
				and custid NOT IN (1077687) -- Betfair
				and recommend not in (11196380) -- foobet
				and transdate BETWEEN @date AND DATEADD(dd, 1, @date)				
				and custid > 0
				and recommend NOT IN (5707545,52466) -- exclude members under BARM,8RM
				and currency NOT IN (20, 27, 28)
				And statusID NOT IN (101,102)
				AND NOT EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.TradeCust t WITH (NOLOCK) WHERE b.custid = t.custid AND t.VendorID = 14)
			GROUP BY b.custid, 
					b.odds, 
					b.stake, 
					b.balance, 
					CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
					WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
					ELSE b.bettype END,
					b.winlostdate, 
					b.matchid,
					b.ip,
					CASE WHEN b.Bettype IN (901,902,903,904) THEN b.RefNo ELSE 0 END	
			HAVING COUNT(*) > 1
			option (maxdop 4)
			--------------------------------------------------------

			SELECT b.custid, b.odds, b.stake, b.balance, b.status, b.statusID, b.bettype, b.winlostdate, b.username, b.transid as refno, b.transdate as bettime, bt.typenamee as typename 
			FROM bodb02.dbo.bettrans b WITH(NOLOCK)
				INNER JOIN #TempData t ON b.custid = t.custid 
					AND b.odds = t.odds
					AND b.stake = t.stake
					AND ISNULL(b.balance,0) = ISNULL(t.balance,0) 
					AND CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
							 WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
							 ELSE b.bettype END = t.bettype
					AND b.winlostdate = t.winlostdate
					AND b.matchid = t.matchid
					AND b.ip = t.ip
					AND CASE WHEN b.bettype IN (901,902,903,904) THEN b.RefNo ELSE 0 END = CASE WHEN t.bettype IN (901,902,903,904) THEN t.RefNo ELSE 0 END
				INNER JOIN bodb02.dbo.bettype bt with(nolock) on bt.typeid = b.bettype
			WHERE b.custid IN (SELECT DISTINCT custid FROM #TempData)
				AND b.statusID NOT IN (101,102)
				AND b.bettype NOT IN (500) -- exclude 500 - charged commission
			ORDER BY b.custid, b.odds, b.stake, b.balance, b.bettype, b.winlostdate, b.Username, b.transid, b.transdate, b.status, b.statusID

			DROP TABLE #TempData			

	END
	ELSE  ----> Get report from new table
	BEGIN 	

		DECLARE @DateFrom DATETIME
		SELECT @DateFrom = DATEADD(dd, 0, DATEDIFF(dd, 0, @Date) ) -- get begin of the day (just in case param input time also)
		 

		SELECT	b.custid, b.odds, b.stake, b.balance, b.status, b.statusID, b.bettype, b.winlostdate, b.username, b.transid as refno, b.transdate as bettime, bt.typenamee as typename 
		FROM	dbo.DuplicatedTicket t WITH (NOLOCK)	
			INNER JOIN bodb02.dbo.Bettrans b WITH (NOLOCK)	
					ON b.TransID = t.TransID
			INNER JOIN bodb02.dbo.bettype bt WITH (NOLOCK) 
					ON bt.typeid = b.bettype
		WHERE	t.Transdate >= @DateFrom 
			AND t.Transdate < DATEADD(dd, 1, DATEDIFF(dd, 0, @DateFrom))
			AND b.statusID NOT IN (101,102)
			AND b.bettype NOT IN (500) -- exclude 500 - charged commission
		ORDER BY b.custid, b.odds, b.stake, b.balance, b.bettype, b.winlostdate, b.Username, b.transid, b.transdate, b.status, b.statusID 


	END
		
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DuplicatedTicketsSel] TO [bodbAdminNet]
GO
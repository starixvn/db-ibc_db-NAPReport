USE [bodb_report]
GO

ALTER PROCEDURE [dbo].[Task_DuplicatedTicketsCheck]	
AS

/*
	Created: 20150211@Sophia
	Task : Job run to check duplicate tickets on bettrans table and insert the result into DuplicateTicket table to view report later
	DB: DBRPT/bodb_report
	Original: Acc_CheckDuplicateTickets

	Revisions:
		- 20151009@Sophia: group by IP [#45176]
		- 20151021@Sophia: Modify the SPs to only cover the tickets of the following products [#45898] 
						1	Sportsbook [inclusive of : Metric Gaming - Superlive and BetTrade tickets (check the refno)]
						3	Number Game
						4	SLI - Live Casino
						5	Virtual Sports
		- 20170323@Sophia: Fix Parlay issue ( can't detect Parlay ticket if checking RefNo) [Redmine: #73884]
						1	Sportsbook
						2	Number Game
						3	SLI - Live Casino
						4	Virtual Sports
						5   Metric Gaming - Superlive
						6   BetTrade (check the refno)
		- 20170424@Percy: Don't check dummy account of Cash Out [RedmineID: #73419]
		- 20170518@Percy:
			1. New request of Cash Out - Check bettype 911 [RedmineID: #73419]
			2. Remove SLI
	     - 20170704@Tom: Integrate Betradar Virtual Sports(#78495)
		 - 20170828@Kean: Integrate Lucky 3(#82191)
	Param's Explanation:

*/

BEGIN
	SET NOCOUNT ON	

	DECLARE @TransId BIGINT, @MaxTransId BIGINT

	SELECT @TransId = CONVERT(BIGINT,VValue) FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastID'
	SELECT @MaxTransId = MAX(TransId) FROM bodb02.dbo.Bettrans WITH (NOLOCK)
	
	
	------Get Sport Bettype Matrix------
	-- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	DECLARE @bettype TABLE (bettype INT)
	INSERT INTO @bettype (bettype)
	SELECT bettype
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)
	WHERE ProductID IN (1, 3, 5, 25, 26, 27) AND BetType NOT IN (500, 912, 913, 914) 	
	--- End Sport Bettype Matrix------

 	; WITH AllTicket AS(	 
	SELECT  b.custid, 
			b.odds, 
			b.stake, 
			b.balance, 
			b.bettype,
			b.winlostdate, 
			b.matchid,
			b.ip,
			CASE WHEN b.Bettype IN (901,902,903,904) THEN b.RefNo ELSE 0 END as RefNo
	FROM	bodb02.dbo.bettrans b WITH(NOLOCK , Index = PK_bettrans)
		INNER JOIN @bettype s ON s.bettype = b.bettype
	WHERE	b.TransID BETWEEN @TransId - 5000 AND @MaxTransId
			----AND b.bettype < 19000			
			AND b.matchid > 0
			AND b.custid NOT IN (50057, 879241, 103873, 851668, 878902) --betdaq
			AND b.custid NOT IN (1077687) -- Betfair
			AND b.recommend NOT IN (11196380) -- foobet	
			AND b.recommend NOT IN (5707545, 52466) -- exclude members under BARM,8RM
			AND b.currency NOT IN (20, 27, 28)
			AND b.statusID NOT IN (101, 102) 
			AND NOT EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.TradeCust t WITH (NOLOCK) WHERE b.custid = t.custid AND t.VendorID = 14)
	)
	SELECT  b.custid, 
			b.odds, 
			b.stake, 
			b.balance, 
			b.bettype,
			b.winlostdate, 
			b.matchid,
			b.ip,
			b.RefNo		
	INTO	#TempData
	FROM	AllTicket b							
	GROUP BY	b.custid, 
				b.odds, 
				b.stake, 
				b.balance, 
				b.bettype,
				b.winlostdate, 
				b.matchid,
				b.ip,
				b.RefNo
	HAVING COUNT(*) > 1
	 

	--------------------------------------------------------
	INSERT INTO dbo.DuplicatedTicket (transid, transdate, winlostdate)
	SELECT  b.transid, b.transdate, b.winlostdate
	FROM	bodb02.dbo.bettrans b WITH(NOLOCK)
		INNER JOIN #TempData t 
			ON	b.custid = t.custid 
			AND b.odds = t.odds
			AND b.stake = t.stake
			AND ISNULL(b.balance,0) = ISNULL(t.balance,0) 
			AND b.bettype = t.bettype
			AND b.winlostdate = t.winlostdate
			AND b.matchid = t.matchid
			AND b.ip = t.ip
			AND CASE WHEN b.bettype IN (901,902,903,904) THEN b.RefNo ELSE 0 END = CASE WHEN t.bettype IN (901,902,903,904) THEN t.RefNo ELSE 0 END  
	WHERE NOT EXISTS (SELECT 1 FROM dbo.DuplicatedTicket d WITH (NOLOCK) WHERE d.TransID = b.TransId)	
	DROP TABLE #TempData
	
	
	UPDATE bodb02.dbo.SystemSettings WITH (UPDLOCK, ROWLOCK) 
	SET	   VValue = @MaxTransId
	WHERE  VName = 'DuplTicketLastID'

	
	UPDATE bodb02.dbo.SystemSettings WITH (UPDLOCK, ROWLOCK) 
	SET	   VValue = CURRENT_TIMESTAMP
	WHERE  VName = 'DuplTicketLastDate' 
		
END

GO 


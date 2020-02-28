/*<info serverAlias="DBRPT-bodb_report" executers="bodbAdminNet" viewers="vnteam" isFunction="0"></info>*/

USE [bodb_report] 
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DuplicatedTicketsSel]
	@Date DATETIME,
	@CheckTime SMALLINT = 1,
	@TimeToCheckDuplicate SMALLINT = 1
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
	- 20170518@Percy:
		1. New request of Cash Out - Check bettype 911 [RedmineID: #73419]
		2. Remove SLI
	- 20170704@Tom: Integrate Betradar Virtual Sports(#78495)
	- 20170828@Kean: Integrate Lucky 3(#82191)
	- 20180115@Tom:  Cashout tickets from separated original tickets are considered as dupplicated tickets (#89256)
	- 20180706@Tom: Add output transdesc column(#97859)
	- 20181129@Dominic: Check WalletType (HotFix #105532)
	- 20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
	- 20191115@Ned.Le: Adjust duplicate ticket report for new condition (#123663)
Param's Explanation:
	- @CheckTime : The time we consider how long the job fails (Compared the last run with the current time).
				   Because job recurs every 30s, so we set @CheckTime = 1 minute as default
	- @TimeToCheckDuplicate : The total time we use to see if successive tickets are duplicates
	                          The default value is 1s (1000ms)


*/

BEGIN
	SET NOCOUNT ON

	-- #TempDup
	CREATE TABLE #TempDup
	(
		custid INT, 
		odds smallmoney,
		stake MONEY,
		balance MONEY,
		status VARCHAR(500),
		statusID INT,
		bettype INT, 
		Matchid INT, 
		winlostdate SMALLDATETIME,
		username VARCHAR(500),
		refno BIGINT,
		refnoGroup BIGINT,
		bettime DATETIME,
		Typename VARCHAR(500),
		transdesc nvarchar(2000)
	)

	-- Declare effective date
	DECLARE @BalanceEffectiveDate DATETIME = '2020-02-13'

	-- Get the transdate of LastTransID
	DECLARE @LastTransDate DATETIME	
	SELECT @LastTransDate = CONVERT(DATETIME, VValue) FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastDate'
	
	-- If it is more than 1 minute then the job fails and call the code of the old report (SP: Acc_CheckDuplicateTickets)
	IF DATEDIFF(MINUTE, @LastTransDate, CURRENT_TIMESTAMP) > @CheckTime
	BEGIN
		-- #TempBettype
		DECLARE @isTest BIT = 0
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
		
		CREATE TABLE #TempBettype(bettype INT)
		
		INSERT INTO #TempBettype (bettype)
		SELECT DISTINCT bettype
		FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)
		WHERE ProductID IN (1, 3, 5, 25, 26, 27) AND BetType NOT IN (500, 912, 913, 914)
		
		CREATE CLUSTERED INDEX ix_TempBettype ON #TempBettype (bettype)
		
		-- #TempData
		CREATE TABLE #TempData
		(
			custid INT,
			odds smallmoney,
			stake MONEY,
			balance MONEY,
			bettype INT,
			winlostdate SMALLDATETIME,
			matchid INT,
			ip nvarchar(30),
			RefNo BIGINT,
			WalletType SMALLINT
		)
		
		INSERT INTO #TempData (custid,odds,stake,balance,bettype,winlostdate,matchid,ip,RefNo,WalletType)
		SELECT  b.custid, 
				b.odds, 
				b.stake, 
				CASE WHEN b.transdate >= @BalanceEffectiveDate THEN NULL ELSE b.balance END balance,
				CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
					 WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
					 ELSE b.bettype END bettype,
				b.winlostdate, 
				b.matchid,
				b.ip,
				CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END as RefNo,
				ISNULL(CAST(b.WalletType AS SMALLINT),-1)	WalletType
		FROM bodb02.dbo.bettrans b WITH(NOLOCK)
			 INNER JOIN #TempBettype s ON s.bettype = b.bettype
		WHERE b.bettype < 19000
			  and custid not in (50057,879241,103873, 851668, 878902) --betdaq
			  and custid NOT IN (1077687) -- Betfair
			  and recommend not in (11196380) -- foobet
			  and transdate >= @date AND Transdate < DATEADD(dd, 1, @date)
			  and matchid > 0
			  and custid > 0
			  and recommend NOT IN (5707545,52466) -- exclude members under BARM,8RM
			  and currency NOT IN (20, 27, 28)
			  and statusID NOT IN (101,102)
			  and NOT EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.TradeCust t WITH (NOLOCK) WHERE b.custid = t.custid AND t.VendorID = 14)
			  and betfrom <> 'v'
		GROUP BY b.custid, 
				 b.odds, 
				 b.stake, 
				 CASE WHEN b.transdate >= @BalanceEffectiveDate THEN NULL ELSE b.balance END, 
				 CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
				      WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
					  ELSE b.bettype END,
				 b.winlostdate, 
				 b.matchid,
				 b.ip,
				 CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END,	
				 ISNULL(CAST(b.WalletType AS SMALLINT),-1)
		HAVING COUNT(*) > 1
		option (maxdop 4)
		
		CREATE CLUSTERED INDEX ix_TempData ON #TempData (custid,matchid,bettype,RefNo,winlostdate)
		
		-- #TempCust
		CREATE TABLE #TempCust(custid INT)
		
		INSERT INTO #TempCust (custid)
		SELECT DISTINCT custid FROM #TempData
		
		CREATE CLUSTERED INDEX ix_TempCust ON #TempCust (custid)
		
		-- #TempDup
		INSERT INTO #TempDup (custid,odds,stake,balance,status,statusID,bettype,Matchid,winlostdate,username,refno,refnoGroup,bettime,Typename,transdesc)
		SELECT b.custid, b.odds, b.stake, b.balance, b.status, b.statusID, b.bettype, b.Matchid, b.winlostdate, b.username, b.transid as refno,b.refno as refnoGroup, b.transdate as bettime, bt.typenamee as typename, b.transdesc
		FROM bodb02.dbo.bettrans b WITH(NOLOCK)
			 INNER JOIN #TempData t ON b.custid = t.custid 
									   AND b.odds = t.odds
									   AND b.stake = t.stake
									   AND CASE WHEN b.transdate >= @BalanceEffectiveDate THEN 0 ELSE ISNULL(b.balance,0) END = ISNULL(t.balance,0) 
									   AND CASE WHEN b.bettype = 9 OR (b.bettype = 29 AND b.betteam = '1') THEN 9  
												WHEN b.bettype = 29 AND b.betteam <> '1' THEN 29 
												ELSE b.bettype END = t.bettype
									   AND b.winlostdate = t.winlostdate
									   AND b.matchid = t.matchid
									   AND b.ip = t.ip
									   AND CASE WHEN b.bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END = CASE WHEN t.bettype IN (901,902,903,904,911) THEN t.RefNo ELSE 0 END
			 INNER JOIN bodb02.dbo.bettype bt with(nolock) on bt.typeid = b.bettype
		WHERE b.custid IN (SELECT custid FROM #TempCust)
			  AND b.statusID NOT IN (101,102)
			  AND b.bettype NOT IN (500) -- exclude 500 - charged commission
		
		-- Drop temp tables
		DROP TABLE #TempBettype
		DROP TABLE #TempCust
		DROP TABLE #TempData

	END
	-- Get report data from new table
	ELSE
	BEGIN
		
		-- get begin of the day (just in case param input time also)
		DECLARE @DateFrom DATETIME
		SELECT @DateFrom = DATEADD(dd, 0, DATEDIFF(dd, 0, @Date) )
		
		-- #TempDup
		INSERT INTO #TempDup (custid,odds,stake,balance,status,statusID,bettype,Matchid,winlostdate,username,refno,refnoGroup,bettime,Typename,transdesc)
		SELECT b.custid, b.odds, b.stake, b.balance, b.status, b.statusID, b.bettype, b.Matchid, b.winlostdate, b.username, b.transid as refno,b.refno as refnoGroup, b.transdate as bettime, bt.typenamee as typename, b.transdesc
		FROM dbo.DuplicatedTicket t WITH (NOLOCK)	
			 INNER JOIN bodb02.dbo.Bettrans b WITH (NOLOCK)	ON b.TransID = t.TransID
			 INNER JOIN bodb02.dbo.bettype bt WITH (NOLOCK) ON bt.typeid = b.bettype
		WHERE t.Transdate >= @DateFrom AND t.Transdate < DATEADD(dd, 1, DATEDIFF(dd, 0, @DateFrom))
			  AND b.statusID NOT IN (101,102)
			  AND b.bettype NOT IN (500) -- exclude 500 - charged commission

	END
	
	-- Get data for report
	;WITH CTE_CheckDiffTime AS(
		SELECT DISTINCT
			   aa.custid, aa.odds, aa.stake, aa.balance, aa.status, aa.statusID, aa.bettype, aa.Matchid, aa.winlostdate, aa.username, aa.refno, aa.refnoGroup, aa.bettime, aa.typename, aa.transdesc
			   ,CASE WHEN ABS(DATEDIFF(ms,aa.bettime,bb.bettime)) < (@TimeToCheckDuplicate * 1000) THEN 1 ELSE 0 END isMeetConditions
		FROM #TempDup aa
			 LEFT JOIN #TempDup bb ON aa.custid = bb.custid
									  AND aa.odds = bb.odds
									  AND aa.stake = bb.stake
									  AND CASE WHEN aa.bettime >= @BalanceEffectiveDate THEN 0 ELSE ISNULL(aa.balance,0) END = CASE WHEN bb.bettime >= @BalanceEffectiveDate THEN 0 ELSE ISNULL(bb.balance,0) END
									  AND aa.bettype = bb.bettype
									  AND aa.Matchid = bb.Matchid
									  AND aa.winlostdate = bb.winlostdate
									  AND aa.refno <> bb.refno
	)
	SELECT custid, odds, stake, balance, status, statusID, bettype, winlostdate, username, refno, refnoGroup, bettime, typename, transdesc
	FROM CTE_CheckDiffTime
	WHERE isMeetConditions = 1
	ORDER BY custid, odds, stake, bettype, winlostdate, Username, refnoGroup, refno, bettime, status, statusID, balance
	
	-- Drop temp tables
	DROP TABLE #TempDup

END
GO
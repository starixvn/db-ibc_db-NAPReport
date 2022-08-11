/*<info serverAlias="DBRPT-bodb_report" executers="bodbAdminNet" viewers="vnteam" isFunction="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_DuplicatedTicketsSel]
	@Date DATETIME,
	@CheckTime SMALLINT = 2
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
	- 20200518@Ned.Le: Add betteam as a new data duplication checking condition
	                   Exclude ticktes that have betfrom='v'
	- 20210416@Ned.Le: NAP Report - Duplicate Tickets - Exclude refund tickets (#153616)
	- 20211013@Jaden: Change datatype for ipv6 (#162587)
    - 20211209@Ned.Le: NAP Report - Duplicate ticket report cannot be loaded (#165870)
    - 20220110@Ned.Le: NAP Report - Enhance the rule for dectect dup (#167195)
    - 20220321@Ned.Le: NAP Report - Integrate FGG & new bettypes Cricket (#170213)
	- 20220726@Roy: NAP Report - Scale out & new transid (#175707)
	                   
Param's Explanation:
	- @CheckTime : The time we consider how long the job fails (Compared the last run with the current time).
				   Because job recurs every 30s, so we set @CheckTime = 1 minute as default


*/
BEGIN
	SET NOCOUNT ON

	/*---- ** 1. Check the transdate of LastTransID and current time  ** ----
	DECLARE @LastTransDate DATETIME	
	SELECT @LastTransDate = CONVERT(DATETIME, VValue) FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastDate'
	
		----> If it's more than 1 minute then the job fails and call the code of the old report (SP: Acc_CheckDuplicateTickets)
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
		CREATE TABLE #TempData (
			custid INT,
			odds SMALLMONEY,
			stake MONEY,
			balance MONEY,
			bettype INT,
			winlostdate SMALLDATETIME,
			matchid INT,
			ip VARCHAR(45),
			RefNo BIGINT,
			WalletType SMALLINT,
			betteam NVARCHAR(10),
            oddsid INT
		)

		INSERT INTO #TempData (custid,odds,stake,balance,bettype,winlostdate,matchid,ip,RefNo,WalletType,betteam,oddsid)
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
				CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END as RefNo,
				ISNULL(CAST(b.WalletType AS SMALLINT),-1)	WalletType,
				b.betteam,
                b.oddsid
		FROM bodb02.dbo.bettrans b WITH(NOLOCK)
			 INNER JOIN #TempBettype s ON s.bettype = b.bettype
		WHERE b.bettype < 19000							
			and custid not in (50057,879241,103873, 851668, 878902) --betdaq
			and custid NOT IN (1077687) -- Betfair
			and recommend not in (11196380) -- foobet
			AND b.betfrom <> 'v'
			and transdate >= @date AND transdate < DATEADD(dd, 1, @date)
			and custid > 0
			and matchid > 0
			and recommend NOT IN (5707545,52466) -- exclude members under BARM,8RM
			and currency NOT IN (20, 27, 28)
			And statusID NOT IN (101,102,103)
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
				CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END,	
				ISNULL(CAST(b.WalletType AS SMALLINT),-1),
				b.betteam,
                b.oddsid
		HAVING COUNT(*) > 1
		option (maxdop 4)

		CREATE CLUSTERED INDEX ix_TempData ON #TempData (custid,matchid,bettype,RefNo,winlostdate)
		
		-- #TempCust
		CREATE TABLE #TempCust(custid INT)
		
		INSERT INTO #TempCust (custid)
		SELECT DISTINCT custid FROM #TempData
		
		CREATE CLUSTERED INDEX ix_TempCust ON #TempCust (custid)

		-- Select Data
		SELECT b.custid, b.odds, b.stake, b.balance, b.status, b.statusID, b.bettype, b.winlostdate, b.username, b.transid as refno,b.refno as refnoGroup,  b.transdate as bettime, bt.typenamee as typename ,b.transdesc, b.matchid
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
				AND CASE WHEN b.bettype IN (901,902,903,904,911) THEN b.RefNo ELSE 0 END = CASE WHEN t.bettype IN (901,902,903,904,911) THEN t.RefNo ELSE 0 END
				AND t.WalletType = ISNULL(CAST(b.WalletType AS SMALLINT),-1)
				AND b.betteam = t.betteam
                AND b.oddsid = t.oddsid
			INNER JOIN bodb02.dbo.bettype bt with(nolock) on bt.typeid = b.bettype
		WHERE b.custid IN (SELECT custid FROM #TempCust)
			AND b.statusID NOT IN (101,102,103)
			AND b.bettype NOT IN (500) -- exclude 500 - charged commission
		ORDER BY b.custid, b.odds, b.stake, b.balance, b.bettype, b.winlostdate, b.Username,b.refno, b.transid, b.transdate, b.status, b.statusID

		DROP TABLE #TempBettype
		DROP TABLE #TempData
		DROP TABLE #TempCust

	END
	ELSE  ----> Get report from new table*/
	-- BEGIN 	

		DECLARE @DateFrom DATETIME
		SELECT @DateFrom = DATEADD(dd, 0, DATEDIFF(dd, 0, @Date) ) -- get begin of the day (just in case param input time also)
		
		SELECT b.custid
			,b.odds
			,b.stake
			,b.balance
			,b.STATUS
			,b.statusID
			,b.bettype
			,b.winlostdate
			,b.username
			,b.transid AS refno
			,b.refno AS refnoGroup
			,b.transdate AS bettime
			,bt.typenamee AS typename
			,b.transdesc
			,b.matchid
			,b.ip
			,ISNULL(CAST(b.WalletType AS SMALLINT),-1) AS WalletType
			,b.betteam
			,b.oddsid
		FROM	dbo.DuplicatedTicket t WITH (NOLOCK)	
			INNER JOIN bodb02.dbo.Bettrans b WITH (NOLOCK)	
					ON b.TransID = t.TransID
			INNER JOIN bodb02.dbo.bettype bt WITH (NOLOCK) 
					ON bt.typeid = b.bettype
		WHERE	t.Transdate >= @DateFrom 
			AND t.Transdate < DATEADD(dd, 1, DATEDIFF(dd, 0, @DateFrom))
			AND b.statusID NOT IN (101,102,103)
			AND b.bettype NOT IN (500) -- exclude 500 - charged commission
		ORDER BY b.custid, b.odds, b.stake, b.balance, b.bettype, b.winlostdate, b.Username,b.refno, b.transid, b.transdate, b.status, b.statusID
		OPTION (RECOMPILE)

	-- END
END

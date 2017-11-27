/*<info serverAlias="DBBET-BK" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CheckBet_Reject]
	@winlostdate datetime
AS 
/*	
	Created by: Elodie
	Date: 20120816
	Task: Show the difference between data backup and current data of reject ticket in detail
	DB: DBBET/BK	
	Revisions:
		- 20120917@Elodie: enhance performance
		- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20130121@Johnson: move sp from DB052.BODB02 to DBBET.BK
		- 20130225@Elodie: Add Virtual Horse Racing report
		- 20141211@Sophia: change the range of bettypes of Tennis (1301 -> 1399)
		- 20150420@Sophia: Apply Sport Bettype Matrix 
		- 20150724@Sophia: Exclude data of Bettrade [#38815]
		- 20160427@Percy: Support ComboParlay [Redmine: #56572]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
		- 20161206@Percy: Integrate Fast Market [RedmineID: #56803]
		- 20170704@Robert: Integrate Betradar Virtual Sports Product [RedmineID: #78495]
		- 20170828@Robert: Integrate Lucky3 product into NAP Acc Reports [RedmineID: #78214]
		- 20171120@Dominic: Integrate Bullfighting product into NAP Acc Reports [RedmineID: #85382], and bug fix for Metric Gaming
	Param's explanation:		
	
*/
Begin
	SET NOCOUNT ON 	

	----Get Sport Bettype Matrix------
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype(ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))
	INSERT INTO #SportBettype (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, Bettype, EventType, SubProduct 
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)
	
	DELETE	#SportBettype  
	WHERE	SubProduct IN ( 'BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss') 


	CREATE TABLE #tmp(transid BIGINT, bettype INT)
    --insert into #tmp
    INSERT INTO #tmp(transid, bettype)
    SELECT bt.transid, BT.bettype
    FROM bodb02.dbo.bettrans bt WITH (nolock) 
        INNER join dbo.betsReject b WITH (nolock) ON bt.transid=b.transid        
		INNER JOIN #SportBettype s on s.bettype = b.bettype
    WHERE bt.winlostdate=@winlostdate
        and bt.custid<>98632
		and (bt.status<>b.status) 
		and b.currency <> 20
		AND s.productID IN ( 1, 2, 3, 5, 26, 27)	
		AND s.SubProduct NOT IN ('MG-SuperLive')
			
	INSERT INTO #tmp(transid, bettype)
	SELECT b.translogid, b.gameID
	FROM   dbo.BetsReject_Translog AS b(nolock)
           INNER JOIN bodb02.dbo.bettrans AS bt(nolock) ON b.translogid = bt.refno AND bt.matchid = b.eventID
           INNER JOIN #SportBettype AS sb ON sb.Bettype = b.gameID
    WHERE  bt.winlostdate = @winlostdate
			AND bt.custid<>98632
			AND b.currency <> 20
			AND (
				sb.ProductID = 30 --Bullfighting
				OR sb.SubProduct IN ('MG-SuperLive')--Metric
			)
			AND b.status <> bt.status

	CREATE TABLE #Match (matchid int, homeid int, awayid int, matchcode nvarchar(50), EventType TINYINT)
	CREATE UNIQUE CLUSTERED INDEX IX_matchid_type ON #Match(matchid, EventType)
	
	INSERT INTO #Match(matchid, homeid, awayid, matchcode, EventType)
	SELECT	matchid,
			homeid,
			awayid,
			matchcode,
			1 AS EventType
	FROM bodb02.dbo.match with (NOLOCK) where eventdate = @winlostdate

	UNION ALL
	SELECT	Match3rdId,
			homeid,
			awayid,
			MatchNo AS matchcode,
			5 as EventType
	FROM bodb02.dbo.Match3rd with (NOLOCK) where eventdate = @winlostdate
		
	UNION ALL	
	SELECT	orid,
			0 as homeid,
			teamid as awayid,
			matchcode,
			2 as EventType
	FROM bodb02.dbo.outright with (NOLOCK) where eventdate = @winlostdate
	
	UNION ALL	
	SELECT	orid as matchid,
			0 as homeid,
			RacerID as awayid,
			convert(NVARCHAR(50), RacerNum) matchcode,
			3 as EventType
	FROM bodb02.dbo.VSOutright with (NOLOCK) where eventdate = @winlostdate

	-- Support Mix Parlay, System Parlay
	UNION ALL
	SELECT 9 as matchid,
		   0 as homeid,
		   0 as awayid,
		   '' as matchcode,
		   0 as EventType

	UNION ALL
	SELECT 29 as matchid,
		   0 as homeid,
		   0 as awayid,
		   '' as matchcode,
		   0 as EventType
	
	UNION ALL
	SELECT 2799 as matchid,
		   0 as homeid,
		   0 as awayid,
		   '' as matchcode,
		   0 as EventType

	
	--Check ticket of sport book, racing, numbergame, virtual sports but Casino, P2P, Live CS, Bingo
	select  bt.transid, 
			bt.transdate,
			bt.CurrencyName,
			CASE WHEN bt.bettype = 9 OR (bt.bettype = 29 AND bt.betteam = '1') THEN 9  
                                        WHEN bt.bettype = 29 AND bt.betteam <> '1' THEN 29 
                                        ELSE bt.bettype END bettype, 
			bt.Username,
			bt.stake, 			
			bt.odds, 			
			CASE WHEN s.ProductID = 26 THEN bt.transdesc ELSE bt.betteam END betteam, 			
			m.homeid,
			m.awayid,
			m.matchcode,
			bt.liveindicator,
			bt.hdp1,
			bt.hdp2,
			bt.oddstype,
			bt.tpositiontaking, 
			bt.status as NewStatus, 
			b.status as OldStatus,
			c.username as Creator			
	from bodb02.dbo.bettrans bt with (NOLOCK)
		inner join dbo.betsreject b with (nolock) on bt.transid=b.transid
		INNER JOIN #tmp t ON bt.transid = t.transid AND bt.bettype = t.bettype
		inner join bodb02.dbo.custinfo c with (nolock) on bt.creator = c.custid
		INNER JOIN #SportBettype s on s.bettype = b.bettype
		inner JOIN #Match m on b.matchid = m.matchid AND m.EventType = s.EventType
	where b.bettype NOT IN (
			SELECT bettype 
			FROM #SportBettype 
			WHERE (
					(ProductID=5 AND EventType =3) 
					OR ProductID=30
					OR SubProduct IN ('MG-SuperLive')
			)
		)
	--betsReject_Translog
	UNION ALL
	select  bt.refno transid, 
			bt.transdate,
			bt.CurrencyName,
			bt.bettype,
			bt.Username,
			bt.stake, 			
			bt.odds, 			
			bt.betteam, 			
			m.homeid,
			m.awayid,
			m.matchcode,
			bt.liveindicator,
			bt.hdp1,
			bt.hdp2,
			bt.oddstype,
			bt.tpositiontaking, 
			bt.status as NewStatus, 
			b.status as OldStatus,
			c.username as Creator
	from bodb02.dbo.bettrans bt with (NOLOCK)
		inner join dbo.BetsReject_Translog b with (nolock) on bt.refno=b.translogid AND bt.matchid=b.eventID
		INNER JOIN #tmp t ON b.translogid = t.transid AND bt.bettype = t.bettype
		inner join bodb02.dbo.custinfo c with (nolock) on bt.creator = c.custid
		INNER JOIN #SportBettype s on s.bettype = b.gameID
		inner JOIN #Match m on bt.matchid = m.matchid AND m.EventType = s.EventType	
	where s.ProductID=30 OR SubProduct IN ('MG-SuperLive')	
	-- Virtual HR
	UNION ALL
	select  bt.transid, 
			bt.transdate,
			bt.CurrencyName,
			bt.bettype,
			bt.Username,
			bt.stake, 			
			bt.odds, 			
			bt.betteam, 			
			m.homeid,
			m.awayid,
			m.matchcode,
			bt.liveindicator,
			bt.hdp1,
			bt.hdp2,
			bt.oddstype,
			bt.tpositiontaking, 
			bt.status as NewStatus, 
			b.status as OldStatus,
			c.username as Creator
	from bodb02.dbo.bettrans bt with (NOLOCK)
		inner join dbo.betsreject b with (nolock) on bt.transid=b.transid
		INNER JOIN #tmp t ON bt.transid = t.transid AND bt.bettype = t.bettype
		inner join bodb02.dbo.custinfo c with (nolock) on bt.creator = c.custid
		INNER JOIN #SportBettype s on s.bettype = b.bettype
		inner JOIN #Match m on bt.oddsid = m.matchid AND m.EventType = s.EventType	
	where (s.ProductID=5 AND s.EventType =3)
	ORDER BY transid		
	
	DROP TABLE #tmp	 	
END
GO
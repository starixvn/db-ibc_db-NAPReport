/*<info serverAlias="DBBET-BK" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CheckBet_Normal]
	@winlostdate datetime
AS 
/*	
	Created by: Elodie
	Date: 20120816
	Task: Show the difference between data backup and current data of normal ticket in detail
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
	Param's explanation:		
	
*/
BEGIN
	SET NOCOUNT ON 	
 
	----Get Sport Bettype Matrix------
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))
	INSERT INTO @SportBettype (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, Bettype, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)
	
	DELETE	@SportBettype  
	WHERE	SubProduct IN ( 'BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss') 

	CREATE TABLE #tmp(transid BIGINT)
    --insert into #tmp
    INSERT INTO #tmp
    SELECT bt.transid
    FROM bodb02.dbo.bettrans bt WITH (nolock) 
        INNER JOIN dbo.bets b WITH (nolock) ON bt.transid=b.transid        
		INNER JOIN @SportBettype s on s.bettype = b.bettype
    WHERE bt.winlostdate=@winlostdate
            AND bt.currency <> 20
			AND s.productID IN ( 1,2,3,5)
				/*
				and (  					
                    bt.bettype < 31  or bt.bettype between 121 AND 999 or bt.bettype between 1301 AND 1399 --sportbook
                    OR bt.bettype BETWEEN 81 AND 120 --number game                    
                    OR bt.bettype IN (31,32,33,41,42,43) --racing
                    OR bt.bettype BETWEEN 1201 AND 1299 --virtual sports				
                )	
				*/
            AND ((bt.stake<>b.stake OR bt.tpositiontaking<>b.tpositiontaking)
                OR (bt.odds<>b.odds AND s.ProductID <> 2) ----bt.bettype NOT IN (31,32,33,41,42,43))
				OR (bt.betteam<>b.betteam AND bt.bettype NOT IN (SELECT bettype FROM @SportBettype WHERE (ProductID=2) OR (ProductID=5 AND EventType =3)))----bt.bettype NOT IN (31,32,33,41,42,43, 1231,1232,1233,1237,1238))
				OR ((bt.matchid<>b.matchid) AND ((s.ProductID=2) OR (s.ProductID = 1 AND s.EventType = 2)))-----bt.bettype IN (31,32,33,41,42,43,10))
				OR ((bt.oddsid<>b.oddsid) AND (s.ProductID = 5 AND s.EventType = 3))---- bt.bettype IN (1231,1232,1233,1237,1238))
				OR (bt.hdp2<>b.hdp2 AND bt.bettype BETWEEN 221 AND 225) -- Fast Market
                )    
                
	DECLARE @Match TABLE (matchid int, homeid int, awayid int, matchcode nvarchar(50), type varchar(10))
	
	INSERT INTO @Match
	SELECT	matchid,
			homeid,
			awayid,
			matchcode,
			'match' as type
	FROM bodb02.dbo.match with (NOLOCK) where eventdate = @winlostdate
		
	UNION ALL	
	SELECT	orid as matchid,
			0 as homeid,
			teamid as awayid,
			matchcode,
			'outright' as type
	FROM bodb02.dbo.outright with (NOLOCK) where eventdate = @winlostdate
	
	UNION ALL	
	SELECT	orid as matchid,
			0 as homeid,
			RacerID as awayid,
			convert(NVARCHAR(50), RacerNum) matchcode,
			'VSOutright' as type
	FROM bodb02.dbo.VSOutright with (NOLOCK) where eventdate = @winlostdate

	-- Support Mix Parlay, System Parlay
	UNION ALL
	SELECT 9 as matchid,
		   0 as homeid,
		   0 as awayid,
		   '' as matchcode,
		   'match' as type

	UNION ALL
	SELECT 29 as matchid,
		   0 as homeid,
		   0 as awayid,
		   '' as matchcode,
		   'match' as type
		
	--Check ticket of sport book, racing, numbergame, virtual sports but Casino, P2P, Live CS, Bingo	
	select  bt.transid, 
			bt.transdate,
			bt.CurrencyName,
			CASE WHEN bt.bettype = 9 OR (bt.bettype = 29 AND bt.betteam = '1') THEN 9  
                                        WHEN bt.bettype = 29 AND bt.betteam <> '1' THEN 29 
                                        ELSE bt.bettype END bettype,
			bt.Username,
			bt.stake as NewStake, 
			b.stake as OldStake, 
			bt.odds as NewOdds,
			case when (s.ProductID=2) then bt.odds else b.odds end as OldOdds, 			
			bt.betteam as NewBetteam,
			case when (s.ProductID=2) then bt.betteam else b.betteam end as OldBetteam, 
			m1.homeid,
			m1.awayid as NewAwayID,			
			case when ((s.ProductID=2) OR (s.ProductID = 1 AND s.EventType = 2)) then m2.awayid else m1.awayid end as OldAwayID, ---bt.bettype IN (31,32,33,41,42,43,10)		
			m1.matchcode as NewMatchCode,		
			case when ((s.ProductID=2) OR (s.ProductID = 1 AND s.EventType = 2)) then m2.matchcode else m1.matchcode end as OldMatchCode, ---bt.bettype IN (31,32,33,41,42,43,10)
			bt.liveindicator,
			bt.hdp1,
			bt.hdp2 AS NewHdp2,
			b.hdp2 AS OldHdp2,
			bt.oddstype,
			bt.tpositiontaking as NewPT, 
			b.tpositiontaking as OldPT, 
			bt.status, 		
			c.username as Creator
	from bodb02.dbo.bettrans bt with (NOLOCK)
		inner join dbo.bets b WITH (NOLOCK) ON bt.transid = b.transid	
		inner join bodb02.dbo.custinfo c with (nolock) on bt.creator = c.custid		
		inner JOIN @Match m1 on bt.matchid = m1.matchid
		inner JOIN @Match m2 on b.matchid = m2.matchid
		INNER JOIN @SportBettype s on s.bettype = b.bettype
	where bt.transid in (SELECT transid from #tmp)	
		  AND m1.type = CASE WHEN ((s.ProductID=2) OR (s.ProductID = 1 AND s.EventType = 2)) THEN 'outright'  --AND m1.type = CASE  WHEN b.bettype IN (31,32,33,41,42,43,10) THEN 'outright'
		 					ELSE 'match' END
		  AND bt.bettype NOT IN (SELECT bettype FROM @SportBettype WHERE (ProductID=5 AND EventType =3)) --- AND bt.bettype NOT IN (1231,1232,1233,1237,1238)
		
	-- Virtual HR		
	UNION ALL
	select  bt.transid, 
			bt.transdate,
			bt.CurrencyName,
			bt.bettype,
			bt.Username,
			bt.stake as NewStake, 
			b.stake as OldStake, 
			bt.odds as NewOdds,
			b.odds as OldOdds, 			
			bt.betteam as NewBetteam,
			bt.betteam as OldBetteam, -- don't use for HR, just keep same format
			m1.homeid,
			m1.awayid as NewAwayID,			
			m2.awayid as OldAwayID,			
			m1.matchcode as NewMatchCode,		
			m2.matchcode as OldMatchCode,
			bt.liveindicator,
			bt.hdp1,
			bt.hdp2 AS NewHdp2,
			bt.hdp2 AS OldHdp2,
			bt.oddstype,
			bt.tpositiontaking as NewPT, 
			b.tpositiontaking as OldPT, 
			bt.status, 		
			c.username as Creator
	from bodb02.dbo.bettrans bt with (NOLOCK)
		inner join dbo.bets b WITH (NOLOCK) ON bt.transid = b.transid	
		inner join bodb02.dbo.custinfo c with (nolock) on bt.creator = c.custid		
		inner JOIN @Match m1 on bt.oddsid = m1.matchid
		inner JOIN @Match m2 on b.oddsid = m2.matchid
		INNER JOIN @SportBettype s on s.bettype = b.bettype
	where bt.transid in (SELECT transid from #tmp)		
		AND m1.type = 'VSOutright'
		AND (s.ProductID=5 AND s.EventType =3) ---AND bt.bettype IN (1231,1232,1233,1237,1238)
		
	order BY bt.transid
	
	DROP TABLE #tmp
END
GO
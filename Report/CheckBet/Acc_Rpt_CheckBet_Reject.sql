/*<info serverAlias="DBBET-BK" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CheckBet_Reject
	@winlostdate    DATETIME
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
		- 20171120@Dominic: Integrate Bullfighting product into NAP Acc Reports [RedmineID: #85382]
		- 20180316@Franklin: Integrate FM2 [#91341] 
		- 20180814@Robert: - NAP Report - Integrate Poker Games into NAP Report[#97830]
	Param's explanation:		
	
*/

BEGIN
    SET NOCOUNT ON;
/*--Get Sport Bettype Matrix------*/

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);

    CREATE TABLE #SportBettype(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));
    INSERT INTO #SportBettype(ProductID
					   , Bettype
					   , EventType
					   , SubProduct)
		 SELECT ProductID
			 , Bettype
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (0, 0, 0, 2, '', '', @isTest);

    DELETE #SportBettype
    WHERE SubProduct IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'MG-SuperLive');


    CREATE TABLE #tmp(
	    transid    BIGINT
	  , bettype    INT);
/*insert into #tmp*/

    INSERT INTO #tmp(transid
			    , bettype)
		 SELECT bt.transid
			 , BT.bettype
		 FROM bodb02.dbo.bettrans AS bt WITH (nolock)
			INNER JOIN dbo.betsReject AS b WITH (nolock) ON bt.transid = b.transid
			INNER JOIN #SportBettype AS s ON s.bettype = b.bettype
		 WHERE bt.winlostdate = @winlostdate
			  AND bt.custid <> 98632
			  AND bt.status <> b.status
			  AND b.currency <> 20
			  AND s.productID IN(1, 2, 3, 5, 26, 27, 33);

    INSERT INTO #tmp(transid
			    , bettype)
		 SELECT b.translogid
			 , b.gameID
		 FROM dbo.BetsReject_Translog AS b(nolock)
			INNER JOIN bodb02.dbo.bettrans AS bt(nolock) ON b.translogid = bt.refno
												   AND bt.matchid = b.eventID
			INNER JOIN #SportBettype AS sb ON sb.Bettype = b.gameID
		 WHERE bt.winlostdate = @winlostdate
			  AND bt.custid <> 98632
			  AND b.currency <> 20
			  AND sb.ProductID IN(30)
			  AND b.status <> bt.status;

    CREATE TABLE #Match(
	    matchid      INT
	  , homeid       INT
	  , awayid       INT
	  , matchcode    NVARCHAR(50)
	  , EventType    TINYINT);
    CREATE UNIQUE CLUSTERED INDEX IX_matchid_type ON #Match(matchid, EventType);

    INSERT INTO #Match(matchid
				 , homeid
				 , awayid
				 , matchcode
				 , EventType)
		 SELECT matchid
			 , homeid
			 , awayid
			 , matchcode
			 , 1 AS EventType
		 FROM bodb02.dbo.match WITH (NOLOCK)
		 WHERE eventdate = @winlostdate
		 UNION ALL
		 SELECT Match3rdId
			 , homeid
			 , awayid
			 , MatchNo AS matchcode
			 , 5 AS       EventType
		 FROM bodb02.dbo.Match3rd WITH (NOLOCK)
		 WHERE eventdate = @winlostdate
		 UNION ALL
		 SELECT orid
			 , 0 AS      homeid
			 , teamid AS awayid
			 , matchcode
			 , 2 AS      EventType
		 FROM bodb02.dbo.outright WITH (NOLOCK)
		 WHERE eventdate = @winlostdate
		 UNION ALL
		 SELECT orid AS                            matchid
			 , 0 AS                               homeid
			 , RacerID AS                         awayid
			 , CONVERT(NVARCHAR(50), RacerNum) AS matchcode
			 , 3 AS                               EventType
		 FROM bodb02.dbo.VSOutright WITH (NOLOCK)
		 WHERE eventdate = @winlostdate
/* Support Mix Parlay, System Parlay*/
		 UNION ALL
		 SELECT 9 AS  matchid
			 , 0 AS  homeid
			 , 0 AS  awayid
			 , '' AS matchcode
			 , 0 AS  EventType
		 UNION ALL
		 SELECT 29 AS matchid
			 , 0 AS  homeid
			 , 0 AS  awayid
			 , '' AS matchcode
			 , 0 AS  EventType
		 UNION ALL
		 SELECT 2799 AS matchid
			 , 0 AS    homeid
			 , 0 AS    awayid
			 , '' AS   matchcode
			 , 0 AS    EventType;
/*Check ticket of sport book, racing, numbergame, virtual sports but Casino, P2P, Live CS, Bingo*/
    SELECT bt.transid
	    , bt.transdate
	    , bt.CurrencyName
	    , CASE
			WHEN bt.bettype = 9
				OR bt.bettype = 29
				   AND bt.betteam = '1'
			THEN 9
			WHEN bt.bettype = 29
				AND bt.betteam <> '1'
			THEN 29
			ELSE bt.bettype
		 END AS           bettype
	    , bt.Username
	    , bt.stake
	    , bt.odds
	    , CASE
			WHEN s.ProductID = 26
			THEN bt.transdesc
			ELSE bt.betteam
		 END AS           betteam
	    , m.homeid
	    , m.awayid
	    , m.matchcode
	    , bt.liveindicator
	    , bt.hdp1
	    , bt.hdp2
	    , bt.oddstype
	    , bt.tpositiontaking
	    , bt.status AS     NewStatus
	    , b.status AS      OldStatus
	    , c.username AS    Creator
	    , bt.oddsspread AS OddsSpread
    FROM bodb02.dbo.bettrans AS bt WITH (NOLOCK)
	   INNER JOIN dbo.betsreject AS b WITH (nolock) ON bt.transid = b.transid
	   INNER JOIN #tmp AS t ON bt.transid = t.transid
						  AND bt.bettype = t.bettype
	   INNER JOIN bodb02.dbo.custinfo AS c WITH (nolock) ON bt.creator = c.custid
	   INNER JOIN #SportBettype AS s ON s.bettype = b.bettype
	   INNER JOIN #Match AS m ON b.matchid = m.matchid
						    AND m.EventType = s.EventType
    WHERE b.bettype NOT IN
					  (
						 SELECT bettype
						 FROM #SportBettype
						 WHERE ProductID = 5
							  AND EventType = 3
					  )
/*betsReject_Translog*/
    UNION ALL
    SELECT bt.refno AS      transid
	    , bt.transdate
	    , bt.CurrencyName
	    , bt.bettype
	    , bt.Username
	    , bt.stake
	    , bt.odds
	    , bt.betteam
	    , m.homeid
	    , m.awayid
	    , m.matchcode
	    , bt.liveindicator
	    , bt.hdp1
	    , bt.hdp2
	    , bt.oddstype
	    , bt.tpositiontaking
	    , bt.status AS     NewStatus
	    , b.status AS      OldStatus
	    , c.username AS    Creator
	    , bt.oddsspread AS OddsSpread
    FROM bodb02.dbo.bettrans AS bt WITH (NOLOCK)
	   INNER JOIN dbo.BetsReject_Translog AS b WITH (nolock) ON bt.refno = b.translogid
													AND bt.matchid = b.eventID
	   INNER JOIN #tmp AS t ON b.translogid = t.transid
						  AND bt.bettype = t.bettype
	   INNER JOIN bodb02.dbo.custinfo AS c WITH (nolock) ON bt.creator = c.custid
	   INNER JOIN #SportBettype AS s ON s.bettype = b.gameID
	   INNER JOIN #Match AS m ON bt.matchid = m.matchid
						    AND m.EventType = s.EventType
    WHERE s.ProductID = 30
/* Virtual HR*/
    UNION ALL
    SELECT bt.transid
	    , bt.transdate
	    , bt.CurrencyName
	    , bt.bettype
	    , bt.Username
	    , bt.stake
	    , bt.odds
	    , bt.betteam
	    , m.homeid
	    , m.awayid
	    , m.matchcode
	    , bt.liveindicator
	    , bt.hdp1
	    , bt.hdp2
	    , bt.oddstype
	    , bt.tpositiontaking
	    , bt.status AS     NewStatus
	    , b.status AS      OldStatus
	    , c.username AS    Creator
	    , bt.oddsspread AS OddsSpread
    FROM bodb02.dbo.bettrans AS bt WITH (NOLOCK)
	   INNER JOIN dbo.betsreject AS b WITH (nolock) ON bt.transid = b.transid
	   INNER JOIN #tmp AS t ON bt.transid = t.transid
						  AND bt.bettype = t.bettype
	   INNER JOIN bodb02.dbo.custinfo AS c WITH (nolock) ON bt.creator = c.custid
	   INNER JOIN #SportBettype AS s ON s.bettype = b.bettype
	   INNER JOIN #Match AS m ON bt.oddsid = m.matchid
						    AND m.EventType = s.EventType
    WHERE s.ProductID = 5
		AND s.EventType = 3
    ORDER BY transid OPTION(RECOMPILE);

    DROP TABLE #tmp;
END;
GO
/*<info serverAlias="DBBET-BK" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CheckBet_Reject_xtest 
     @winlostdate DATETIME
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
		- 20171110@Robert: NAP Reports - Integrate Bullfighting [RedmindID: #85383]
	Param's explanation:		
	
*/

BEGIN
    SET NOCOUNT ON; 	

    ----Get Sport Bettype Matrix------
    DECLARE 
         @isTest BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);

    CREATE TABLE #SportBettype
    (
         ProductID  INT, 
         Bettype    INT, 
         EventType  INT, 
         SubProduct VARCHAR(500)
    );

    CREATE UNIQUE CLUSTERED INDEX IX_Bettype ON #SportBettype(Bettype);

    INSERT INTO              #SportBettype
                                          (ProductID, 
                                           Bettype, 
                                           EventType, 
                                           SubProduct)
           SELECT ProductID, 
                  Bettype, 
                  EventType, 
                  SubProduct
           FROM   bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);

    DELETE #SportBettype
    WHERE  SubProduct IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss');

    CREATE TABLE #tmp
    (
         transid BIGINT
    );
    --insert into #tmp
    INSERT INTO #tmp
           SELECT bt.refno
           FROM     bodb02.dbo.bettrans bt WITH (nolock)
                    INNER JOIN dbo.betsReject_Translog b WITH (nolock) ON bt.refno = b.translogid
                                                                          AND bt.matchid = b.eventID
                    INNER JOIN #SportBettype s ON s.bettype = b.gameID
           WHERE   bt.winlostdate = @winlostdate
                   AND bt.custid <> 98632
                   AND bt.status <> b.status
                   AND b.currency <> 20
                   AND s.productID IN(1, 2, 3, 5, 26, 27)
           UNION ALL
           SELECT bt.refno
           FROM   bodb02.dbo.bettrans bt WITH (nolock)
                  INNER JOIN dbo.betsReject_Translog b WITH (nolock) ON bt.refno = b.translogid
                                                                        AND bt.matchid = b.eventID
                  INNER JOIN #SportBettype s ON s.bettype = b.gameID
           WHERE  bt.winlostdate = @winlostdate
                  AND bt.custid <> 98632
                  AND bt.status <> b.status
                  AND b.currency <> 20
                  AND s.productID IN(30);

    DECLARE 
         @Match TABLE
    (
         matchid   INT, 
         homeid    INT, 
         awayid    INT, 
         matchcode NVARCHAR(50), 
         type      VARCHAR(10)
    );

    INSERT INTO @Match
           SELECT matchid, 
                  homeid, 
                  awayid, 
                  matchcode, 
                  'match' AS type
           FROM     bodb02.dbo.match WITH (NOLOCK)
           WHERE   eventdate = @winlostdate
           UNION ALL
           SELECT orid, 
                  0 AS          homeid, 
                  teamid AS     awayid, 
                  matchcode, 
                  'outright' AS type
           FROM     bodb02.dbo.outright WITH (NOLOCK)
           WHERE   eventdate = @winlostdate
           UNION ALL
           SELECT orid AS                          matchid, 
                  0 AS                             homeid, 
                  RacerID AS                       awayid, 
                  CONVERT( NVARCHAR(50), RacerNum) matchcode, 
                  'VSOutright' AS                  type
           FROM     bodb02.dbo.VSOutright WITH (NOLOCK)
           WHERE   eventdate = @winlostdate

           -- Support Mix Parlay, System Parlay
           UNION ALL
           SELECT 9 AS       matchid, 
                  0 AS       homeid, 
                  0 AS       awayid, 
                  '' AS      matchcode, 
                  'match' AS type
           UNION ALL
           SELECT 29 AS      matchid, 
                  0 AS       homeid, 
                  0 AS       awayid, 
                  '' AS      matchcode, 
                  'match' AS type
           UNION ALL
           SELECT 2799 AS    matchid, 
                  0 AS       homeid, 
                  0 AS       awayid, 
                  '' AS      matchcode, 
                  'match' AS type
           UNION ALL
           SELECT Match3rdId, 
                  homeid, 
                  awayid, 
                  MatchNo, 
                  'match' AS type
           FROM   bodb02.dbo.Match3rd(nolock)
           WHERE  eventdate = @winlostdate;

	
    --Check ticket of sport book, racing, numbergame, virtual sports but Casino, P2P, Live CS, Bingo
    SELECT bt.transid, 
           bt.transdate, 
           bt.CurrencyName,
           CASE
               WHEN bt.bettype = 9
                    OR bt.bettype = 29
                    AND bt.betteam = '1'
               THEN 9
               WHEN bt.bettype = 29
                    AND bt.betteam <> '1'
               THEN 29
               ELSE bt.bettype
           END           bettype, 
           bt.Username, 
           bt.stake, 
           bt.odds,
           CASE
               WHEN s.ProductID = 26
               THEN bt.transdesc
               ELSE bt.betteam
           END           betteam, 
           m.homeid, 
           m.awayid, 
           m.matchcode, 
           bt.liveindicator, 
           bt.hdp1, 
           bt.hdp2, 
           bt.oddstype, 
           bt.tpositiontaking, 
           bt.status AS  NewStatus, 
           b.status AS   OldStatus, 
           c.username AS Creator
    FROM     bodb02.dbo.bettrans bt WITH (NOLOCK)
             INNER JOIN dbo.betsreject b WITH (nolock) ON bt.transid = b.transid
             INNER JOIN bodb02.dbo.custinfo c WITH (nolock) ON bt.creator = c.custid
             INNER JOIN @Match m ON b.matchid = m.matchid
             INNER JOIN #SportBettype s ON s.bettype = b.bettype
    WHERE   bt.transid IN
    (
        SELECT transid
        FROM   #tmp
    )
            AND m.type = CASE
                             WHEN s.ProductID = 2
                                  OR s.ProductID = 1
                                  AND s.EventType = 2
                             THEN 'outright'  ----- b.bettype IN (31,32,33,41,42,43,10) THEN 'outright'
                             ELSE 'match'
                         END
            AND b.bettype NOT IN
    (
        SELECT bettype
        FROM   #SportBettype
        WHERE  ProductID IN(5, 30)
               AND EventType = 3
    ) 
		
    -- Virtual HR
    UNION ALL
    SELECT bt.transid, 
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
           bt.status AS  NewStatus, 
           b.status AS   OldStatus, 
           c.username AS Creator
    FROM     bodb02.dbo.bettrans bt WITH (NOLOCK)
             INNER JOIN dbo.betsreject b WITH (nolock) ON bt.transid = b.transid
             INNER JOIN bodb02.dbo.custinfo c WITH (nolock) ON bt.creator = c.custid
             INNER JOIN @Match m ON bt.oddsid = m.matchid
             INNER JOIN #SportBettype s ON s.bettype = b.bettype
    WHERE   bt.transid IN
    (
        SELECT transid
        FROM   #tmp
    )
            AND m.type = 'VSOutright'
            AND s.ProductID = 5
            AND s.EventType = 3 

    -- Bullfighting
    UNION ALL
    SELECT bt.refno, 
           bt.transdate, 
           bt.CurrencyName, 
           bt.bettype, 
           bt.Username, 
           bt.stake AS           NewStake, 
           b.stake AS            OldStake, 
           bt.odds AS            NewOdds, 
           b.odds AS             OldOdds, 
           bt.betteam AS         NewBetteam, 
           b.custom3 AS          OldBetteam, 
           m1.homeid, 
           m1.awayid AS          NewAwayID, 
           m2.awayid AS          OldAwayID, 
           m1.matchcode AS       NewMatchCode, 
           m2.matchcode AS       OldMatchCode, 
           bt.liveindicator, 
           bt.hdp1, 
           bt.hdp2 AS            NewHdp2, 
           bt.hdp2 AS            OldHdp2, 
           bt.oddstype, 
           bt.tpositiontaking AS NewPT, 
           b.tpositiontaking AS  OldPT, 
           bt.status, 
           c.username AS         Creator
    FROM   bodb02.dbo.bettrans bt WITH (NOLOCK)
           INNER JOIN dbo.betsReject_Translog b WITH (NOLOCK) ON bt.refno = b.translogid
           INNER JOIN bodb02.dbo.custinfo c WITH (nolock) ON bt.creator = c.custid
           INNER JOIN @Match m1 ON bt.matchid = m1.matchid
           INNER JOIN @Match m2 ON b.eventID = m2.matchid
           INNER JOIN #SportBettype s ON s.bettype = b.gameID
    WHERE  bt.transid IN
    (
        SELECT transid
        FROM   #tmp
    )
           AND m1.type = 'match'
           AND s.ProductID IN(30)
           AND s.EventType = 5
    ORDER BY bt.transid;

    DROP TABLE #tmp;
END;

GO

GRANT VIEW DEFINITION ON dbo.Acc_Rpt_CheckBet_Reject TO [vnteam];
GO

GRANT EXECUTE ON dbo.Acc_Rpt_CheckBet_Reject TO [bodbAdminNet];
GO
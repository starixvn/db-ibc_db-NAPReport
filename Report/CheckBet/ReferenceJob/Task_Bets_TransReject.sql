USE [bk];
GO
ALTER PROCEDURE [dbo].[Task_Bets_TransReject] @transid BIGINT -- no need, will remove after
AS

/*
Created: 
Task:	 
DB: DBBET/BK
Revisions:
	- 20120904@Viet: add new sportsbook and number game bettype		   
	- 20130121@Johnson: move sp from DB052.BODB02 to DBBET/BK
	- 201604015@Percy: fix missed ticket in bet check report [Redmine: #53217]
	- 20170704@Robert: Integrate Betradar Virtual Sports Product [Redmine: #78495]

Param's Explanation:
*/

     BEGIN
         SET NOCOUNT ON;
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         DECLARE @SportBettype TABLE
         (ProductID  INT,
          Bettype    INT,
          EventType  INT,
          SubProduct VARCHAR(500)
         );
         INSERT INTO @SportBettype
         (ProductID,
          Bettype,
          EventType,
          SubProduct
         )
                SELECT ProductID,
                       Bettype,
                       EventType,
                       SubProduct
                FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', 0)
                WHERE ProductID IN(1, 2, 3, 5, 25, 27);
         DELETE @SportBettype
         WHERE SubProduct IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss');
         DECLARE @transID_bt BIGINT;
         SELECT @transID_bt = MIN(transid)
         FROM bodb02.dbo.bettrans(NOLOCK)
         WHERE matchid > 0;
         INSERT INTO dbo.betsreject
                SELECT transid,
                       hdp1,
                       hdp2,
                       odds,
                       stake,
                       STATUS,
                       livehomescore,
                       liveawayscore,
                       liveindicator,
                       betteam,
                       tpositiontaking,
                       matchid,
                       oddsid,
                       ruben,
                       b.bettype,
                       currency,
                       custid,
                       winlostdate
                FROM bodb02.dbo.bettrans b WITH (NOLOCK)
                     INNER JOIN @SportBettype sb ON b.bettype = sb.Bettype
                WHERE NOT EXISTS
                (
                    SELECT transid
                    FROM dbo.betsreject r WITH (NOLOCK)
                    WHERE r.transid = b.transid
                          AND r.transid >= @transID_bt
                )
                      AND statusID IN(101, 102); ----Reject , Void
     END;
GO
GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TransReject] TO [vnteam] AS [dbo];
GO
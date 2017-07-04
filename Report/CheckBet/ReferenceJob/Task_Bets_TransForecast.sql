USE [bk];
GO
ALTER PROCEDURE [dbo].[Task_Bets_TransForecast] @transid BIGINT
AS

/*
	Created: 
	Task:	 
	DB: DBBET/BK
	Revisions:
		- 20120904@Viet: add new sportsbook and number game bettype		   
		- 20130121@Johnson: move sp from DB052.BODB02 to DBBET/BK
		- 20160415@Percy: expand range Sportbook [Redmine: #53217]
		- 20170424@Percy: apply Cash Out [RedmineID: #73419]
		- 20170704@Robert: Integrate Betradar Virtual Sports Product [Redmine: #78495]

	Param's Explanation:
*/

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
     INSERT INTO dbo.bets
     (transid,
      hdp1,
      hdp2,
      odds,
      stake,
      status,
      livehomescore,
      liveawayscore,
      liveindicator,
      betteam,
      tpositiontaking,
      matchid,
      oddsid,
      ruben,
      bettype,
      currency,
      custid,
      winlostdate
     )
            SELECT transid,
                   hdp1,
                   hdp2,
                   odds,
                   CASE
                       WHEN betdaqid <> 0
                            OR ExtraInfo IS NULL
                       THEN stake
                       WHEN ExtraInfo LIKE '%p25%'
                       THEN ISNULL(CAST(('<xml>'+ExtraInfo+'</xml>') AS XML).value('data(/xml/p25/@s)[1]', 'MONEY'), 0)
                       ELSE stake
                   END AS stake,
                   status,
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
            WHERE transid > @transid;
GO
GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TransForecast] TO [vnteam] AS [dbo];
GO
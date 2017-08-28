USE BK;
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Task_Bets_TransReject    Script Date: 8/14/2017 11:01:47 AM ******/
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
	- 20170814@Tom: Enhance performance
	- 20170828@Robert: Integrate Lucky3 product into NAP Acc Reports [RedmineID: #78214]

Param's Explanation:
*/

BEGIN
 SET NOCOUNT ON;
 DECLARE @isTest BIT= 0;
 SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);		 
 
 DECLARE @transID_bt BIGINT;
 
 SELECT @transID_bt = MIN(transid)		 
 FROM bodb02.dbo.bettrans WITH(NOLOCK)
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
			   winlostdate,
			   case when b.bettype = 1600 then transdesc else NULL end as transdesc
		FROM bodb02.dbo.bettrans b WITH (NOLOCK)
		WHERE NOT EXISTS
			(
				SELECT transid
				FROM dbo.betsreject r WITH (NOLOCK)
				WHERE r.transid = b.transid
					  AND r.transid >= @transID_bt
			)
			AND b.statusID IN(101, 102)
			AND b.bettype IN (
				SELECT  Bettype                       
							FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)
							WHERE ProductID IN(1, 2, 3, 5, 25, 26, 27)
							AND SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
				   )
  OPTION (MAXDOP 8);
END;

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TransReject] TO [vnteam]
GO 

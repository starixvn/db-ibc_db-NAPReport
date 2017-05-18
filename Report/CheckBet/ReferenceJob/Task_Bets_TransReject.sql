USE [bk]
GO
ALTER PROCEDURE [dbo].[Task_Bets_TransReject]
	@transid BIGINT -- no need, will remove after
AS
/*
Created: 
Task:	 
DB: DBBET/BK
Revisions:
	- 20120904@Viet: add new sportsbook and number game bettype		   
	- 20130121@Johnson: move sp from DB052.BODB02 to DBBET/BK
	- 201604015@Percy: fix missed ticket in bet check report [Redmine: #53217]

Param's Explanation:
*/ 
BEGIN 
	SET NOCOUNT ON

	DECLARE @transID_bt BIGINT
	SELECT  @transID_bt = MIN(transid) FROM bodb02.dbo.bettrans (NOLOCK) WHERE matchid > 0

	INSERT INTO dbo.betsreject
	SELECT
		transid
		,hdp1
		,hdp2
		,odds
		,stake
		,STATUS
		,livehomescore
		,liveawayscore
		,liveindicator
		,betteam
		,tpositiontaking
		,matchid
		,oddsid
		,ruben
		,bettype
		,currency
		,custid
		,winlostdate
	FROM bodb02.dbo.bettrans b WITH (NOLOCK)		
	WHERE NOT EXISTS (SELECT transid FROM dbo.betsreject r WITH (NOLOCK) WHERE r.transid = b.transid AND r.transid >= @transID_bt)
		AND
		(
			bettype < 50 
			OR bettype BETWEEN 81 AND 999
			OR bettype BETWEEN 1201	AND 1299
			OR bettype BETWEEN 1301 AND 1399  -- Open range of Sportsbook			
		)
		AND statusID IN (101,102) ----Reject , Void
END
GO
GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TransReject] TO [vnteam] AS [dbo]
GO
/*<info serverAlias="DBWH-bodb_dwrs" executers="" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetQueueCnt]
AS
/*
	Created by: Roy
	Date:2024-12-25
	Task: Something about scaling services
	DB: DBACC.bodb02
	
	Revisions:
		20241225@Jaden: Init
*/
BEGIN
    SET NOCOUNT ON;
	
	SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
	
	SELECT CASE WHEN ml.sporttype = 1 THEN 0
				WHEN ml.sporttype > 1 AND ml.SportType < 100 THEN 1
				WHEN ml.sporttype > 99 THEN 2
				ELSE -1 END AS GroupID
		,COUNT(DISTINCT MatchID) AS [Count]
	FROM bodb_Account.dbo.MatchList ml WITH(ROWLOCK) 				  
	WHERE JobGenerated = 1 AND JobFinished = 0
	GROUP BY CASE WHEN ml.sporttype = 1 THEN 0
				WHEN ml.sporttype > 1 AND ml.SportType < 100 THEN 1
				WHEN ml.sporttype > 99 THEN 2
				ELSE -1 END
END

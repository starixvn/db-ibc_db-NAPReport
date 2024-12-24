/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetQueueCnt]
AS

/*
	Created by: Dom
	Date:2014-04-29
	Task: Get Job for Windows service
	DB: DBWH.bodb_dwrs
	
	Revisions:
	   2017.10.02@Tom-Add @GroupSports Parameter Input
		  0: Sportbook-Soccer
		  1: Sportbook-OtherSport
		  2: 3rd Sports
	   20180719@Tom:Enhance_the_flow_get_Virtual_Sport(98520)
	   20210423@Roy: NAP Report - Move Save bet db & service (#153147)
	   20221129@Roy: NAP Report - Save Bet Report out of memory (#180701)
		
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

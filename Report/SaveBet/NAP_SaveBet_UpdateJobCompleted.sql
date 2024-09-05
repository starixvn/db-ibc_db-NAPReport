/*<info serverAlias="DBWH-bodb_dwrs" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_UpdateJobCompleted]
	@MatchID INT
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Mark the match as generated Data for excel file
	DB: DBWH.bodb_dwrs
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
		20240905@Roy: Many Pending MatchIDs (#210349)
*/
BEGIN
	SET NOCOUNT ON
	UPDATE bodb_Account.dbo.MatchList WITH(ROWLOCK,UPDLOCK)
	SET JobFinished = 1
		,EventStatus = 'completed'
	WHERE MatchID = @MatchID
	OPTION (RECOMPILE)
END

/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
*/
BEGIN
	SET NOCOUNT ON
	UPDATE bodb_Account.dbo.MatchList WITH(ROWLOCK,UPDLOCK) SET JobFinished = 1 WHERE MatchID = @MatchID
END

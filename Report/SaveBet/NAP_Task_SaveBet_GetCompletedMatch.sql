USE [bodb_ACC]
GO

ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_GetCompletedMatch]
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Completed match.
	DB: DBACC.bodb_ACC
	
	Revisions:
*/

BEGIN
	
	DECLARE @movebetdate DATETIME
	SELECT  @movebetdate = max(winlostdate) 
    FROM    bodb02.dbo.bettrans14 WITH(NOLOCK)

	INSERT INTO MatchList(MatchID,EventDate,EventStatus,JobFinished,JobGenerated,SportType,LeagueID,MatchCode,HomeID,AwayID)
	SELECT MatchID,EventDate,EventStatus,0,0,sporttype,leagueid,MatchCode,HomeID,AwayID
	FROM bodb02.dbo.match WITH(NOLOCK)
	WHERE matchid NOT IN (select matchlist.MatchID from MatchList WHERE match.eventdate BETWEEN @movebetdate AND GETDATE()) 
		AND eventdate BETWEEN DATEADD(DD,-1,GETDATE()) AND GETDATE()
		AND eventstatus = 'completed'
		AND (
			sporttype < 99
			OR sporttype IN (180,186)
		)
	
END	
GO
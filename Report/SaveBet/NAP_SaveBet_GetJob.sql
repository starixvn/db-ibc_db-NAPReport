/*<info serverAlias="DBACC-bodb_ACC" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_ACC]
GO

ALTER PROCEDURE [dbo].[NAP_SaveBet_GetJob]
	@MatchID INT = 0,
	@GroupSports INT = 0
AS

/*
	Created by: Dom
	Date:2014-04-29
	Task: Get Job for Windows service
	DB: DBACC.BODB_ACC
	
	Revisions:
	   2017.10.02@Tom-Add @GroupSports Parameter Input
		  0: Sportbook-Soccer
		  1: Sportbook-OtherSport
		  2: 3rd Sports
		
*/

BEGIN
    SET NOCOUNT ON;

	IF @matchid =0
		SELECT JobID,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate FROM ServiceJob s WITH(NOLOCK)
		INNER JOIN (
			SELECT TOP 1 ml.EventDate , ml.MatchID
			 FROM MatchList ml WITH(NOLOCK) 				  
				WHERE JobGenerated = 1 AND JobFinished = 0 
				    AND (
					   (@GroupSports = 0 AND (ml.sporttype = 1))
					   OR (@GroupSports = 1 AND ml.sporttype > 1 AND ml.SportType <100)
					   OR (@GroupSports = 2 AND ml.sporttype > 99)
					   ) 
				ORDER BY ml.EventDate ASC
		) ml ON ml.MatchID = s.MatchID
	ELSE
			SELECT JobID,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate FROM ServiceJob s WITH(NOLOCK)
		INNER JOIN (
			SELECT TOP 1 * FROM MatchList ml WITH(NOLOCK) WHERE ml.MatchID = @MatchID
		) ml ON ml.MatchID = s.MatchID


	/*
	SELECT JobID,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate FROM ServiceJob s WITH(NOLOCK)
	INNER JOIN (
		SELECT  * FROM MatchList ml WITH(NOLOCK) WHERE JobGenerated = 1 AND JobFinished = 0 and ml.MatchID=8786329
	) ml ON ml.MatchID = s.MatchID*/
END
GO

USE [bodb_ACC];
GO
ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_GetCompletedMatch]
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Completed match.
	DB: DBACC.bodb_ACC
	
	Revisions:
		- 20170704@Robert: Integrate Betradar Virtual Sports Product [RedmineID: #78495]
*/

     BEGIN
	    SET NOCOUNT ON;

         DECLARE @movebetdate DATETIME, @CurentDate DATETIME;
         SELECT @CurentDate = CONVERT( VARCHAR(10), GETDATE(), 120);
         SELECT @movebetdate = MAX(eventdate)
         FROM bodb02.dbo.match14 WITH (NOLOCK);
         INSERT INTO dbo.MatchList
         (MatchID,
          EventDate,
          EventStatus,
          JobFinished,
          JobGenerated,
          SportType,
          LeagueID,
          MatchCode,
          HomeID,
          AwayID
         )
                SELECT MatchID,
                       EventDate,
                       EventStatus,
                       0,
                       0,
                       sporttype,
                       leagueid,
                       MatchCode,
                       HomeID,
                       AwayID
                FROM bodb02.dbo.match WITH (NOLOCK)
                WHERE matchid NOT IN
                (
                    SELECT matchlist.MatchID
                    FROM MatchList
                    WHERE match.eventdate BETWEEN @movebetdate AND GETDATE()
                )
                      AND eventdate BETWEEN DATEADD(DD, -1, @CurentDate) AND @CurentDate
                      AND eventstatus = 'completed'
                      AND (sporttype < 99
                           OR sporttype IN(180, 186, 190, 191));
     END;
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.NAP_Task_SaveBet_GetCompletedMatch    Script Date: 9/10/2014 3:22:01 PM ******/

CREATE PROCEDURE [dbo].[NAP_Task_SaveBet_GetCompletedMatch]
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Completed match.
	DB: DB06.BODB02
	
	Revisions:
*/

BEGIN
	
	DECLARE @movebetdate DATETIME
	SELECT @movebetdate = max(winlostdate) 
    FROM  bodb02.dbo.bettrans14 WITH(NOLOCK)

	INSERT INTO MatchList(MatchID,EventDate,EventStatus,JobFinished,JobGenerated,SportType,LeagueID,MatchCode,HomeID,AwayID)
	SELECT MatchID,EventDate,EventStatus,0,0,sporttype,leagueid,MatchCode,HomeID,AwayID
	FROM bodb02.dbo.match WITH(NOLOCK)
	WHERE matchid NOT IN (select matchlist.MatchID from MatchList WHERE match.eventdate BETWEEN @movebetdate AND GETDATE()) 
	AND matchid IN(select Distinct matchID from bodb02.dbo.bettrans WITH(NOLOCK))
	--AND eventdate BETWEEN DATEADD(DD,-1,GETDATE()) AND GETDATE()
	AND eventstatus = 'completed'
	AND (sporttype < 99 OR sporttype IN (180,186))
	
END	


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 

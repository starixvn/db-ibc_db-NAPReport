
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.NAP_SaveBet_ListMatchByLeague    Script Date: 9/10/2014 3:22:02 PM ******/
CREATE PROCEDURE [dbo].[NAP_SaveBet_ListMatchByLeague]
	@SportType INT,
	@LeagueID INT = -1,
	@Date DATETIME	
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Matches by leagueid
	DB: DB06.bodb_ACC
	
	Revisions:
*/	
BEGIN
	SELECT ml.MatchID,MatchCode,home.teamname Home, away.teamname away,ml.EventDate,ml.SportType
	FROM MatchList ml WITH(NOLOCK)
	INNER JOIN bodb02.dbo.Team home WITH(NOLOCK) ON home.teamid = ml.HomeID
	INNER JOIN bodb02.dbo.Team away WITH(NOLOCK) ON away.teamid = ml.AwayID
	WHERE ml.sporttype = @SportType
	AND (@LeagueID=-1 OR (ml.LeagueID = @LeagueID))
	AND ml.EventDate = @date
	AND ml.JobFinished=1
	ORDER BY ml.MatchID ASC
END

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[NAP_SaveBet_ListMatchByLeague] TO [bodbAdminNet]
GO 
 GRANT VIEW DEFINITION ON [dbo].[NAP_SaveBet_ListMatchByLeague] TO [vnteam]
GO 

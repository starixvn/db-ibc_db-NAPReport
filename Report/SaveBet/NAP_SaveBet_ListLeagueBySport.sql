
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.NAP_SaveBet_ListLeagueBySport    Script Date: 9/10/2014 3:22:01 PM ******/

CREATE PROCEDURE [dbo].[NAP_SaveBet_ListLeagueBySport]
	@Date DATETIME,
	@SportType INT
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Leagues by sportid
	DB: DB06.bodb_ACC
	
	Revisions:
*/	

SELECT DISTINCT ml.leagueid, l.leaguename
FROM MatchList ml WITH(NOLOCK)
INNER JOIN bodb02.dbo.League l WITH(NOLOCK) ON l.leagueid = ml.LeagueID
WHERE ML.EventDate=@Date
AND ml.sporttype = @SportType
ORDER BY l.leaguename

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[NAP_SaveBet_ListLeagueBySport] TO [bodbAdminNet]
GO 
 GRANT VIEW DEFINITION ON [dbo].[NAP_SaveBet_ListLeagueBySport] TO [vnteam]
GO 

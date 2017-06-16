
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.NAP_SaveBet_ListSportByDate    Script Date: 9/10/2014 3:22:01 PM ******/

CREATE PROCEDURE [dbo].[NAP_SaveBet_ListSportByDate]-- '20140501'
	@Date DATETIME
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Sports by date
	DB: DB06.bodb_ACC
	
	Revisions:
*/	

SELECT DISTINCT ml.SportType,s.SportName 
FROM MatchList ml WITH(NOLOCK) INNER JOIN bodb02.dbo.Sports s WITH(NOLOCK) ON s.sporttype = ml.sporttype
WHERE EventDate=@Date
ORDER BY ml.SportType
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[NAP_SaveBet_ListSportByDate] TO [bodbAdminNet]
GO 
 GRANT VIEW DEFINITION ON [dbo].[NAP_SaveBet_ListSportByDate] TO [vnteam]
GO 

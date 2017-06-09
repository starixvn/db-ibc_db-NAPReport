
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.NAP_SaveBet_UpdateJobCompleted    Script Date: 9/10/2014 3:22:02 PM ******/
CREATE PROCEDURE [dbo].[NAP_SaveBet_UpdateJobCompleted]
	@MatchID INT
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Mark the match as generated Data for excel file
	DB: DB06.BODB02
	
	Revisions:
*/

UPDATE MatchList WITH(ROWLOCK,UPDLOCK) SET JobFinished = 1 WHERE MatchID = @MatchID



GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[NAP_SaveBet_UpdateJobCompleted] TO [bodbAdminNet]
GO 
 GRANT VIEW DEFINITION ON [dbo].[NAP_SaveBet_UpdateJobCompleted] TO [vnteam]
GO 

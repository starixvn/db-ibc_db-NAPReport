USE BK;
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

ALTER PROCEDURE [dbo].[Task_Bets_TranslogForecast] @translogid BIGINT
AS

/*
	Created: Dominic@20171101
	Task: Capture data of newly created tickets in translog #85382	 
	DB: DBBET/BK
	Revisions:

	Param's Explanation:
*/
BEGIN
	 SET NOCOUNT ON;
	
     DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
    
     INSERT INTO [dbo].[bets_Translog]
           ([translogid]
           ,[custid]
           ,[transdate]
           ,[odds]
           ,[stake]
           ,[status]
           ,[tpositiontaking]
           ,[winlostdate]
           ,[currency]
           ,[transdesc]
           ,[productID]
           ,[gameID]
           ,[eventID]
           ,[vendorID]
           ,[GameId3rd]
           ,[TranId3rd]
           ,[custom1]
           ,[custom2]
           ,[custom3]
           ,[LiveIndicator])
    SELECT [translogid]
		  ,[custid]
		  ,[transdate]
		  ,[odds]
		  ,[stake]
		  ,[status]
		  ,[tpositiontaking]
		  ,[winlostdate]
		  ,[currency]
		  ,[transdesc]
		  ,[productID]
		  ,[gameID]
		  ,[eventID]
		  ,[vendorID]
		  ,[GameId3rd]
		  ,[TranId3rd]
		  ,[custom1]
		  ,[custom2]
		  ,[custom3]
		  ,[LiveIndicator]
    FROM bodb02.dbo.translog b WITH (NOLOCK)
    WHERE translogid > @translogid
		AND b.gameID IN (
					SELECT  Bettype                       
					FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)
					WHERE ProductID IN(30)
			)
	OPTION (MAXDOP 8);
END
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TranslogForecast] TO [vnteam]
GO 

set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



ALTER   PROCEDURE [dbo].[Acc_LiveCasinoGetGameType]
AS
/*    
	Created: 20130508@Jim
    Task : Add Game types filter for Live Casino Win Loss report 
    DB  : DB052.bodb02    
     
    Revisions:      
			- 20131030@Jim: return all bettype of live casino
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid 	  AS Bettype,
		typenamee AS GametypeName
	FROM bettype WITH (NOLOCK)
	WHERE 
		typeid BETWEEN 1101 AND 1199
	
END  

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_GamesActiveMember] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_GamesActiveMember] TO [vnteam]
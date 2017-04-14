ALTER PROCEDURE [dbo].[Acc_SporttypeGetVirtualSport]
AS
/*    
 Created : Henry    
 Date : 2012-08-28  
    Task : Get all sport types for virtual sport 
    DB  : DB052.bodb02    
     
    Revisions:      
    
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype,SportName  
	FROM Sports WITH (NOLOCK)  
	WHERE sporttype BETWEEN 180 AND 199
	ORDER BY sporttype ASC 
END  


GO
GRANT EXECUTE ON [dbo].[Acc_SporttypeGetVirtualSport] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_SporttypeGetVirtualSport] TO [vnteam]     
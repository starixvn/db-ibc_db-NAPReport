ALTER PROCEDURE [dbo].[Acc_BetTypeSel_NumberGame]
AS
SET NOCOUNT ON
/*
Created by: Jamie
Date: 2011-10-28
Task : Retrieve NG Bettypes 
DB: DB06.bodb02
Original:

Revisions:

*/
SET NOCOUNT ON
SELECT	b.typeID, b.typenamee 
FROM	bettype b WITH (NOLOCK) 
WHERE	typeid BETWEEN 81 AND 120
ORDER BY b.typeID ASC

GO
GRANT EXECUTE ON [dbo].[Acc_BetTypeSel_NumberGame] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_BetTypeSel_NumberGame] TO [vnteam]
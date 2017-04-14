ALTER procedure [dbo].[Acc_MT_SportTypeSel]
as 
SET NOCOUNT ON
/*
Created: 
Task : Retrieve Customer Setting Sporttypes.
DB: DB052.bodb02
Original:

Revisions:
	- 20091201@Kiwi: Union with CustSetting3rd.

*/

SELECT DISTINCT t.sporttype, s.sportname 
FROM (	SELECT cs.custid, cs.sporttype FROM CustSetting cs WITH (NOLOCK)
		UNION 
		SELECT cs3rd.custid, cs3rd.sporttype FROM CustSetting3rd cs3rd WITH (NOLOCK)
	 ) t
INNER JOIN sports s WITH(NOLOCK) ON t.sporttype = s.sporttype
WHERE t.custid = 73104
ORDER BY t.sporttype


GO
GRANT EXECUTE ON [dbo].[Acc_MT_SportTypeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_MT_BetTypeSel] TO [vnteam]
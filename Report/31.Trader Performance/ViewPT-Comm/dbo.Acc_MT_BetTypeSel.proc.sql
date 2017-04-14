ALTER procedure [dbo].[Acc_MT_BetTypeSel]
	@Sporttype int = null
as 
SET NOCOUNT ON
/*
Created: 
Task : Retrieve Customer Setting Bet types.
DB: DB052.bodb02
Original:

Revisions:
	- 20091201@Kiwi: Union with CustSetting3rd.

*/

SELECT DISTINCT t.bettype, b.typenamee 
FROM (	SELECT cs.custid, cs.bettype, cs.sporttype FROM CustSetting cs WITH (NOLOCK)
		UNION 
		SELECT cs3rd.custid, cs3rd.bettype, cs3rd.sporttype FROM CustSetting3rd cs3rd WITH (NOLOCK)
	 ) t
INNER JOIN bettype b WITH (NOLOCK) ON t.bettype=b.typeid
WHERE t.custid = 73104 AND t.sporttype=ISNULL(@sporttype,t.sporttype)
ORDER BY t.bettype


GO
GRANT EXECUTE ON [dbo].[Acc_MT_BetTypeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_MT_BetTypeSel] TO [vnteam]
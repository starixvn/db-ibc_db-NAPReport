CREATE PROCEDURE [dbo].[Acc_Rpt_WinlostNG_Details14]
	@winlostdate	datetime
AS 
	/*	Creator: Henry
		Date: 2010-10-05
		Task: Report 2A for Number Game 
		DB:  DB06 
		Original: 
	
		Revisions:
			

		Explanation's Param:

	*/
	SET NOCOUNT ON

	SELECT	bettype,
			currency,
			currencyName,
			isnull(sum(actual_stake * bettrans.actualrate),0) Turnover,
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum(scomm*bettrans.actualrate),0) comm,
			isnull(sum(scomm*bettrans.virtualrate),0) VirtualComm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal	,		
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.virtualrate),0) as VirtualLineTotal
	FROM	bettrans14 bettrans with (NOLOCK) 
	WHERE	winlostdate = @winlostdate 
			AND ruben = 1 
			AND bettrans.bettype IN (81,82,83,84,85,86,87)
			AND bettrans.matchid > 0  
			--and status NOT in ('done','VOID','REJECT','REFUND')
			and statusID NOT in (101,102,103,121)
	GROUP BY bettype, currency, currencyName 
	ORDER BY bettype, currency

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostNG_Details14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostNG_Details14] TO [VNTeam]
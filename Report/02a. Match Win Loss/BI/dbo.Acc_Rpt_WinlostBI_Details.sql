CREATE PROCEDURE [dbo].[Acc_Rpt_WinlostBI_Details]
	@winlostdate	datetime
AS 
	/*	Creator: Henry
		Date: 2009-09-16
		Task: Report 2A for Bingo 
		DB: DB02, DB06 
		Original: 
	
		Revisions:
		- 20130705@Kathy: Update matchid for Bingo (73)	

		Explanation's Param:

	*/
	SET NOCOUNT ON

	SELECT	bettype,
			currency,
			currencyName,
			isnull(sum(actual_stake * bettrans.actualrate),0) Turnover,
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum( scomm*bettrans.actualrate),0) comm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal			
	FROM	bettrans with (NOLOCK) 
	WHERE	winlostdate = @winlostdate 
			AND ruben = 1 
			AND bettrans.bettype = 73
			AND bettrans.matchid in (0, 73) 
			--AND status NOT in ('VOID','REJECT','done')
			AND statusID NOT IN (101,102,121)
	GROUP BY bettype, currency, currencyName 
	ORDER BY bettype, currency

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostBI_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostBI_Details] TO [VNTeam]
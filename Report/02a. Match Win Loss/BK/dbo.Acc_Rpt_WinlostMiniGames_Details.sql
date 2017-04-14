ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostMiniGames_Details]
	@winlostdate	datetime
AS 
	/*	Creator: Daniel
		Date: 2010-03-26
		Task: Report 2A for Casino 
		DB: DB02, DB06 
		Original: Acc_Rpt_WinlostCA_Details
	
		History:
			- 20100326@Daniel: Added
		Explanation's Param:

	*/
	SET NOCOUNT ON

	SELECT	currency,
			isnull(sum(actual_stake * bettrans.actualrate),0) Turnover,
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum( scomm*bettrans.actualrate),0) comm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal			
	FROM	bettrans with (NOLOCK) 
	WHERE	winlostdate = @winlostdate 
			AND ruben = 1 
			AND bettrans.bettype = 73
			AND bettrans.matchid =0
			AND status NOT in ('VOID','REJECT','done')
	GROUP BY currency, currencyName 
	ORDER BY currency

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostMiniGames_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostMiniGames_Details] TO [VNTeam]
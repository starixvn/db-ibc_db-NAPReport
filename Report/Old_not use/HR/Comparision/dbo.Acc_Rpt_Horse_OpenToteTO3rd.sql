ALTER PROCEDURE [dbo].[Acc_Rpt_Horse_OpenToteTO3rd]
(
	@winlostdate	DATETIME
)
AS
/*	Created by: Jamie
	Date: 2010-06-08
	Task: 3rd Turnover and Dividend Comparision
	DB: DBACC/BODB_ACC
	
	Revisions:
		- 20130224@Lukas: move SP to new database bodb_ACC

*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency currencyName, SUM(cost) TO3rd, SUM(payout) DividendWon3rd 
	FROM	dbo.Acc_HorseTransaction3rd WITH (NOLOCK)
	WHERE	winlostdate = @winlostdate 
			AND status = 'SUCCESS' 
			AND has_refund = 'N' 
			AND cancelled ='N'
	GROUP BY currency 
END



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Horse_OpenToteTO3rd] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Horse_OpenToteTO3rd] TO [vnteam]
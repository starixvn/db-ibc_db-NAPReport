CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_12Bet_SelCurrency]
AS
/*	Created by: Henry
	Date: 2009-12-03
	Task: Getting currency list for 12BET Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('12Bet')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_12Bet_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_12Bet_SelCurrency] TO [vnteam]

ALTER PROCEDURE [dbo].[Acc_Rpt_Winloss_ALog_SelCurrency]
AS
/*	Created by: Henry
	Date: 2010-06-29
	Task: Getting currency list for Asian Logic Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('ALog')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_ALog_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_ALog_SelCurrency] TO [vnteam]

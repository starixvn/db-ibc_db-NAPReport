 CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Zzun88_SelCurrency]
AS
/*	Created by: Johnson
	Date: 2011-01-21
	Task: Getting currency list for Zzun88 Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('Zzun88')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Zzun88_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Zzun88_SelCurrency] TO [vnteam]

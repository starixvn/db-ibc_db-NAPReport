CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_AB88_SelCurrency]
AS
/*	Created by: Henry
	Date: 2009-11-27
	Task: Getting currency list for AB88 Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('asiabet88')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_AB88_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_AB88_SelCurrency] TO [vnteam]

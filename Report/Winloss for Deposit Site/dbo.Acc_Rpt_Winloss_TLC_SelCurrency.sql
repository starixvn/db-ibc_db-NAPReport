CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_TLC_SelCurrency]
AS
/*
	Created: Henry
	Date: 2010-11-18
	Task: Getting currency list for TLC Report Winloss
	DB: DB052.BODB02
*/
BEGIN
	SET NOCOUNT ON
	SELECT currency, custid FROM dbo.f_DepSuperByCurrency('TLC')
	ORDER BY currency
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_TLC_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_TLC_SelCurrency] TO [vnteam]
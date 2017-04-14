CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Spondemo_SelCurrency]
AS
/*
	Created: Johnson
	Date: 2010-11-13
	Task: Getting currency list for Spondemo Report Winloss
	DB: DB052.BODB02
*/
BEGIN
	SET NOCOUNT ON
	SELECT currency, custid FROM dbo.f_DepSuperByCurrency('Spondemo')
	ORDER BY currency
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Spondemo_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Spondemo_SelCurrency] TO [vnteam]
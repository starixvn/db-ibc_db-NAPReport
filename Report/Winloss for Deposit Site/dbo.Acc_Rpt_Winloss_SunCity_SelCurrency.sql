  CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_SunCity_SelCurrency]
AS
/*	Created by: Johnson
	Date: 2011-01-21
	Task: Getting currency list for SunCity Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('SunCity')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_SunCity_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_SunCity_SelCurrency] TO [vnteam]

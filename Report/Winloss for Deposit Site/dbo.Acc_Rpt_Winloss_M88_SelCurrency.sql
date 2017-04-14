ALTER PROCEDURE [dbo].[Acc_Rpt_Winloss_M88_SelCurrency]
AS
/*	Created by: Jamie
	Date: 2009-10-30
	Task: Getting currency list for M88 Winloss Report
	DB: DB052.bodb02
*/
BEGIN
	SET NOCOUNT ON
	SELECT	currency, custid 
	FROM	dbo.f_DepSuperByCurrency('Mansion88')
	ORDER BY currency 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_M88_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_M88_SelCurrency] TO [vnteam]

CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Dela_SelCurrency]  
AS  
/* Created by: Henry  
 Date: 2010-11-11  
 Task: Getting currency list for DELA Winloss Report  
 DB: DB052.bodb02  
*/  
BEGIN  
 SET NOCOUNT ON  
 SELECT currency, custid   
 FROM dbo.f_DepSuperByCurrency('DELA')  
 ORDER BY currency   
END  
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Dela_SelCurrency] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Dela_SelCurrency] TO [vnteam]

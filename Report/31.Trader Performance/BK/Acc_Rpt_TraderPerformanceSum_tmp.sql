
/****** Object:  Stored Procedure dbo.Acc_Rpt_TraderPerformanceSum    Script Date: 3/7/2011 4:02:13 PM ******/  
  
ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceSum_tmp]  
 @fromdate datetime,  
 @todate datetime,  
 @isSoccer bit =1  
AS  
  
/*  
Created: 2011-06-13
Task : This Sp temporary use to get data from bodb_Archive.dbo.bettrans_bk
DB: DB06.bodb02  
Original:  
*/  
  
SET NOCOUNT ON  
  
SELECT * FROM tmpTrader_SUm WITH (nolock)
WHERE date BETWEEN @fromdate AND @todate
  

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TraderPerformanceSum_tmp] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TraderPerformanceSum_tmp] TO [vnteam]
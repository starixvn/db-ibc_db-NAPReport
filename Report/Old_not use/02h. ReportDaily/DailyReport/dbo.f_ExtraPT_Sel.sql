USE [bodb02]
GO
/****** Object:  UserDefinedFunction [dbo].[f_ExtraPT_Sel]    Script Date: 03/11/2016 13:21:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER FUNCTION [dbo].[f_ExtraPT_Sel]  
( @ProductID INT = 0,  
 @Sporttype INT = 0,  
 @SubProduct VARCHAR(500) = '',  
 @Date DATETIME   
)  
RETURNS TABLE   
AS  
/*  
Creator: Jim  
Date: 20160309   
Task: Daily Winloss Report/ExtraPT  [#53194]  
DB: DBACC/bodb02   
*/  
RETURN  
(  
 WITH cte_tmp  
  AS  
 (SELECT   ProductID,  SportType,GroupName, e.SubProduct, e.SuperId, SUM(e.ExtraPT) ExtraPT, MIN(e.FromDate)FromDate, MIN(e.ToDate)ToDate  
 FROM bodb_ACC.dbo.Acc_GroupExtraPTSetting e WITH(NOLOCK)  
 WHERE  (@Date BETWEEN e.FromDate AND e.ToDate )  AND   
     (@ProductID = 0 OR e.ProductID = @ProductID) AND   
     (@Sporttype = 0 OR e.Sporttype = @Sporttype) AND  
     ((@SubProduct = '' OR e.SubProduct = @SubProduct))  
     AND e.GroupName <>'BC'  
 GROUP BY  
   ProductID,  SportType,GroupName, e.SubProduct, e.SuperId
 )  
 ,cte_tmpBC  
 AS  
 (  
 SELECT e.ProductID, e.SportType,e.GroupName, e.SubProduct, e.SuperId, e.ExtraPT, e.FromDate, e.ToDate  
 FROM bodb_ACC.dbo.Acc_GroupExtraPTSetting e WITH(NOLOCK)  
 WHERE  (@Date BETWEEN e.FromDate AND e.ToDate )  AND   
     (@ProductID = 0 OR e.ProductID = @ProductID) AND   
     (@Sporttype = 0 OR e.Sporttype = @Sporttype) AND  
     ((@SubProduct = '' OR e.SubProduct = @SubProduct))  
     AND e.GroupName ='BC'  
 )   
   
 SELECT  a.ProductID, a.SportType, a.SubProduct, a.SuperId,  
   CASE WHEN a.GroupName IN ('ACCTHAI2','ACCTHAI56','ACCTHAI99') AND ISNULL(b.SuperId,0) <> 0 THEN a.ExtraPT+b.ExtraPT ELSE a.ExtraPT END ExtraPT,  
   a.FromDate, a.ToDate  
 FROM cte_tmp a  
  LEFT JOIN cte_tmpBC b ON a.ProductId= b.ProductID  
        AND a.SportType = b.SportType  
        AND a.SubProduct = b.SubProduct  
        AND a.SuperId = b.SuperId  
        AND a.FromDate = b.FromDate  
        AND a.ToDate = b.ToDate  
   
)  
GO 
 GRANT VIEW DEFINITION ON [dbo].[f_ExtraPT_Sel] TO [vnteam]
GO 
 GRANT SELECT ON [dbo].[f_ExtraPT_Sel] TO [bodbAdminNet]
GO
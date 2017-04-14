USE [bodb_CustomerLog]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Company_History]    Script Date: 04/16/2010 14:12:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Company_History]
	@BalanceUpDay SMALLDATETIME = NULL
AS
SET NOCOUNT ON
/*
Task: Check company balance chage after balance up due to Exrate Updated.
DB: DB05.bodb_CustomerLog
Revisions:
*/
IF @BalanceUpDay IS NULL
	SELECT TOP 100
		DATEADD(DAY,1,BalanceUpDay) BalanceUpDay, 
		SUM(CompBalBefore) CompBalBefore, SUM(CompBalAfter) CompBalAfter,
		SUM(CompBalBefore) - SUM(CompBalAfter) AS DIFFERENCE
	FROM dbo.CompanyBalance_History h (NOLOCK)
	GROUP BY BalanceUpDay
	ORDER BY BalanceUpDay DESC
ELSE
	SELECT 
		@BalanceUpDay BalanceUpDay, 
		SUM(CompBalBefore) CompBalBefore, SUM(CompBalAfter) CompBalAfter,
		SUM(CompBalBefore) - SUM(CompBalAfter) AS DIFFERENCE
	FROM dbo.CompanyBalance_History h (NOLOCK)
	WHERE DATEADD(DAY,-1,@BalanceUpDay) = BalanceUpDay  
	GROUP BY BalanceUpDay
	ORDER BY BalanceUpDay DESC


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Company_History] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Company_History] TO [vnteam]

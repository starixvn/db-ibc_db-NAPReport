/*<info serverAlias="DBSUM-bodb_Summary" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Summary]
GO

CREATE PROCEDURE [dbo].[Acc_Rpt_Balance_Company_History]
	@BalanceUpDay SMALLDATETIME = NULL
AS

/*
	Creator: Ned.Le
	Date: 2020-09-14
	Task: Check company balance chage after balance up due to Exrate Updated.
	DB: DBSUM.bodb_Summary
	Revisions:
		20200914@Ned.Le: Migrate Log DBs from DB052 to DB054 (Phase 1) (#140783)
*/

BEGIN
	
	SET NOCOUNT ON

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

END
GO

/*<info serverAlias="DBMA-bodb_Maintenance" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
/*
	Creator:	20251111@Robert
	Task:	Fail Safe System Control [#244040]

	Database:	DBMA.bodb_Maintenance
	
	Revisions:
		- 20251111@Robert-Fail Safe System Control [#244040]
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/
CREATE PROC [dbo].[FailSafeSystemControl_SelectCurrent]
AS
BEGIN
	SET NOCOUNT ON;

	SELECT TOP 1 f.Id,
		f.UserId,
		f.UserName,
		f.ActionDate,
		f.IsAutoDisableProduct,
		f.Description
	FROM FailSafeSystemControl f(NOLOCK)
	ORDER BY f.Id DESC
END
GO



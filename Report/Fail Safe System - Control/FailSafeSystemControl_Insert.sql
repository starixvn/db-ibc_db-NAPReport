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
CREATE PROC [dbo].[FailSafeSystemControl_Insert] @UserId INT,
	@UserName VARCHAR(30),
	@IsAutoDisableProduct BIT,
	@Description VARCHAR(200)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ActionDate DATETIME = GETDATE();

	INSERT INTO [dbo].[FailSafeSystemControl] (
		UserId,
		UserName,
		ActionDate,
		IsAutoDisableProduct,
		Description
		)
	VALUES (
		@UserId,
		@UserName,
		@ActionDate,
		@IsAutoDisableProduct,
		@Description
		);
END
GO



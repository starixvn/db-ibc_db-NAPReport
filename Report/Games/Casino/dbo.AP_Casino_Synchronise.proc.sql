Alter PROCEDURE [dbo].[AP_Casino_Synchronise]
	@Keyword nvarchar(50),	
	@RoleID tinyint = null,
	@ErrCode		varchar(5)	= '' OUTPUT,	--Return ErrCode
	@ErrMsg			nvarchar(500)= '' OUTPUT	--Return Exception Message
AS
--Original: SP Casino Synchronised List
--UPDATED : 03/19/2009@Tuan 
--Task:	Get Casino synchronised List.

SET NOCOUNT ON

BEGIN TRY

	--Get data 
	Declare @CustID int

	-- Check Username exist on Casino DB and synchronised.
	Select @CustID = CustID
	FROM Customer with (NOLOCK)
	Where username = @Keyword and IBCCustID is not null
	
	-- Get Synchronised List for every level.
	SELECT	IBCCustID CustID, UserName, EnableCasino
	FROM Customer with (NOLOCK)
	WHERE	(CustID=@CustID or SAgentID=@CustID or MAgentID=@CustID or AgentID=@CustID)
			AND (RoleID = @RoleID)
			AND IBCCustID is not null

END TRY

BEGIN CATCH
	SELECT @ErrCode = 'E0004'
	SELECT @ErrMsg = left(Convert(varchar, ERROR_NUMBER()) + ' ' + ERROR_PROCEDURE() + ' ' + Convert(varchar, ERROR_LINE()) + ' ' + ERROR_MESSAGE(),500)
END CATCH


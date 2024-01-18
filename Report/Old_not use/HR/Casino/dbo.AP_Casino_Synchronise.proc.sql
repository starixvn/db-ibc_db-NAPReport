Alter PROCEDURE [dbo].[AP_Casino_Synchronise]
	@Keyword nvarchar(50) = '',
	@IBCSCustID int = null,		
	@IBCMCustID int = null,		
	@IBCACustID int = null,		
	@RoleID tinyint = null,
	@ErrCode		varchar(5)	= '' OUTPUT,	--Return ErrCode
	@ErrMsg			nvarchar(500)= '' OUTPUT	--Return Exception Message
AS
--Original: SP Casino Synchronised List
--UPDATED : 03/19/2009@Tuan 
--Task:	Get Super List synchronised.

SET NOCOUNT ON

BEGIN TRY

	--Get data 
	SELECT	CST.IBCCustID CustID, CST.UserName, CST.EnableCasino
	FROM Customer CST with (NOLOCK)
	WHERE	(@IBCSCustID IS NULL OR CST.SAgentID IN (SELECT CustID FROM Customer WITH (NOLOCK) WHERE IBCCustID = @IBCSCustID))
			AND (@IBCMCustID IS NULL OR CST.MAgentID IN (SELECT CustID FROM Customer WITH (NOLOCK) WHERE IBCCustID = @IBCMCustID))
			AND (@IBCACustID IS NULL OR CST.AgentID IN (SELECT CustID FROM Customer WITH (NOLOCK) WHERE IBCCustID = @IBCACustID))
			AND (@RoleID IS NULL OR CST.RoleID = @RoleID)
			AND IBCCustID is not null

END TRY

BEGIN CATCH
	SELECT @ErrCode = 'E0004'
	SELECT @ErrMsg = left(Convert(varchar, ERROR_NUMBER()) + ' ' + ERROR_PROCEDURE() + ' ' + Convert(varchar, ERROR_LINE()) + ' ' + ERROR_MESSAGE(),500)
END CATCH


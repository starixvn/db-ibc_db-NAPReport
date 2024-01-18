Alter PROCEDURE [dbo].[Acc_CustomerSyncUpd]
	@UserID int,
	@custid int,
	@ErrCode int = 0 OUTPUT,
	@ErrMsg nvarchar(200) = '' OUTPUT
AS
/*	Created by: Simon
	Date: 2009-07-04
	DB: DB0?.BODB02
	Task: Update SyncCasino = 1 belong @custid.	
*/

SET NOCOUNT ON

--Check permission for account site: @phuc20080213
EXEC db03.bodb02.dbo.Acc_Con_CheckPermission @custid=@UserID,@funcname='[Customer]',@ErrCode=@ErrCode output,@ErrMsg=@ErrMsg output
If @ErrCode <> 0
	RETURN
--end

if exists (select 1 from custinfo (NOLOCK) where custid = @CustID)
BEGIN
	Update custinfo with (ROWLOCK)
	set SyncCasino = 1
	where custid = @custid
END
else
BEGIN	
	Select @ErrMsg = 'Invalid user!!',
		@ErrCode = 101	
	return	
END
		
declare @LogData nvarchar(200),@LogSPData varchar(5000)
Select @LogData = 'Update SyncCasino = 1 in Custinfo Table with CustID: ' + cast(@custid as varchar(10)) 
EXEC WriteLog_UserLog @UserID = @UserID, @Doing = @LogData

Select @LogSPData = 'CustID='+ coalesce(cast(@CustID as varchar(50)),space(1)) + ',
UserID='+ coalesce(cast(@UserID as varchar(50)),space(1)) + ',
SyncCasino=1'+ ',
ErrCode='+ coalesce(cast(@ErrCode as varchar(50)),space(1)) + ' O,
ErrMsg='+ coalesce(cast(@ErrMsg as varchar(400)),space(1))+' O
'

EXEC DB06.bodb02.dbo.WriteLog_UserLog_RunSP 
	@UserID = @UserID,
	@CustID = @CustID,
	@SpName = 'Acc_CustomerSyncUpd',
	@Doing = @LogSPData
			
GO
GRANT EXECUTE ON [dbo].[Acc_CustomerSyncUpd] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_CustomerSyncUpd] TO [vnteam]
ALTER PROCEDURE [dbo].[Acc_BalanceNegativeUpd_StatusID]
  @LogIDs	VARCHAR(8000)
 ,@ErrCode	INT = 0 OUTPUT
 ,@ErrMsg	VARCHAR(1000) = '' OUTPUT  

AS
/*
	Created by: Jamie
	Date: 2013-06-26
	Task: Retrieve Negative Balance by Site 
	DB: DBTXN/bodb02 
	
	Revision: 
	
	Param's Explanation:
		+ @LogIDs : '1,2,3,xxx' with xxx: LogID already notified 
	
*/
BEGIN 
	SET NOCOUNT ON 
	UPDATE	BalanceNegativeHistory WITH (UPDLOCK,ROWLOCK)
	SET		StatusID = 1
	WHERE	LogID IN (SELECT val FROM dbo.strSplit(@LogIDs,','))
		
	IF @@ERROR  <> 0
	BEGIN
		SELECT	 @ErrCode	= 101
				,@ErrMsg	= 'Update Status unsuccessfully!'	
		RETURN
	END	
END 
GO 
GRANT EXECUTE ON [dbo].[Acc_BalanceNegativeUpd_StatusID] TO [bodbAdminNet]
GO 

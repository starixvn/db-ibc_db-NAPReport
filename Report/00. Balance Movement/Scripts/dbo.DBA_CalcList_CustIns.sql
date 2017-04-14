ALTER PROCEDURE [dbo].[DBA_CalcList_CustIns]
	@custid			INT,
	@winlostdate	DATETIME,
	@roleid			INT = 4
AS
/*	Created: Jamie
	Date: 2009-09-23
	Task: Generate test data for the list of customers need to be updated the balance 
	DB: DBACC/BODB_ACC
	
	Revisions: 
		- 20130224@Lukas: move table CalcList_Customer to new database bodb_ACC
*/
BEGIN
	SET NOCOUNT ON
	INSERT INTO dbo.CalcList_Customer( winlostdate, custid, roleid, addTime)
	VALUES( @winlostdate, @custid, @roleid, GETDATE())
END

GO
GRANT VIEW DEFINITION ON [dbo].[DBA_CalcList_CustIns] TO [vnteam]
GO
GRANT EXECUTE ON [dbo].[DBA_CalcList_CustIns] TO [vnteam]
GO

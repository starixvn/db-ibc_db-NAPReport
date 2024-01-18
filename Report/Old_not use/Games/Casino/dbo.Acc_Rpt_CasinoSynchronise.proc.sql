ALTER PROCEDURE [dbo].[Acc_Rpt_CasinoSynchronise]
	@Keyword	NVARCHAR(20)	= '',
	@SearchBy	BIT,	 -- 0: Casino  ;  1: IBC.
	@RoleID		TINYINT			= 0 OUTPUT
AS
/*	Created by: Anh Tuan
	Date: 2009-03-25
	DB: DBCUST.CustDB
	Task: Get Casino unSynchronised List.
	Revisions:
		- 20150610@Kos: Separate CustDB to DBCUST server (Move SP to DBCUST.CustDB)
*/

SET NOCOUNT ON

DECLARE @CustID INT

SELECT 
	@CustID = CustID, 
	@RoleID = RoleID
FROM custinfo WITH (NOLOCK)
WHERE username = @Keyword 

SELECT 
	custid, 
	username, 
	roleid, 
	srecommend, 
	mrecommend, 
	recommend, 
	disableCasino 
FROM custinfo WITH (NOLOCK)
WHERE syncCasino = @SearchBy 
	AND (srecommend = @CustID or mrecommend = @CustID or recommend = @CustID or CustID = @CustID)
ORDER BY 
	srecommend,
	mrecommend ASC,
	recommend ASC,
	username ASC

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CasinoSynchronise] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CasinoSynchronise] TO [vnteam]
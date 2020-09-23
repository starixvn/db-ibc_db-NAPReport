/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_SiteSel @IsTest BIT = 0
AS
/*
	Created: Jaden.Tang@20200923
	Task: Get list of Sites from drop down list in LeagueWL report
	DB: DBACC.bodb02

	Revisions:
		- 20200923@Jaden: Initial commit
*/

BEGIN
	SET NOCOUNT ON

	-- use DBLink to query from DW's tbl_Site as it contains a complete set of site data
	SELECT CASE WHEN isDeposit = 0 THEN 'Credit' ELSE 'Deposit' END AS SiteGroup, 
		   site AS SiteName
	FROM DBDW.bodb_Account.dbo.tbl_Site WITH (NOLOCK)
	WHERE siteid <> - 1 AND IsTest = @IsTest
	ORDER BY isDeposit, site

END
GO

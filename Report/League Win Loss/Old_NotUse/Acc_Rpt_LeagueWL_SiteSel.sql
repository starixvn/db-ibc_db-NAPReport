/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_SiteSel @IsTest BIT = 0
AS
/*
	Created: Jaden.Tang@20200923
	Task: Get list of Sites from drop down list in LeagueWL report
	DB: DBDW.bodb_dwrs

	Revisions:
		- 20200923@Jaden: Initial commit
		- 20220119@Jaden.Tang: use Acc_Rpt_SiteList instead (#182497)
*/

BEGIN
	SET NOCOUNT ON

	SELECT CASE WHEN isDeposit = 0 THEN 'Credit' ELSE 'Deposit' END AS SiteGroup, 
		   site AS SiteName
	FROM bodb_Account.dbo.tbl_Site WITH (NOLOCK)
	WHERE siteid <> - 1 AND IsTest = @IsTest
	ORDER BY isDeposit, site

END
GO

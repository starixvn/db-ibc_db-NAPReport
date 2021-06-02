/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE Acc_Rpt_CompanyWinloss_DivisionSel
AS
/*
	Created: 20210601@Roy
	Task : Get all sites separate into Credit and Deposit group
	DB: DBDW.bodb_dwrs

	Revisions:
		20210601@Jaden: Add the League textbox and Division dropdown (#???)
*/
BEGIN
	SET NOCOUNT ON

	SELECT isDeposit SiteGroup
		,siteid SiteId
		,site SiteName
	FROM bodb_Account.dbo.tbl_Site WITH (NOLOCK)
	WHERE siteid <> - 1 AND IsTest = 0
	ORDER BY isDeposit, site
END

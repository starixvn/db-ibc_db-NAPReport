/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel_DivisionSel
AS
/*
	Created: 20210105@Roy
	Task : Get all sites separate into Credit and Deposit group
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		20220119@Jaden.Tang: use Acc_Rpt_SiteList instead (#182497)
		
	Param's Explanation:
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel_DivisionSel
*/
BEGIN
	SET NOCOUNT ON

	SELECT isDeposit SiteGroup
		,siteid SiteId
		,site SiteName
	FROM bodb_Account.dbo.tbl_Site WITH (NOLOCK)
	WHERE siteid <> - 1
		AND IsTest = 0
	ORDER BY isDeposit
		,site
END

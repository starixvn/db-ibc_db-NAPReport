/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/

/*
	Created: 20200611@Percy
	DB: DBLIC.bodb_LicenseeReport
	Task: Grant select permission on rpt_CustomerWL_ExtraGMT table to 2 accounts: bodbAdminNet & bodbLicenseeNet
	RedmineID: 134867
*/

USE bodb_LicenseeReport
GO

GRANT SELECT ON dbo.rpt_CustomerWL_ExtraGMT TO bodbAdminNet AS dbo
GO
GRANT SELECT ON dbo.rpt_CustomerWL_ExtraGMT TO bodbLicenseeNet AS dbo
GO
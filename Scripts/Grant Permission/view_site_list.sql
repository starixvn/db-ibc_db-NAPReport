/*<info serverAlias="DBLIC-bodb_Licensee"></info>*/

/*
	Created: 20210202@Percy
	DB: DBLIC-bodb_Licensee
	Task: Grant select on view_site_list to dwrs
*/

-- run both DB052 & DB053
USE bodb_Licensee
GO

GRANT SELECT ON dbo.view_site_list TO dwrs AS dbo
GO
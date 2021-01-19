/*<info serverAlias="DBWH-bodb_Account"></info>*/
/*
	Created: 20210114@Percy
	DB: DBWH@bodb_Account
	Task: Update data for new table HNISettings

	Revisions:
		- 20210114@Percy: Update isEnable = 0 and EndOfSupportDate = NULL for Happy 5 Linked Games & Big Games for UAT testing
*/

use bodb_Account
go

update dbo.HNISettings with (rowlock)
set isEnable = 0, EndOfSupportDate = NULL
where ProductPrefix in ('H5LG', 'BGG')
go
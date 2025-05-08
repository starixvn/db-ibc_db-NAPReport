/*<info serverAlias="DBWH-bodb_Account"></info>*/
/*
Created by Aries@20250508
Run at DBWH@bodb_Account
Task: NAP Report - Saba Soccer Pingoal Marble Product


Revisions:
	- 20250508@Aries: NAP Report - Saba Soccer Pingoal Marble Product [Redmine:#225685]

*/

USE bodb_Account
GO

UPDATE dbo.SystemSettings
SET VValue = '42,74,108,113,122,151,252'
WHERE VID = 5 
    AND VName = 'SABA LeagueGroupID on OLTP system'
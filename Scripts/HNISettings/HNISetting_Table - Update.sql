/*<info serverAlias="DBWH-bodb_Account"></info>*/
/*
	Created: 20210114@Percy
	DB: DBWH@bodb_Account
	Task: Update data for new table HNISettings

	Revisions:
		- 20210114@Percy: Update isEnable = 0 and EndOfSupportDate = NULL for Happy 5 Linked Games & Big Games for UAT testing
		- 20210730@Ned.Le: Letstalk Reports - Apply monthly formula for MTD value like LA Reports (#157953)
*/

USE bodb_Account
GO

UPDATE hni
SET hni.LogicCode = 1
--SELECT *
FROM bodb_Account.dbo.HNISettings hni
WHERE hni.ProductID = 59
      AND hni.ProductPrefix = 'GDG'
	  AND hni.isDeposit = 0
	  AND hni.SubFigure = 'Pay to Supplier'
GO
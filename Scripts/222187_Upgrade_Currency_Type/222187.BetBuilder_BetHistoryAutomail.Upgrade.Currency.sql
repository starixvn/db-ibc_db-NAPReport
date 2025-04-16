/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
use bodb_Report;

ALTER TABLE dbo.BetBuilder_BetHistoryAutomail
ALTER COLUMN CurrencyId SMALLINT NOT NULL;

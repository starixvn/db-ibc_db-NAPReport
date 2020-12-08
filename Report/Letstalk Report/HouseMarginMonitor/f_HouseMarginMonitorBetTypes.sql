/*<info serverAlias="DBACC-bodb02" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/

USE [bodb02]
GO

ALTER FUNCTION [dbo].f_HouseMarginMonitorBetTypes() 
 
/*
	Created: 20201208@Jaden.Tang	
	Task :  Retrieve list of monitored bet types for LetsTalk House Margin Monitoring report (#146591)
	DB: DBACC.bodb02

	Revisions:
        20201208@Jaden: Creation
		
	Param's Explanation:
		
*/ 
RETURNS TABLE

RETURN
    WITH InputBetTypes AS (
        SELECT 228 Bettype
    )
    SELECT bt.typeid BetType, bt.typenamee BetTypeName
    FROM InputBetTypes sd
    LEFT JOIN bodb02.dbo.bettype bt
        ON sd.Bettype = bt.typeid
GO 
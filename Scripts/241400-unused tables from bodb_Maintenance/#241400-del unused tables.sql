
/*<info serverAlias="DBMA-bodb_Maintenance" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

    
/*
	Creator:	20251113@Robert
	Task:	Letstalk/NAP Report - Upgrade datatype of SporttypeID - Delete some unused tables from bodb_Maintenance [241400]

	Database:	DBMA.bodb_Maintenance
	
	Revisions:
		- Letstalk/NAP Report - Upgrade datatype of SporttypeID - Delete some unused tables from bodb_Maintenance [241400]
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

IF OBJECT_ID('DeadballOdds', 'U') IS NOT NULL
    DROP TABLE DeadballOdds;
GO

IF OBJECT_ID('OutRightOdds', 'U') IS NOT NULL
    DROP TABLE OutRightOdds;
GO

IF OBJECT_ID('LiveOdds', 'U') IS NOT NULL
    DROP TABLE LiveOdds;
GO

/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250829@Robert
	Task:	236740-OFA Live Product Integration

	Database:	DBACC.bodb02
	
	Revisions:
		- 236740-OFA Live Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 113;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 113;
*/

EXEC LetstalkAlertSportsInsertProduct 
	@ProductId = 113, 
	@SportType = 119, 
	@TimeSetting = '90 Mins', 
	@IsTest = 1;
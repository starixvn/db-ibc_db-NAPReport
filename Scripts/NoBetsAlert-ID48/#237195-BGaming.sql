
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250916@Robert
	Task:	237195-OFA BGaming Product Integration

	Database:	DBACC.bodb02
	
	Revisions:
		- 237195-OFA BGaming Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 114;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 114;
*/

EXEC LetstalkAlertSportsInsertProduct 
	@ProductId = 114, 
	@SportType = 118, 
	@TimeSetting = '90 Mins', 
	@IsTest = 1;
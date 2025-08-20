
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250820@Robert
	Task:	236071-Smartsoft Product Integration


	Database:	DBACC.bodb02
	
	Revisions:
		- 236071-Smartsoft Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 99;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 99;
*/

EXEC LetstalkAlertSportsInsertProduct 
	@ProductId = 99, 
	@SportType = 135, 
	@TimeSetting = '90 Mins', 
	@IsTest = 1;
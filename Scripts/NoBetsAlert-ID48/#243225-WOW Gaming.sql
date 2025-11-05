/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
/*
	Creator:	20251105@Robert
	Task:	243225-WOW Gaming Product Integration

	Database:	DBACC.bodb02
	
	Revisions:
		- 243225-WOW Gaming Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/
/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 117;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 117;
*/


EXEC LetstalkAlertSportsInsertProduct @ProductId = 117,
	@SportType = 113,
	@TimeSetting = '90 Mins',
	@IsTest = 1;


/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20251014@Robert
	Task:	240439-GEMINI Product Integration

	Database:	DBACC.bodb02
	
	Revisions:
		- 240439-GEMINI Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 115;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 115;
*/

EXEC LetstalkAlertSportsInsertProduct 
	@ProductId = 115, 
	@SportType = 117, 
	@TimeSetting = '90 Mins', 
	@IsTest = 1;
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
/*
	Creator:	20251022@Robert
	Task:	241356-Vertex Play Product Integration

	Database:	DBACC.bodb02
	
	Revisions:
		- 241356-Vertex Play Product Integration
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/
/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 116;
SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 116;
*/


DELETE l
FROM LetstalkAlertSports l
WHERE l.ProductId = 115
	AND l.SportType = 117

EXEC LetstalkAlertSportsInsertProduct @ProductId = 116,
	@SportType = 115,
	@TimeSetting = '90 Mins',
	@IsTest = 1;

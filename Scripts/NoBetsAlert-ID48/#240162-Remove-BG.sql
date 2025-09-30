/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
/*
	Creator:	20250930@Robert
	Task:	#240162-Remove-BG

	Database:	DBACC.bodb02
	
	Revisions:
		- 240162-Remove-BG
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/
/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 57;

SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 57;
*/


DELETE l
FROM LetstalkAlertSports l
WHERE l.ProductId = 57

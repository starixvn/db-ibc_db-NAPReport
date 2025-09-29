
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250929@Robert
	Task:	#240162-Remove-WE-LiveCasino

	Database:	DBACC.bodb02
	
	Revisions:
		- 240162-Remove-WE-LiveCasino
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

/*
SELECT 
	  *
FROM Products p
WHERE p.ProductID = 80;

SELECT DISTINCT 
	  sb.ProductID, 
	  sb.SportType
FROM SportBettypeMatrix sb
WHERE sb.ProductID = 80;
*/

delete l from LetstalkAlertSports l where l.ProductId = 80
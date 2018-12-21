/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_BetTypeSel_NumberGame
AS
SET NOCOUNT ON;
/*
    Created by: Jamie
    Date: 2011-10-28
    Task : Retrieve NG Bettypes 
    DB: DBACC.bodb02
    Revisions:
	   - 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 

Revisions:

*/

BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
		 s.SportName
	    , b.typeID
	    , b.typenamee
    FROM bettype AS b WITH (NOLOCK)
	   INNER JOIN SportBettypeMatrix AS sb WITH (NOLOCK) ON b.typeid = sb.BetType
	   INNER JOIN Sports AS s WITH (NOLOCK) ON s.SportType = sb.SportType
    WHERE sb.ProductID = 3
    ORDER BY s.SportName DESC
		 , b.typeID ASC;
END;
GO

GRANT EXECUTE ON dbo.Acc_BetTypeSel_NumberGame TO [bodbAdminNet];
GO
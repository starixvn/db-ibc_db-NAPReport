/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_TreeWinlost_SporttypeSel
AS
/*
	Created: Cherry@202000703
	Task: Get Sporttype list for filter area (NAP Reports - Tree Winloss)
	DB: DBACC.bodb02

	Revisions:
		202000703@Cherry: NAP Report - Add filter Sport of Sportbook (#135880)
		

	Param's Explanation:

	Example:
		1: Soccer
		2: Basketball
		43: E-Sports
		10000: Other Sports
		20000: Parlay
*/

BEGIN

	SET NOCOUNT ON

	SELECT SportType, SportName
	FROM bodb02.dbo.Sports WITH(NOLOCK)
	WHERE SportType IN (1,2,43)
	UNION 
	SELECT 10000 SportType, 'Other Sports' SportName
	UNION 
	SELECT 20000 SportType, 'Parlay' SportName

END
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

CREATE PROCEDURE dbo.Acc_Rpt_LeagueWL_SporttypeSel
AS
/*
	Created: Ned.Le@20200422
	Task: Get Sporttype list for filter area (NAP Reports - League Winloss)
	DB: DBACC.bodb02

	Revisions:
		- 20200422@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)

	Param's Explanation:

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_SporttypeSel
*/

BEGIN

	SET NOCOUNT ON

	;WITH CTE_ListOfSports AS (
		-- Soccer & Others
		SELECT DISTINCT
			   CASE WHEN sbm.SportType = 1 THEN 5000
					ELSE 15000 END SportGroupType,
			   CASE WHEN sbm.SportType = 1 THEN 'Soccer'
					ELSE 'Others' END SportGroupName,
			   sbm.SportType,
			   s.SportName
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
			 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON sbm.SportType = s.SportType
		WHERE sbm.ProductID = 1
			  AND sbm.SportType <> 27
		UNION ALL
		-- Parlay
		SELECT 10000 SportGroupType,
			   'Parlay' SportGroupName,
			   10000 SportType,
			   'Parlay' SportName
	)
	SELECT SportGroupType,
		   SportGroupName,
		   SportType,
		   SportName
	FROM CTE_ListOfSports
	ORDER BY SportGroupType ASC,
			 SportName ASC

END
GO

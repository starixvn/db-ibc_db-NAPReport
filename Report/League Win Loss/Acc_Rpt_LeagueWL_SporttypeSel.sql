/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_SporttypeSel
AS
/*
	Created: Ned.Le@20200422
	Task: Get Sporttype list for filter area (NAP Reports - League Winloss)
	DB: DBACC.bodb02

	Revisions:
		- 20200422@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200806@Jaden.Tang: NAP Report - Enhancement for League Win Loss (#138995)
		- 20200930@Jaden.Tang: Odds Spread Adjustment (#141750)

	Param's Explanation:

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_SporttypeSel
*/

BEGIN

	SET NOCOUNT ON

	;WITH CTE_ListOfSports AS (
		-- Soccer & Others
		SELECT DISTINCT
			   CASE WHEN sbm.SportType = 1 THEN 1
			   		WHEN sbm.SportType = 2 THEN 2
					ELSE 20000 END SportGroupType,
			   CASE WHEN sbm.SportType = 1 THEN 'Soccer'
			   		WHEN sbm.SportType = 2 THEN 'Basketball'
					ELSE 'Others' END SportGroupName,
			   sbm.SportType,
			   s.SportName SportName,
			   CASE
					WHEN (sbm.BetType IN (1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122,123, 126, 151, 301, 302, 303, 304)
						AND s.SportType = 1)  --Soccer
						OR
						(sbm.BetType IN (1, 2, 3, 7, 8, 12)
						AND s.SportType = 2) --Basketball
					THEN 'Major Bet Types'
					WHEN (sbm.BetType NOT IN (1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122,123, 126, 151, 301, 302, 303, 304)
						AND s.SportType = 1)  --Soccer
						OR
						(sbm.BetType NOT IN (1, 2, 3, 7, 8, 12)
						AND s.SportType = 2) --Basketball
					THEN 'Minor Bet Types'
					ELSE SportName
			   END BetGroupName,
			   sbm.BetType Bettype,
			   b.typenamee BettypeName
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
			 LEFT JOIN bodb02.dbo.Sports s (NOLOCK) ON sbm.SportType = s.SportType
			 LEFT JOIN bodb02.dbo.bettype b (NOLOCK) ON sbm.BetType = b.typeid
		WHERE sbm.ProductID = 1
			  AND sbm.SportType <> 27
			  AND sbm.SubProduct NOT LIKE 'BT%'
			  AND sbm.BetType NOT IN (9, 29)
		UNION ALL
		-- Parlay
		SELECT DISTINCT
			   10000 SportGroupType,
			   'Parlay' SportGroupName,
			   10000 SportType,
			   'Parlay' SportName,
			   'Parlay' BetGroupName,
			   sbm.BetType Bettype,
			   b.typenamee BettypeName
		FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
			 LEFT JOIN bodb02.dbo.bettype b (NOLOCK) ON sbm.BetType = b.typeid
		WHERE sbm.ProductID = 1
			  AND sbm.BetType IN (9, 29, 999)
		UNION ALL
		-- Odds Spread Adjustment
		SELECT 10001 SportGroupType,
			   'SB Adjustment' SportGroupName,
			   10001 SportType,
			   'SB Adjustment' SportName,
			   'SB Adjustment' BetGroupName,
			   999 Bettype,
			   'Odds Spread Adjustment' BettypeName
	)
	SELECT SportGroupType,
		   SportGroupName,
		   SportType,
		   SportName,
		   BetGroupName,
		   Bettype,
		   BettypeName
	FROM CTE_ListOfSports
	WHERE BettypeName IS NOT NULL
	ORDER BY SportGroupType ASC,
			 SportName ASC,
			 BetGroupName ASC,
			 BettypeName ASC

END
GO

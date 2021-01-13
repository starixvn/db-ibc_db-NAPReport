/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel_SportSel
AS
/*
	Created: 20210105@Roy
	Task : Get all Sporttype separate into Major Bet Types and Minor Bet Types
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		
	Param's Explanation:
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel_SportSel
*/
BEGIN

	SET NOCOUNT ON

	;WITH CTE_ListOfSports
	AS (
		-- Soccer & Others
		SELECT DISTINCT CASE 
				WHEN sbm.SportType = 1
					THEN 1
				WHEN sbm.SportType = 2
					THEN 2
				ELSE 20000
				END SportGroupType
			,CASE 
				WHEN sbm.SportType = 1
					THEN 'Soccer'
				WHEN sbm.SportType = 2
					THEN 'Basketball'
				ELSE 'Others'
				END SportGroupName
			,sbm.SportType
			,s.SportName SportName
			,CASE 
				WHEN ( sbm.BetType IN (1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304)
						AND s.SportType = 1 ) --Soccer
					OR ( sbm.BetType IN (1, 2, 3, 7, 8, 12)
						AND s.SportType = 2 ) --Basketball
					THEN 'Major Bet Types'
				WHEN ( sbm.BetType NOT IN (1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304)
						AND s.SportType = 1 ) --Soccer
					OR ( sbm.BetType NOT IN (1, 2, 3, 7, 8, 12)
						AND s.SportType = 2 ) --Basketball
					THEN 'Minor Bet Types'
				ELSE SportName
			END BetGroupName
			,sbm.BetType Bettype
			,b.typenamee BettypeName
		FROM bodb02.dbo.SportBettypeMatrix sbm(NOLOCK)
		INNER JOIN bodb02.dbo.bettype b(NOLOCK) ON sbm.BetType = b.typeid
		LEFT JOIN bodb02.dbo.Sports s(NOLOCK) ON sbm.SportType = s.SportType
		WHERE sbm.ProductID = 1
			AND sbm.SportType <> 27 --Cricket (use 50)
			AND sbm.SubProduct NOT IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			AND sbm.BetType NOT IN (9, 29, 999) --Parlay & Odds Spread Adjustment
		)
	SELECT SportGroupType
		,SportGroupName
		,SportType
		,SportName
		,BetGroupName
		,Bettype
		,BettypeName
	FROM CTE_ListOfSports
	ORDER BY SportGroupType ASC
		,SportName ASC
		,BetGroupName ASC
		,BettypeName ASC
END

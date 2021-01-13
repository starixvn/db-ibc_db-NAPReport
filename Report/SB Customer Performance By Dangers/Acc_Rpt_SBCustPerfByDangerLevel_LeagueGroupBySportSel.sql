/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel_LeagueGroupBySportSel
	@SportBettype VARCHAR(MAX) = 'ALL'
AS
/*
	Created: 20210105@Roy
	Task : Get all LeagueGroups name by sport
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		
	Param's Explanation:
		@SportTypeList: Set of sporttypes, seperate by ',' (ex: '43_2,29_9')
		
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel_LeagueGroupBySportSel @SportBettype='43_2,29_9'
*/
BEGIN

	SET NOCOUNT ON

	CREATE TABLE #tmpSport ( SportType SMALLINT )
	CREATE TABLE #tmpLeagueGroups ( GroupID SMALLINT, GroupName VARCHAR(200) )
	
	INSERT INTO #tmpSport ( SportType )
	SELECT DISTINCT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS SportType
	FROM dbo.strSplit(REPLACE(@SportBettype, ' ', ''), ',')
	WHERE val <> 'ALL'
		AND LEN(val) > 0

	INSERT INTO #tmpLeagueGroups (
		GroupID
		,GroupName
	)	
	SELECT GroupName
		,GroupID
	FROM (
		SELECT GroupName
			,GroupID
		FROM bodb02.dbo.LeagueGroup(NOLOCK) lg
		WHERE IsActive = 1
			AND GroupID >= 0
			AND GroupName NOT LIKE '%test%'
			AND ('ALL' = @SportBettype
				OR (lg.SportType = 0 OR EXISTS (SELECT 1 FROM #tmpSport s WHERE lg.SportType = s.SportType))
				)		
		UNION
		
		SELECT 'Non-group Leagues' GroupName
			,-1 AS GroupID
	) as tmp

	/*
		Return list of LeagueGroupIDs grouped by GroupName
			Non-group Leagues: -1 include Parlay
	*/
	SELECT GroupName
			,GroupID = STUFF((
					SELECT ',' + convert(NVARCHAR(10), GroupID)
					FROM #tmpLeagueGroups t1
					WHERE t1.GroupName = t2.GroupName
					ORDER BY t1.GroupID
					FOR XML PATH('')
					), 1, 1, '')
		FROM #tmpLeagueGroups t2
		GROUP BY GroupName
		ORDER BY ( CASE 
					WHEN GroupName = 'Non-group Leagues'
						THEN 2
					ELSE 1
				END )
				,GroupName
				,GroupID

	DROP TABLE #tmpLeagueGroups
	DROP TABLE #tmpSport
END

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel_LeagueBySportSel
	@SportBettype VARCHAR(MAX) = 'ALL'
	,@SearchText NVARCHAR(500)
AS
/*
	Created: 20210105@Roy
	Task : Get top 20 leagues name by sport
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		
	Param's Explanation:
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel_LeagueBySportSel @SportBettype='43_2,29_9', @SearchText=N'*ENG'
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #tmpSport ( SportType SMALLINT )
	
	INSERT INTO #tmpSport ( SportType )
	SELECT DISTINCT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS SportType
	FROM dbo.strSplit(REPLACE(@SportBettype, ' ', ''), ',')
	WHERE val <> 'ALL'
		AND LEN(val) > 0

	CREATE CLUSTERED INDEX PK_tmpSport ON #tmpSport( SportType )

	;WITH CTE_LeagueName AS (
		SELECT DISTINCT l.leaguename
		FROM bodb02.dbo.league l (NOLOCK)
		WHERE ('ALL' = @SportBettype OR EXISTS (SELECT 1 FROM #tmpSport s WHERE l.SportType = s.SportType))
			  AND l.isTest = 0
			  AND l.leaguename LIKE '%' + @SearchText + '%'
			  AND l.leaguename NOT LIKE '%test%'
	)
	SELECT TOP(20) l.leaguename
	FROM CTE_LeagueName l
	ORDER BY LEN(l.leaguename)
		,l.leaguename

	DROP TABLE #tmpSport
END

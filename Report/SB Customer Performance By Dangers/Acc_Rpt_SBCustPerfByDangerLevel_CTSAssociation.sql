/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel_CTSAssociation
	@CustIDs VARCHAR(MAX)
AS
/*
	Created: 20210105@Roy
	Task : Get No. associated accounts by list of CustIDs
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		
	Param's Explanation:
		@CustIDs: List of customer id separated by comma

	Script:
		EXEC Acc_Rpt_SBCustPerfByDangerLevel_CTSAssociation
													@CustIDs='123, 1176070, 17004, 1606266, 38878126, 43600693, 1176086'
*/
BEGIN
	SET NOCOUNT ON
	
	---Create temp tables---
	CREATE TABLE #tmpCusts (
		CustID INT
	)

	/*
		Define CustIDs
		From: @CustIDs
		To: #tmpCusts ( CustID )
	*/
	INSERT INTO #tmpCusts (	CustID )
	SELECT val CustID
	FROM dbo.strSplit(REPLACE(@CustIDs, ' ', ''), ',')
	WHERE LEN(val) > 0
		AND ISNUMERIC(val + '.0e0') = 1
	
	CREATE CLUSTERED INDEX [CIX_tmpCusts] ON #tmpCusts( CustID )

	;WITH CTE_Assoc AS (
		SELECT a.CustID
			,a.AssoCustID
		FROM #tmpCusts AS c
			INNER JOIN bodb_Account.dbo.CTS_Association AS a WITH (NOLOCK) ON c.CustID = a.CustID
		GROUP BY a.CustID
			,a.AssoCustID
	)
	SELECT CustID
		,COUNT(1) NoAssoc
	FROM CTE_Assoc
	GROUP BY CustID
	OPTION (RECOMPILE)

	DROP TABLE #tmpCusts
END

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
	
	Script:
		EXEC Acc_Rpt_SBCustPerfByDangerLevel_CTSAssociation
													@CustIDs='123, 1176070, 17004, 1606266, 38878126, 43600693, 1176086'
*/
BEGIN
	SET NOCOUNT ON
	
	---Create temp tables---
	CREATE TABLE #tmpCusts (
		CustID INT
		,CTSCustID BIGINT
	)
	CREATE TABLE #tmpAssociation (
		FromCustID BIGINT
		,ToCustID BIGINT
	)

	/*
		Define CustIDs
		From: @CustIDs
		To: #tmpCusts ( CustID, CTSCustID )
	*/
	;WITH CTE_CustIDs AS (
		SELECT val CustID
		FROM dbo.strSplit(REPLACE(@CustIDs, ' ', ''), ',')
		WHERE LEN(val) > 0
			AND ISNUMERIC(val + '.0e0') = 1
	)
	INSERT INTO #tmpCusts (
		CustID
		,CTSCustID
	)
	SELECT pc.CustID
		,ISNULL(c.CTSCustID, -1 )
	FROM CTE_CustIDs pc
		LEFT JOIN bodb_Account.dbo.CTS_CTSCustomer AS c WITH (NOLOCK) ON pc.CustID = c.CustID
	GROUP BY pc.CustID
		,ISNULL(c.CTSCustID, -1 )
	CREATE CLUSTERED INDEX [CIX_tmpCusts] ON #tmpCusts( CTSCustID, CustID )

	/*
		Define Cust By Devices
		From: #tmpCusts, CTS_AssociationByDevice
		To: #tmpAssociation ( FromCustID, ToCustID )
	*/
	;WITH CTE_ToCusts AS (
		SELECT DCSDeviceID
			,CTSCustID
		FROM bodb_Account.dbo.CTS_AssociationByDevice WITH (NOLOCK)
		GROUP BY DCSDeviceID
			,CTSCustID
	)
	,CTE_FromCusts AS (
		SELECT ass.CTSCustID
			,ass.DCSDeviceID
		FROM bodb_Account.dbo.CTS_AssociationByDevice AS ass WITH (NOLOCK)
			INNER JOIN #tmpCusts AS c ON ass.CTSCustID = c.CTSCustID
		WHERE c.CTSCustID >= 0
		GROUP BY ass.CTSCustID
			,ass.DCSDeviceID
	)
	INSERT INTO #tmpAssociation (
		FromCustID
		,ToCustID
	)
	SELECT f.CTSCustID FromCustID
		,t.CTSCustID ToCustID
	FROM CTE_FromCusts f
		LEFT JOIN CTE_ToCusts t ON f.DCSDeviceID = t.DCSDeviceID
	WHERE f.CTSCustID <> t.CTSCustID
	GROUP BY f.CTSCustID
		,t.CTSCustID

	/*
		Define Cust By Manual
		From: #tmpCusts, CTS_AssociationByManual
		To: #tmpAssociation ( FromCustID, ToCustID )
	*/
	INSERT INTO #tmpAssociation (
		FromCustID
		,ToCustID
	)
	SELECT DISTINCT c.CTSCustID FromCustID
		,( CASE 
			WHEN ass.FromCTSCustID = c.CTSCustID
				THEN ass.ToCTSCustID
			ELSE ass.FromCTSCustID
			END ) ToCustID
	FROM #tmpCusts AS c
		INNER JOIN bodb_Account.dbo.CTS_AssociationByManual AS ass WITH (NOLOCK) ON ( c.CTSCustID = ass.FromCTSCustID
																		OR c.CTSCustID = ass.ToCTSCustID )
	WHERE c.CTSCustID >= 0
	
	CREATE CLUSTERED INDEX [CIX_tmpAssociation] ON #tmpAssociation( FromCustID, ToCustID )

	/*
		Remove
		From: #tmpCusts, CTS_AssociationByManual
		To: #tmpAssociation ( FromCustID, ToCustID )
	*/
	;WITH CTE_Remove_ToCusts AS (
		SELECT DISTINCT ( CASE 
			WHEN ass.FromCTSCustID = c.CTSCustID
				THEN ass.ToCTSCustID
			ELSE ass.FromCTSCustID
			END ) ToCustID
		FROM #tmpCusts AS c
			INNER JOIN bodb_Account.dbo.CTS_AssociationRemove AS ass WITH (NOLOCK) ON ( c.CTSCustID = ass.FromCTSCustID
																			OR c.CTSCustID = ass.ToCTSCustID )
		WHERE c.CTSCustID >= 0
	)
	DELETE ass
	FROM #tmpAssociation ass
		INNER JOIN CTE_Remove_ToCusts AS r ON ass.ToCustID = r.ToCustID

	---Return result---
	;WITH CTE_Association AS (
		SELECT FromCustID
			,ToCustID
		FROM #tmpAssociation
		GROUP BY FromCustID
			,ToCustID
	)
	SELECT c.CustID
		,SUM(CASE WHEN (c.CTSCustID < 0 OR ass.ToCustID IS NULL) THEN 0
				ELSE 1
			END) NoAssoc
	FROM #tmpCusts AS c
		LEFT JOIN CTE_Association AS ass ON c.CTSCustID = ass.FromCustID
	GROUP BY c.CustID

	DROP TABLE #tmpCusts
	DROP TABLE #tmpAssociation
END

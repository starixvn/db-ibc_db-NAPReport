/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_TreeWinlostBulkGetVR]
	@CustIDs NVARCHAR(MAX)
AS
/*  
	Created by: Dominic  
	Date: 20180507
	Task : Get VR infor for a list of customers in bulk(Used to export excel) 
	DB: DBACC.bodb02 

	Parameters explain:
		@CustIDList: Comma seperated string of CustomerIDs
	Revision: 
		- 20190702@Dominic: Not show E-Sports [RedmineID:#114830]
*/
BEGIN
	DECLARE @XML XML  = NULL
	SET @XML = N'<root><r>' + REPLACE(@CustIDs, ',', '</r><r>') + '</r></root>'

	SELECT CAST(r.value('.', 'INT') AS INT) CustID
	INTO #TblCustID
	FROM @xml.nodes('//root/r') AS RECORDS(r)
	WHERE LEN(ISNULL(r.value('.', 'INT'), '')) > 0

	CREATE UNIQUE CLUSTERED INDEX  IX_CustID ON #TblCustID(CustID)

	SELECT ci.username,ci.custid
	INTO #tmpCustinfo
	FROM		custinfo				AS ci  WITH(NOLOCK) 
	WHERE	ci.custid IN (SELECT CustID FROM #TblCustID)
			AND ci.virtualMultiplier = 1

	CREATE UNIQUE CLUSTERED INDEX  IX_CustID ON #tmpCustinfo(CustID)

	SELECT	ci.username,
			cvs.custid,
			pvs.sporttype,
			pvs.bettype,
			pvs.islive,
			(CASE WHEN CAST(substring(cvs.bitmapVirtual, 1+((pvs.profileID-1)%64), 1) as int) > 200 THEN ((CAST(substring(cvs.bitmapVirtual, 1+((pvs.profileID-1)%64), 1) as int) - 200)*5 + 200) ELSE CAST(substring(cvs.bitmapVirtual, 1+((pvs.profileID-1)%64), 1) as int) END) / 100.0 AS virtualMultiplier
	FROM		#tmpCustinfo				AS ci  WITH(NOLOCK) 
	INNER JOIN	CustVirtualSetting		AS cvs WITH(NOLOCK) 
			ON	ci.custid = cvs.custid
	INNER JOIN	ProfileVirtualSetting	AS pvs WITH(NOLOCK)
			ON	cvs.seqNo = pvs.seqNo
	WHERE pvs.isActive = 1 AND pvs.sporttype <> 43
	ORDER BY username, sporttype, islive DESC, bettype
END

GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TreeWinlostBulkGetVR] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_TreeWinlostBulkGetVR] TO [bodbAdminNet]
GO 
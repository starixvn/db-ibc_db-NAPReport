/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO 
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTableSel]
AS
/*
	Created by: 20160908@Sophia.Nguyen
	Task : Get all game tables (leagueid) of SLI - Live Casino  [Redmine: #62430]
	DB: DBACC/bodb02
	Original:
	Revisions:	

	Param Explaintaion:
		@GameTypeID: Get all game tables (leagueid  of SLI - Live Casino : ProductID = 4)

*/

BEGIN
SET NOCOUNT ON
	 
	SELECT
		leagueid AS GameTableId,
		leaguename AS GameTable, 
		CONVERT(INT,leaguenametc) AS TypeId,
		IsTest
	FROM dbo.league WITH (NOLOCK)
	WHERE sporttype = 162			
	ORDER BY leaguename
		
END  


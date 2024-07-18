/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_GetTableData]
	@TableName NVARCHAR(MAX) = ''
AS
/*
	Created by: 20240719@Cherry
	Task: Get data from table (#207725)
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		20240719@Cherry: Initial
*/
BEGIN
	SET NOCOUNT ON
SELECT * --GroupId, PartyId, GroupType
	FROM DBCUST.bodb_Licensee.dbo.LA_CombinedGroupAssignment WITH(NOLOCK)

SELECT * --GroupId, GroupName, PathCode
	FROM DBCUST.bodb_Licensee.dbo.LA_CombinedGroup WITH(NOLOCK)

END
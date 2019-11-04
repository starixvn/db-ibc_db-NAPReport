/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceBK_Mapping]   
	@FromDate	DATETIME,  
	@ToDate		DATETIME,  
	@Type	BIT = 1   
AS
/*
	Creator: Cherry
	Date: 2019-10-10
	DB: DBACC.bodb02
	Task: Trader Performance Report - trader_bk

	Revisions:

		20191010@Cherry: Apply new table for Trader (#120746)

	Param's Explanation:
		@Type: Get data of Trader
			0: Dot_admin_Assignment_Operator_bk
			1: Dot_Admin_Assignment_Trader_bk
*/			
BEGIN
	SET NOCOUNT ON
	CREATE TABLE #tmpDot_Admin_Assignment_Trader (
			ID INT PRIMARY KEY,
			eventdate DATE,
			matchid INT,
			bettype SMALLINT,
			liveindicator TINYINT,
			Detail_X SMALLINT,
			Detail_Y SMALLINT,
			Detail_Z SMALLINT,
			TraderID INT,
			UpdatedTime DATETIME
		)
		
	CREATE TABLE #tmpTraderAssignment (
		eventdate DATE,
		matchid INT,
		bettype SMALLINT,
		TraderID INT
	)	
	
	IF @Type = 1
	BEGIN
		INSERT INTO #tmpDot_Admin_Assignment_Trader(ID,EventDate,matchid,bettype,liveindicator,Detail_X,Detail_Y,Detail_Z,TraderID,UpdatedTime)
		SELECT t.ID
			   ,m.eventdate
			   ,t.matchid
			   ,t.bettype
			   ,t.liveindicator
			   ,t.Detail_X
			   ,t.Detail_Y
			   ,t.Detail_Z
			   ,t.TraderID
			   ,t.UpdatedTime
		FROM bodb_Archive.dbo.Dot_Admin_Assignment_Trader_bk t (NOLOCK)
			 INNER JOIN bodb_Archive.dbo.match_bk m (NOLOCK) ON t.matchid = m.matchid 
		WHERE m.eventdate BETWEEN @FromDate AND @ToDate
			AND m.eventstatus = 'completed'									
			AND m.matchcode NOT LIKE '%hedge%'
			AND t.liveindicator = 1
			AND t.bettype IN (1, 3, 5, 7, 8, 15, 2, 12);

		WITH
		CTE_Group1 AS (
			SELECT t.ID,t.eventdate,t.matchid,t.bettype,t.liveindicator,t.TraderID
				   ,RANK() OVER(PARTITION BY t.matchid,t.bettype,t.liveindicator ORDER BY t.UpdatedTime DESC,t.ID DESC) Rank_
			FROM #tmpDot_Admin_Assignment_Trader t (NOLOCK)		
		)
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,TraderID)
		SELECT DISTINCT t.eventdate, t.matchid, t.bettype, t.TraderID
		FROM CTE_Group1 t
		WHERE t.Rank_ = 1;
	END
	ELSE
	BEGIN
		INSERT INTO #tmpTraderAssignment(eventdate,matchid,bettype,TraderID)
			SELECT DISTINCT
				m.eventdate,
				m.matchid,
				CASE 					 
					WHEN operatortype = 1 AND (bettype = 1 OR bettype = 5) THEN 1
					WHEN operatortype = 1 AND bettype = 4 THEN 2
					WHEN operatortype = 1 AND bettype = 2 THEN 3
					WHEN operatortype = 1 AND bettype = 3 THEN 5
					WHEN operatortype = 2 AND bettype = 1 THEN 7
					WHEN operatortype = 2 AND bettype = 2 THEN 8
					WHEN operatortype = 2 AND bettype = 4 THEN 12
					WHEN operatortype = 2 AND bettype = 3 THEN 15
				END bettype,
				a.operatorid				
			FROM bodb_Archive.dbo.Dot_admin_Assignment_Operator_bk a WITH (NOLOCK)
				INNER JOIN bodb_Archive.dbo.match_bk m WITH (NOLOCK) ON a.matchid = m.matchid
			WHERE
				m.eventdate BETWEEN @FromDate AND @ToDate
				AND m.eventstatus = 'completed'
				AND a.operatortype < 3
				AND m.matchcode NOT LIKE '%hedge%'
	END
	
	SELECT eventdate,
		matchid,
		bettype,
		TraderID 
	FROM #tmpTraderAssignment 
	
	DROP TABLE #tmpDot_Admin_Assignment_Trader
	DROP TABLE #tmpTraderAssignment
END
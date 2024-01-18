/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_WinLostSummary_Sporttype_Racing]
	@sporttype	INT,
	@fromdate	DATETIME,
	@todate		DATETIME
AS
	/*
		Created: Johnson
		Date: 2013-06-24
		Task: Get summary winlost by match for racing
		DB: DBRPT/bodb_Report
		
		Revisions:
			- 20130716@Johnson: get min eventdate by oddsstatus = 'completed'			
			- 20130822@Johnson: change to use rptWinlost instead rptWinlost2
			- 20130917@Johnson: get @movebetday base on match14
			- 20210420@Cherry: Renovation, change source table to DW (#153530)
		Parameter's Explanation:
	*/
SET NOCOUNT ON
	Declare @RPT TABLE (
		race varchar(50), bettype smallint, meetingid int,
		realWinLost money, realPosition money, realCommission money, realTurnover money, realLineTotal money,
		virtualTurnover money, virtualLineTotal money		
	)
	
	Declare @movebetsday datetime,
			@f_date datetime,
			@t_date datetime
	SELECT @f_date = @fromdate, @t_date = @todate
	
	CREATE TABLE #tmpoutright
		(orid INT, 
		leagueid INT, 
		eventdate DATETIME, 
		groupmatch VARCHAR(20))
			
	INSERT INTO #tmpoutright
		(orid, 
		leagueid, 
		eventdate, 
		groupmatch)
	SELECT matchid, 
		leagueid, 
		eventdate, 
		groupmatch
	FROM bodb_Account.dbo.outright WITH(NOLOCK)
	WHERE eventdate BETWEEN @f_date AND @t_date
	UNION
	SELECT orid, 
		leagueid, 
		eventdate, 
		groupmatch
	FROM bodb_archive.dbo.outright WITH(NOLOCK)
	WHERE eventdate BETWEEN @f_date AND @t_date
						
	CREATE CLUSTERED INDEX IX_orid ON #tmpoutright (orid) 

	INSERT INTO @RPT(
				race, bettype, meetingid, realWinlost, realPosition, realCommission, realTurnover, realLineTotal,
				virtualTurnover, virtualLineTotal
			)
	SELECT m.groupmatch as race
		,b.bettype
		,m.leagueid
		,ISNULL(SUM(realWinlost),0)
		,ISNULL(SUM(realPosition),0)
		,ISNULL(SUM(realCommission),0)
		,ISNULL(SUM(realTurnover),0)
		,ISNULL(SUM(realLineTotal),0)
		,ISNULL(SUM(realTurnover),0) as virtualTurnover
		,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
	FROM bodb_Account.dbo.rptWinlost b WITH(NOLOCK)
		INNER JOIN #tmpoutright m ON b.matchid = m.orid
	WHERE b.winlostdate between @f_date and @t_date
		AND b.sporttype = @sporttype
	GROUP BY m.groupmatch, b.bettype, m.leagueid		
	
	SELECT * FROM @RPT
	ORDER BY bettype,meetingid,CAST(race AS TINYINT)
	
	DROP TABLE #tmpoutright

GO


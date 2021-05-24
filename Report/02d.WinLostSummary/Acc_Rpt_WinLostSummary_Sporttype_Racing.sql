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

	SELECT @movebetsday = MoveBetsDay
	FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
	IF @todate > @movebetsday
	BEGIN
		IF @fromdate <= @movebetsday
				SELECT @f_date = @movebetsday + 1
			ELSE
				SELECT @f_date = @fromdate
				
			SELECT @t_date = @todate
			
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
				INNER JOIN bodb02.dbo.outright m WITH(NOLOCK) ON b.matchid = m.orid
			WHERE b.winlostdate between @f_date and @t_date
				AND b.sporttype = @sporttype
			GROUP BY m.groupmatch, b.bettype, m.leagueid
	END
	
	IF @fromdate <=@movebetsday
	BEGIN
		IF @todate <= @movebetsday
			SELECT @t_date = @todate
		ELSE
			SELECT @t_date = @movebetsday
			
		SELECT @f_date = @fromdate
				
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
			INNER JOIN bodb02.dbo.outright14 m WITH(NOLOCK) ON b.matchid = m.orid
		WHERE b.winlostdate between @f_date and @t_date
			AND b.sporttype = @sporttype
		GROUP BY m.groupmatch,b.bettype,m.leagueid
	END
	
	SELECT * FROM @RPT
	ORDER BY bettype,meetingid,CAST(race AS TINYINT)

GO


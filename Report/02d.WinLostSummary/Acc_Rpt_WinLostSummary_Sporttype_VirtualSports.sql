/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_WinLostSummary_Sporttype_VirtualSports] 
	@fromdate DATETIME,
	@todate		DATETIME,
	@sporttype	INT
AS
	/*
		Created: Johnson
		Date: 2013-06-25
		Task: Get summary winlost for virtual sports(exclude virtual HR) by match
		DB: DBRPT/bodb_Report
		
		Revisions:
			- 20130822@Johnson: change to use rptWinlost instead rptWinlost2
			- 20131204@Johnson: get @movebetday base on match14
			- 20210420@Cherry: Renovation, change source table to DW (#153530)
		Parameter's Explanation:
	*/
SET NOCOUNT ON 
	Declare @RPT TABLE (
		matchcode nvarchar(50) COLLATE SQL_Latin1_General_CP1_CS_AS,
		HomeId int, AwayId int,		
		bettype smallint, leagueid int,
		realWinLost money, realPosition money, realCommission money, realTurnover money, realLineTotal money,
		virtualLineTotal money, virtualTurnover money		
	)
	
	Declare @movebetdate datetime,
			@f_date datetime,
			@t_date datetime
    
    SELECT @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
	IF @todate > @movebetdate
	BEGIN
		IF @fromdate <= @movebetdate
			SELECT @f_date = @movebetdate + 1
		ELSE
			SELECT @f_date = @fromdate
			
		SELECT @t_date = @todate
		
		INSERT INTO @RPT(
			matchcode, homeid, awayid, bettype, leagueid, 
			realWinlost, realPosition, realCommission, realTurnover, realLineTotal,
			virtualLineTotal, virtualTurnover
		)
		SELECT matchcode
			,homeid
			,awayid
			,b.bettype
			,m.leagueid
			,ISNULL(SUM(realWinlost),0) 
			,ISNULL(SUM(realPosition),0)
			,ISNULL(SUM(realCommission),0)
			,ISNULL(SUM(realTurnover),0)
			,ISNULL(SUM(realLineTotal),0)
			,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
			,ISNULL(SUM(realTurnover),0) as virtualTurnover								
		FROM bodb_Account.dbo.rptWinlost b WITH(NOLOCK)
			INNER JOIN bodb02.dbo.match m WITH(NOLOCK) ON b.matchid = m.matchid
		WHERE winlostdate BETWEEN @f_date AND @t_date
			AND b.sporttype = @sporttype			
		GROUP BY matchcode, homeid, awayid, bettype, leagueid
		
	END
	
	IF @fromdate <= @movebetdate
	BEGIN
		IF @todate <= @movebetdate
			SELECT @t_date = @todate
		ELSE
			SELECT @t_date = @movebetdate
			
		SELECT @f_date = @fromdate
	
		INSERT INTO @RPT(
			matchcode, homeid, awayid, bettype, leagueid, 
			realWinlost, realPosition, realCommission, realTurnover, realLineTotal,
			virtualLineTotal, virtualTurnover
		)
		SELECT matchcode
			,homeid
			,awayid
			,b.bettype
			,m.leagueid
			,ISNULL(SUM(realWinlost),0) 
			,ISNULL(SUM(realPosition),0)
			,ISNULL(SUM(realCommission),0)
			,ISNULL(SUM(realTurnover),0)
			,ISNULL(SUM(realLineTotal),0)
			,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
			,ISNULL(SUM(realTurnover),0) as virtualTurnover							
		FROM bodb_Account.dbo.rptWinlost b WITH(NOLOCK)
			INNER JOIN bodb02.dbo.match14 m WITH(NOLOCK) ON b.matchid = m.matchid
		WHERE winlostdate BETWEEN @f_date AND @t_date
			AND b.sporttype = @sporttype			
		GROUP BY matchcode, homeid, awayid, bettype, leagueid
	END
	
	SELECT * FROM @RPT
	ORDER BY bettype, leagueid, matchcode, homeid

GO

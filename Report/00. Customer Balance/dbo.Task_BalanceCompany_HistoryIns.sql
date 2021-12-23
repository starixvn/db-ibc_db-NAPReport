/*<info serverAlias="DBSUM-bodb_Summary" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_Summary]
GO

ALTER PROCEDURE [dbo].[Task_BalanceCompany_HistoryIns]
AS

/*
	Creator: Ned.Le
	Date: 2020-09-14
	Task: used for company balance difference report
	DB: DBSUM.bodb_Summary
	Revisions:
		20200914@Ned.Le: Migrate Log DBs from DB052 to DB054 (Phase 1) (#140783)
		20211118@Cherry: Split Transfer table (#164378)
*/

BEGIN
	
	SET NOCOUNT ON 

	DECLARE @BalanceUpDay SMALLDATETIME
	SET @BalanceUpDay = DATEADD(DAY,-7,CONVERT(VARCHAR(10), CURRENT_TIMESTAMP, 120))

	IF (DATEPART(weekday,@BalanceUpDay)<> 6)
	BEGIN
		PRINT 'Today is not Friday'
		SELECT 'Today is not Friday' RESULT
		RETURN
	END
	
	CREATE TABLE #tmpDiff (diff MONEY)
	
	INSERT INTO #tmpDiff (diff)
	SELECT
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*(b.actualrate - e.actualrate)) diff
	FROM bodb02.dbo.bettrans b WITH (NOLOCK)		
		INNER JOIN bodb02.dbo.exchange e WITH (NOLOCK) ON b.currency = e.exchangeid
	WHERE
		ruben = 1 AND winlostdate <= @BalanceUpDay AND bettype < 19999
	
	INSERT INTO #tmpDiff (diff)	
	SELECT
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*(b.actualrate - e.actualrate)) diff
	FROM bodb02.dbo.[Transfer] b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.exchange e WITH (NOLOCK) ON b.currency = e.exchangeid
	WHERE
		winlostdate <= @BalanceUpDay		

	IF NOT EXISTS(
		SELECT 1
		FROM #tmpDiff		
		WHERE ABS(diff) > 0.01
	)
	BEGIN
		PRINT 'No difference'
		SELECT 'No difference' RESULT
		RETURN
	END

	IF EXISTS(SELECT 1 FROM CompanyBalance_History (READPAST) WHERE BalanceUpDay = @BalanceUpDay)
	BEGIN
		DELETE FROM CompanyBalance_History WHERE BalanceUpDay = @BalanceUpDay
	END
	
	CREATE TABLE #tmpData 
	(	Currency INT,
		CompBalBefore FLOAT,
		CompBalAfter FLOAT
	)
	
	INSERT INTO #tmpData(Currency, CompBalBefore, CompBalAfter)
	SELECT    		
		exchangeid AS currency,
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate) CompBalBefore,
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)* e.actualrate) CompBalAfter
	FROM bodb02.dbo.bettrans b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.exchange e WITH (NOLOCK) ON b.currency = e.exchangeid
	WHERE
		ruben = 1 AND winlostdate <= @BalanceUpday AND bettype < 19999
	GROUP BY  exchangeid
	
	INSERT INTO #tmpData(Currency, CompBalBefore, CompBalAfter)
	SELECT    		
		exchangeid AS currency,
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate) CompBalBefore,
		SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)* e.actualrate) CompBalAfter
	FROM bodb02.dbo.[Transfer] b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.exchange e WITH (NOLOCK) ON b.currency = e.exchangeid
	WHERE
		winlostdate <= @BalanceUpday
	GROUP BY  exchangeid

	INSERT INTO CompanyBalance_History(BalanceUpDay, Currency, CompBalBefore, CompBalAfter)
	SELECT    
		@BalanceUpday AS BalanceUpday,
		Currency,
		SUM(CompBalBefore) CompBalBefore,
		SUM(CompBalAfter) CompBalAfter
	FROM #tmpData		
	GROUP BY  Currency
	
	DROP TABLE #tmpDiff
	DROP TABLE #tmpData

END
GO

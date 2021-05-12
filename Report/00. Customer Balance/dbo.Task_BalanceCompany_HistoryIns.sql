/*<info serverAlias="DBSUM-bodb_Summary" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_Summary]
GO

CREATE PROCEDURE [dbo].[Task_BalanceCompany_HistoryIns]
AS

/*
	Creator: Ned.Le
	Date: 2020-09-14
	Task: used for company balance difference report
	DB: DBSUM.bodb_Summary
	Revisions:
		20200914@Ned.Le: Migrate Log DBs from DB052 to DB054 (Phase 1) (#140783)
		20210510@Roy: NAP Report - Adjust balance reports for new movebet process (#154649)
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

	IF NOT EXISTS(
		SELECT 1
		FROM
		(
			SELECT
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*(b.actualrate - e.actualrate)) diff
			FROM bodb02.dbo.bettrans b WITH (NOLOCK)
				INNER JOIN bodb02.dbo.custinfo ci (NOLOCK) ON b.custid = ci.custid
				INNER JOIN bodb02.dbo.exchange e (NOLOCK) ON ci.currency = e.exchangeid
			WHERE
				ruben=1 AND winlostdate <= @BalanceUpDay
		) a
		WHERE ABS(a.diff) > 0.01
	)
	BEGIN
		PRINT 'No difference'
		SELECT 'No difference' RESULT
		RETURN
	END

	IF EXISTS(SELECT 1 FROM CompanyBalance_History (NOLOCK) WHERE BalanceUpDay = @BalanceUpDay)
	BEGIN
		DELETE FROM CompanyBalance_History WHERE BalanceUpDay = @BalanceUpDay
	END

	INSERT INTO CompanyBalance_History(BalanceUpDay, Currency, CompBalBefore, CompBalAfter)
	SELECT    
		@BalanceUpday AS BalanceUpday,
		exchangeid AS currency,
		SUM( (winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)* b.actualrate) CompBalBefore,
		SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)* e.actualrate) CompBalAfter
	FROM bodb02.dbo.bettrans b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.custinfo ci (NOLOCK) ON b.custid = ci.custid
		INNER JOIN bodb02.dbo.exchange e (NOLOCK) ON ci.currency = e.exchangeid
	WHERE
		ruben=1 AND winlostdate <= @BalanceUpday
	GROUP BY  exchangeid

END
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Company]
	@IsYesterdayBalance BIT = 0 
AS
/*
Task: used for company balance report.
DB: DBACC.bodb02
Revisions:
	- --bettrans.bettype between 1 and 106 AND --20080926: removed by Thien, should include all bettype
	- 20090217@Kiwi: In case of bettype < 99, we use column actualrate on bettrans table instead of exchange table.
	- 20090619@Kiwi: Remove Exchange
	- 20110516@Lukas: re-arrange bettype
	- 20141126@Tom.Vo:
		1. Change Alias DB DB06 to DBACC
		2. Add 2 new columns Today Rate and Yesterday Rate
	- 20151221@Sophia: Company Yesterday Balance [Redmine: #49458]
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Today SMALLDATETIME
		,@Yesterday SMALLDATETIME	

	IF OBJECT_ID('tempdb..#TblCurrency') IS NOT NULL
	BEGIN
		DROP TABLE #TblCurrency
	END

	CREATE TABLE #TblCurrency (
		ExchangeId INT
		,Today FLOAT
		,Yesterday FLOAT
		)

	
	IF OBJECT_ID('tempdb..#TblBalance') IS NOT NULL
	BEGIN
		DROP TABLE #TblBalance
	END

	CREATE TABLE #TblBalance (
		Currency INT
		,CurrencyName NVARCHAR(10)
		,TotalamtLocal DECIMAL(20,8)
		,Totalamt DECIMAL(20,8)
		)
		

	SELECT @Today =  CONVERT(DATE, GETDATE())
	SELECT @Yesterday = DATEADD(DAY, - 1, @Today)

	IF @IsYesterdayBalance = 1 
	BEGIN
		SELECT @Today =  @Yesterday
		SELECT @Yesterday = DATEADD(DAY, - 1, @Today)
	END 
	
	INSERT INTO #TblCurrency (
		ExchangeId
		,Yesterday
		,Today
		)
	SELECT ExchangeId
		,[1] Yesterday
		,[2] Today
	FROM (
		SELECT CASE 
				WHEN ExchangeDate = @Yesterday THEN 1
				WHEN ExchangeDate = @Today THEN 2
				ELSE 3
				END _Date
			,ExchangeId
			,ActualRate
		FROM dbo.[ExchangeDailyOanda] WITH (NOLOCK)
		WHERE (ExchangeDate BETWEEN @Yesterday AND @Today)
		) tblSource
	PIVOT(MAX(ActualRate) FOR _Date IN ([1], [2])) tblDec

	IF @IsYesterdayBalance = 0
	BEGIN 	
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum(CASE 
					WHEN bt.bettype < 19999 THEN ((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate)
					ELSE ((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate)
					END) TotalAmt
		FROM dbo.bettrans bt WITH (NOLOCK)
		WHERE ruben = 1
			  AND bt.bettype NOT IN (21008, 21009)
		GROUP BY currency
			,currencyname

	END 
	ELSE 
	BEGIN 		
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum(CASE 
					WHEN bt.bettype < 19999 THEN ((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate)
					ELSE ((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate)
					END) TotalAmt
		FROM dbo.bettrans bt WITH (NOLOCK)
		WHERE ruben = 1
			  AND winlostdate <= @Today
			  AND bt.bettype NOT IN (21008, 21009)
		GROUP BY currency
			,currencyname
	END 


	SELECT CurrencyName
		,TotalamtLocal
		,TotalAmt
		,Today
		,Yesterday
	FROM #TblBalance bt WITH (NOLOCK)
		LEFT JOIN #TblCurrency tmp
		ON bt.currency = tmp.ExchangeId
	ORDER BY CurrencyName

 	
 
	IF OBJECT_ID('tempdb..#TblBalance') IS NOT NULL
	BEGIN
		DROP TABLE #TblBalance
	END

	IF OBJECT_ID('tempdb..#TblCurrency') IS NOT NULL
	BEGIN
		DROP TABLE #TblCurrency
	END
END
GO
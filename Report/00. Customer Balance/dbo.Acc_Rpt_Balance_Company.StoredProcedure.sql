/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
	- 20210505@Sol: NAP - Alpha - Allow more time for transfer - [Redmine: #149927]
	- 20211124@Danny: Split transfer tickets out of bettrans [Redmine: #164196]
	- 20230227@Evan: Balance-Up support transfer 247 [Redmine: #173554]
	- 20240826@Bobby: Reward Payment transfer [Redmine: #209633]


*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Today SMALLDATETIME
		,@Yesterday SMALLDATETIME	

	DROP TABLE IF EXISTS #TblCurrency;
	CREATE TABLE #TblCurrency (
		ExchangeId INT
		,Today FLOAT
		,Yesterday FLOAT
	)

	-- get move bet date
	DECLARE @balanceUpDay SMALLDATETIME, @moveBetsDay SMALLDATETIME
	DECLARE @tblMoveBetBalanceUp AS TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)

	INSERT INTO @tblMoveBetBalanceUp(BalanceUpDay,MoveBetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	SELECT @balanceUpDay = BalanceUpDay, @moveBetsDay = MoveBetsDay FROM @tblMoveBetBalanceUp

	DROP TABLE IF EXISTS #TblBalance;
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
		-- bettrans
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate) TotalAmt
		FROM dbo.bettrans bt WITH (NOLOCK)
		WHERE ruben = 1
			  AND winlostdate > @moveBetsDay
		GROUP BY currency
			,currencyname

		-- transfer
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate) TotalAmt
		FROM dbo.transfer bt WITH (NOLOCK)
		WHERE bt.bettype NOT IN (21008, 21009)
			 AND 1 = CASE WHEN bettype = 19999 AND winlostdate > @moveBetsDay THEN 0 --> new sum
						WHEN bettype = 20000 AND winlostdate > @balanceUpDay THEN 0 --> new bal
						WHEN winlostdate < @balanceUpDay THEN 0 --> old data
					ELSE 1 END
		GROUP BY currency
			,currencyname

		-- transferExtra
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
		)
		SELECT bt.currencyId AS Currency
			,ex.Currency AS CurrencyName
			,sum(bt.credit - bt.debit) TotalamtLocal
			,sum((bt.credit - bt.debit) * bt.actualrate) TotalAmt
		FROM dbo.transferExtra bt WITH (NOLOCK)
		INNER JOIN dbo.Exchange ex WITH(NOLOCK) ON ex.ExchangeId = bt.currencyId
		WHERE 1 = CASE 
					WHEN bettype = 30000 AND winlostdate > @balanceUpDay THEN 0 --> new bal
					WHEN winlostdate < @balanceUpDay THEN 0 --> old data
					ELSE 1 END
		GROUP BY bt.currencyId
			,ex.Currency

	END 
	ELSE 
	BEGIN 		
		-- bettrans
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate) TotalAmt
		FROM dbo.bettrans bt WITH (NOLOCK)
		WHERE ruben = 1
			  AND winlostdate <= @Today
			  AND winlostdate > @moveBetsDay
		GROUP BY currency
			,currencyname

		-- transfer
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
			)
		SELECT bt.currency AS Currency
			,bt.CurrencyName
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm)) TotalamtLocal
			,sum((bt.winlost - bt.actual_stake + bt.awinlost + bt.mwinlost + bt.swinlost + bt.scomm) * bt.actualrate) TotalAmt
		FROM dbo.transfer bt WITH (NOLOCK)
		WHERE winlostdate <= @Today
				AND bt.bettype NOT IN (21008, 21009)
			 AND 1 = CASE WHEN bettype = 19999 AND winlostdate > @moveBetsDay THEN 0 --> new sum
						WHEN bettype = 20000 AND winlostdate > @balanceUpDay THEN 0 --> new bal
						WHEN winlostdate < @balanceUpDay THEN 0 --> old data
					ELSE 1 END
		GROUP BY currency
			,currencyname

		-- transferExtra
		INSERT INTO #TblBalance (
			Currency
			,CurrencyName
			,TotalamtLocal
			,Totalamt
		)
		SELECT bt.currencyId AS Currency
			,ex.Currency AS CurrencyName
			,sum(bt.credit - bt.debit) TotalamtLocal
			,sum((bt.credit - bt.debit) * bt.actualrate) TotalAmt
		FROM dbo.transferExtra bt WITH (NOLOCK)
		INNER JOIN dbo.Exchange ex WITH(NOLOCK) ON ex.ExchangeId = bt.currencyId
		WHERE winlostdate <= @Today
			AND 1 = CASE 
					WHEN bettype = 30000 AND winlostdate > @balanceUpDay THEN 0 --> new bal
					WHEN winlostdate < @balanceUpDay THEN 0 --> old data
					ELSE 1 END
		GROUP BY bt.currencyId
			,ex.Currency
	END 


	SELECT CurrencyName
		,SUM(TotalamtLocal) TotalamtLocal
		,SUM(TotalAmt) TotalAmt
		,Today
		,Yesterday
	FROM #TblBalance bt WITH (NOLOCK)
		LEFT JOIN #TblCurrency tmp
		ON bt.currency = tmp.ExchangeId
	GROUP BY CurrencyName, Today, Yesterday
	ORDER BY CurrencyName

END
GO
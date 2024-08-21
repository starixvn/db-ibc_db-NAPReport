/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Agent_Yesterday
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Agent Balance
	DB: DB06.BODB02
	Revisions:
		20200930@Roy: NAP Report - Enhance the way we get Direct Balance report (#144094)
		20201030@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
		20211111@Cherry: Split transfer table (#164378)
		20230119@Roy: NAP Report - BU 247 (#175206)
		20240821@Jaden: Add currency name for web (#199583)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate datetime 
	SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)
	
	CREATE TABLE #directAgent (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,mrecommend INT
		)
	---get directAgent---
	INSERT INTO #directAgent
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.mrecommend
	FROM dbo.custinfo ci WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON ci.roleid = 2 AND ci.custid = d.custid
	WHERE ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)
	
	---Include finance accounts---
	INSERT INTO #directAgent
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.mrecommend
	FROM dbo.CustAgent AS ca WITH (NOLOCK)
		INNER JOIN dbo.custinfo ci WITH (NOLOCK) ON ci.roleid = 2 AND ca.custid = ci.custid
	WHERE ca.IsInternal = 1
		AND ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
		AND NOT EXISTS ( SELECT 1 FROM #directAgent d WHERE ca.custid = d.custid )
	OPTION (RECOMPILE)

	CREATE CLUSTERED INDEX [CIX_Direct] ON #directAgent( mrecommend, custid )
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--see Balance_Direct_Master report
			case when b.winlostdate <= @MoveBetsDay and bettype < 19999 then NULL
				 else b.recommend
			end recommend,
			isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end),0) AS bal,
			
			isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0)
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end)*actualrate),0) AS Basebal
	FROM	bettrans b WITH (NOLOCK)
	WHERE	ruben = 1 AND 
		--status NOT IN ('VOID','REJECT','REFUND')
		statusID NOT IN (101,102,103)
		AND b.bettype < 19999
		AND EXISTS ( SELECT 1 FROM #directAgent d WHERE b.mrecommend = d.mrecommend )
	GROUP BY case when b.winlostdate <= @MoveBetsDay and bettype < 19999 then NULL
				 else b.recommend
			end 
			
	OPTION(RECOMPILE)
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--see Balance_Direct_Master report
			case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.recommend
			end recommend,
			isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end),0) AS bal,
			
			isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0)
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end)*actualrate),0) AS Basebal
	FROM	dbo.[Transfer] b WITH (NOLOCK)
	WHERE	b.bettype NOT IN (21008, 21009)
		AND EXISTS ( SELECT 1 FROM #directAgent d WHERE b.mrecommend = d.mrecommend )
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.recommend
			end
			
	OPTION(RECOMPILE)
	
	---Return data---
	SELECT	a.custid,
			a.username, 
			a.currency, 
			MAX(ex.currency) AS currencyname,
			SUM(IsNull(bal.Balance,0)) AS Balance, 
			SUM(IsNull(bal.BaseBalance,0)) AS BaseBalance
	FROM	#directAgent a 
			LEFT JOIN #Data Bal ON a.custid = Bal.Custid
			LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = a.currency
	GROUP BY a.custid,
			a.username, 
			a.currency
	ORDER BY a.username
	
	DROP TABLE #Data
	DROP TABLE #directAgent
END

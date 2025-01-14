/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Master_Yesterday
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Master Balance 
	DB: DB06.BODB02
	Revisions:
		20200930@Roy: NAP Report - Enhance the way we get Direct Balance report (#144094)
		20201030@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
		20211111@Cherry: Split transfer table (#164378)
		20230119@Roy: NAP Report - BU 247 (#175206)
		20240821@Jaden: Add currency name for web (#199583)
		20241022@Jaden: Credit Reward Wallet (#212482)
		20241230@Jaden: Add support to view super/master's direct member (#213629)
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentdate DATETIME
	SELECT @currentdate = convert(varchar(10), CURRENT_TIMESTAMP, 120)
	
	CREATE TABLE #directMaster (custid INT,username VARCHAR(50), currency INT, srecommend INT)
	---get directMaster---
	INSERT INTO #directMaster
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.srecommend
	FROM dbo.custinfo ci WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON ci.roleid = 3 AND ci.custid = d.custid
	WHERE ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)
	
	---Include finance accounts---
	INSERT INTO #directMaster
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.srecommend
	FROM dbo.CustMaster AS cm WITH (NOLOCK)
		INNER JOIN dbo.custinfo ci WITH (NOLOCK) ON ci.roleid = 3 AND cm.custid = ci.custid
	WHERE cm.IsInternal = 1
		AND ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
		AND NOT EXISTS ( SELECT 1 FROM #directMaster d WHERE cm.custid = d.custid )
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_Direct] ON #directMaster( srecommend, custid )
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT 	--see Balance_Direct_Master report
			case when b.winlostdate <= @MoveBetsDay then NULL
				 else b.mrecommend
			end mrecommend,
			isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
			+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0) AS bal, 	
			
			isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
			+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0) AS Basebal								
	FROM	bettrans b WITH (NOLOCK)	
	WHERE	ruben = 1 AND 
		--status NOT IN ('VOID','REJECT','REFUND')				
		statusID NOT IN (101,102,103)
		AND b.bettype < 19999
		AND EXISTS ( SELECT 1 FROM #directMaster d WITH (NOLOCK) WHERE b.srecommend = d.srecommend )
	GROUP BY case when b.winlostdate <= @MoveBetsDay then NULL
				else b.mrecommend
			end
			
	OPTION (RECOMPILE)
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT 	--see Balance_Direct_Master report
			case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.mrecommend
			end mrecommend,
			isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
			+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0) AS bal, 	
			
			isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
			+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0) AS Basebal								
	FROM	dbo.[Transfer] b WITH (NOLOCK)	
	WHERE	b.bettype NOT IN (21008, 21009)
		AND EXISTS ( SELECT 1 FROM #directMaster d WITH (NOLOCK) WHERE b.srecommend = d.srecommend )
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.mrecommend
			end
			
	OPTION (RECOMPILE)
	
	--reward wallet
	--the pendingreward amount super haven't paid master
	CREATE TABLE #unpaidReward 
	(
		masterid INT,
		amount MONEY,
		amount_rm MONEY
	)

	INSERT #unpaidReward (masterid, amount, amount_rm)
	SELECT Mrecommend, SUM(amount) amount_original, SUM(amount * actualrate) amount_rm
	FROM bodb02.dbo.SabaWalletTicket WITH (NOLOCK)
	WHERE PaymentStatus & 4 = 0 --check 3rd bit from right is 0
		AND SabaWalletTicket.WinlostDate < @currentDate
	GROUP BY Mrecommend

	---Return data---
	;WITH grouped_data AS (
		SELECT custid, SUM(Balance) AS Balance, SUM(BaseBalance) AS BaseBalance
		FROM #Data
		GROUP BY custid
	)
	SELECT	m.custid,
			'Master' as role,
			m.username, 
			m.currency,
			MAX(ex.currency) AS currencyname,
			SUM(IsNull(bal.Balance,0)) AS Balance,
			SUM(IsNull(bal.BaseBalance,0)) AS BaseBalance
			, SUM(ISNULL(ur.amount, 0)) AS Reward
			, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM	#directMaster m WITH (NOLOCK)
			LEFT JOIN grouped_data as  bal ON m.custid = bal.custid
			LEFT JOIN bodb02.dbo.Exchange ex WITH (NOLOCK) ON ex.exchangeid = m.currency
			LEFT JOIN #unpaidReward ur ON ur.masterid = m.custid
	GROUP BY m.custid,
			m.username, 
			m.currency
	ORDER BY m.username
	
	DROP TABLE #Data
	DROP TABLE #directMaster
END

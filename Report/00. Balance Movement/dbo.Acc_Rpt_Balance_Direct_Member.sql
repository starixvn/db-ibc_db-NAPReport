/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Member
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Jamie
	Date: 2009-07-17
	Task: Direct Member Balance
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of agent instead of get agent balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	- 20130131@Johnson: Add filter by username and currency
	- 20200930@Roy: NAP Report - Enhance the way we get Direct Balance report (#144094)
	- 20201030@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
	- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
	- 20211111@Cherry: Split transfer table (#164378)
	- 20230119@Roy: NAP Report - BU 247 (#175206)
	- 20240821@Jaden: Add currency name for web (#199583)
	- 20241022@Jaden: Credit Reward Wallet (#212482)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	CREATE TABLE #directMember (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,recommend INT
		)
	---get directMember---
	INSERT INTO #directMember
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.recommend	 
	FROM dbo.custinfo ci WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON ci.roleid = 1 AND ci.custid = d.custid
	WHERE ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)

	---Include finance accounts---
	INSERT INTO #directMember
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.recommend		
	FROM dbo.CustAgent AS ca WITH (NOLOCK)
		INNER JOIN dbo.custinfo ci WITH (NOLOCK) ON ci.roleid = 1 AND ca.custid = ci.recommend
	WHERE ca.IsInternal = 1
		AND ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
		AND NOT EXISTS ( SELECT 1 FROM #directMember d WHERE ci.custid = d.custid )
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_Direct] ON #directMember( recommend, custid )	
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--see Balance_Direct_Master report
		case when b.winlostdate <= @MoveBetsDay then NULL
			 else b.custid
		end custid,
		isnull(SUM(winlost - actual_stake + playercomm),0) bal,
		isnull(SUM((winlost - actual_stake + playercomm)* actualrate),0) as Basebal
	FROM	bettrans b WITH (NOLOCK)
	WHERE	ruben = 1 AND 
		--status NOT IN ('VOID','REJECT','REFUND')
		statusID NOT IN (101,102,103)
		AND b.bettype < 19999
		AND EXISTS ( SELECT 1 FROM #directMember d WITH (NOLOCK) WHERE b.recommend = d.recommend )
	GROUP BY case when b.winlostdate <= @MoveBetsDay then NULL
				 else b.custid
			end
			
	OPTION (RECOMPILE)
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--see Balance_Direct_Master report
		case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
			when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
			when b.winlostdate < @BalanceUpDay then NULL --> old bal
			else b.custid
		end custid,
		isnull(SUM(winlost - actual_stake + playercomm),0) bal,
		isnull(SUM((winlost - actual_stake + playercomm)* actualrate),0) as Basebal
	FROM	dbo.[Transfer] b WITH (NOLOCK)
	WHERE	b.bettype NOT IN (21008, 21009)
		AND EXISTS ( SELECT 1 FROM #directMember d WITH (NOLOCK) WHERE b.recommend = d.recommend )		
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay AND bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.custid
			end
			
	OPTION (RECOMPILE)
	
	--reward wallet
	--the pendingreward amount cust haven't been paid
	CREATE TABLE #unpaidReward 
	(
		custid INT,
		amount MONEY,
		amount_rm MONEY
	)

	INSERT #unpaidReward (custid, amount, amount_rm)
	SELECT custid, SUM(amount) amount_original, SUM(amount * actualrate) amount_rm
	FROM bodb02.dbo.SabaWalletTicket WITH (NOLOCK)
	WHERE PaymentStatus & 1 = 0 --check 1st bit from right
	  AND custid IN (SELECT custid FROM #directMember)
	GROUP BY custid

	---Return data---
	SELECT  mem.custid,
			mem.username, 
			mem.currency, 
			MAX(ex.currency) AS currencyname,
			SUM(IsNull(bal.Balance,0)) Balance, 
			SUM(IsNull(bal.BaseBalance,0)) BaseBalance
			, SUM(ISNULL(ur.amount, 0)) AS Reward
			, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM	#directMember mem WITH (NOLOCK)
			LEFT JOIN #Data bal ON mem.custid = bal.custid
			LEFT JOIN bodb02.dbo.Exchange ex WITH (NOLOCK) ON ex.exchangeid = mem.currency
			LEFT JOIN #unpaidReward ur ON mem.custid = ur.custid
	GROUP BY mem.custid,
			mem.username, 
			mem.currency
	ORDER BY mem.username
	

	DROP TABLE #directMember
END

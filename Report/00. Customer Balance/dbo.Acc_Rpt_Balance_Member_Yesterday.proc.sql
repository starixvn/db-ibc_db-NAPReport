/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Member_Yesterday]
	@agentid	INT
AS
/*
Created:
Task : Get member yesterday balance
DB: DBACC.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Enhence Performance
	- 20100112@Jamie: Get currencyName from Cache
	- 20101229@Lukas: Re-arrange bettype
	- 20131118@Lukas: add filter to exclude running tickets
	- 20190923@Bobby: Enhance SMA Balance report [redmine: #119990]
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
	- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
	- 20211111@Cherry: Split transfer table (#164378)
	- 20230119@Roy: NAP Report - BU 247 (#175206)
	- 20240821@Jaden: Add currency name for web (#199583)
	- 20241022@Jaden: Credit Reward Wallet (#212482)
	- 20241230@Jaden: Add support to view super/master's direct member (#213629)
	- 20250721@Jaden: Exclude agency cash in today's balance for Direct Yesterday reports (#233327)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate		SMALLDATETIME
			, @yesterday		SMALLDATETIME
			, @_agentid			INT
			, @srecommend		INT

		SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
			,@yesterday			= @currentDate -1
			,@_agentid			= ISNULL(@agentid, 0)
			
	SELECT @srecommend = srecommend
	FROM dbo.custinfo  (nolock)
	WHERE custid = @_agentid
		AND roleid = 2

	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT
			custid,
			SUM(bet.winlost) AS balance,
			SUM(bet.winlost * b.actualrate) AS baseBalance
	FROM dbo.bettrans b with (nolock)
		CROSS APPLY (
			SELECT 
					--skip volatile rows during move bet process (see Balance_Direct_Master report)
					CASE WHEN b.winlostdate <= @MoveBetsDay 
						THEN 0 ELSE 1 END
					*
					CASE 
						WHEN b.bettype >= 20000 OR b.winlostdate <= @yesterday THEN (winlost - actual_stake + playercomm) 
						ELSE 0
					END
				AS winlost
		) AS bet
	WHERE b.recommend = @_agentid
		AND b.winlostdate <= @currentDate
		AND b.ruben = 1
		AND b.statusID NOT IN (101,102,103)
		AND b.bettype < 19999
	GROUP BY b.custid
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT
			custid,
			SUM(CASE WHEN b.bettype between 31001 and 31006 and b.winlostdate >= @currentDate THEN 0 ELSE bet.winlost END) AS balance,
			SUM(CASE WHEN b.bettype between 31001 and 31006 and b.winlostdate >= @currentDate THEN 0 ELSE bet.winlost END*b.actualrate) AS baseBalance
	FROM dbo.[Transfer] b with (nolock)
		CROSS APPLY (
			SELECT 
					--skip volatile rows during move bet process (see Balance_Direct_Master report)
					(CASE WHEN b.winlostdate > @MoveBetsDay AND b.bettype = 19999 THEN 0
						WHEN b.winlostdate > @BalanceUpDay AND b.bettype = 20000 THEN 0 --> new bal
						WHEN b.winlostdate < @BalanceUpDay THEN 0 --> old bal
					ELSE 1 END)
					*
					CASE 
						WHEN b.bettype >= 20000 OR b.winlostdate <= @yesterday THEN (winlost - actual_stake + playercomm) 
						ELSE 0
					END
				AS winlost
		) AS bet
	WHERE b.recommend = @_agentid
		AND b.srecommend = @srecommend
		AND b.winlostdate <= @currentDate		
		AND b.bettype NOT IN (21008, 21009)
	GROUP BY b.custid
		
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
	  AND WinlostDate <= @yesterday
	  AND Recommend = @_agentid
	GROUP BY custid

	;WITH grouped_data AS (
		SELECT custid, SUM(Balance) AS Balance, SUM(BaseBalance) AS BaseBalance
		FROM #Data
		GROUP BY custid
	)
	SELECT
		c.custid, 
		'Member' as role,
		c.username, 
		c.currency,
		MAX(ex.currency) AS currencyname,
		IsNull(SUM(b.balance), 0) Balance,
		IsNull(SUM(baseBalance),0) AS BaseBalance
		, SUM(ISNULL(ur.amount, 0)) AS Reward
		, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM
		dbo.custinfo c (nolock)
		LEFT JOIN grouped_data b ON c.custid = b.custid
		LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = c.currency
		LEFT JOIN #unpaidReward ur ON ur.custid = c.custid
	WHERE
		c.roleid = 1 AND c.recommend = @_agentid 
	GROUP BY 
		c.custid, 
		c.username, 
		c.currency
	ORDER BY c.username
	
	DROP TABLE #Data
END
GO
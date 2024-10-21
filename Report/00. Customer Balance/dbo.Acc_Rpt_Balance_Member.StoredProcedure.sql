/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Member]
	@agentid	INT
AS
/*
Created:
Task : Get member balance
DB: DBACC.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Enhence Performance
	- 20100112@Jamie: Get currencyName from Cache
	- 20131118@Lukas: add filter to exclude running tickets
	- 20190923@Bobby: Enhance SMA Balance report [redmine: #119990]
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
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

	DECLARE @currentDate		SMALLDATETIME
			, @_agentid			INT
			, @srecommend		INT

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
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
	SELECT	--skip volatile rows during move bet process, see Balance_Direct_Master report
					case when b.winlostdate <= @MoveBetsDay then NULL
						 else b.custid
					end custid,
					SUM(b.winlost - b.actual_stake + b.playercomm) AS Balance,
					SUM((b.winlost - b.actual_stake + b.playercomm)* b.actualrate) AS BaseBalance
	FROM	dbo.bettrans b with (nolock)
	WHERE	b.recommend = @_agentid
		AND b.winlostdate <= @currentDate
		AND b.bettype < 19999
		AND b.ruben = 1
		AND b.statusID NOT IN (101,102,103)
	GROUP BY case when b.winlostdate <= @MoveBetsDay then NULL
				else b.custid
			end
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--skip volatile rows during move bet process, see Balance_Direct_Master report
					case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay and b.bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.custid
			end custid,
					SUM(b.winlost - b.actual_stake + b.playercomm) AS Balance,
					SUM((b.winlost - b.actual_stake + b.playercomm)* b.actualrate) AS BaseBalance
	FROM	dbo.[Transfer] b with (nolock)
	WHERE	b.recommend = @_agentid
		AND b.srecommend = @srecommend
		AND b.winlostdate <= @currentDate				
		AND b.bettype NOT IN (21008, 21009)
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				when b.winlostdate > @BalanceUpDay and b.bettype = 20000 then NULL --> new bal
				when b.winlostdate < @BalanceUpDay then NULL --> old bal
				else b.custid
			end

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
	  AND Recommend = @_agentid
	GROUP BY custid

	SELECT
			c.custid, 
			c.username, 
			c.currency,
			MAX(ex.currency) AS currencyname,
			IsNull(SUM(b.Balance), 0) Balance,
			IsNull(SUM(b.BaseBalance),0) AS BaseBalance
			, SUM(ISNULL(ur.amount, 0)) AS Reward
			, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM
		dbo.custinfo c (nolock)
		LEFT JOIN #Data b ON c.custid = b.custid
		LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = c.currency
		LEFT JOIN #unpaidReward ur ON ur.custid = c.custid
	WHERE
		c.roleid = 1 AND c.recommend = @_agentid
	GROUP BY c.custid, 
			c.username, 
			c.currency
	ORDER BY c.username

	DROP TABLE #Data
	
END
GO
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Agent_Yesterday]
	@masterid INT = 0
AS
/*
Created:
Task: Get Agent yesterday balance
DB: DB06.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Remove Exchange
	- 20100111@Jamie: Get currencyName from cache
	- 20110516@Lukas: re-arrange bettype
	- 20131119@Lukas: remove running/void/reject/refund tickets
	- 20190919@Bobby: Enhance SMA Balance report [redmine: #119990]
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

	DECLARE @currentDate	SMALLDATETIME
		, @yesterday		SMALLDATETIME
		, @_masterid		INT
		, @srecommend		INT

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
		,@yesterday			= @currentDate -1
		,@_masterid			= ISNULL(@masterid,0)
	
	CREATE TABLE #AgentInfo (
		custid				INT PRIMARY KEY
		, username			NVARCHAR(50)
		, currency			INT
	)

	INSERT INTO #AgentInfo (custid, username, currency)
	SELECT c.custid, c.username, c.currency
	FROM dbo.custinfo c (nolock)
	WHERE c.mrecommend = @_masterid
		AND c.roleid = 2
		
	SELECT @srecommend = srecommend
	FROM dbo.custinfo  (nolock)
	WHERE mrecommend = @_masterid
		AND roleid = 2

	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	b.recommend AS custid
		,SUM(bet.Balance) AS Balance
		,SUM(bet.Balance * b.actualrate) AS BaseBalance
	FROM #AgentInfo ai
		INNER JOIN dbo.bettrans b WITH (NOLOCK)	ON b.recommend = ai.custid
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN b.winlostdate <= @MoveBetsDay
					THEN 0 ELSE 1 END
				*
				CASE 
					WHEN b.winlostdate <= @yesterday THEN
						(CASE WHEN b.custid = b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
						+ (CASE WHEN b.custid <> b.recommend THEN winlost-actual_stake+playercomm else 0 end) -- member level
					ELSE 0
				END 
				AS Balance
			) AS bet
	WHERE b.winlostdate <= @currentDate
		AND b.ruben = 1
		AND b.statusID NOT IN (101,102,103)
		AND b.bettype < 19999
	GROUP BY b.recommend
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	b.recommend AS custid
		,SUM(bet.Balance) AS Balance
		,SUM(bet.Balance * b.actualrate) AS BaseBalance
	FROM #AgentInfo ai
		INNER JOIN dbo.[Transfer] b WITH (NOLOCK) ON b.recommend = ai.custid
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				(CASE WHEN b.winlostdate > @MoveBetsDay AND b.bettype = 19999 THEN 0
					WHEN b.winlostdate > @BalanceUpDay AND b.bettype = 20000 THEN 0 --> new bal
					WHEN b.winlostdate < @BalanceUpDay THEN 0 --> old bal
				ELSE 1 END)
				*
				CASE 
					WHEN (b.bettype >= 20000 OR b.winlostdate <= @yesterday) THEN
						(CASE WHEN b.custid = b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
						+ (CASE WHEN b.custid <> b.recommend THEN winlost-actual_stake+playercomm else 0 end) -- member level
					ELSE 0
				END 
				AS Balance
			) AS bet
	WHERE b.winlostdate <= @currentDate		
		AND b.bettype NOT IN (21008, 21009)
		AND b.srecommend = @srecommend
	GROUP BY b.recommend

	--reward wallet
	--the pendingreward amount master haven't paid agent
	CREATE TABLE #unpaidReward 
	(
		agentid INT,
		amount MONEY,
		amount_rm MONEY
	)

	INSERT #unpaidReward (agentid, amount, amount_rm)
	SELECT Recommend, SUM(amount) amount_original, SUM(amount * actualrate) amount_rm
	FROM bodb02.dbo.SabaWalletTicket WITH (NOLOCK)
	WHERE PaymentStatus & 2 = 0 --check 2nd bit from right is 0
	  AND WinlostDate <= @yesterday
	GROUP BY Recommend

	SELECT c.custid, c.username,c.currency
		,MAX(ex.currency) AS currencyname
		,ISNULL(SUM(Balance),0) Balance
		,ISNULL(SUM(BaseBalance),0) BaseBalance  
		, SUM(ISNULL(ur.amount, 0)) AS Reward
		, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM #AgentInfo c
		LEFT JOIN #Data AS bal ON c.custid = bal.custid
		LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = c.currency
		LEFT JOIN #unpaidReward ur ON ur.agentid = c.custid
	GROUP BY c.custid, c.username,c.currency
	ORDER BY c.username
	
	DROP TABLE #Data
	DROP TABLE #AgentInfo
	
END
GO
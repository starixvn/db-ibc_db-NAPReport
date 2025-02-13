/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Master] 
	@superid		INT = 0
	, @Currency		INT = NULL
AS
/*
Created:
Task : Get Master balance
DB: DB06.bodb02
Original:
Revisions:
		--UPDATED 02/10/2006
		--Th(060719):	Get Total Balance of all masters
		--				Use left join to get all masters (even the master which has no bettrans) and calculate BaseBalance faster
		--				Refer admin_rpt_mabalance in case require superid as input
		- 20090619@Kiwi: Remove Exchange
		--20090515@Jamie: Enhance for using right index
		- 20131119@Lukas: remove running/void/reject/refund tickets
		- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
		- 20190919@Bobby: Enhance SMA Balance report [redmine: #119990]
		- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
		- 20211111@Cherry: Split transfer table (#164378)
		- 20230119@Roy: NAP Report - BU 247 (#175206)
	    - 20240821@Jaden: Add currency name for web (#199583)
		- 20241022@Jaden: Credit Reward Wallet (#212482)
		- 20241230@Jaden: Add support to view super/master's direct member (#213629)
						  Removed unnecessary parameters
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate	SMALLDATETIME

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
		,@superid			= ISNULL(@superid,0)
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)

	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT CASE WHEN b.mrecommend > 0 THEN b.mrecommend ELSE b.custid END AS custid
		,SUM(bal.totalBalance) AS Balance
		,SUM(bal.totalBalance * b.actualrate) AS BaseBalance
	FROM dbo.bettrans b WITH (NOLOCK)
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN b.winlostdate <= @MoveBetsDay 
					THEN 0 ELSE 1 END
				*
				(
					(CASE WHEN b.custid=b.mrecommend THEN winlost-actual_stake ELSE mwinlost+acomm-comm END) -- master level
					+ (CASE WHEN b.custid=b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
					+ (CASE WHEN b.custid <> b.recommend and b.custid <> b.mrecommend THEN winlost-actual_stake+playercomm ELSE 0 END) -- member level
				 ) AS totalBalance
			) AS bal
	WHERE b.srecommend = @superid
		AND b.winlostdate <= @currentDate
		AND b.ruben = 1
		AND b.bettype < 19999
		AND b.statusID NOT IN (101,102,103)
	GROUP BY CASE WHEN b.mrecommend > 0 THEN b.mrecommend ELSE b.custid END
	OPTION (RECOMPILE)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT CASE WHEN b.mrecommend > 0 THEN b.mrecommend ELSE b.custid END AS custid
		,SUM(bal.totalBalance) AS Balance
		,SUM(bal.totalBalance * b.actualrate) AS BaseBalance
	FROM dbo.[Transfer] b WITH (NOLOCK)
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				(CASE WHEN b.winlostdate > @MoveBetsDay AND b.bettype = 19999 THEN 0
					WHEN b.winlostdate > @BalanceUpDay AND b.bettype = 20000 THEN 0 --> new bal
					WHEN b.winlostdate < @BalanceUpDay THEN 0 --> old bal
				ELSE 1 END)
				*
				(
					(CASE WHEN b.custid=b.mrecommend THEN winlost-actual_stake ELSE mwinlost+acomm-comm END) -- master level
					+ (CASE WHEN b.custid=b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
					+ (CASE WHEN b.custid <> b.recommend and b.custid <> b.mrecommend THEN winlost-actual_stake+playercomm ELSE 0 END) -- member level
				 ) AS totalBalance
			) AS bal
	WHERE b.srecommend = @superid
		AND b.CustId <> @superid
		AND b.winlostdate <= @currentDate		
		AND b.bettype NOT IN (21008, 21009)
	GROUP BY CASE WHEN b.mrecommend > 0 THEN b.mrecommend ELSE b.custid END
	
	IF @Currency IS NOT NULL
	BEGIN 
		DELETE FROM #Data WHERE Custid IN (SELECT custid FROM dbo.vw_Customer WHERE currency <> @currency)
	END  

	--reward wallet
	--the pendingreward amount super haven't paid master or direct member
	CREATE TABLE #unpaidReward 
	(
		custid INT,
		amount MONEY,
		amount_rm MONEY
	)

	INSERT #unpaidReward (custid, amount, amount_rm)
	SELECT Mrecommend, SUM(amount) amount_original, SUM(amount * actualrate) amount_rm
	FROM bodb02.dbo.SabaWalletTicket WITH (NOLOCK)
	WHERE PaymentStatus & 4 = 0 --check 3rd bit from right is 0
	  AND Srecommend = @superid
	  AND Mrecommend > 0
	GROUP BY Mrecommend

	INSERT #unpaidReward (custid, amount, amount_rm)
	SELECT CustID, SUM(amount) amount_original, SUM(amount * actualrate) amount_rm
	FROM bodb02.dbo.SabaWalletTicket WITH (NOLOCK)
	WHERE PaymentStatus & 1 = 0 --check 1st bit from right is 0
	  AND Srecommend = @superid
	  AND Mrecommend < 0
	GROUP BY CustID

	;WITH grouped_data AS (
		SELECT custid, SUM(Balance) AS Balance, SUM(BaseBalance) AS BaseBalance
		FROM #Data
		GROUP BY custid
	)
	SELECT ISNULL(bal.custid, ur.custid) AS custid
		, case c.roleid when 4 then 'Super' when 3 then 'Master' when 2 then 'Agent' else 'Member' end role
		, c.username, c.currency 
		, MAX(ex.currency) AS currencyname
		, ISNULL(SUM(bal.Balance),0) AS Balance
		, ISNULL(SUM(bal.BaseBalance),0) AS BaseBalance
		, SUM(ISNULL(ur.amount, 0)) AS Reward
		, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM vw_Customer c 
		LEFT JOIN grouped_data bal ON bal.Custid = c.custid
		LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = c.currency
		LEFT JOIN #unpaidReward ur ON ur.custid = c.custid
	WHERE c.custid IN (select custid from #data)
    	OR c.custid IN (select custid from #unpaidReward)
	GROUP BY ISNULL(bal.custid, ur.custid), c.roleid, c.username, c.currency 
	ORDER BY c.username

	DROP TABLE #Data
	
END
GO
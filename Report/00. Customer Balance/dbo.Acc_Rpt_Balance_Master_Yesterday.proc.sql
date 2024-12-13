/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Master_Yesterday] 
	@superid		INT = 0
	, @Keyword		NVARCHAR(50) = ''
	, @FirstChar	NVARCHAR(6) = ''
	, @Currency		INT = NULL
AS


/*
Created:
Task : Get Master balance
DB: DB06.bodb02
Original:
Revisions:
		--Balance calculated with the correct transfer date @Phuong20080927
		- 20090619@Kiwi: Remove Exchange
		--20090515@Jamie: Enhance for using right index
		- 20100112@Jamie: Get currencyName from Cache
		- 20110516@Lukas: re-arrange bettype
		- 20131119@Lukas: remove running/void/reject/refund tickets
		- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
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
		, @srecommend		INT

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
		,@yesterday			= @currentDate -1
		,@superid			= ISNULL(@superid,0)
	
	CREATE TABLE #SuperKey (
		srecommend			INT PRIMARY KEY
	)

	CREATE TABLE #MasterInfo (
		custid				INT PRIMARY KEY
		, srecommend		INT
		, username			NVARCHAR(50)
		, currency			INT
	)
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)

	IF @superid = 0 
	BEGIN
		-- Direct level
		IF @keyword <> '' 
			OR @FirstChar <> ''
		BEGIN
			INSERT INTO #MasterInfo (custid,username,srecommend, currency)
			SELECT custid, username,srecommend, currency
			FROM dbo.customer c WITH (NOLOCK)
			WHERE c.roleid = 3
			AND (
				srecommend < 100
				OR srecommend IN (21278849, 21278858)
				)
			AND c.username LIKE '%' + @Keyword + '%'
			AND c.username LIKE @FirstChar + '%'

		
		END
		ELSE 
		BEGIN 
			INSERT INTO #MasterInfo (custid,username,srecommend, currency)
			SELECT custid, username,srecommend, currency
			FROM dbo.customer c with (nolock)
			WHERE c.roleid = 3
			AND (
				srecommend < 100
				OR srecommend IN (21278849, 21278858)
				)
		END 
	END 
	ELSE 
	BEGIN
		-- Drill down level
		INSERT INTO #MasterInfo (custid,username,srecommend, currency)
		SELECT custid, username,srecommend, currency
		FROM dbo.customer c with (nolock)
		WHERE c.roleid = 3 AND srecommend = @superid 
	 
	END

	INSERT INTO #SuperKey
	SELECT DISTINCT srecommend
	FROM #MasterInfo

	----EMPTY first
	--IF(@@ROWCOUNT = 0) RETURN

	IF @Currency IS NOT NULL
	BEGIN 
		DELETE FROM #MasterInfo WHERE currency <> @currency 
	END  

	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT b.mrecommend AS custid
		,SUM(bal.totalBalance) AS Balance
		,SUM(bal.totalBalance * b.actualrate) AS BaseBalance
	FROM #SuperKey sk
		INNER JOIN dbo.bettrans b WITH (NOLOCK) ON b.srecommend = sk.srecommend 
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN b.winlostdate <= @MoveBetsDay 
					THEN 0 ELSE 1 END
				*
				CASE 
				WHEN b.winlostdate <= @yesterday THEN
					(CASE WHEN b.custid=b.mrecommend THEN winlost-actual_stake ELSE mwinlost+acomm-comm END) -- master level
					+ (CASE WHEN b.custid=b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
					+ (CASE WHEN b.custid <> b.recommend and b.custid <> b.mrecommend THEN winlost-actual_stake+playercomm ELSE 0 END) -- member level
				ELSE 0
				END
			AS totalBalance
			) AS bal
	WHERE EXISTS (SELECT TOP 1 1 FROM #MasterInfo mt WHERE b.mrecommend = mt.custid)
		AND b.winlostdate <= @currentDate
		AND b.ruben = 1
		AND b.statusID NOT IN (101,102,103)
		AND b.bettype < 19999
	GROUP BY b.mrecommend
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT b.mrecommend AS custid
		,SUM(bal.totalBalance) AS Balance
		,SUM(bal.totalBalance * b.actualrate) AS BaseBalance
	FROM #SuperKey sk
		INNER JOIN dbo.[Transfer] b WITH (NOLOCK) ON b.srecommend = sk.srecommend 
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
					(CASE WHEN b.custid=b.mrecommend THEN winlost-actual_stake ELSE mwinlost+acomm-comm END) -- master level
					+ (CASE WHEN b.custid=b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
					+ (CASE WHEN b.custid <> b.recommend and b.custid <> b.mrecommend THEN winlost-actual_stake+playercomm ELSE 0 END) -- member level
				ELSE 0
				END
			AS totalBalance
			) AS bal
	WHERE EXISTS (SELECT TOP 1 1 FROM #MasterInfo mt WHERE b.mrecommend = mt.custid)
		AND b.winlostdate <= @currentDate		
		AND b.bettype NOT IN (21008, 21009)
	GROUP BY b.mrecommend

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
		AND SabaWalletTicket.WinlostDate <= @yesterday
	GROUP BY Mrecommend

	;WITH grouped_data AS (
		SELECT custid, SUM(Balance) AS Balance, SUM(BaseBalance) AS BaseBalance
		FROM #Data
		GROUP BY custid
	)
	SELECT mi.custid, mi.username, mi.currency 
		, MAX(ex.currency) AS currencyname
		, ISNULL(SUM(bal.Balance),0) AS Balance
		, ISNULL(SUM(bal.BaseBalance),0) AS BaseBalance
		, SUM(ISNULL(ur.amount, 0)) AS Reward
		, SUM(ISNULL(ur.amount_rm, 0)) AS RewardRM
	FROM #MasterInfo mi
		LEFT JOIN grouped_data bal ON bal.custid = mi.custid
		LEFT JOIN Exchange ex WITH (NOLOCK) ON ex.ExchangeId = mi.currency
		LEFT JOIN #unpaidReward ur ON ur.masterid = mi.custid
	GROUP BY mi.custid, mi.username, mi.currency 
	ORDER BY mi.username   

	DROP TABLE #MasterInfo
	DROP TABLE #Data
	
END
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Super] 
	@Keyword			NVARCHAR(50) = ''
	, @FirstChar		NVARCHAR(6) = ''
	, @Currency			INT = NULL
	, @IsViewTotalOnly	BIT = 0
	, @Total			MONEY = 0 OUTPUT
AS

/*
Created:
Task : Get Total Balance of all supers
DB: DBACC.bodb02
Original: call from /admin/account/sabalance.asp
Revisions:
	-(060719)	Use left join to get all super (even the super which has no bettrans) and calculate BaseBalance faster
	- Super which custid<100 is reserved for non-super members and for currency logic
	- 20090619@Kiwi: Enhence Performance by using #SuperInfo
	- 20091130@Jamie: Move from DB06 to DB052 (Replication)
	- 20100112@Jamie: Get currencyName from Cache
	- 20120712@Elodie:  Add @IsViewTotalOnly and @Total params to show total value when user want to view total only
						Rewrite SP to enhance performance
	- 20131119@Lukas: remove running/void/reject/refund tickets
	- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
	- 20190909@Viet: Workaround - include CN88 Headline amount [redmine: #119921] 
	- 20190919@Bobby: Enhance SMA Balance report [redmine: #119990] 
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
	- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)

Parameters Explanation:
	- Search keyword: '%keyword%'
	- First char
			A: 'A%'
			B: 'B%'
			0-9: '[0-9]%'
					
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay DATE
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate	SMALLDATETIME
		,@isSearchCust		BIT = 0
		,@isSearchHeadline	BIT = 0

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)

	CREATE TABLE #SuperInfo (
		custid				INT PRIMARY KEY
		, username			NVARCHAR(50)
		, currency			INT
		, roleId			INT
		, headlineEnabled	BIT DEFAULT(0)
	)

	CREATE TABLE #superBalance (
		CustID			INT
		, Balance		MONEY
		, BaseBalance	MONEY
	)

	IF (@Keyword <> '' 
		OR @FirstChar <> '' OR @Currency is not NULL)						
	BEGIN
		INSERT INTO #SuperInfo (custid, username, currency, roleid, headlineEnabled)
		SELECT c.custid, c.username, c.currency, c.roleid
			, CASE WHEN c.roleid = 0 THEN 1 ELSE 0 END AS headlineEnabled
		FROM dbo.custinfo c with (nolock)
		WHERE c.roleid IN (4, 0) -- mark headline as super
			AND 1 = CASE 
						WHEN @Currency IS NULL THEN 1
						WHEN c.currency = @Currency	THEN 1
						ELSE 0
					END
			AND 1 = CASE 
						WHEN @Keyword IS NULL THEN 1
						WHEN c.username LIKE '%' + LTRIM(RTRIM(@Keyword)) + '%'  THEN 1
						ELSE 0
					END
			AND 1 = CASE
						WHEN @FirstChar IS NULL THEN 1
						WHEN c.username LIKE LTRIM(RTRIM(@FirstChar)) + '%'	THEN 1
						ELSE 0
					END

		IF @@ROWCOUNT > 0
			SET @isSearchCust = 1
	END
	ELSE
	BEGIN
		INSERT INTO #SuperInfo (custid,username, currency, roleid, headlineEnabled)
		SELECT c.custid, c.username, c.currency,c.roleid
			, CASE WHEN c.roleid = 0 THEN 1 ELSE 0 END AS headlineEnabled
		FROM dbo.custinfo c with (nolock)
			INNER JOIN dbo.Exchange e WITH (NOLOCK) ON e.exchangeid = c.currency  --Filter currency test 
		WHERE c.roleid IN (4, 0) -- mark headline as super
	END

	-- EMPTY first
	IF NOT EXISTS(SELECT TOP 1 1 FROM #SuperInfo)
	BEGIN
		RETURN
	END

	-- check headline
	SELECT @isSearchHeadline = 1
	WHERE EXISTS(SELECT TOP 1 1 FROM #SuperInfo WHERE roleid = 0)

	-- cal Super's balance
	;
	WITH cte_bettrans AS
	(
		SELECT 
			si.custid
			,SUM(bal.totalBalance) AS Balance
			,SUM(bal.totalBalance*b.actualrate) AS BaseBalance
		FROM #SuperInfo si
		INNER JOIN dbo.bettrans b with (NOLOCK)
			ON b.srecommend = si.custid AND si.roleId = 4
		CROSS APPLY (
			SELECT
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
					THEN 0 ELSE 1 END
				*
				((CASE WHEN b.custid = b.srecommend THEN winlost-actual_stake ELSE swinlost+scomm-acomm END) -- super level
				+ (CASE WHEN b.custid = b.mrecommend THEN winlost-actual_stake ELSE mwinlost+acomm-comm END) -- master level
				+ (CASE WHEN b.custid = b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
				+ (CASE WHEN b.custid <> b.recommend AND b.custid <> b.mrecommend AND b.custid <> b.srecommend THEN winlost-actual_stake+playercomm ELSE 0 END) --member level
				) AS totalBalance
		) AS bal
		WHERE b.winlostdate <= @currentDate
			AND ruben = 1
			AND statusID NOT IN (101,102,103)
			AND b.bettype NOT IN (21008, 21009)
		GROUP BY si.custid
	)
	INSERT #superBalance (CustID, Balance, BaseBalance)
	SELECT CustID, Balance, BaseBalance
	FROM cte_bettrans

	-- re-CAL headline balance = [headline's all transfer]
	IF(@isSearchHeadline = 1)
	BEGIN
		WITH CTE_HeadlineTransfer AS (
			SELECT 
				si.custid
				,SUM(bal.winlost) AS Balance
				,SUM(bal.winlost*b.actualrate) AS BaseBalance
			FROM #SuperInfo si
			INNER JOIN dbo.bettrans b with (NOLOCK) 
				ON b.custid = si.custid AND si.roleId = 0
			CROSS APPLY (
				SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
					THEN 0 ELSE 1 END
				*
				(winlost - actual_stake) AS winlost
			) AS bal
			WHERE b.winlostdate <= @currentDate
				  AND b.bettype NOT IN (21008, 21009)
			GROUP BY si.custid
		)
		INSERT #superBalance (CustID, Balance, BaseBalance)
		SELECT CustID, Balance, BaseBalance
		FROM CTE_HeadlineTransfer
	END
		
	IF @IsViewTotalOnly = 0	
	BEGIN
			SELECT si.CustID, si.username, si.currency, si.headlineEnabled
			, SUM(ISNULL(bal.Balance, 0)) AS Balance
			, SUM(ISNULL(bal.BaseBalance, 0)) AS BaseBalance
		FROM #SuperInfo si
		LEFT JOIN #superBalance bal  ON si.custid = bal.custid
		GROUP BY 
			si.CustID, si.username, si.currency, si.headlineEnabled

		ORDER BY 
			CASE 
				WHEN si.custid < 100 
					OR si.custid IN (21278849, 21278858) 
				THEN 0 
				ELSE 1 END
			, si.username
	END
	ELSE
	BEGIN
		SELECT @Total = SUM(ISNULL(bal.BaseBalance, 0))
		FROM #SuperInfo si
		LEFT JOIN #superBalance bal  ON si.custid = bal.custid
	END

	DROP TABLE #SuperInfo
	DROP TABLE #superBalance
END
GO
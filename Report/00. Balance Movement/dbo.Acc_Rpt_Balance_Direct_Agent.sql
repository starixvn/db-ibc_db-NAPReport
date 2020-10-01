/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Agent
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Jamie
	Date: 2009-07-17
	Task: Direct Agent Balance
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of master instead of get master balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	- 20130131@Johnson: Add filter by username and currency
	- 20200930@Roy: HotFix - NAP Report - Direct member balance report getting wrong account list (#142334)
*/
BEGIN
	SET NOCOUNT ON
	
	---display round(balance,2) > 0---
	DECLARE @MinBal DECIMAL(3,3) = 0.005
	
	CREATE TABLE #directAgent (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,mrecommend INT)
	---get directAgent---
	INSERT INTO #directAgent
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.mrecommend
	FROM dbo.custinfo ci WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON ci.roleid = 2 AND ci.custid = d.custid
	WHERE ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency,ci.currency)
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
	
	---Return data---
	SELECT	a.custid,
			a.username, 
			a.currency, 
			IsNull(bal.bal,0) AS Balance, 
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	#directAgent a WITH (NOLOCK)
			LEFT JOIN (
				SELECT	recommend, 
						isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) AS bal,
					
						isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) AS Basebal
				FROM	bettrans b WITH (NOLOCK)
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				AND EXISTS ( SELECT 1 FROM #directAgent d WITH (NOLOCK) WHERE b.mrecommend = d.mrecommend )
				GROUP BY recommend 
			)as Bal ON a.custid = Bal.recommend
	WHERE bal.bal >= @MinBal
	ORDER BY a.username
	OPTION (RECOMPILE)

	DROP TABLE #directAgent
END
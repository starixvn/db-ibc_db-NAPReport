/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Master
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Jamie
	Date: 2009-07-16
	Task: Direct Master Balance 
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of super instead of get super balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	-- 20121115@Lukas: change query to get only needed data
	- 20130131@Johnson: Filter by username and currency
	- 20200930@Roy: HotFix - NAP Report - Direct member balance report getting wrong account list (#142334)
*/
BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #directMaster (custid INT,username VARCHAR(50), currency INT, srecommend INT)
	---get directMaster---
	INSERT INTO #directMaster
	SELECT m.custid
		,m.username
		,m.currency
		,m.srecommend
	FROM dbo.custinfo m WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON m.roleid = 3 AND m.custid = d.custid
	WHERE m.username LIKE '%' + @username + '%'
		AND m.currency = ISNULL(@currency, m.currency)
		AND (@ExclTestCurr = 0 OR m.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)
	
	---Include finance accounts---
	INSERT INTO #directMaster
	SELECT m.custid
		,m.username
		,m.currency
		,m.srecommend
	FROM dbo.CustMaster AS cm WITH (NOLOCK)
		INNER JOIN dbo.custinfo m WITH (NOLOCK) ON cm.custid = m.custid
	WHERE cm.IsInternal = 1
		AND username LIKE '%' + @username + '%'
		AND currency = ISNULL(@currency,currency)
		AND (@ExclTestCurr = 0 OR m.currency NOT IN (20, 27, 28))
		AND NOT EXISTS ( SELECT 1 FROM #directMaster d WHERE cm.custid = d.custid )
	OPTION (RECOMPILE)
	
	---Return data---
	SELECT	m.custid,
			m.username, 
			m.currency,
			IsNull(bal.bal,0) AS Balance,
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	#directMaster m WITH (NOLOCK)
			LEFT JOIN (
				SELECT 	b.mrecommend,
						isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
						+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) AS bal,
					
						isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
						+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) AS Basebal
				FROM	bettrans b WITH (NOLOCK)
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				AND EXISTS ( SELECT 1 FROM #directMaster d WITH (NOLOCK) WHERE b.srecommend = d.srecommend )
				GROUP BY b.mrecommend
			) as  bal ON m.custid = bal.mrecommend
	WHERE ROUND(IsNull(bal.bal,0), 2) > 0
	ORDER BY m.username

	DROP TABLE #directMaster
END

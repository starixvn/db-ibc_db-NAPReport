/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

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
	- 20200930@Roy: HotFix - NAP Report - Direct member balance report getting wrong account list (#142334)
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #directMember (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,recommend INT)
	---get directMember---
	INSERT INTO #directMember
	SELECT m.custid
		,m.username
		,m.currency
		,m.recommend
	FROM dbo.custinfo m WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON m.roleid = 1 AND m.custid = d.custid
	WHERE m.username LIKE '%' + @username + '%'
		AND m.currency = ISNULL(@currency, m.currency)
		AND (@ExclTestCurr = 0 OR m.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)

	---Return data---
	SELECT  mem.custid,
			mem.username, 
			mem.currency, 
			IsNull(bal.bal,0) Balance, 
			IsNull(bal.BaseBal,0) BaseBalance
	FROM	#directMember mem WITH (NOLOCK)
			LEFT JOIN (
				SELECT	custid,
						isnull(SUM(winlost - actual_stake + playercomm),0) bal,
						isnull(SUM((winlost - actual_stake + playercomm)* actualrate),0) as Basebal
				FROM	bettrans WITH (NOLOCK)
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				AND EXISTS ( SELECT 1 FROM #directMember d WITH (NOLOCK) WHERE a.recommend = d.recommend )
				GROUP BY custid
			) bal ON mem.custid = bal.custid
	WHERE ROUND(IsNull(bal.bal,0), 2) > 0
	ORDER BY username

	DROP TABLE #directMember
END

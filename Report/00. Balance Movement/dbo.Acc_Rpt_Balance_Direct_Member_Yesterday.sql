/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Member_Yesterday
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Johnson
	Date: 203-01-31
	Task: Direct Member Balance
	DB: DB06.BODB02
		
	Revisions:	
		- 20130531@Johnson: add playercomm for bettype > 19000 to fix data summary bettype(19999)
		- 20200930@Roy: HotFix - NAP Report - Direct member balance report getting wrong account list (#142334)
*/
BEGIN
	SET NOCOUNT ON 
	
	DECLARE @currentDate datetime 
	SELECT @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)
	
	CREATE TABLE #directMember (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,recommend INT)
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
	
	---Return data---
	SELECT  mem.custid,
			mem.username, 
			mem.currency, 
			IsNull(bal.bal,0) Balance, 
			IsNull(bal.BaseBal,0) BaseBalance
	FROM	#directMember mem WITH (NOLOCK)
			LEFT JOIN (
				SELECT	custid,
						isnull(SUM(case when bettype < 19001 and winlostdate < @currentdate then winlost - actual_stake + playercomm
										when bettype > 19000 then winlost - actual_stake + playercomm
									else 0 end),0) bal,
								
						isnull(SUM((case when bettype < 19001 and winlostdate < @currentdate then winlost - actual_stake + playercomm
										 when bettype > 19000 then winlost - actual_stake  + playercomm
										else 0 end)* actualrate),0) as Basebal
				FROM	bettrans b WITH (NOLOCK)
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				AND EXISTS ( SELECT 1 FROM #directMember d WITH (NOLOCK) WHERE b.recommend = d.recommend )
				GROUP BY custid
			) bal ON mem.custid = bal.custid
	ORDER BY mem.username
	OPTION (RECOMPILE)

	DROP TABLE #directMember
END

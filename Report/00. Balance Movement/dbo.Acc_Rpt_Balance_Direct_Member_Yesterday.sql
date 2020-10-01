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
	
	---display round(balance,2) > 0---
	DECLARE @MinBal DECIMAL(3,3) = 0.005
	
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
	WHERE bal.bal >= @MinBal
	ORDER BY mem.username
	OPTION (RECOMPILE)

	DROP TABLE #directMember
END

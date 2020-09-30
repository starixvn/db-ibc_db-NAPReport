/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Agent_Yesterday
	@username varchar(50) = ''
	,@currency int = null
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Agent Balance
	DB: DB06.BODB02
	Revisions:
		20200930@Roy: HotFix - NAP Report - Direct member balance report getting wrong account list (#142334)
	
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @currentDate datetime 
	SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

	CREATE TABLE #directAgent (
		custid INT
		,username VARCHAR(50)
		,currency INT
		,mrecommend INT)
	---get directAgent---
	INSERT INTO #directAgent
	SELECT m.custid
		,m.username
		,m.currency
		,m.mrecommend
	FROM dbo.custinfo m WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON m.roleid = 2 AND m.custid = d.custid
	WHERE username LIKE '%' + @username + '%'
		AND currency = ISNULL(@currency,currency)
	OPTION (RECOMPILE)
	
	---Include finance accounts---
	INSERT INTO #directAgent
	SELECT m.custid
		,m.username
		,m.currency
		,m.mrecommend
	FROM dbo.CustAgent AS ca WITH (NOLOCK)
		INNER JOIN dbo.custinfo m WITH (NOLOCK) ON ca.custid = m.custid
	WHERE ca.IsInternal = 1
		AND username LIKE '%' + @username + '%'
		AND currency = ISNULL(@currency,currency)
		AND NOT EXISTS ( SELECT 1 FROM #directAgent d WHERE ca.custid = d.custid )

	---Return data---
	SELECT	a.custid,
			a.username, 
			a.currency, 
			IsNull(bal.bal,0) AS Balance, 
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	#directAgent a 
			LEFT JOIN (
				SELECT	recommend, 
						isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
						- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end),0) AS bal,
						
						isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0)
						- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end)*actualrate),0) AS Basebal
				FROM	bettrans with (nolock) 
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				AND EXISTS ( SELECT 1 FROM #directAgent d WHERE a.mrecommend = d.mrecommend )
				GROUP BY recommend 
			)as Bal ON a.custid = Bal.recommend
	ORDER BY a.username

	DROP TABLE #directAgent
END

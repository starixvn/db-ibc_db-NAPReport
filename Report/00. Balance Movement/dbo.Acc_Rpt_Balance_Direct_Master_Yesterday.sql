/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_Balance_Direct_Master_Yesterday
	@username varchar(50) = ''
	,@currency int = null
	,@ExclTestCurr bit = 0
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Master Balance 
	DB: DB06.BODB02
	Revisions:
		20200930@Roy: NAP Report - Enhance the way we get Direct Balance report (#144094)
		20201030@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
		20211111@Cherry: Split transfer table (#164378)
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @MoveBetsDay DATE
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentdate DATETIME
	SELECT @currentdate = convert(varchar(10), CURRENT_TIMESTAMP, 120)
	
	CREATE TABLE #directMaster (custid INT,username VARCHAR(50), currency INT, srecommend INT)
	---get directMaster---
	INSERT INTO #directMaster
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.srecommend
	FROM dbo.custinfo ci WITH (NOLOCK)
		INNER JOIN dbo.CustDirectAccount d WITH (NOLOCK) ON ci.roleid = 3 AND ci.custid = d.custid
	WHERE ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
	OPTION (RECOMPILE)
	
	---Include finance accounts---
	INSERT INTO #directMaster
	SELECT DISTINCT ci.custid
		,ci.username
		,ci.currency
		,ci.srecommend
	FROM dbo.CustMaster AS cm WITH (NOLOCK)
		INNER JOIN dbo.custinfo ci WITH (NOLOCK) ON ci.roleid = 3 AND cm.custid = ci.custid
	WHERE cm.IsInternal = 1
		AND ci.username LIKE '%' + @username + '%'
		AND ci.currency = ISNULL(@currency, ci.currency)
		AND (@ExclTestCurr = 0 OR ci.currency NOT IN (20, 27, 28))
		AND NOT EXISTS ( SELECT 1 FROM #directMaster d WHERE cm.custid = d.custid )
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_Direct] ON #directMaster( srecommend, custid )
	
	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT 	--see Balance_Direct_Master report
			case when b.winlostdate <= @MoveBetsDay then NULL
				 else b.mrecommend
			end mrecommend,
			isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
			+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0) AS bal, 	
			
			isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
			+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0) AS Basebal								
	FROM	bettrans b WITH (NOLOCK)	
	WHERE	ruben = 1 AND 
		--status NOT IN ('VOID','REJECT','REFUND')				
		statusID NOT IN (101,102,103)
		AND b.bettype < 19999
		AND EXISTS ( SELECT 1 FROM #directMaster d WITH (NOLOCK) WHERE b.srecommend = d.srecommend )
	GROUP BY case when b.winlostdate <= @MoveBetsDay then NULL
				else b.mrecommend
			end
			
	OPTION (RECOMPILE)
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT 	--see Balance_Direct_Master report
			case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				 else b.mrecommend
			end mrecommend,
			isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
			+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
			- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0) AS bal, 	
			
			isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
			+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
			+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
			- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0) AS Basebal								
	FROM	[Transfer] b WITH (NOLOCK)	
	WHERE	b.bettype NOT IN (21008, 21009)
		AND EXISTS ( SELECT 1 FROM #directMaster d WITH (NOLOCK) WHERE b.srecommend = d.srecommend )
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				else b.mrecommend
			end
			
	OPTION (RECOMPILE)
	
	---Return data---
	SELECT	m.custid,
			m.username, 
			m.currency,
			SUM(IsNull(bal.Balance,0)) AS Balance,
			SUM(IsNull(bal.BaseBalance,0)) AS BaseBalance
	FROM	#directMaster m WITH (NOLOCK)
			LEFT JOIN #Data as  bal ON m.custid = bal.custid
	GROUP BY m.custid,
			m.username, 
			m.currency
	ORDER BY m.username
	
	DROP TABLE #Data
	DROP TABLE #directMaster
END

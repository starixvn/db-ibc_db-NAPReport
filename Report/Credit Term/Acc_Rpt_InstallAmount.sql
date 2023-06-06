/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_InstallAmount]
	@RoleID tinyint
AS
/*	Created by: []
	Date:[]
	Task: Credit Term 
	DB: DBACC.bodb02

	Revisions:
		- 20090701@Jamie: Use actualrate from bettrans table instead of exchange table. 
		- 20100105@Khoa: get currency name from cache
		- 20100105@Jamie: 
			+ Enhance code at member/agent/super level and remove exchange table 
			+ Remove columns: creditgrade, preagreeamount, accountremark, accountremarkdate
		- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
		- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
		- 20211118@Cherry: Split Transfer table (#164378)
		- 20230119@Roy: NAP Report - BU 247 (#175206)
*/	

SET NOCOUNT ON

	DECLARE @MoveBetsDay SMALLDATETIME
		,@BalanceUpDay SMALLDATETIME
	SELECT @MoveBetsDay = MoveBetsDay
		,@BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	CREATE TABLE #tmpCust (
		custid				INT,
		username			VARCHAR(50),
		curr				INT,
		creditgrade			VARCHAR(1) DEFAULT NULL,
		installmentdate		VARCHAR(50),
		installmentamount	MONEY
	)
	
	CREATE TABLE #tmpData (
		custid INT,
		bal MONEY,
		bal_base MONEY
	)

if @RoleID = 1 --member
BEGIN
	INSERT INTO #tmpCust(
		custid, 
		username, 
		curr,
		installmentdate,
		installmentamount
	)
	SELECT	c.custid, 
			c.username, 
			c.currency,
			ca.installmentdate,
			ca.installmentamount
	FROM	Customer c WITH (NOLOCK)
			INNER JOIN CustAccount ca WITH (NOLOCK) ON c.custid = ca.custid 
	WHERE	c.roleid = 1 AND ca.installmentAmount > 0 
	
	INSERT INTO #tmpData (
		custid,
		bal,
		bal_base)
	SELECT	custID,
			SUM(winlost-actual_stake+playercomm) as balance,
			SUM((winlost-actual_stake+playercomm)*actualrate) as balance_base
	FROM	bettrans WITH (NOLOCK)
	WHERE	ruben = 1
			AND bettype < 19999
			AND CASE WHEN winlostdate <= @MoveBetsDay
					THEN 0 ELSE 1 END = 1
	GROUP BY custID	
	UNION ALL
	SELECT	custID,
			SUM(winlost-actual_stake+playercomm) as balance,
			SUM((winlost-actual_stake+playercomm)*actualrate) as balance_base
	FROM	dbo.[Transfer] WITH (NOLOCK)
	WHERE	bettype NOT IN (21008, 21009)
			AND (CASE WHEN winlostdate > @MoveBetsDay AND bettype = 19999 THEN 0
					WHEN winlostdate > @BalanceUpDay AND bettype = 20000 THEN 0 --> new bal
					WHEN winlostdate < @BalanceUpDay THEN 0 --> old bal
				ELSE 1 END) = 1
	GROUP BY custID
	
	SELECT	
			ca.custid as custid
			, ca.username 
			, ca.curr
			, SUM(ISNULL(b.balance,0)) as balance
			, SUM(ISNULL(b.balance_base,0)) as balance_base
			, SUM(ca.installmentamount) installmentamount
			, ca.installmentdate
	from	#tmpCust ca
			LEFT JOIN (
				SELECT custid,
					SUM(bal) balance,
					SUM(bal_base) balance_base
				FROM #tmpData
				GROUP BY custid
			) b ON ca.custid = b.custid
	group by ca.custid 
			, ca.username 
			, ca.curr
			, ca.installmentdate
	order by ca.username 
END
else if @RoleID = 2 --agent
BEGIN
	INSERT INTO #tmpCust(
		custid, 
		username, 
		curr,
		installmentdate,
		installmentamount
	)
	SELECT	c.custid, 
			c.username, 
			c.currency,
			ca.installmentdate,
			ca.installmentamount
	FROM	Customer c WITH (NOLOCK)
			INNER JOIN CustAccount ca WITH (NOLOCK) ON c.custid = ca.custid 
	WHERE	c.roleid = 2 AND ca.installmentAmount > 0 	
		
	INSERT INTO #tmpData (
		custid,
		bal,
		bal_base)
	SELECT recommend,
		sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
		sum(case when custid <> recommend and ruben=1 then winlost-actual_stake+playercomm else 0 end) Bal,
		sum(case when custid=recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
		sum(case when custid <> recommend and ruben=1 then (winlost-actual_stake+playercomm)*actualrate else 0 end) bal_base				
	FROM bettrans (nolock)
	WHERE bettype < 19999
		AND CASE WHEN winlostdate <= @MoveBetsDay 
				THEN 0 ELSE 1 END = 1
	GROUP BY bettrans.recommend
	UNION ALL
	SELECT recommend,
		sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
		sum(case when custid <> recommend then winlost-actual_stake+playercomm else 0 end) Bal,
		sum(case when custid=recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
		sum(case when custid <> recommend then (winlost-actual_stake+playercomm)*actualrate else 0 end) bal_base				
	FROM dbo.[Transfer] (nolock)
	WHERE bettype NOT IN (21008, 21009)
		AND (CASE WHEN winlostdate > @MoveBetsDay AND bettype = 19999 THEN 0
				WHEN winlostdate > @BalanceUpDay AND bettype = 20000 THEN 0 --> new bal
				WHEN winlostdate < @BalanceUpDay THEN 0 --> old bal
			ELSE 1 END) = 1
	GROUP BY recommend

	SELECT 
			ca.custid
			,ca.username
			,ca.curr
			,SUM(IsNull(bal,0)) balance
			,SUM(IsNull(bal_base,0)) balance_base 
			,ca.installmentdate
			,SUM(ca.installmentamount) installmentamount
	FROM	#tmpCust ca
			LEFT OUTER JOIN (
				SELECT custid,
					SUM(bal) bal,
					SUM(bal_base) bal_base
				FROM #tmpData
				GROUP BY custid
			) bal ON ca.custid = bal.custid
	GROUP BY ca.custid
			,ca.username
			,ca.curr
			,ca.installmentdate
	order by username
END
else if @RoleID = 3 --master
BEGIN
	INSERT INTO #tmpData (
		custid,
		bal,
		bal_base)
	SELECT mrecommend,
		sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)+
		sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
		sum(case when custid <> recommend and custid <> mrecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end) Bal,
		sum(case when custid=mrecommend then (winlost-actual_stake)*actualrate else (mwinlost+acomm-comm)*actualrate end)+
		sum(case when custid=recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
		sum(case when custid <> recommend and custid <> mrecommend and ruben=1 then (winlost-actual_stake+playercomm)*actualrate else 0 end) Bal_base
	FROM bettrans (nolock)
	WHERE bettype < 19999
		AND CASE WHEN winlostdate <= @MoveBetsDay 
				THEN 0 ELSE 1 END = 1				
	GROUP BY mrecommend
	UNION ALL
	SELECT mrecommend,
		sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)+
		sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
		sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end) Bal,
		sum(case when custid=mrecommend then (winlost-actual_stake)*actualrate else (mwinlost+acomm-comm)*actualrate end)+
		sum(case when custid=recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
		sum(case when custid <> recommend and custid <> mrecommend then (winlost-actual_stake+playercomm)*actualrate else 0 end) Bal_base
	FROM dbo.[Transfer] (nolock)
	WHERE bettype NOT IN (21008, 21009)
		AND (CASE WHEN winlostdate > @MoveBetsDay AND bettype = 19999 THEN 0
				WHEN winlostdate > @BalanceUpDay AND bettype = 20000 THEN 0 --> new bal
				WHEN winlostdate < @BalanceUpDay THEN 0 --> old bal
			ELSE 1 END) = 1				
	GROUP BY mrecommend
	
	SELECT
			c.custid
			,c.username
			,c.currency as curr
			,SUM(IsNull(bal,0)) balance
			,SUM(IsNull(bal_base,0)) balance_base 
			,ca.installmentdate
			,SUM(ca.installmentamount) installmentamount
	FROM	customer c (nolock)
			LEFT OUTER JOIN (
				SELECT custid,
					SUM(bal) bal,
					SUM(bal_base) bal_base
				FROM #tmpData
				GROUP BY custid
			) bal ON c.custid = bal.custid
			INNER JOIN custAccount ca (nolock) ON c.custid = ca.custid and ca.installmentamount > 0
	WHERE c.roleID = 3 
	GROUP BY c.custid
			,c.username
			,c.currency 
			,ca.installmentdate
	order by username
END
else if @RoleID = 4 --partner
BEGIN
	
	INSERT INTO #tmpCust(
		custid, 
		username, 
		curr,
		installmentdate,
		installmentamount
	)
	SELECT	c.custid, 
			c.username, 
			c.currency,
			ca.installmentdate,
			ca.installmentamount
	FROM	Customer c WITH (NOLOCK)
			INNER JOIN CustAccount ca WITH (NOLOCK) ON c.custid = ca.custid 
	WHERE	c.roleid = 4 AND ca.installmentAmount > 0 
	
	INSERT INTO #tmpData (
		custid,
		bal,
		bal_base)
	SELECT srecommend,
		IsNull(sum(case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end),0)
		+ IsNull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
		+ IsNull(sum(case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end),0)
		+ IsNull(sum(case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end),0) Bal,
		IsNull(sum(case when custid=srecommend then (winlost-actual_stake)*actualrate else (swinlost+scomm-acomm)*actualrate end),0)
		+ IsNull(sum(case when custid=mrecommend then (winlost-actual_stake)*actualrate else (mwinlost+acomm-comm)*actualrate end),0)
		+ IsNull(sum(case when custid=recommend  then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end),0)
		+ IsNull(sum(case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then (winlost-actual_stake+playercomm)*actualrate else 0 end),0) Bal_base
	FROM bettrans (nolock)
	WHERE bettype < 19999
		AND CASE WHEN winlostdate <= @MoveBetsDay 
				THEN 0 ELSE 1 END = 1
	GROUP BY srecommend
	UNION ALL
	SELECT srecommend,
		IsNull(sum(case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end),0)
		+ IsNull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
		+ IsNull(sum(case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end),0)
		+ IsNull(sum(case when custid <> recommend and custid <> mrecommend and custid <> srecommend then winlost-actual_stake+playercomm else 0 end),0) Bal,
		IsNull(sum(case when custid=srecommend then (winlost-actual_stake)*actualrate else (swinlost+scomm-acomm)*actualrate end),0)
		+ IsNull(sum(case when custid=mrecommend then (winlost-actual_stake)*actualrate else (mwinlost+acomm-comm)*actualrate end),0)
		+ IsNull(sum(case when custid=recommend  then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end),0)
		+ IsNull(sum(case when custid <> recommend and custid <> mrecommend and custid <> srecommend then (winlost-actual_stake+playercomm)*actualrate else 0 end),0) Bal_base
	FROM dbo.[Transfer] (nolock)
	WHERE bettype NOT IN (21008, 21009)
		AND (CASE WHEN winlostdate > @MoveBetsDay AND bettype = 19999 THEN 0
				WHEN winlostdate > @BalanceUpDay AND bettype = 20000 THEN 0 --> new bal
				WHEN winlostdate < @BalanceUpDay THEN 0 --> old bal
			ELSE 1 END) = 1
	GROUP BY srecommend

	SELECT 
		ca.custid
		,ca.username
		,ca.curr
		,SUM(IsNull(bal,0)) balance
		,SUM(IsNull(bal_base,0)) balance_base
		,ca.installmentdate 
		,SUM(ca.installmentamount) installmentamount
	FROM	#tmpCust ca 
			LEFT OUTER JOIN (
				SELECT custid,
					SUM(bal) bal,
					SUM(bal_base) bal_base
				FROM #tmpData
				GROUP BY custid
			) bal ON ca.custid = bal.custid
	GROUP BY ca.custid
		,ca.username
		,ca.curr
		,ca.installmentdate 
	order by CASE when (ca.custid < 100 or ca.custid in (21278849, 21278858))then 0 ELSE 1 END, ca.username
END
	DROP TABLE #tmpCust
	DROP TABLE #tmpData
GO
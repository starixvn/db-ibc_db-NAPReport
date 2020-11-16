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
*/	

SET NOCOUNT ON

	DECLARE @tmpCust TABLE (
		custid				INT,
		username			VARCHAR(50),
		curr				INT,
		creditgrade			VARCHAR(1) DEFAULT NULL,
		installmentdate		VARCHAR(50),
		installmentamount	MONEY
	)

if @RoleID = 1 --member
BEGIN
	INSERT INTO @tmpCust(
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
	
	SELECT	
			ca.custid as custid
			, ca.username 
			, ca.curr
			, ISNULL(b.balance,0) as balance
			, ISNULL(b.balance_base,0) as balance_base
			, ca.installmentamount
			, ca.installmentdate
	from	@tmpCust ca
			LEFT JOIN (
				SELECT	custID,
						SUM(bettrans.winlost-bettrans.actual_stake+bettrans.playercomm) as balance,
						SUM((bettrans.winlost-bettrans.actual_stake+bettrans.playercomm)*bettrans.actualrate) as balance_base
				FROM	bettrans WITH (NOLOCK)
				WHERE	ruben = 1
						AND bettrans.bettype NOT IN (21008, 21009)
				GROUP BY custID
			) b ON ca.custid = b.custid
	order by ca.username 
END
else if @RoleID = 2 --agent
BEGIN
	INSERT INTO @tmpCust(
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
		

	SELECT 
			ca.custid
			,ca.username
			,ca.curr
			,IsNull(bal,0) balance
			,IsNull(bal_base,0) balance_base 
			,ca.installmentdate
			,ca.installmentamount
	FROM	@tmpCust ca
			LEFT OUTER JOIN (
				SELECT recommend,
					sum(case when bettrans.custid=bettrans.recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
					sum(case when bettrans.custid <> bettrans.recommend and ruben=1 then winlost-actual_stake+playercomm else 0 end) Bal,
					sum(case when bettrans.custid=bettrans.recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
					sum(case when bettrans.custid <> bettrans.recommend and ruben=1 then (winlost-actual_stake+playercomm)*actualrate else 0 end) bal_base				
				FROM bettrans (nolock)
				WHERE bettrans.bettype NOT IN (21008, 21009)
				GROUP BY bettrans.recommend
			) bal ON ca.custid = bal.recommend
	order by username
END
else if @RoleID = 3 --master
BEGIN
	SELECT
			c.custid
			,c.username
			,c.currency as curr
			,IsNull(bal,0) balance
			,IsNull(bal_base,0) balance_base 
			,ca.installmentdate
			,ca.installmentamount
	FROM	customer c (nolock)
			LEFT OUTER JOIN (
				SELECT mrecommend,
					sum(case when bettrans.custid=bettrans.mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)+
					sum(case when bettrans.custid=bettrans.recommend then winlost-actual_stake else awinlost+comm-playercomm end)+ 
					sum(case when bettrans.custid <> bettrans.recommend and bettrans.custid <> bettrans.mrecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end) Bal,
					sum(case when bettrans.custid=bettrans.mrecommend then (winlost-actual_stake)*actualrate else (mwinlost+acomm-comm)*actualrate end)+
					sum(case when bettrans.custid=bettrans.recommend then (winlost-actual_stake)*actualrate else (awinlost+comm-playercomm)*actualrate end)+ 
					sum(case when bettrans.custid <> bettrans.recommend and bettrans.custid <> bettrans.mrecommend and ruben=1 then (winlost-actual_stake+playercomm)*actualrate else 0 end) Bal_base
				FROM bettrans (nolock)
				WHERE bettrans.bettype NOT IN (21008, 21009)
				GROUP BY bettrans.mrecommend
			) bal ON c.custid = bal.mrecommend
			INNER JOIN custAccount ca (nolock) ON c.custid = ca.custid and ca.installmentamount > 0
	WHERE c.roleID = 3 
	order by username
END
else if @RoleID = 4 --partner
BEGIN
	
	INSERT INTO @tmpCust(
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

	SELECT 
		ca.custid
		,ca.username
		,ca.curr
		,IsNull(bal,0) balance
		,IsNull(bal_base,0) balance_base
		,ca.installmentdate 
		,ca.installmentamount
	FROM	@tmpCust ca 
			LEFT OUTER JOIN (
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
				WHERE bettrans.bettype NOT IN (21008, 21009)
				GROUP BY bettrans.srecommend
			) bal ON ca.custid = bal.srecommend
	order by CASE when (ca.custid < 100 or ca.custid in (21278849, 21278858))then 0 ELSE 1 END, ca.username
END
GO
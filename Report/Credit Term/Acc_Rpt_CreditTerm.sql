/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CreditTerm]
	--@groupID smallint = 0,
	@checkername nvarchar(50) =null,
	@pre1 money =null,
	@pre2 money = null
AS

/*	Created by: [Khoa]
	Date: 20100105
	Task: CreditTerm report
	DB: DBACC/bodb02

	Revisions:		
		- 20100105@Khoa: get currency name from cache
		- 20130820@Viet: enhance SP
		- 20130810@Thien: fix to show TOTAL BALANCE for Agent level, instead of Cash balance
		- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
		- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
	Param's Explanation:

*/

SET NOCOUNT ON
BEGIN

	DECLARE @MoveBetsDay DATE
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	create table #groupHeadLine
	(
		groupID smallint PRIMARY KEY, 
		custid int, 
		PreAgreeAmount money, 
		AccountRemark nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS, 
		AccountRemarkDate smalldatetime, 
		username nvarchar(50),
		phone nvarchar(50), 
		Role nvarchar(10),
		currency tinyint, 
		actualrate float,
		checkerid int,
		checkername nvarchar(50)
	)

	create table #Balance 
	(
		custid int,
		groupID smallint, 
		Balance money, 
		username nvarchar(50), 
		Role nvarchar(10), 
		currency tinyint, 
		actualrate float
	)
	
	--Get Lists of GroupHeadLine account
	INSERT INTO #groupHeadLine
	SELECT
		groupID, a.custid, PreAgreeAmount, AccountRemark, AccountRemarkDate, 
		c.username,c.phone, CASE c.roleid WHEN 1 THEN 'Member' WHEN 2 THEN 'Agent' WHEN 3 THEN 'Master' WHEN 4 THEN 'Super' END Role,
		c.Currency, e.actualrate, a.checker, cr.username 
	FROM custAccount a with (nolock)
		INNER JOIN customer c with (nolock) ON a.custid = c.custid
		INNER JOIN exchange e with (nolock) ON c.currency = e.exchangeid
		LEFT JOIN Customer cr with (nolock) ON a.checker = cr.custid 
	WHERE IsGroupHeadline = 1		

	-- super
	CREATE TABLE #super (custid int primary key, groupid smallint)
	INSERT INTO #super(custid, groupid)
	SELECT c.custid, a.groupid
	FROM CustInfo c with(nolock)
		inner join custAccount a with(nolock) on c.custid = a.custid
	WHERE roleid = 4 and (PreAgreeAmount > 0 OR groupID > 0)
	
	;WITH s_data as (
		SELECT b.srecommend, 
			IsNull(SUM(case when b.custid=b.srecommend then winlost-actual_stake else swinlost+scomm-acomm end) ,0) +
			IsNull(SUM(case when b.custid=b.mrecommend then winlost-actual_stake else mwinlost+acomm- comm end) ,0) + 
			IsNull(SUM(case when b.custid=b.recommend  then winlost-actual_stake else awinlost+comm-playercomm end) ,0)  +
			IsNull(SUM(case when b.custid<>b.recommend AND b.custid <> b.mrecommend AND b.custid <> b.srecommend AND b.ruben=1 then winlost-actual_stake+playercomm else 0 end) ,0) Balance
		FROM dbo.bettrans b with(nolock)
		WHERE b.srecommend in (select custid from #super)
			  AND b.bettype NOT IN (21008, 21009)
			  AND CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
				THEN 0 ELSE 1 END = 1
		GROUP BY b.srecommend
	)	
	INSERT INTO #Balance(custid, groupID, Balance)
	SELECT b.srecommend, a.groupid, Balance
	FROM s_data b
		INNER JOIN #super a on b.srecommend = a.custid	
		
	drop table #super
	
	-- master, agent & members		
	;WITH sMaster as (
		SELECT m.custid, srecommend as uplineid, a.groupid
		FROM CustInfo m with(nolock)
			inner join custAccount a with(nolock) on m.custid = a.custid
		WHERE m.roleid = 3 and (PreAgreeAmount > 0 OR groupID > 0)
	)
	INSERT INTO #Balance(custid, groupID, Balance)	
	SELECT a.custid, a.groupid, --master
		IsNull(SUM(case when b.custid=b.mrecommend then winlost-actual_stake else mwinlost+acomm-comm end) ,0) + 
		IsNull(SUM(case when b.custid=b.recommend then winlost-actual_stake else awinlost+comm-playercomm end) ,0) +  
		IsNull(SUM(case when b.custid<>b.recommend AND b.custid <> b.mrecommend AND ruben=1 then winlost-actual_stake+playercomm else 0 end) ,0) 
	FROM sMaster a
		INNER JOIN dbo.bettrans b with(nolock) on a.custid = b.mrecommend
	WHERE  b.srecommend = a.uplineid
		   AND b.bettype NOT IN (21008, 21009)
		   AND CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
				THEN 0 ELSE 1 END = 1
	GROUP BY a.custid, a.groupid
	
	UNION ALL --agent
	
	SELECT b.recommend, a.groupID,
		ISNULL(SUM(CASE WHEN b.recommend = b.custid THEN b.winlost-b.actual_stake ELSE b.awinlost+b.comm-b.playercomm END),0)
		+ IsNull(SUM(case when b.custid<>b.recommend AND b.ruben=1 then winlost-actual_stake+playercomm else 0 end) ,0)
	FROM bettrans b with(nolock, index=IX_recommend)
		INNER JOIN custInfo c with(nolock) on c.custid = b.recommend
			INNER JOIN custAccount a with(nolock) on c.custid = a.custid
	WHERE roleid = 2 AND (PreAgreeAmount > 0 OR groupID > 0)
		  AND b.bettype NOT IN (21008, 21009)
		  AND CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
			THEN 0 ELSE 1 END = 1
	GROUP BY b.recommend, a.groupid	
	
	UNION ALL
	
	SELECT a.custid, a.groupid, --member
		IsNull(SUM(winlost-actual_stake+playercomm) ,0) balance
	FROM dbo.bettrans b WITH(NOLOCK)
		INNER JOIN custAccount a on b.custid = a.custid
		INNER JOIN custInfo c on a.custid = c.custid
	WHERE b.statusID NOT IN (0,1)	
		AND c.roleid = 1	
		AND (PreAgreeAmount > 0 OR groupID > 0)
		AND b.bettype NOT IN (21008, 21009)
		AND CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate = @MoveBetsDay and bettype < 19999)
			THEN 0 ELSE 1 END = 1
	GROUP BY a.custid, a.groupid	

	UPDATE #Balance
	SET
		username = c.Username,
		Role = CASE c.roleid WHEN 1 THEN 'Member' WHEN 2 THEN 'Agent' WHEN 3 THEN 'Master' WHEN 4 THEN 'Super' END,
		currency = c.Currency, actualrate = e.actualrate
	FROM
		custInfo c with (nolock)
		INNER JOIN exchange e with (nolock) ON c.currency = e.exchangeid
		INNER JOIN #Balance b ON c.custid = b.custid

	--Groups:
	SELECT
		a.groupID,
		b.Username, b.currency, b.Role,
		b.Balance, b.Balance * b.actualrate Balance_Base,
		a.PreAgreeAmount, a.AccountRemark, 
		g.phone, g.checkerid, g.checkername,
		a.AccountRemarkDate,
		CASE
		WHEN ABS(b.Balance) > a.PreAgreeAmount THEN 1
		ELSE 0 END OverLimit
	FROM
		custAccount a with (nolock)
		INNER JOIN #Balance b ON a.custid = b.custid
		INNER JOIN #groupHeadLine g ON a.groupID = g.groupID 
	WHERE
		a.groupID = 0 
		and isnull(g.checkername, '') = coalesce(@checkername, isnull(g.checkername, ''))
		and isnull(a.preAgreeAmount, 0) >= coalesce(@pre1, isnull(a.preAgreeAmount, 0))
		and isnull(a.preAgreeAmount, 0) <= coalesce(@pre2, isnull(a.preAgreeAmount, 0))
					   
	UNION ALL
	SELECT
		g.groupID,
		g.Username, g.currency, g.Role,
		b.TotalBalance Balance, b.TotalBalance_Base Balance_Base,
		g.PreAgreeAmount, g.AccountRemark, 
		g.phone, g.checkerid,g.checkername,
		g.AccountRemarkDate,
		b.OverLimit
	FROM
		(SELECT
			b.groupID,
			SUM(b.Balance * b.actualrate)/h.actualrate TotalBalance,
			SUM(b.Balance * b.actualrate) TotalBalance_Base,
			CASE
			WHEN ABS(SUM(b.Balance * b.actualrate)/h.actualrate) > h.preAgreeAmount THEN 1
			ELSE 0 END OverLimit
		FROM
			#Balance b
			INNER JOIN #groupHeadLine h ON b.groupID = h.groupID
		WHERE
			b.groupID > 0 AND h.preAgreeAmount > 0
		GROUP BY
			b.groupID, h.actualrate, h.preAgreeAmount
		) b
		INNER JOIN #groupHeadLine g ON b.groupID = g.groupID
	WHERE 
		isnull(g.checkername, '') = coalesce(@checkername, isnull(g.checkername, ''))
		and isnull(g.preAgreeAmount, 0) >= coalesce(@pre1, isnull(g.preAgreeAmount, 0))
		and isnull(g.preAgreeAmount, 0) <= coalesce(@pre2, isnull(g.preAgreeAmount, 0))

	ORDER BY 
		b.currency, 
		groupID,
		OverLimit desc, 	
		AccountRemarkDate DESC
	-------------------------------------------------------------

	--Groups'detail:
	SELECT
		a.groupID,b.custid,
		b.Username, b.currency, b.Role,
		b.Balance, b.Balance* b.actualrate Balance_Base,
		(b.Balance*b.actualrate) / g.actualrate Balance_Group,
		a.AccountRemark, a.AccountRemarkDate,
		a.IsGroupHeadLine,
		g.phone, g.checkerid
	FROM
		custAccount a with (nolock)
		INNER JOIN #Balance b ON a.custid = b.custid
		INNER JOIN #groupHeadLine g ON a.groupID = g.groupID
	ORDER BY
		a.groupID,
		a.IsGroupHeadLine DESC, 
		a.AccountRemarkDate DESC
	---------------------------------------------------------------\

	--END 


	drop table #groupHeadLine
	drop table #Balance	
END



ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Deposit_Yesterday]

AS
/*	Created by: Henry (based on Peter's script)
	Date: 2010-08-05
	Task: Add Deposit Balance Report for Account department
	DB: DB06.BODB02
	
	Revision:
		- 20101014@Johnson: Open new TLC site under Fun88 Super
		- 20101106@Henry: New site for DELA and SPONDEMO
		- 20101118@Henry: New site for TLC (TLC will be out of Fun88)
		- 20110106@Lukas: Re-arrange bettype
		- 20110118@Kevin: Add Alog site
		- 20110126@Johnson: Add new site Zzun88,SunCity, Mayfair
		- 20110224@Henry: Add new site Bezbet
		- 20110801@Henry: Add new site Haifa
		- 20110920@Henry: Add new site Bodog
		- 20111026@Henry: Add new site: SilverGoose8, VWin, Galaxy
		- 20120131@Henry: Change Sungame username prefix
		- 20120511@Henry: using Dep_Custsuper instead of using username prefix
		- 20120607@Viet: exclude all dummy agents from the list.
		- 20120615@Henry: hard-code not to show Bezbet
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @currentDate datetime 
	SELECT @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)	

	/*Select All total balance member under agents under all 12betsupers*/
	Declare @CustAgent table(username nvarchar(50),custid int ,currency varchar(20),actualrate float)
	Declare @CustSuper table(username nvarchar(50),custid int ,currency varchar(20),actualrate float)


	--12BET
	Insert into @CustAgent(username,custid,currency,actualrate)
	SELECT 
		c.username,
		c.custid,
		e.currency ,
		e.actualrate
	FROM
		Custinfo c WITH (NOLOCK)
		inner join exchange e (nolock) on e.exchangeid=c.currency
	WHERE 
		c.roleid = 2
		AND e.exchangeid <> 20
		AND c.srecommend IN (SELECT custid FROM dep_custsuper WITH (NOLOCK) WHERE site = '12Bet' )
		AND (c.username = '12BET' + e.currency + '01' or c.username =  '12BET' + e.currency + '02')
	
	--Others
	Insert into @CustAgent(username,custid,currency,actualrate)
	SELECT 
		c.username,
		c.custid,
		e.currency ,
		e.actualrate
	FROM
		Custinfo c WITH (NOLOCK)
		inner join (
			select replace(username, 'super', '') prefix, e.currency, e.actualrate, custid
			from dep_custsuper c WITH (NOLOCK)
				inner join exchange e  WITH (NOLOCK) on c.currency = e.exchangeid
			where site NOT in  ('12bet','bezbet')
				and exchangeid <> 20
		) e on c.srecommend = e.custid
	WHERE 
		c.roleid = 2		
		AND c.username = e.prefix + '01'
	--SELECT 
	--	c.username,
	--	c.custid,
	--	e.currency ,
	--	e.actualrate
	--FROM
	--	Custinfo c WITH (NOLOCK)
	--	inner join exchange e (nolock) on e.exchangeid=c.currency
	--WHERE 
	--	c.roleid = 2
	--	AND e.exchangeid <> 20
	--	AND c.srecommend IN (SELECT custid FROM dep_custsuper WITH (NOLOCK) WHERE site <> '12Bet' )
	--	AND (c.username LIKE '%' + e.currency + '01')
		
	/*
	select 
		username,
		custid,
		e.currency ,
		e.actualrate
	from 
		CustInfo c with (nolock) 
		inner join exchange e (nolock) on e.exchangeid=c.currency
	 where 
		roleid=2 and
		exchangeid <> 20 and --exclude UUS
		(username = '12BET' + e.currency + '01' or username =  '12BET' + e.currency + '02'
		 or username = 'AB88' + e.currency + '01' or username = 'TLC' + e.currency + '01' or  username = 'MS88' + e.currency + '01'
		 or username = 'SPON' + e.currency + '01' or username = 'DELA' + e.currency + '01'
		 or username = 'alog' + e.currency + '01' or username = 'Z88' + e.currency + '01' 
		 or username = 'SUG' + e.currency + '01' or username = 'MF' + e.currency + '01'
		 or username = 'BEZBET' + e.currency + '01' or username = 'HAIFA' + e.currency + '01'
		 or username = 'BODOG' + e.currency + '01' or username = 'SG8' + e.currency + '01'
		 or username = 'VWin' + e.currency + '01' or username = 'Galaxy' + e.currency + '01'
		 )
	*/	 

	Insert into @CustSuper(username,custid,currency,actualrate)
	SELECT
		s.username,
		s.custid,
		s.currency,
		e.actualrate
	FROM 
		Dep_custsuper s WITH (NOLOCK)
		INNER JOIN exchange e (NOLOCK) ON e.exchangeid = s.currency
	WHERE 
		e.exchangeid <> 20
		and s.site <>  'bezbet'
	/*
	select 
		username,
		custid,
		e.currency ,
		e.actualrate
	from 
		CustInfo c (nolock)
		inner join exchange e (nolock) on e.exchangeid=c.currency
	 where 
		roleid=4 and
		exchangeid <> 20 and --exclude UUS
		(username = '12betsuper' + e.currency or username = 'AB88Super' + e.currency or username = 'MS88Super' + e.currency
		or username = 'SPONSuper' + e.currency or username = 'DELASuper' + e.currency or username = 'TLCSuper' + e.currency
		or username = 'AlogSuper' + e.currency or username = 'Z88Super' + e.currency or username = 'SUGSuper' + e.currency
		or username = 'MFSuper' + e.currency or username = 'BEZBETSuper' + e.currency or username = 'HAIFASuper' + e.currency
		or username = 'BODOGSuper' + e.currency or username = 'SG8Super' + e.currency or username = 'GalaxySuper' + e.currency
		or username = 'VwinSuper' + e.currency
		)
	*/

	select 
		a.username,
		a.currency,
		a.actualrate,
		isnull(bal.balance,0) balance ,
		isnull(bal.balance,0)*a.actualrate basebalance
	from 
		@CustAgent a 
	    left join
		(
				select 
					b.recommend, 
					sum(IsNull(winlost,0)-IsNull(actual_stake,0) + IsNull(playercomm,0)) as balance
				from 
					bettrans b with (nolock)
				where 
					b.recommend in (Select custid from @CustAgent) 
					and ((bettype < 19001 and winlostdate < @currentDate) or bettype>19000)
					and b.custid <> b.recommend 
					and b.custid <> b.mrecommend 
					and b.custid <> b.srecommend
				group by b.recommend 
		 ) bal on bal.recommend=a.custid
	order by a.username

	select 
		s.username,
		s.currency,
		s.actualrate,
		(isnull(superCash,0) + isnull(masterCash,0) + isnull(agentCash,0) +isnull(memberCash,0) - isnull(TodayCompanyBalance,0) ) as balance,
		s.actualrate*(isnull(superCash,0) + isnull(masterCash,0) + isnull(agentCash,0) +isnull(memberCash,0) - isnull(TodayCompanyBalance,0) ) as basebalance
	from 
		@CustSuper s
		left join
		(
			select  
					b.srecommend,
					sum(case when b.custid=b.srecommend then isNull(winlost,0)-IsNull(actual_stake,0) else IsNull(swinlost,0) + IsNull(scomm,0) -IsNull(acomm,0) end) as superCash,
					sum(case when b.custid=b.mrecommend then isNull(winlost,0)-isNull(actual_stake,0) else isNull(mwinlost,0)+isNull(acomm,0)-isNull(comm,0) end) as masterCash,
					sum(case when b.custid=b.recommend  then isNull(winlost,0)-isNull(actual_stake,0) else isNull(awinlost,0) + isNull(comm,0)-isNull(playercomm,0) end) as agentCash,
					sum(case when b.custid <> b.recommend and b.custid <> b.mrecommend and b.custid <> b.srecommend and ruben=1 then isNull(winlost,0)-isNull(actual_stake,0) + isNull(playercomm,0) else 0 end) as memberCash,
					sum (case when b.bettype < 19001 and b.winlostdate >= @currentDate  and ruben = 1 then  isNull(swinlost,0) + isNull(scomm,0) + isNull(mwinlost,0) + isNull(awinlost,0) + isNull(winlost,0)-isNull(actual_stake,0) else 0 end) as TodayCompanyBalance
			from 
				bettrans b with (nolock)
			where 
				b.srecommend in (select custid from @CustSuper)
			group by b.srecommend
		)bal on bal.srecommend=s.custid
	 order by s.username

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Deposit_Yesterday] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Deposit_Yesterday] TO [vnteam]
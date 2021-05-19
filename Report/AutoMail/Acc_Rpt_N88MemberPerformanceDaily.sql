/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_N88_SB_Member_Performance_Daily] 
	@FromDate SMALLDATETIME,
	@ToDate SMALLDATETIME 
AS
	/*
	 Created: 20191101@Harry
	 Task: #145586 - SAS - Daily report - N88 Member Data
	 DB: DB061.BODB02
	 
	 Revisions:
	 - 20201117@Jaden: from adhoc to SP
	 - 20210519@Jaden: Switch to daily report
	 */
BEGIN 
	Create table #tmp_data
	(
		winlostdate date,
		CurrencyName nvarchar(10),
		leagueid int,
		sporttype int,
		homeid int,
		awayid int,
		username nvarchar (100),
		betcount int,
		WinlossP money,
		stake money,
		[effective betting value] money
	) 
	
	--bettrans---------------------------------------------------------------------------------------------------------------
	insert into #tmp_data
	select
		winlostdate,
		mc.CurrencyName,
		m.leagueid,
		m.sporttype,
		homeid,
		awayid,
		mc.username,
		(case when t.custid is not null then 0 else 1 end) [betcount],
		sum(winlost - actual_stake),
		sum(abs(stake)),
		sum(abs(winlost - actual_stake))
	from
		bettrans mc with (nolock)
		Inner join match m with (nolock) on mc.matchid = m.matchid
		and m.sporttype < 100
		Inner join vw_customer c with (nolock) on c.custid = mc.srecommend
		left join bodb02.dbo.TradeCust t with (nolock) on t.custid = mc.custid
	where
		mc.ruben = 1
		and winlostdate >= @FromDate and winlostdate <= @ToDate
		and mc.statusID in (111, 112, 113)
		and mc.Currency <> 20
		and mc.bettype not in (38, 901, 902, 903, 904, 911, 912, 913, 914)
		and c.site = 'N88'
	group by
		winlostdate,
		transid,
		mc.CurrencyName,
		m.leagueid,
		m.sporttype,
		homeid,
		awayid,
		mc.username,
		case when t.custid is not null then 0 else 1 end
	
	--------------------------------------------------------------------------------------------------------------------------------
	SELECT
		CAST(winlostdate as date) 'Date',
		b.username,
		s.SportName,
		l.leaguename,
		ISNULL(
			t1.teamname + ' vs ' + t2.teamname,
			'Combine Parlay Match'
		) [Match],
		CurrencyName,
		SUM(betcount) BetCount,
		SUM(b.Stake) AS [Turnover Member],
		SUM(b.WinlossP) AS [Winloss Member],
		SUM(b.[effective betting value]) as [Effective betting value]
	FROM
		#tmp_data b WITH (NOLOCK)
		LEFT join League l with (nolock) on l.leagueid = b.leagueid
		LEFT join Sports s with (nolock) on s.SportType = b.sporttype
		LEFT JOIN bodb02.dbo.team t1 WITH (nolock) on b.homeid = t1.teamid
		LEFT JOIN bodb02.dbo.team t2 WITH(nolock) on b.awayid = t2.teamid
	group by
		CAST(winlostdate as date),
		username,
		l.leaguename,
		b.leagueid,
		CurrencyName,
		s.SportName,
		ISNULL(
			t1.teamname + ' vs ' + t2.teamname,
			'Combine Parlay Match'
		)
	order by
		CAST(winlostdate as date),
		username,
		s.SportName,
		l.leaguename,
		CurrencyName 
	
	drop table #tmp_data
END
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
	 - 20210520@Jaden: Add column bettype
	 - 20210602@Jaden: Add more sites, Live indicator, Odds
	 - 20211222@Jaden: Add parlay
	 */
BEGIN 
	Create table #tmp_data
	(
		winlostdate date,
		CurrencyName nvarchar(10),
		liveindicator int,
		odds smallmoney,
        oddstype money,
		leagueid int,
		sporttype int,
		bettype int,
		homeid int,
		awayid int,
		username nvarchar (100),
		Sitename nvarchar (100),
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
		liveindicator,
		odds,
        oddstype,
		m.leagueid,
		m.sporttype,
		bettype,
		homeid,
		awayid,
		mc.username,
		c.site,
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
		and c.site in ('N88','N8B','N8G')
	group by
		winlostdate,
		transid,
		mc.CurrencyName,
		liveindicator,
		odds,
        oddstype,
		m.leagueid,
		m.sporttype,
		bettype,
		homeid,
		awayid,
		mc.username,
		c.site,
		case when t.custid is not null then 0 else 1 end
	
	--Add parlay bettype
	insert into #tmp_data
	select
		winlostdate,
		mc.CurrencyName,
		-11111,
		odds,
        -11111,
		-11111,
		-11111,
		CASE
			WHEN bettype = 29 AND betteam = 1 THEN 9
			ELSE 29 end,
		-11111,
		-11111,
		mc.username,
		c.site,
		(case when t.custid is not null then 0 else 1 end) [betcount],
		sum(winlost - actual_stake),
		sum(abs(stake)),
		sum(abs(winlost - actual_stake))
	from
		bettrans mc with (nolock)
		Inner join vw_customer c with (nolock) on c.custid = mc.srecommend
		left join bodb02.dbo.TradeCust t with (nolock) on t.custid = mc.custid
	where
		mc.ruben = 1
		and winlostdate >= @FromDate and winlostdate <= @ToDate
		and mc.statusID in (111, 112, 113)
		and mc.Currency <> 20
		and mc.bettype in (9,29)
		and c.site in ('N88','N8B','N8G')
	group by
		winlostdate,
		transid,
		mc.CurrencyName,
		odds,	
		CASE
			WHEN bettype = 29 AND betteam = 1 THEN 9
			ELSE 29 end,
		mc.username,
		c.site,
		case when t.custid is not null then 0 else 1 end
		
	--------------------------------------------------------------------------------------------------------------------------------
	SELECT
		CAST(winlostdate as date) 'Date',
		b.sitename,
		b.username,
		ISNULL(s.SportName,'Combine Parlay') [SportName],
		ISNULL(l.leaguename,'Combine Parlay') [leaguename],
		ISNULL(
			t1.teamname + ' vs ' + t2.teamname,
			'Combine Parlay'
		) [Match],
		CurrencyName,
		CASE 
			 WHEN liveindicator = -11111
				  THEN 'Combine Parlay'
			 WHEN liveindicator = 0
				  THEN 'Non-Live'
			 WHEN liveindicator = 1
				  THEN 'Live'
			 ELSE 'Live & Non-Live'
		 END [Live],
		CASE
            WHEN b.oddstype = 5 THEN odds*100
            Else odds
        END [odds],
        CASE
            WHEN b.oddstype = 1 THEN 'Dec'
            WHEN b.oddstype = 2 THEN 'HK'
            WHEN b.oddstype = 3 THEN 'Indo'
            WHEN b.oddstype = 4 THEN 'MY'
            WHEN b.oddstype = 5 THEN 'US'
			ELSE ''
        END [Odd Type],
		bt.typenamee [Bettype],
		SUM(betcount) BetCount,
		SUM(b.Stake) AS [Turnover Member],
		SUM(b.WinlossP) AS [Winloss Member],
		SUM(b.[effective betting value]) as [Effective betting value]
	FROM
		#tmp_data b WITH (NOLOCK)
		LEFT join League l with (nolock) on l.leagueid = b.leagueid
		LEFT join Sports s with (nolock) on s.SportType = b.sporttype
		LEFT join bettype bt with (nolock) on bt.typeid=b.bettype
		LEFT JOIN bodb02.dbo.team t1 WITH (nolock) on b.homeid = t1.teamid
		LEFT JOIN bodb02.dbo.team t2 WITH(nolock) on b.awayid = t2.teamid
	group by
		CAST(winlostdate as date),
		b.sitename,
		username,
		ISNULL(s.SportName,'Combine Parlay'),
		ISNULL(l.leaguename,'Combine Parlay'),
		CurrencyName,
		CASE 
			 WHEN liveindicator = -11111
				  THEN 'Combine Parlay'
			 WHEN liveindicator = 0
				  THEN 'Non-Live'
			 WHEN liveindicator = 1
				  THEN 'Live'
			 ELSE 'Live & Non-Live'
		 END,
		CASE
            WHEN b.oddstype = 5 THEN odds*100
            Else odds
        END,
        CASE
            WHEN b.oddstype = 1 THEN 'Dec'
            WHEN b.oddstype = 2 THEN 'HK'
            WHEN b.oddstype = 3 THEN 'Indo'
            WHEN b.oddstype = 4 THEN 'MY'
            WHEN b.oddstype = 5 THEN 'US'
			ELSE ''
        END,
		bt.typenamee,
		ISNULL(
			t1.teamname + ' vs ' + t2.teamname,
			'Combine Parlay'
		)
	order by
		CAST(winlostdate as date),
		username,
		ISNULL(s.SportName,'Combine Parlay'),
		ISNULL(l.leaguename,'Combine Parlay'),
		CurrencyName 
	
	drop table #tmp_data
END

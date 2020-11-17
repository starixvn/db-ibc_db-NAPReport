/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_TimeMachineTicket] @RptDate DATETIME 
AS
	/*
	 Created: 20191101@Harry
	 Task: #145519 - SAS - Daily report - Time machine tickets
	 DB: DB061.BODB02
	 
	 Revisions:
	 - 20191231@Harry: add reasons: Robot Betting and Irrigation Bet (?)
	 - 20201117@Jaden: from adhoc to SP
	 */
BEGIN 
	Create table #tmp_data
	(
		rptdate date,
		transid bigint,
		transdate datetime,
		liveindicator int,
		bettype int,
		leagueid int,
		betteam nvarchar (20),
		username nvarchar (100),
		currency int,
		sporttype int,
		odds smallmoney,
		transdesc nvarchar(1000),
		oddstype money,
		status nvarchar(10),
		homeid int,
		awayid int,
		hdp1 smallmoney,
		oddsspread money,
		livehomescore int,
		liveawayscore int,
		CurrencyName nvarchar(10),
		betcount int,
		WinlossP money,
		stake money,
		WinlossP_RM money,
		stake_RM money
	) 
	
	--bettrans data-------------------------------------------------------------------------------------------------------------------------------------------------
	Insert into #tmp_data 
	select
		winlostdate,
		transid,
		transdate,
		liveindicator,
		bettype,
		m.leagueid,
		betteam,
		mc.username,
		mc.currency,
		m.sporttype,
		mc.odds,
		transdesc,
		mc.oddstype,
		mc.[status],
		m.homeid,
		m.awayid,
		hdp1 + 1 'hdp1',
		oddsspread,
		mc.livehomescore,
		mc.liveawayscore,
		CurrencyName,
		1 as [betcount],
		(winlost - actual_stake),
		abs(stake),
		(winlost - actual_stake) * actualrate,
		abs(stake) * actualrate
	from
		bettrans mc with (nolock)
		Inner join match m with (nolock) on mc.matchid = m.matchid
	where
		winlostdate = @rptdate
		and mc.currency <> 20
		and mc.bettype = 228
		and mc.ruben = 1 --and mc.liveindicator = 1
	--------------------------------------------------------------------------------------------------------------------------------
	SELECT
		cast(b.rptdate as date) 'WinlossDate',
		cast(b.transid as varchar(100)) 'transid',
		s.SportName,
		username 'Customer ID',
		ISNULL(
			t1.teamname + ' vs ' + t2.teamname,
			'Combine Parlay Match'
		) [Match],
		CASE
			WHEN liveindicator = 0 THEN 'Non-Live'
			WHEN liveindicator = 1 THEN 'Live'
			ELSE 'Live & Non-Live'
		END [Live],
		bt.typenamee 'Bettype',
		CASE
			when betteam = 'o' then 'Over'
			when betteam = 'u' then 'Under'
		END + ' ' + cast(oddsspread as varchar(10)) [Bet Choice],
		'Before Minute' + ' ' + CAST(hdp1 as varchar(10)) 'Bet on selection',
		case
			when liveindicator = 1 then cast(livehomescore as varchar(10)) + ' - ' + cast(liveawayscore as varchar(10))
			else ''
		end 'Live Score',
		CurrencyName,
		(b.Stake) AS [Turnover Member_Original],
		(b.WinlossP) AS [Winloss Member_Original],
		(b.Stake_RM) AS [Turnover Member_RM],
		(b.WinlossP_RM) AS [Winloss Member_RM],
		b.odds,
		CASE
			WHEN b.oddstype = 1 THEN 'Dec'
			WHEN b.oddstype = 2 THEN 'HK'
			WHEN b.oddstype = 3 THEN 'Indo'
			WHEN b.oddstype = 4 THEN 'MY'
			WHEN b.oddstype = 5 THEN 'US'
		END [Odd Type],
		b.status
	FROM
		#tmp_data b WITH (NOLOCK)
		Left join bettype bt with (nolock) on bt.typeid = b.bettype
		Left join Sports s with (nolock) on s.SportType = b.sporttype
		LEFT JOIN team t1 WITH (nolock) on b.homeid = t1.teamid
		LEFT JOIN team t2 WITH(nolock) on b.awayid = t2.teamid 
		
	drop table #tmp_data
END
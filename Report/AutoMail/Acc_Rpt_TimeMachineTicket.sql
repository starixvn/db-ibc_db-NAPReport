/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_TimeMachineTicket] 
	 @FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
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
		bettime int,
		oddsspread money,
		livehomescore int,
		liveawayscore int,
		CurrencyName nvarchar(10),
		betcount int,
		WinlossP money,
		stake money,
		WinlossP_RM money,
		stake_RM money,
		matchid int
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
		hdp1,
		oddsspread,
		mc.livehomescore,
		mc.liveawayscore,
		CurrencyName,
		1 as [betcount],
		(winlost - actual_stake),
		abs(stake),
		(winlost - actual_stake) * actualrate,
		abs(stake) * actualrate,
		mc.matchid	
	from
		bettrans mc with (nolock)
		Inner join match m with (nolock) on mc.matchid = m.matchid
	where
		winlostdate = @FromDate
		and mc.currency <> 20
		and mc.bettype = 228
		and mc.ruben = 1 --and mc.liveindicator = 1
	--------------------------------------------------------------------------------------------------------------------------------
	select  *
	into #minute
	from DBDW2.bodb_DT.dbo.MatchTicker3rdStateDetail with (nolock) 
	where matchid in (select distinct matchid  from #tmp_data)
	--------------------------------------------------------------------------------------------------------------------------------
	SELECT
		cast(b.rptdate as date) 'WinlossDate',
		transdate,
		CASE WHEN (DATEDIFF(minute,mrd.[State1_Begin],ISNULL(mrd.[State1Extra_Begin],mrd.[State1Break_Begin])) BETWEEN 44 AND 47) 
			AND (DATEDIFF(minute,mrd.[State2_Begin],mrd.[State2Extra_Begin]) BETWEEN 44 AND 47) THEN
				CASE 
					WHEN   DATEDIFF(mi,mrd.State2Extra_Begin,b.TransDate)>=0 THEN 'Extra Time 2'
					WHEN DATEDIFF(mi,mrd.State2_Begin,b.TransDate)>=0 THEN 'Second Half'
					WHEN DATEDIFF(mi,mrd.State1Break_Begin,b.TransDate)>=0 THEN 'Break Time'
					WHEN DATEDIFF(mi,mrd.State1Extra_Begin,b.TransDate)>=0 THEN 'Extra Time 1'
					WHEN DATEDIFF(mi,mrd.State1_Begin,b.TransDate)>=0 THEN 'First Half'
					WHEN b.TransDate < mrd.State1_Begin THEN 'Early KO'
					ELSE 'N/A' END
				
		END		[Mission],
		CASE WHEN b.matchid IS NULL THEN 0
			WHEN CASE WHEN b.bettype IN (9,29) THEN b.livehomescore ELSE CAST(b.liveindicator AS tinyint) END <> 1 THEN 0
			WHEN (DATEDIFF(minute,mrd.[State1_Begin],ISNULL(mrd.[State1Extra_Begin],mrd.[State1Break_Begin])) BETWEEN 44 AND 47) 
					AND (DATEDIFF(minute,mrd.[State2_Begin],mrd.[State2Extra_Begin]) BETWEEN 44 AND 47) THEN
				CASE 
					WHEN DATEDIFF(mi,mrd.State2Extra_Begin,b.TransDate)=0 THEN 1
					WHEN DATEDIFF(mi,mrd.State2Extra_Begin,b.TransDate)>0 THEN DATEDIFF(mi,mrd.State2Extra_Begin,b.TransDate)
					WHEN DATEDIFF(mi,mrd.State2_Begin,b.TransDate)=0 THEN 1
					WHEN DATEDIFF(mi,mrd.State2_Begin,b.TransDate)>0 THEN DATEDIFF(mi,mrd.State2_Begin,b.TransDate)
					WHEN DATEDIFF(mi,mrd.State1Break_Begin,b.TransDate)=0 THEN 1
					WHEN DATEDIFF(mi,mrd.State1Break_Begin,b.TransDate)>0 THEN DATEDIFF(mi,mrd.State1Break_Begin,b.TransDate)
					WHEN DATEDIFF(mi,mrd.State1Extra_Begin,b.TransDate)=0 THEN 1
					WHEN DATEDIFF(mi,mrd.State1Extra_Begin,b.TransDate)>0 THEN DATEDIFF(mi,mrd.State1Extra_Begin,b.TransDate)
					WHEN DATEDIFF(mi,mrd.State1_Begin,b.TransDate)=0 THEN 1
					WHEN DATEDIFF(mi,mrd.State1_Begin,b.TransDate)>0 THEN DATEDIFF(mi,mrd.State1_Begin,b.TransDate)
					WHEN ISNULL(DATEDIFF(mi,b.TransDate,mrd.State1_Begin),0)>5 THEN 5
					WHEN b.TransDate < mrd.State1_Begin  THEN ISNULL(DATEDIFF(mi,b.TransDate,mrd.State1_Begin),0)
					ELSE 0 END
		END [GameTime],
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
		bettime,
		'Before Minute' + ' ' + CAST(hdp1 as varchar(10)) 'Bet on selection',
		case
			when liveindicator = 1 then cast(b.livehomescore as varchar(10)) + ' - ' + cast(b.liveawayscore as varchar(10))
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
		LEFT JOIN bettype bt with (nolock) on bt.typeid = b.bettype
		LEFT JOIN Sports s with (nolock) on s.SportType = b.sporttype
		LEFT JOIN team t1 WITH (nolock) on b.homeid = t1.teamid
		LEFT JOIN team t2 WITH(nolock) on b.awayid = t2.teamid 
		LEFT JOIN  #minute mrd WITH(nolock)  on mrd.matchid=b.matchid
	    LEFT JOIN match m (NOLOCK) ON b.matchid = m.matchid
		
	drop table #tmp_data
	drop table #minute
END
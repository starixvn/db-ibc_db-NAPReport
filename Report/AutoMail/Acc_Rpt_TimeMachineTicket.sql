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
	 - 20210122@Jaden: New changes
     - 20210422@Jaden: Implement 229 (#153872)
     - 20210506@Jaden: new bug fixes (#145519)
     - 20210603@Jaden: Include 8RM data (#145586)
     - 20220124@Jaden: Separate TM corners bet type (#145519)
	 - 20220314@Roy: extend data type of extrainfo
     - 20220517@Jaden: add leaguename (#145519)
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
        WinlossP_RM money,
        stake_RM money,
        company_VirtualTO money,
        company_VirtualWL money,
        company_VarianceTO money,
        company_VarianceWL money,
        company_RealTO money,
        company_RealWL money,
        matchid int,
        mission nvarchar (100),
        [minute] nvarchar (10),
        extrainfo nvarchar (max)
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
        (winlost - actual_stake) * actualrate,
        abs(stake) * actualrate,
        (ABS(Stake) * (1-tpositiontaking-isnull(mc.epositiontaking,0) ) * mc.virtualrate) VirtualTO,
        - ((winlost-actual_stake)* (1-tpositiontaking-isnull(mc.epositiontaking,0))* mc.virtualrate 
+ (Scomm - case when tpositiontaking = 1  then 0 else Scomm / (1-tpositiontaking) * isnull(mc.epositiontaking,0) end) * case when virtualrate < actualrate then virtualrate else actualrate end ) VirtualWL,
        (ABS(Stake) * (1-tpositiontaking -isnull(mc.epositiontaking,0)) * abs(virtualrate - actualrate)) VarianceTO,
        (((winlost-actual_stake)*(1-tpositiontaking-isnull(mc.epositiontaking,0)) + case when mc.virtualrate< actualrate then (scomm - case when tpositiontaking = 1  then 0 else Scomm / (1-tpositiontaking) * isnull(mc.epositiontaking,0) end) else 0 end)*(mc.virtualrate - actualrate)) VarianceWL,
        (ABS(Stake) * (1-tpositiontaking-isnull(mc.epositiontaking,0)) * case when mc.virtualrate > actualrate then mc.virtualrate else actualrate end) RealTO,
        - (((winlost-actual_stake)*(1-tpositiontaking-isnull(mc.epositiontaking,0))+ (Scomm - case when tpositiontaking = 1  then 0 else Scomm / (1-tpositiontaking) * isnull(mc.epositiontaking,0) end))*actualrate) RealWL,
        mc.matchid,      
         CASE WHEN  CAST(extrainfo AS XML).value('(/p1/@isht)[1]', 'varchar(50)') IS NOT NULL 
                                    THEN 'isht' 
                            ELSE   'mtimer'  
                        END, 
         CASE WHEN  CAST(extrainfo AS XML).value('(/p1/@isht)[1]', 'varchar(50)') IS NOT NULL 
                    THEN  CAST(extrainfo AS XML).value('(/p1/@isht)[1]', 'varchar(50)') 
            ELSE    CAST(extrainfo AS XML).value('(/p1/@mtimer)[1]', 'varchar(50)')  
        END 
        ,extrainfo
    from
        bettrans mc with (nolock)
        Inner join match m with (nolock) on mc.matchid = m.matchid
    where
        winlostdate between @FromDate and @ToDate
        and mc.currency <> 20
        and mc.bettype in (228, 229)
        and mc.ruben = 1 
    --------------------------------------------------------------------------------------------------------------------------------
    update  a
    set mission='Extra Time 1'
    from #tmp_data a
    where [minute] like '%+%'

	update  a
    set [minute]= REPLACE([minute],'1H','')
    from #tmp_data a
    where [minute] like '%1H%' and mission='mtimer'

	update  a
    set [minute]= cast(REPLACE([minute],'2H','') as int) + 45
    from #tmp_data a
    where [minute] like '%2H%' and mission='mtimer'
    --------------------------------------------------------------------------------------------------------------------------------

    SELECT
        cast(b.rptdate as date) 'WinlossDate',
        transdate,
        Case    
            When mission='isht' then 'Break Time'
            When mission='Extra Time 1' then 'Extra Time 1'
            When mission='mtimer' and cast([minute] as int)=0 and liveindicator = 0 then 'Early KO'
            When mission='mtimer' and cast([minute] as int)<45 then 'First Half'
            When mission='mtimer' and cast([minute] as int)>=45 then 'Second Half'
            Else 'N/A'
        end [Mission],
        Case
            When mission='mtimer' and cast([minute] as int)>=45 then convert(nvarchar(10),convert(int,left([minute],2))-45)
            else  [minute] 
            end [GameTime],
        Bettime,        
        cast(b.transid as varchar(100)) 'transid',
        s.SportName,
        l.leaguename,
        ISNULL(
            t1.teamname + ' - vs - ' + t2.teamname,
            'Combine Parlay Match'
        ) [Match],
        CASE
            WHEN liveindicator = 0 THEN 'Non-Live'
            WHEN liveindicator = 1 THEN 'Live'
            ELSE 'Live & Non-Live'
        END [Live],
        Case 
			When childmatchtype=204 then bt.typenamee + ' (Corners)'
			else bt.typenamee 
        end 'Bettype',
        CASE
            when betteam = 'o' then 'Over' + ' ' + cast(oddsspread as varchar(10))
            when betteam = 'u' then 'Under' + ' ' + cast(oddsspread as varchar(10))
            when betteam = 'h' then 'Home' + ' ' + cast(oddsspread as varchar(10))
            when betteam = 'a' then 'Away' + ' ' + cast(-oddsspread as varchar(10))
        END  [Bet Choice],
        'Before Minute' + ' ' + CAST(hdp1 as varchar(10)) 'Bet on selection',
        case
            when liveindicator = 1 then cast(b.livehomescore as varchar(10)) + ' - ' + cast(b.liveawayscore as varchar(10))
            else ''
        end 'Live Score',
        CurrencyName,
        (b.Stake_RM) AS [Turnover Member_RM],
        (b.WinlossP_RM) AS [Winloss Member_RM],
        company_VirtualTO ,
        company_VirtualWL ,
        company_VarianceTO ,
        company_VarianceWL ,
        company_RealTO ,
        company_RealWL ,
        CASE
            WHEN b.oddstype = 1 THEN odds+1
            WHEN b.oddstype = 5 THEN odds*100
            Else odds
        END [odds],
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
        LEFT JOIN match m (NOLOCK) ON b.matchid = m.matchid
        LEFT JOIN league l (NOLOCK) ON l.leagueid=b.leagueid
	order by cast(b.rptdate as date),
        transdate

    drop table #tmp_data
END

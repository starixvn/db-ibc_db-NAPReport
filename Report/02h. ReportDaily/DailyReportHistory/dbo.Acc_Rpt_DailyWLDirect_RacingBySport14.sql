ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_RacingBySport14]
	@winlostdate	datetime,
	@sporttype		INT
AS

	/*	Creator: Phuong Dao
		Date: 2009-03-03
		Task: Horse Racing WinLost Summary report
		DB: DBACC/bodb02
		Original: [Acc_Rpt_DailyWLDirect_HorseRacing14]
		
		Revisions:
			- 20090606@PhuongDao: PT Winloss Tote HR 
				+ 	FreeDue2 = AmtoteFee + PGIFee with AmtoteFee = 0.0033 PGIFee = 0.005
			- 20090722@Kiwi: Improve peformance by using table variable
			- 20090731@Jamie: Not to view data in range of date, but only one date at once 	
			- 20090815@Jamie: Include Fixed Odds HR
			- 20100331@Jamie: arrange the new structure for HR meetings 
				+ Remove hard-code FeeDue2 
				+ Remove Fixed Odds out as well
			-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20110314@Johnson: - Change SP's name
								- Add parameter @sporttype	
								- Check Tote Fee is passed to Partners or not							
			- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
			- 20130618@Johnson: Add NSW racing's pools from AUST
			- 20130801@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)			
			- 20151120@Percy: Change column name (to match DW) [RedmineID: #46576]	
	*/
	SET NOCOUNT ON
	--insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)
	
	DECLARE @CommSetting TABLE
	(	MatchID			int,
		IBCFee			bit,
		ToteCommWin		smallmoney,
		ToteCommPlace	smallmoney,
		ToteCommWP		smallmoney,
		ToteFee			smallmoney	
	)
	
	CREATE TABLE #DepAgent (custid int primary key)
		
	INSERT INTO #DepAgent 
	SELECT custid
	FROM custInfo with(NOLOCK)
	WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
		AND roleid = 2
	UNION
	SELECT 5707545--BARM
		
	
	INSERT INTO @tmpIBCFee (partnerID, IBCFee)
		SELECT 1,1 --RACE-PHU
	UNION ALL
		SELECT 2,0 --RACE-ATRUK
	UNION ALL
		SELECT 3,0 --RACE-ATRIRL
	UNION ALL
		SELECT 4,0 --RACE-RUK
	UNION ALL
		SELECT 5,1 --RACE-TABCORP
	UNION ALL
		SELECT 6,1 --RACE-TABCORPNSW
	UNION ALL
		SELECT 101,1 --GREY-DTOTEUK
	UNION ALL
		SELECT 102,1 --GREY-DTOTEIRL
	UNION ALL
		SELECT 103,1 --GREY-TABCORP
	UNION ALL
		SELECT 104,1 --GREY-TABCORPNSW
	UNION ALL
		SELECT 201,1 --HAR-TABCORP
	UNION ALL
		SELECT 202,1 --HAR-TABCORPNSW
		
	INSERT INTO @CommSetting (MatchID, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
	SELECT	DISTINCT o.orid as matchid, t.IBCFee, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright14 o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID AND p.programDate = o.programDate 
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON p.leagueid = r.meetingid 
			INNER JOIN League l WITH(NOLOCK) ON p.leagueid = l.leagueid
			INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID 
	WHERE	o.eventdate = @winlostdate AND l.sporttype = @sporttype
	
	SELECT	b.bettype,
			case when dep.custid is null then 1 else 2 end as [site],
			sum((b.winlost -b.actual_stake)*b.actualrate) WinLost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) Position,
			sum(b.scomm*b.actualrate) Commission,
			-(sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
			- sum(case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when bettype in (31,32) then b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0) ) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
			+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 33 then bm.TOPhum*cs.ToteCommWP 
								else 0 end)*b.actualrate) --commIncomeIBC
			- sum(b.scomm*b.actualrate)) LineTotal,
			sum(case when bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) Turnover
			
	FROM	bettrans14 b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid  
			 left join (
				select	refno,
						sum(case when bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm14 with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			LEFT JOIN (select custid from #DepAgent) dep ON b.recommend = dep.custid 		
	WHERE	b.ruben =1 
			and b.bettype in (31,32,33)
			and b.matchid >0
			and b.winlostdate = @winlostdate
			--and b.status not in ('VOID','REJECT','DONE','REFUND')
			and b.statusID not in (101,102,103,121)

	GROUP BY b.bettype, case when dep.custid is null then 1 else 2 end 
	ORDER BY b.bettype, site 
	
	DROP TABLE #DepAgent
	
	
	
	GO
    GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_RacingBySport14] TO [bodbAdminNet]
	GO
	GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_RacingBySport14] TO [vnteam]
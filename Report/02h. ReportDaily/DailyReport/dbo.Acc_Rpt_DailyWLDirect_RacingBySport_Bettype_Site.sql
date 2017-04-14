 ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_RacingBySport_Bettype_Site]
	@sporttype		INT,
	@winlostdate	DATETIME,
	@bettype		INT,
	@site			TINYINT
 AS
	/*
		Creator: Johnson
		Date: 2013-07-31
		Task: Report winlost summary for racing
		DB: DBACC/bodb02 
		
		Revisions:
			- 20151120@Percy: Change column name (to match DW) [RedmineID: #46576]
		
		Parameter's Explanation:
			- @site: 1: credit
					2: deposit	
	*/	
BEGIN
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
	
	CREATE TABLE #DepAgent (custid int primary key , site varchar(50))
	
	INSERT INTO #DepAgent (custid, site)
	SELECT c.custid, site
	FROM customer c WITH(NOLOCK)
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid, site)
	SELECT 52466,'XYZBET' WHERE @site = 1--8RM
	UNION
	SELECT 5707545,'BEST-ODDS' WHERE @site =2 --BARM
		
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
	FROM	outright o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID and p.programDate = o.programDate
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON p.leagueid = r.meetingid
			INNER JOIN league l WITH(NOLOCK) ON p.leagueid = l.leagueid 
			INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.eventdate = @winlostdate and l.sporttype = @sporttype

	
	SELECT	[site],
			sum((b.winlost -b.actual_stake)*b.actualrate) WinLost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) Position,
			sum(b.scomm*b.actualrate) Commission,
			-(sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
			- sum(case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when bettype in (31,32) then b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0) ) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
			+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 33 then bm.TOPhum*cs.ToteCommWP 
								else 0 end)*b.actualrate) --commIncomeIBC
			- sum(b.scomm*b.actualrate)) RealLineTotal,
			-(sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
			- sum(case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when bettype in (31,32) then b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0) ) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
			+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 33 then bm.TOPhum*cs.ToteCommWP 
								else 0 end)*b.actualrate) --commIncomeIBC
			- sum(b.scomm*b.actualrate)) VirtualLineTotal,
			sum(case when bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) RealTurnover,
			sum(case when bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) VirtualTurnover
			
	FROM	bettrans b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid  
			 left join (
				select	refno,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			 INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE	b.ruben =1 
			and b.bettype = @bettype
			and b.matchid >0
			and b.winlostdate = @winlostdate
			--and b.status not in ('VOID','REJECT','DONE','REFUND')
			and b.statusID NOT IN (101,102,103,121)

	GROUP BY site
	ORDER BY site
	
	DROP TABLE #DepAgent
END





GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_RacingBySport_Bettype_Site] TO [bodbAdminNet]

 
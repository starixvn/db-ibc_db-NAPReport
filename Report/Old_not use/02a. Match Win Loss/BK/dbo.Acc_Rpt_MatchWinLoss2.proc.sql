ALTER PROCEDURE [dbo].[Acc_Rpt_MatchWinLoss2]
	@winlostdate		 datetime,
	@WinLost_8RM		 money OUTPUT,
	@WinLost_BARM		 money = 0 OUTPUT
	--@FI_3rdShare		 money = 0 OUTPUT
AS

	/*	Creator: Thien Pham
		Date: 2008
		Task: Report 2A
		DB: DB06.BODB02
		
		Original: \account\matchwinloss2.asp
	
		History:
			- 20081119@PhuongDao: Display winlost for Horse Racing
			- 20081128@PhuongDao: Show winlost of 12BET Agent 
								   + 12 BET AGENT 01 : NORMAL DEPOSIT 
								   + 12 BET AGENT 02 : AFF 
			- 20081218@PhuongNguyen: Get isNeutral from Match table insteade of Match_remark table 
			- 20081220@PhuongDao: Show winlost for Finance 	
								  + Dummy account for Third Party: FI3rdShareUS$, FI3rdShareEURO,...	
			- 20090120@KhoaTran: Show kickoff time for each match 					
			- 20090417@PhuongDao: Show Casino and P2P report 	
			- 20090423@DungTong: Improve performance 	
			- 20090505@PhuongDao: Remove the calculation via the virtualrate for Mix Parlay, Outright and 8RM
			- 20090507@PhuongDao: Remove params @WinLost_8RM_Live and @WinLost_8RM_NonLive 
			- 20090606@PhuongDao: PT Winloss Tote HR 
				+ FreeDue2 = AmtoteFee + PGIFee   
				+ AmtoteFee = 0.0033 PGIFee = 0.005	
			- 20090719@KhoaTran: remove sp Admin_3rdAutoSettlement_s201
			- 20090722@Kiwi: Improve peformance for Horse Racing by using table variable
			- 20090731@Jamie: Not to view data in range of date, but only one day. 
			- 20090815@Jamie: Include Fixed Odds HR Report
			- 20100331@Jamie: arrange the new structure for HR meetings 
				+ Remove hard-code FeeDue2 
				+ Remove Fixed Odds out as well 
			-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20100611@Henry: Change mix-parlay match from 0 to 9
			- 20100916@Henry: Include Bingo + Number Game
			- 20110311@Johnson: - Change bettype 'Tote HR' to 'Racing'
								- Check Tote Fee is passed to Partners or not
								- Remove Finance 
			- 20110520@Amy: Re-arrange bettype
			- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
			- 20110728@Johnson: - add new bettype mix-parlay combination
								- add more bettype for number game Warrior, Next Combo, Number Group
			- 20110929@Tom: 1. Add Report for P2P Games  Bettype: 1000	
							2. Hide code Report Casino and Bingo
			- 20111122@Tom: Unhide code Report Casino and Bingo
			- 20111202@Sophia: Add new range of sportbook from 121 to 999
			- 20120231@Sophia: Add live casino bettype from 1101 to 1199
			- 20120405@Hurri: Exclude bettype 72 (P2P bet ticket) in the calculation of Casino
			- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
			- 20120503@Sophia: Edit LineTotal for P2P
			- 20120530@Elodie: Edit VirtualLineTotal for Mix Parlay and Outright
							   Change formula of 8RM/BARM winloss
			- 20120626@Elodie: exclude outright from sportbook ( in case of matchid = orid)
			- 20120813@Elodie: Add Virtual sports report
			- 20130618@Johnson: Add NSW racing's pool from AUST
		Explanation's Param:
		 - @WinLost_8RM: winlost for outsource 
		 - @WinLost_BARM: winlost for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)

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
	FROM outright o WITH (NOLOCK)
		INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID and p.programDate = o.programDate
		INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid
		INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.eventdate = @winlostdate 
	

	select
        m.matchcode,
        m.eventdate,
        m.kickofftime,
        b.liveindicator,
        b.bettype,   
        m.homeid,
        m.awayid,
        b.winlost,
        b.pos,
        b.comm,   
        b.VirtualComm,
        b.LineTotal,
        b.VirtualLineTotal,
        UPPER(case when l.leaguenametc = '' or l.leaguenametc is null  then 'Other Sports' else l.leaguenametc end) as leaguenametc,
        isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral
    from
     (
           select matchid,liveindicator,bettype,
                sum((winlost-actual_stake)*actualrate) winlost,
                sum((awinlost+mwinlost+swinlost)*actualrate) pos,
                sum((scomm)*actualrate) comm,   
                sum((scomm)*virtualrate) VirtualComm,
                sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal,
                sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal
            from	bettrans with (nolock)
            where   winlostdate = @winlostdate and
                    ruben=1 and               
                    ((bettype < 31 AND bettype <> 10) OR bettype between 121 and 999) and --20120626@Elodie: exclude outright from sportbook					
                    matchid>=0 and
					--status not in ('VOID','REJECT','REFUND')
					statusID NOT IN (101,102,103)
						                   
             group by matchid,liveindicator,bettype
               
     )b
        inner join match m with (nolock) on m.matchid=b.matchid
        inner join league l with (nolock) on l.leagueid=m.leagueid
   
    order by l.leaguenametc, b.bettype, b.liveindicator desc, m.matchcode

	------------------------------------------------
	-- Mix Parlay
	------------------------------------------------
	select	b.winlostdate,
			b.winlost,
			b.pos,
			b.comm,
			b.comm as virtualComm,
			b.Linetotal,
			b.VirtualLineTotal,
			b.bettype
	from (
			select bettrans.winlostdate, 
				sum((winlost-actual_stake)*bettrans.actualrate)  winlost, 
				sum((awinlost+mwinlost+swinlost)*bettrans.actualrate) pos,
				sum((scomm)*bettrans.actualrate) comm,
				sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate) as LineTotal,
				sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.virtualrate) as VirtualLineTotal,
				'Parlay-' + bettrans.status bettype 
			from bettrans bettrans with (nolock)
			where bettrans.winlostdate = @winlostdate
					AND bettrans.ruben=1  
					--and bettrans.matchid=0  
					AND 1 = CASE WHEN bettrans.bettype= 9 AND bettrans.matchid = 9 THEN 1
								WHEN bettrans.bettype= 29 AND bettrans.matchid = 29 THEN 1
								ELSE 0 END					
					--and bettrans.status not in ('VOID','REJECT','REFUND')
					AND bettrans.statusID not in (101,102,103)
			group by bettrans.winlostdate, bettrans.status 
	) b 	
	------------------------------------
	--- OUTRIGHT 
	------------------------------------
	union all
	select	o.winlostdate,
			o.winlost,
			o.pos,
			o.comm,
			o.comm as virtualComm,
			o.Linetotal,
			o.VirtualLineTotal,
			'Out Right' bettype
	from (
			select  bettrans.winlostdate, 
					sum((winlost-actual_stake)*bettrans.actualrate)  winlost, 
					sum((awinlost+mwinlost+swinlost)*bettrans.actualrate) pos,
					sum((scomm)*bettrans.actualrate) comm,
					sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate) as LineTotal,
					sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.virtualrate) as VirtualLineTotal
			from bettrans bettrans with (nolock)
			where	bettrans.winlostdate = @winlostdate
					and bettrans.ruben=1  
					and bettrans.bettype=10 
					and bettrans.matchid >0 
					--and bettrans.status not in ('VOID','REJECT','REFUND')
					and bettrans.statusID not in (101,102,103)
			group by bettrans.winlostdate 
	) o 
	-------------------------------------------------
	--- FINANCE
	-------------------------------------------------	
	/*UNION ALL
	select  bettrans.winlostdate, 
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum( scomm*bettrans.actualrate),0) comm,
			0 VirtualComm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			0 VirtualLineTotal, --virtualrate = actualrate    
			'Finance' bettype 
	from bettrans with (nolock)
	where 	bettrans.winlostdate = @winlostdate
			and bettrans.ruben=1  
			and bettrans.bettype between 51 and 66 
			and bettrans.matchid > 0 
			--and bettrans.status not in ('VOID','REJECT','done','REFUND')
			and bettrans.statusID not in (101,102,103,121)
	group by bettrans.winlostdate 
	*/
	-----------------------------------------------
	---- RACING 
	-----------------------------------------------
	UNION ALL
	SELECT	b.winlostdate,
			sum((b.winlost -b.actual_stake)*b.actualrate) winlost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) pos,
			sum(b.scomm*b.actualrate) comm,
			0 VirtualComm,
			-(
				sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) -- PTWLIBC, 
				- sum(case when cs.IBCFee = 0 then 0 else
						(case when b.bettype = 33 then bm.TOPhum 
							when b.bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0)) else 0 end)*b.actualrate*cs.ToteFee end) -- FeeDue2 ,
				+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
									when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
									when 33 then bm.TOPhum*cs.ToteCommWP 
									else 0 end)*b.actualrate)-- commIncomeIBC
				- sum(b.scomm*b.actualrate)
			) Linetotal,
			0 VirtualLineTotal,
			'Racing' bettype
	FROM	bettrans b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid  
			 left join (
				select	refno,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore<>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
	WHERE	b.ruben =1 
			and b.bettype in (31,32,33)
			and b.matchid >0
			and b.winlostdate = @winlostdate
			--and b.status not in ('VOID','REJECT','DONE','REFUND')
			and b.statusID not in (101,102,103,121)
	GROUP BY b.winlostdate
	
	-----------------------------------------------
	----CASINO - 71
	-----------------------------------------------
	
	UNION ALL
	select  bettrans.winlostdate, 
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum( scomm*bettrans.actualrate),0) comm,
			0 VirtualComm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			0 VirtualLineTotal, --virtualrate = actualrate    
			'Casino' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.winlostdate = @winlostdate
			and bettrans.ruben=1  
			and bettrans.bettype = 71								--20120405@Hurri
			AND bettrans.matchid = 0 
			--and status NOT in ('done','VOID','REJECT','REFUND')
			and statusID NOT in (101,102,103,121)
	group by bettrans.winlostdate

	--BINGO - 73
	UNION ALL
	select  bettrans.winlostdate, 
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			isnull(sum( scomm*bettrans.actualrate),0) comm,
			0 VirtualComm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			0 VirtualLineTotal, --virtualrate = actualrate    
			'Bingo' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.winlostdate = @winlostdate
			and bettrans.ruben=1  
			and bettrans.bettype = 73
			AND bettrans.matchid = 0 
			--and status NOT in ('done','VOID','REJECT','REFUND')
			and statusID NOT in (101,102,103,121)
	group by bettrans.winlostdate	

	
	--P2P Game - 1000
	UNION ALL
	select  bettrans.winlostdate, 
			isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			0 pos,
			isnull(sum(scomm*bettrans.actualrate),0) comm,
			0 VirtualComm,
			isnull(sum(-1*(odds-scomm)*bettrans.actualrate),0) as LineTotal,
			0 VirtualLineTotal, --virtualrate = actualrate    
			'P2P' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.bettype = 1000
			and bettrans.matchid = 1000 
			and bettrans.ruben=1  
			and bettrans.winlostdate = @winlostdate			
			and statusID NOT in (101,102,103,121)
	group by bettrans.winlostdate		
	
	--NUMBER GAME 
	UNION ALL
	select  bettrans.winlostdate, 
			ISNULL(SUM((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			ISNULL(SUM((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			ISNULL(SUM( scomm*bettrans.actualrate),0) comm,
			ISNULL(SUM( scomm*bettrans.virtualrate),0) VirtualComm,
			ISNULL(SUM((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			ISNULL(SUM((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.virtualrate),0) as VirtualLineTotal,
			'Number Game' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.winlostdate = @winlostdate
			AND bettrans.ruben=1  
			AND bettrans.bettype BETWEEN 81 AND 120
			AND bettrans.matchid >= 0 
			--and status NOT in ('done','VOID','REJECT','REFUND')
			AND statusID NOT IN (101,102,103,121)
	group by bettrans.winlostdate	
	
	--Virtual Sports
	UNION ALL
	select  bettrans.winlostdate, 
			ISNULL(SUM((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			ISNULL(SUM((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			ISNULL(SUM( scomm*bettrans.actualrate),0) comm,
			0 as VirtualComm,
			ISNULL(SUM((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			0 as VirtualLineTotal,
			'Virtual Sports' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.winlostdate = @winlostdate
			AND bettrans.ruben=1  
			AND bettrans.bettype BETWEEN 1201 AND 1299
			AND bettrans.matchid >= 0 
			--and status NOT in ('done','VOID','REJECT','REFUND')
			AND statusID NOT IN (101,102,103,121)
	group by bettrans.winlostdate	

	--Live Casino
	UNION ALL
	select  bettrans.winlostdate, 
			ISNULL(SUM((winlost-actual_stake)*bettrans.actualrate),0)  winlost, 
			ISNULL(SUM((awinlost+mwinlost+swinlost)*bettrans.actualrate),0) pos,
			ISNULL(SUM( scomm*bettrans.actualrate),0) comm,
			0 as VirtualComm,
			ISNULL(SUM((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*bettrans.actualrate),0) as LineTotal,
			0 as VirtualLineTotal,
			'Live Casino' bettype 
	from bettrans bettrans with (nolock)
	where 
			bettrans.winlostdate = @winlostdate
			AND bettrans.ruben=1  
			AND bettrans.bettype BETWEEN 1101 AND 1199
			AND bettrans.matchid >= 0 
			--and status NOT in ('done','VOID','REJECT','REFUND')
			AND statusID NOT IN (101,102,103,121)
	group by bettrans.winlostdate	
	
	--------------------------------------------------
	---- Third Party Finance 
	--------------------------------------------------
	/*SELECT	@FI_3rdShare = isnull(sum((winlost-actual_stake)*bettrans.actualrate),0)
	FROM	bettrans with (nolock)
	WHERE	bettrans.ruben=1 and
			bettrans.winlostdate = @winlostdate and
			bettrans.bettype between 51 and 66 and 
			bettrans.matchid > 0 and 
			bettrans.custid in (SELECT custid FROM customer c with (nolock) 
												   INNER JOIN exchange e with (nolock) on c.currency = e.exchangeid 
										  WHERE c.username ='FI3rdShare'+ e.currency)*/
	
	/*Hidden temporarily*/
	-------------------------------------------------
	--== 12 BET Agents 
	-------------------------------------------------

--	UNION ALL
--	SELECT 
--			'' winlostdate, 
--			0 winlost,
--			0 pos,
--			0 comm,
--			0 VirtualComm ,
--			ISNULL(SUM(LineTotal),0) LineTotal,
--			ISNULL(SUM(VirtualLineTotal),0) VirtualLineTotal,
--			'12BET Agents' bettype
--	FROM (
--			SELECT  
--					isnull(sum(-awinlost * bettrans.actualrate) ,0) LineTotal, 
--					isnull(sum(-awinlost * bettrans.virtualrate) ,0)  VirtualLineTotal
--						
--			FROM bettrans  with (nolock)
--			WHERE	bettrans.winlostdate = @winlostdate
--					and bettrans.ruben=1 and bettype < 91 
--					and bettrans.recommend in (
--												791083,	--	12BETUS$01
--												791088,	--	12BETEURO01
--												836210,	--	12BETTB01
--												836215,	--	12BETGBP01
--												836224,	--	12BETRM01
--												836230,	--	12BETRMB01
--												858249,	--	12BETUUS01
--												1015422,--	12BETAUD01
--												1015430	--	12BETCHF01					
--											  )
--
--				
--			UNION ALL
--
--			SELECT  isnull(sum(-mwinlost * bettrans.actualrate) ,0) LineTotal, 
--					isnull(sum(-mwinlost * bettrans.virtualrate) ,0)  VirtualLineTotal
--			FROM bettrans  with (nolock)
--			WHERE	bettrans.winlostdate = @winlostdate
--					and bettrans.ruben=1 and bettype < 91 
--					and bettrans.recommend in (	
--												860376,	--	12BETUS$02
--												860379,	--	12BETEURO02
--												860380,	--	12BETTB02
--												860383,	--	12BETGBP02
--												860386,	--	12BETRM02
--												860387,	--	12BETRMB02
--												916515,	--	12BETUUS02
--												1015423,--	12BETAUD02
--												1015433	--	12BETCHF02
--											  )	
--			) bettrans

	select  @WinLost_8RM = - isnull(sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm),0) 
	from	bettrans with (nolock)
	where	recommend = 52466 and
			winlostdate = @winlostdate and
			matchid >=0 and 
			ruben=1 and
			bettype <= 999 and 
			--status not in ('VOID','REJECT','REFUND')
			statusID not in (101,102,103)
			
	-- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
	select  @WinLost_BARM = - isnull(sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm),0) 
	from	bettrans with (nolock)
	where	recommend = 5707545 and
			winlostdate = @winlostdate and
			matchid >=0 and 
			ruben=1 and
			bettype <= 999 and 
			--status not in ('VOID','REJECT','REFUND')
			statusID not in (101,102,103)
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchWinLoss2] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchWinLoss2] TO [vnteam]
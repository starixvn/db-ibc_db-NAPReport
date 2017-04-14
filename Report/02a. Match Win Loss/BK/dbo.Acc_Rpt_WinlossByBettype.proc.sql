ALTER PROCEDURE [dbo].[Acc_Rpt_WinlossByBettype]
	@winlostdate		datetime
AS
	/*	Creator: Vinh Truong 
		Date: 2008-03-20		
		Task: Report winlost by bettype 
		DB: DBACC/BODB02

		History:
			- 20081119@PhuongDao: Display winlost for Horse Racing
									+ CommIncFrHR : IBC Income
									+ CommExp4HR : IBC Expense 

			- 20081128@PhuongDao: Show winlost of 12BET Agent 
								   + 12 BET AGENT 01 : NORMAL DEPOSIT 
								   + 12 BET AGENT 02 : AFF 
								   + Non-Live Others = TotalLine - ( Live Soccer + Non-Live Soccer + Live Others) 
			- 20081220@PhuongDao: Show winlost for Finance 	
								  + Dummy account for Third Party: FI3rdShareUS$, FI3rdShareEURO,...	
			- 20090418@PhuongDao: Show Casino and P2P Report 
			- 20090608@PhuongDao: PT Winloss Tote HR 
				+ FeeDue2 = AmtoteFee + PGIFee  (0.0033 + 0.005) 
			- 20090731@Jamie: Not to view data in range of date, but only one day. 	
			- 20090815@Jamie: Include Fixed Odds Report
			- 20100331@Jamie: arrange the new structure for HR meetings 
				+ Remove hard-code FeeDue2 
				+ Remove Fixed Odds out as well 
			-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20100611@Henry: Change mix-parlay match from 0 to 9
			- 20100924@Henry: Include Bingo + Number Game
			- 20110411@Johnson: - Change bettype 'Tote HR' to 'Racing'
								- Check Tote Fee is passed to Partners or not
								- Remove Finance 
			- 20110520@Amy: Re-arrange bettype
			- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
			- 20110728@Johnson:- add new bettype mix-parlay combination
							   - add more bettype for number game Warrior, Next Combo, Number Group			
			- 20110929@Tom: 1. Add Report for P2P Games  Bettype: 1000	
							2. Hide code Report Casino and Bingo
			- 20111122@Tom: Unhide code Report Casino and Bingo
			- 20111202@Sophia: Add new range of sportbook from 121 to 999
			- 20120231@Sophia: Add live casino bettype from 1101 to 1199
			- 20120405@Hurri: Exclude bettype 72 (P2P bet ticket) in the calculation of Casino
			- 20120412@Hurri: Get win lost of agent 'BARM'
			- 20120419@Johnson: Exclude refund tickets for game
			- 20120503@Sophia: Edit LineTotal for P2P
			- 20120530@Elodie: Edit VirtualLineTotal for Mix Parlay and Outright ( bettype = 9, 29, 10)
							   Change formula of 8RM/BARM winloss
			- 20120626@Elodie: exclude outright from sportbook ( in case of matchid = orid)
			- 20120813@Elodie: Add Virtual sports report
			- 20121004@Elodie: Performance tuning
			- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
			- 20130225@Elodie: Add Virtual Horse Racing report
			- 20130618@Johnson: Add NSW racing's pools from AUST
			- 20130705@Kathy: Update matchid for RnG Casino (71) and Bingo (73)
			- 20140303@Dom: Add keno
			- 20141203@Dom: Apply sport bettype matrix
			- 20150520@Sophia: Apply Gold Deluxe and Metric Gaming - SuperLive and revise Sport Betype Matrix [#35359] 
			- 20150701@Sophia: Apply Microgaming and Super Balance [#38168]
			- 20150723@Sophia: Apply Bettrade [#38815]
			- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	*/
	SET NOCOUNT ON

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5

	-- Horse racing
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
	SELECT	o.orid as MatchID, t.IBCFee, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM outright o WITH (NOLOCK)
		INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID AND p.programDate = o.programDate 
		INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid
		INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.eventdate = @winlostdate
	
	----------------------------------------------------------------------------------			
	CREATE TABLE #tmpBettrans ( bettype int, matchid int, liveindicator bit,  
								LineTotal_live money, VirtualLineTotal_live money, LineTotal money, VirtualLineTotal money)	
	create index IX_bettype on #tmpBettrans(bettype)
	
	INSERT INTO #tmpBettrans (  bettype, matchid, liveindicator, LineTotal_live, VirtualLineTotal_live, LineTotal, VirtualLineTotal)
	select	bettype, matchid, liveindicator,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal_live,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate), 0) as VirtualLineTotal_live,		
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate), 0) as VirtualLineTotal
	from 	bettrans with (nolock)
	where	winlostdate = @winlostdate and ruben = 1 and statusID not in (101,102,103,121)			
	group by bettype, matchid, liveindicator

	-- Sportbook
	select	10 Num,
			b.bettype,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when liveindicator = 1 and sporttype = 1 then LineTotal_live else 0 end) as LineTotal_soccer_live,
			sum(case when liveindicator = 1 and sporttype = 1 then VirtualLineTotal_live else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when liveindicator = 1 and sporttype <> 1 then LineTotal_live else 0 end) as LineTotal_others_live,
			sum(case when liveindicator = 1 and sporttype <> 1 then VirtualLineTotal_live else 0 end) as VirtualLineTotal_others_live,
			sum(case when liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others			
	from 	#tmpBettrans b
			inner join match m with(nolocK) on b.matchid = m.matchid
			inner join @SportBettype s on s.bettype = b.bettype
	where   s.ProductId = 1 
		AND s.eventtype = 1
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
		/*((bettype < 31 and bettype <> 10) 
				OR bettype between 121 and 999 				
				OR bettype BETWEEN 1301 and 1334)	*/
	group by 
			b.bettype, 
			case when matchcode like '%hedge%' then ' (hedge)' else '' end
	

	-- Metric Gaming- Super Live
	UNION ALL
	select	11 Num,
			b.bettype,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when liveindicator = 1 and sporttype = 1 then LineTotal_live else 0 end) as LineTotal_soccer_live,
			sum(case when liveindicator = 1 and sporttype = 1 then VirtualLineTotal_live else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when liveindicator = 1 and sporttype <> 1 then LineTotal_live else 0 end) as LineTotal_others_live,
			sum(case when liveindicator = 1 and sporttype <> 1 then VirtualLineTotal_live else 0 end) as VirtualLineTotal_others_live,
			sum(case when liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others			
	from 	#tmpBettrans b
			inner join match m with(nolocK) on b.matchid = m.matchid
			inner join @SportBettype s on s.bettype = b.bettype
	where   s.ProductId = 1 
		AND s.eventtype = 1
		AND s.SubProduct = 'MG-SuperLive'
		/*((bettype < 31 and bettype <> 10) 
				OR bettype between 121 and 999 				
				OR bettype BETWEEN 1301 and 1334)	*/
	group by 
			b.bettype, 
			case when matchcode like '%hedge%' then ' (hedge)' else '' end

		---Bettrade
	UNION ALL 
	SELECT	12 Num,
			b.bettype,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when liveindicator = 1 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer_live,
			sum(case when liveindicator = 1 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when liveindicator = 1 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when liveindicator = 1 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,
			sum(case when liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			
			0 as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
			inner join match m with (nolock) on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
	WHERE  	s.ProductId = 1
		AND s.EventType = 1
		AND s.SubProduct IN ('BT-Comm', 'BT-Winloss')
	GROUP BY 
			b.bettype, 
			case when matchcode like '%hedge%' then ' (hedge)' else '' end


	-- Virtual sports
	UNION ALL 
	select	20 Num,
			b.bettype,
			'' Hedge,
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0  VirtualLineTotal_others 		
	from 	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	where   s.ProductId = 5
		--b.bettype BETWEEN 1201 and 1299
	group by b.bettype			
			
	-- Casino
	UNION ALL 
	SELECT	30 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0  VirtualLineTotal_others    
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 6
		--bettype = 71 
		and matchid in (0, 71)  			
	group by b.bettype
	
	-- Vegas Games
	UNION ALL
	SELECT	31 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 14	
	GROUP BY b.bettype	


	-- BINGO 
	UNION ALL
	SELECT	40 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0  VirtualLineTotal_others    
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 7
		--bettype = 73 
		and matchid in (0, 73)	
	group by b.bettype	
	
	--KENO
	UNION ALL
	SELECT	50 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 VirtualLineTotal_others	
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 8
		--bettype BETWEEN 1501 AND 1599			
	GROUP BY b.bettype		
	
	--NUMBER GAME
	UNION ALL
	SELECT	60 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			sum(case when liveindicator = 1 then LineTotal_live else 0 end) as LineTotal_others_live,
			sum(case when liveindicator = 1 then VirtualLineTotal_live else 0 end) as VirtualLineTotal_others_live,		
			sum(case when liveindicator = 0 then LineTotal else 0 end) as LineTotal_others,
			sum(case when liveindicator = 0 then VirtualLineTotal else 0 end) as VirtualLineTotal_others	
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 3
		--bettype BETWEEN 81 AND 120			
	GROUP BY b.bettype
	
	-- Live Casino
	UNION ALL
	SELECT	70 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 4
		--bettype BETWEEN 1101 AND 1199			
	GROUP BY b.bettype		
	
	-- Gold Deluxe
	UNION ALL
	SELECT	71 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 12 	
	GROUP BY b.bettype		
	
	-- Microgaming
	UNION ALL
	SELECT	72 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 13 	
	GROUP BY b.bettype			

	-- AG Casino
	UNION ALL
	SELECT	73 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others
	FROM	#tmpBettrans b
	inner join @SportBettype s on s.bettype = b.bettype
	WHERE	s.ProductId = 11 	
	GROUP BY b.bettype							
	
	-- Mix parlay, System parlay
	UNION ALL 
	select 	80 Num,
			m1.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			LineTotal_soccer,
			VirtualLineTotal_soccer,
			
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			LineTotal - LineTotal_soccer as LineTotal_others,
			VirtualLineTotal - VirtualLineTotal_soccer as VirtualLineTotal_others
	from
		(
			select 	bettype,	
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal_soccer,
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate), 0) as VirtualLineTotal_soccer
			from	bettrans with (nolock,index=CIX_matchid_bettype)
			where 
					ruben=1 and
					bettype IN (9, 29) and
					winlostdate = @winlostdate and
					matchid in (9, 29)
					and refno IN(select refno from bettransm with (nolock) inner join match with (nolock) on bettransm.matchid = match.matchid where sporttype=1)
			GROUP by bettype
		) m1
		inner join
		(
			select 	bettype,	
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal,
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate), 0) as VirtualLineTotal
			from	bettrans with (nolock,index=CIX_matchid_bettype)
			where 
					ruben=1 and
					bettype IN (9, 29) and
					winlostdate = @winlostdate and
					matchid in (9, 29)
			GROUP by bettype
		) m2 on m1.bettype = m2.bettype		
		
	-- outright
	UNION ALL 
	select	90 Num,
			10 bettype,	
			'' Hedge,
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,	
			sum(case when sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,		
			sum(case when sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others
	from #tmpBettrans b
		inner join outright o with (nolock) on b.matchid = o.orid
		inner join league l with (nolock) on o.leagueid = l.leagueid	
	where b.bettype=10 
	
	-- HORSE RACING
	UNION ALL
	SELECT	100 Num,
			b.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			-(sum((case when b.bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate)
			+ sum((case b.bettype	when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 33 then bm.TOPhum*cs.ToteCommWP 
								else 0  end)*b.actualrate) --IBCIncome
			- sum(b.scomm*b.actualrate)
			- sum((case when cs.IBCFee = 0 then 0 else 
								case when b.bettype = 33 then bm.TOPhum 
										when b.bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(b.oddsspread,0))
								 else 0 end
					 end)*b.actualrate*cs.ToteFee)) Lintotal_others,
			0  VirtualLineTotal_others
	FROM	bettrans b with (nolock)			
			inner join @CommSetting cs on b.matchID = cs.matchid  
			 left join (
				select	refno,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore<>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			 inner join @SportBettype s on s.bettype = b.bettype
	WHERE	
			s.ProductId = 2
			--b.bettype in (31,32,33)
			and b.matchid > 0
			and b.winlostdate = @winlostdate
			and b.ruben =1 
			and b.statusID not in (101,102,103,121)
	GROUP BY b.bettype
	
	--P2P Game - 1000
	UNION ALL
	SELECT	110 Num,
			bettrans.bettype,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			isnull(sum(-1*(odds-scomm)*bettrans.actualrate),0)  LineTotal_others,
			0  VirtualLineTotal_others    
	FROM	bettrans with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = bettrans.bettype
	WHERE	s.ProductId = 9
			--bettype = 1000
			--and matchid = 1000  
			and winlostdate = @winlostdate
			and ruben=1
			and statusID not in (101,102,103,121 )
	GROUP BY bettrans.bettype			
	
	-- 8RM & BARM
	UNION ALL 		
	select	120 Num,
			case WHEN recommend = 52466 then 400 
				 when recommend = 5707545 then 401 end bettype,	
			'' Hedge,	
			LineTotal_soccer_live,
			LineTotal_soccer_live as VirtualLineTotal_soccer_live,
			LineTotal_soccer,
			LineTotal_soccer as VirtualLineTotal_soccer,
			LineTotal_others_live,
			LineTotal_others_live as VirtualLineTotal_others_live,		
			LineTotal_others,
			LineTotal_others as VirtualLineTotal_others
	FROM (
			SELECT recommend,
				-isnull(sum(case when liveindicator = 1 and sporttype = 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_soccer_live,
				-isnull(sum(case when liveindicator = 0 and sporttype = 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_soccer,
				-isnull(sum(case when liveindicator = 1 and sporttype <> 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_others_live,
				-isnull(sum(case when liveindicator = 0 and sporttype <> 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_others
			from 
				bettrans bettrans with (nolock)
				inner join match match with (nolock) on match.matchid=bettrans.matchid
			where 
				(recommend = 52466 or recommend = 5707545) and
				winlostdate = @winlostdate and
				bettrans.matchid >=0 and 
				bettype <= 19000 and
				bettrans.ruben=1
			GROUP by recommend				
	)rm	
	
	order by 1, bettype, Hedge	
	DROP table #tmpBettrans

	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlossByBettype] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlossByBettype] TO [vnteam] AS [dbo] 
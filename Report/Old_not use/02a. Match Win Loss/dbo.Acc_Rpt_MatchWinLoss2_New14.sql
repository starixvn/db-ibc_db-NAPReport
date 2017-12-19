USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_MatchWinLoss2_New14]
	@winlostdate		 datetime,
	@WinLost_8RM		 money = 0 OUTPUT,
	@WinLost_BARM		 money = 0 OUTPUT,
	@IBCTurnover_8RM	 money = 0 OUTPUT,
	@IBCTurnover_BARM	 money = 0 OUTPUT
AS
	/*	Creator: Elodie	
		Date: 20120827
		Task: Report 2A
		DB: DBACC/BODB02		
		Original: Acc_Rpt_MatchWinLoss2
	
		History: 
			- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
			- 20130306@Don: 
			    + Solving discrepancy by returning all resultsets in one call
			    + Add column [IBC Turnover] into resultset
				+ Treat [Turnover of 8RM/BARM] as negative value
			- 20130618@Johnson: Add NSW racing's pools from AUST
			- 20130703@Kathy: Update matchid for RnG Casino (71) and Bingo (73)
			- 20130717@Kathy: Apply Progressive Bonus: add bettype 72 for Casino
			- 20140304@Dom: Add Keno
			- 20141203@Dom: Apply sport bettype matrix
			- 20150520@Sophia: Apply Gold Deluxe and Metric Gaming - SuperLive and revise Sport Betype Matrix [#35359] 
			- 20150701@Sophia: Apply Microgaming and Super Balance [#38168]
			- 20150723@Sophia: Apply Bettrade [#38815]
			- 20150827@Sophia: Apply Colossus Bets [#41935]
			- 20150917@Jim: Integrate MO product (Feature #41935)
			- 20150929@Sophia: Order by for MO product [#41935]
			- 20151109@Sophia: Microgaming RNG Casino New sporttype [RedmineID: #46576]
			- 20151215@Sophia: Change bettype of 8RM & BARM to negative
			- 20160226@Jim: Offer AllBet ,Cockfighting,MBC-RNG Casino,Cricket product [RedmineID: #50921]
			- 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product - using sporttype bettype matrix function [RedmineID: #55584]
			- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sporttype, bettye matrix function, change the way to get data Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
			- 20160509@Robert: Rename product "Voidbridge" to "Macau Games" [RedmineID: #57182]
			- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
			- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
		Explanation's Param:
		    - @WinLost_8RM: winlost for outsource 
		    - @WinLost_BARM: winlost for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)
		    - @IBCTurnover_8RM: turnover for outsource 
		    - @IBCTurnover_BARM: turnover for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)

			

	*/
BEGIN	
	SET NOCOUNT ON		

	----Get Sport Bettype Matrix------
	DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500),OrderKey TINYINT,liveindicator BIT)
	INSERT INTO @SportBettype (ProductID  , Bettype  ,EventType  ,SubProduct)
	SELECT ProductID,
              Bettype,
              EventType,
              SubProduct
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);
	
	UPDATE @SportBettype
	SET liveindicator =0
	
	INSERT INTO @SportBettype(ProductID,Bettype,EventType,SubProduct,liveindicator)
	SELECT ProductID
		 ,Bettype
		 ,EventType
		 ,SubProduct
		 ,1 AS liveindicator
	FROM @SportBettype
	WHERE liveindicator =0	
	
	UPDATE @SportBettype
	SET OrderKey =  CASE  WHEN Bettype =1   AND liveindicator =0   THEN 1
						WHEN Bettype =301 AND liveindicator =0   THEN 2
						WHEN Bettype =1   AND liveindicator =1   THEN 3
						WHEN Bettype =301 AND liveindicator =1   THEN 4
						WHEN Bettype =3   AND liveindicator =0   THEN 5
						WHEN Bettype =302 AND liveindicator =0   THEN 6
						WHEN Bettype =3   AND liveindicator =1   THEN 7
						WHEN Bettype =302 AND liveindicator =1   THEN 8
						WHEN Bettype =7   AND liveindicator =0   THEN 9
						WHEN Bettype =303 AND liveindicator =0   THEN 10
						WHEN Bettype =7   AND liveindicator =1   THEN 11
						WHEN Bettype =303 AND liveindicator =1   THEN 12
						WHEN Bettype =8   AND liveindicator =0   THEN 13
						WHEN Bettype =304 AND liveindicator =0   THEN 14
						WHEN Bettype =8   AND liveindicator =1   THEN 15
						WHEN Bettype =304 AND liveindicator =1   THEN 16
						ELSE 17
						END
		
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
	FROM outright14 o WITH (NOLOCK)
		INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID and p.programDate = o.programDate
		INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid
		INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.eventdate = @winlostdate 
	
	-- Fill data of Racing, 8RM&BARM and all sports into temporary tables 
	    -- Racing
	SELECT	b.bettype,
	        sum((b.winlost -b.actual_stake)*b.actualrate) Winlost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) Pos,
			sum(b.scomm*b.actualrate) Comm,
			0 VirtualComm,
	        -(
		        sum((case when b.bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) -- PTWLIBC, 
		        - sum(case when cs.IBCFee = 0 then 0 else
				        (case when b.bettype = 33 then bm.TOPhum 
					        when b.bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0)) else 0 end)*b.actualrate*cs.ToteFee end) -- FeeDue2 ,
		        + sum((case b.bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
							        when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
							        when 33 then bm.TOPhum*cs.ToteCommWP 
							        else 0 end)*b.actualrate)-- commIncomeIBC
		        - sum(b.scomm*b.actualrate)
	        ) LineTotal,
			0 VirtualLineTotal,
			sum(case when b.bettype = 33 then bm.TOIBC*b.actualrate else abs(b.stake)*isnull(oddsspread,0)*b.actualrate end) IBCTurnover
    INTO #Racing
	FROM	bettrans14 b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid  
			 left join (
				select	refno,
				        sum(case when bettype = 32 and liveawayscore = 0 then 0 else abs(stake)*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore<>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm14 with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			 INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	b.ruben = 1 
			--and b.bettype in (31,32,33)
			and s.ProductID = 2
			and b.matchid > 0
			and b.winlostdate = @winlostdate			
			and b.statusID not in (101,102,103,121) --('VOID','REJECT','REFUND','DONE')
    GROUP BY b.bettype
    
        -- 8RM & BARM
    SELECT	case WHEN recommend = 52466 then -400 
				 when recommend = 5707545 then -401 end bettype,	
			'' Hedge,	
			LineTotal_soccer_live,
			LineTotal_soccer_live as VirtualLineTotal_soccer_live,
			LineTotal_soccer,
			LineTotal_soccer as VirtualLineTotal_soccer,
			LineTotal_others_live,
			LineTotal_others_live as VirtualLineTotal_others_live,		
			LineTotal_others,
			LineTotal_others as VirtualLineTotal_others,
			IBCTurnover
	INTO #R_8RM
	FROM (
			SELECT recommend,
				-isnull(sum(case when liveindicator = 1 and sporttype = 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_soccer_live,
				-isnull(sum(case when liveindicator = 0 and sporttype = 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_soccer,
				-isnull(sum(case when liveindicator = 1 and sporttype <> 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_others_live,
				-isnull(sum(case when liveindicator = 0 and sporttype <> 1 then (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) else 0 end), 0) as LineTotal_others,
				-isnull(sum((1-tpositiontaking)*abs(stake)),0) IBCTurnover
			FROM 
				bettrans14 with (nolock)
				inner join match14 with (nolock) on match14.matchid = bettrans14.matchid
			WHERE 
				recommend in (52466,5707545) and
				winlostdate = @winlostdate and
				bettrans14.matchid > 0 and 
				bettype <= 19000 and
				bettrans14.ruben = 1 and
				statusID not in (101,102,103,121)
			GROUP BY recommend
	)rm
	
        -- All sports
	CREATE TABLE #tmpBettrans (matchid int, bettype int, betteam NVARCHAR(10) NULL, statusID int, liveindicator bit, winlost money, pos money, comm money, VirtualComm money, LineTotal money, VirtualLineTotal money, IBCTurnover money)
	CREATE INDEX IX_bettype on #tmpBettrans(bettype)
	
	INSERT INTO #tmpBettrans (matchid, bettype, betteam, statusID, liveindicator, winlost, pos, comm, VirtualComm, LineTotal, VirtualLineTotal, IBCTurnover)
	SELECT  matchid, b.bettype, b.betteam, statusID, b.liveindicator,
			sum((winlost-actual_stake)*actualrate)  winlost,
			sum((awinlost+mwinlost+swinlost)*actualrate) pos,
			sum((scomm)*actualrate) comm,
			sum((scomm)*virtualrate) VirtualComm,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as IBCTurnover
	FROM	bettrans14 b with (nolock)
	   INNER JOIN @SportBettype sb on b.bettype = sb.Bettype AND b.liveindicator = sb.liveindicator
	WHERE	winlostdate = @winlostdate
			AND ruben = 1  
			AND statusID not in (101,102,103,121) --('VOID','REJECT','REFUND','DONE')
			AND sb.ProductID not in (6, 17, 21, 22)--AND b.bettype <= 19000 AND b.bettype NOT BETWEEN 2101 AND 2399 -- MBC-RNG Casino, Microgaming-RNG Casino, Allbet and Macau Games
	GROUP BY matchid, b.bettype, b.betteam, statusID, b.liveindicator
	UNION ALL 
	SELECT	 0 as matchid, gameID, '', statusID, 0 as liveindicator,
			sum((winlost-actual_stake)*actualrate)  winlost,
			sum((awinlost+mwinlost+swinlost)*actualrate) pos,
			sum((scomm)*actualrate) comm,
			sum((scomm)*virtualrate) VirtualComm,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as IBCTurnover
	FROM	bettransRnG14 b with (nolock)
	   INNER JOIN @SportBettype sb on b.gameID = sb.Bettype
	WHERE	winlostdate = @winlostdate
			AND statusID  IN (111,112,113) 
			AND sb.ProductID IN(6, 17, 22) --gameID   BETWEEN 2101 AND 2399
			AND sb.liveindicator = 0
	GROUP BY   gameID, statusID	
	-- END - Fill data of Racing, 8RM&BARM and all sports into temporary tables 
	
	-- Resultset of Sportbook without Parlay and Outright
	SELECT 
	UPPER(case when l.leaguenametc = '' or l.leaguenametc is null  then 'Other Sports' else l.leaguenametc end) as leaguenametc,
		s.bettype,
		s.OrderKey,
		b.liveindicator,		
		m.matchcode,
		m.kickofftime,
		b.matchid,
		m.homeid,
		m.awayid,
	    isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
        SUM( b.winlost) winlost,
        b.pos,
        SUM(b.comm) comm,   
        SUM(b.VirtualComm) VirtualComm,
        SUM(b.LineTotal) LineTotal,
        SUM(b.VirtualLineTotal) VirtualLineTotal,
        SUM(b.IBCTurnover) IBCTurnover
		INTO #tmpReturn1
	FROM 
	    (
	        SELECT 
	            matchid, bettype, liveindicator,
	            sum(winlost) winlost,
                sum(pos) pos,
                sum(comm) comm,
                sum(VirtualComm) VirtualComm,
                sum(LineTotal) LineTotal,
                sum(VirtualLineTotal) VirtualLineTotal,
                sum(IBCTurnover) IBCTurnover
	        FROM #tmpBettrans with (nolock)
	        GROUP BY matchid, bettype, liveindicator
	    ) b
		inner join match14 m with (nolock) on m.matchid = b.matchid
		inner join league l with (nolock) on l.leagueid = m.leagueid
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE s.ProductID = 1
		AND s.EventType = 1
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
    GROUP BY	l.leaguenametc,
				s.bettype,
				s.OrderKey,
				b.liveindicator,		
				m.matchcode,
				m.kickofftime,
				b.matchid,
				m.homeid,
				m.awayid,
				isnull(m.isNeutral, CONVERT(BIT,0)),  
				b.pos 	
	--((bettype < 31 AND bettype <> 10) OR bettype between 121 and 999 OR bettype between 1301 and 1334) 
	ORDER BY l.leaguenametc, s.OrderKey asc,s.bettype, b.liveindicator desc 
	
	SELECT  leaguenametc,
			bettype,
			liveindicator,		
			matchcode,
			kickofftime,
			matchid,
			homeid,
			awayid,
			IsNeutral,
			winlost,
			pos,
			comm,   
			VirtualComm,
			LineTotal,
			VirtualLineTotal,
			IBCTurnover
	FROM #tmpReturn1
	ORDER BY Orderkey ASC
	
	-- Resultset of 3rd products and Parlay, Outright
	    -- Mix Parlay
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.comm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Parlay-' + case when b.statusID = 111 THEN 'DRAW'
							 WHEN b.statusID = 113 THEN 'LOSE'
							 WHEN b.statusID = 112 THEN 'WON' END as bettype
	FROM	#tmpBettrans b with (nolock)
	WHERE	bettype = 9 OR bettype = 29 	
	GROUP BY statusID		
	
	    -- Outright 
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.comm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,			
			sum(b.IBCTurnover) IBCTurnover,
			'Out Right' as bettype
	FROM	#tmpBettrans b with (nolock)
	WHERE	bettype = 10 			
	
	    -- Racing
	UNION ALL
    SELECT	@winlostdate winlostdate,
            isnull(sum(Winlost),0) Winlost,
			isnull(sum(Pos),0) Pos,
			isnull(sum(Comm),0) Comm,
			isnull(sum(VirtualComm),0) VirtualComm,
		    isnull(sum(LineTotal),0) LineTotal,
			isnull(sum(VirtualLineTotal),0) VirtualLineTotal,
			isnull(sum(IBCTurnover),0) IBCTurnover,
			'Racing' bettype
    FROM #Racing with (nolock)
	
	    -- Casino - 71
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			SUM( IBCTurnover) IBCTurnover,
			'MBC - RNG Casino' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 6
		--bettype IN(71, 72)	
		
	   -- Vegas Games
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(isnull(b.IBCTurnover,0)) IBCTurnover,
			'Macau' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 14
		 	

	    -- Bingo - 73
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			0 as IBCTurnover,
			'Bingo' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype  AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 7
		--bettype = 73		
	
	-- Keno
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(isnull(b.winlost,0)) as winlost,
			sum(isnull(b.pos,0)) as pos,
			sum(isnull(b.comm,0)) as comm,
			0 virtualComm,
			sum(isnull(b.Linetotal,0)) as LineTotal,
			0 VirtualLineTotal,
			sum(isnull(b.IBCTurnover,0)) IBCTurnover,
			'Keno' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 8
		--b.bettype BETWEEN 1501 AND 1599 		

	    -- P2P Game - 1000
	UNION ALL
	SELECT  @winlostdate winlostdate,
	        isnull(sum((winlost-actual_stake)*bettrans14.actualrate),0)  winlost, 
			0 pos,
			isnull(sum(scomm*bettrans14.actualrate),0) comm,
			0 VirtualComm,
			isnull(sum(-1*(odds-scomm)*bettrans14.actualrate),0) as LineTotal,
			0 VirtualLineTotal, --virtualrate = actualrate    
			0 IBCTurnover,
			'P2P' bettype 
	FROM bettrans14 with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = bettrans14.bettype AND bettrans14.liveindicator=s.liveindicator
	WHERE 
			--bettrans14.bettype = 1000
			--and bettrans14.matchid = 1000 
			s.ProductID = 9
			and bettrans14.ruben = 1 
			and bettrans14.winlostdate = @winlostdate			
			and statusID NOT in (101,102,103,121)
	
	 -- Number Game
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.comm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Number Game' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 3	
		--bettype BETWEEN 81 AND 120 			
	
	    -- Virtual Sports
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Virtual Sports' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 5
		--bettype BETWEEN 1201 AND 1299			

	    -- Live Casino
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Live Casino' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 4	
		--bettype BETWEEN 1101 AND 1199	

		---Gold Deluxe
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Gold Deluxe' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 12

	---Microgaming Live Casino
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Microgaming - Live Casino' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 13

	---Microgaming RNG Casino
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'Microgaming - RNG Casino' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 17

	---AG Casino
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			0 as virtualComm,
			sum(b.Linetotal) as LineTotal,
			0 as VirtualLineTotal,		
			sum(b.IBCTurnover) IBCTurnover,
			'AG Casino' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 11

			
	  -- Metric Gaming - Super Live
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.VirtualComm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,
			sum(b.IBCTurnover) IBCTurnover,
			'Metric Gaming - Superlive' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE s.ProductID = 1
		AND s.EventType = 1	
		AND s.SubProduct = 'MG-SuperLive'

	-- Bettrade
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			0 AS comm,
			0 AS virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,
			0 AS IBCTurnover,
			'Bettrade' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE s.ProductID = 1
		AND s.EventType = 1			
		AND s.SubProduct IN ('BT-Comm', 'BT-Winloss')

	-- Colossus Bets
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.comm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.Linetotal) as VirtualLineTotal,
			sum(b.IBCTurnover) IBCTurnover,
			'Colossus Bets' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 15
	-- Cock_Fighting Section 
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.comm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.Linetotal) as VirtualLineTotal,
			sum(b.IBCTurnover) IBCTurnover,
			'Cockfighting' as bettype  
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductID = 19		
	--- Allbet Section
	UNION ALL
	SELECT	@winlostdate winlostdate,
	        sum((winlost-actual_stake)*actualrate) as winlost,
			sum((awinlost+mwinlost+swinlost)*actualrate) as pos,
			sum((scomm)*actualrate) as comm,
			sum((scomm)*virtualrate) as virtualComm,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal,
			sum((1-tpositiontaking)*abs(stake)*actualrate) IBCTurnover,
			'Allbet' as bettype
	FROM	 bettransLC14 b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.GameID  
	 WHERE	s.ProductID = 21			
			AND b.winlostdate = @winlostdate
			AND b.statusID IN (111,112,113)
			AND s.liveindicator = 0

    -- Macau Games Section
     UNION ALL
	SELECT	
			@winlostdate winlostdate,
	          sum(b.winlost) as winlost,
			sum(b.pos) as pos,
			sum(b.comm) as comm,
			sum(b.VirtualComm) as virtualComm,
			sum(b.Linetotal) as LineTotal,
			sum(b.VirtualLineTotal) as VirtualLineTotal,
			sum(b.IBCTurnover) IBCTurnover,
			'Macau Games' as bettype
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND s.liveindicator = b.liveindicator
	WHERE	s.ProductID = 22
				
    -- Resultset of 8RM and BARM
    SELECT  @WinLost_8RM = isnull(sum(case when bettype = -400 then (LineTotal_soccer_live + LineTotal_soccer + LineTotal_others_live + LineTotal_others) else 0 end),0),
            @WinLost_BARM = isnull(sum(case when bettype = -401 then (LineTotal_soccer_live + LineTotal_soccer + LineTotal_others_live + LineTotal_others) else 0 end),0),
            @IBCTurnover_8RM = isnull(sum(case when bettype = -400 then IBCTurnover else 0 end),0),
            @IBCTurnover_BARM = isnull(sum(case when bettype = -401 then IBCTurnover else 0 end),0)
	FROM	#R_8RM with (nolock)
	-- END - Resultset of 3rd products and Parlay, Outright
	
	-- Resultset by bettype of 
	    -- Sportbook without Parlay and Outright
	CREATE TABLE #tmpReturn2 (Num TinyINT
							,bettype smallint
							,OrderKey TINYINT
							,Hedge NVARCHAR(50)
							,LineTotal_soccer_live MONEY
							,VirtualLineTotal_soccer_live MONEY
							,LineTotal_soccer MONEY
							,VirtualLineTotal_soccer MONEY
							,LineTotal_others_live MONEY
							,VirtualLineTotal_others_live MONEY
							,LineTotal_others MONEY
							,VirtualLineTotal_others MONEY
							,IBCTurnover MONEY
							)	
	INSERT INTO #tmpReturn2 (Num  
							,bettype 
							,OrderKey  
							,Hedge  
							,LineTotal_soccer_live  
							,VirtualLineTotal_soccer_live 
							,LineTotal_soccer  
							,VirtualLineTotal_soccer  
							,LineTotal_others_live  
							,VirtualLineTotal_others_live  
							,LineTotal_others  
							,VirtualLineTotal_others
							,IBCTurnover)		
							
	SELECT	10 Num,
			b.bettype,
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when b.liveindicator = 1 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer_live,
			sum(case when b.liveindicator = 1 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when b.liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when b.liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when b.liveindicator = 1 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when b.liveindicator = 1 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			
			sum(IBCTurnover) as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
			inner join match14 m with (nolock) on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE  	s.ProductId = 1
		AND s.EventType = 1
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
			/*((bettype < 31 and bettype <> 10) 
				OR bettype between 121 and 999 
				OR (bettype BETWEEN 1201 and 1299 and b.bettype not in (1231, 1232, 1233, 1237, 1238))
				OR bettype BETWEEN 1301 and 1334)	*/
	GROUP BY 
			b.bettype, 
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end
	
		---Metric Gaming - Super Live
	UNION ALL 
	SELECT	11 Num,
			b.bettype,
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			0 as LineTotal_soccer_live,
			0 as VirtualLineTotal_soccer_live,
			0 as LineTotal_soccer,
			0 as VirtualLineTotal_soccer,
			
			sum(case when b.liveindicator = 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when b.liveindicator = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,
			sum(case when b.liveindicator = 0 then LineTotal else 0 end) as LineTotal_others,
			sum(case when b.liveindicator = 0 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			
			sum(IBCTurnover) as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
			inner join match14 m with (nolock) on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE  	s.ProductId = 1
		AND s.EventType = 1
		AND s.SubProduct = 'MG-SuperLive'				
	GROUP BY 
			b.bettype, 
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end


		---Bettrade
	UNION ALL 
	SELECT	12 Num,
			903,
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when b.liveindicator = 1 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_soccer_live,
			sum(case when b.liveindicator = 1 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when b.liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when b.liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,
			sum(case when b.liveindicator = 1 and sporttype = 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when b.liveindicator = 1 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			
			0 as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
			inner join match14 m with (nolock) on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE  	s.ProductId = 1
		AND s.EventType = 1
		AND s.SubProduct IN ('BT-Comm', 'BT-Winloss')
	GROUP BY 
			b.bettype, 
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end
	
	
	---- Virtual Sports
	UNION ALL
	SELECT	20 Num,
			b.bettype,
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end Hedge,
			sum(case when b.liveindicator = 1 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer_live,
			sum(case when b.liveindicator = 1 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer_live,
			sum(case when b.liveindicator = 0 and sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when b.liveindicator = 0 and sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			
			sum(case when b.liveindicator = 1 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when b.liveindicator = 1 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when b.liveindicator = 0 and sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			
			sum(IBCTurnover) as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
			inner join match14 m with (nolock) on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE   s.ProductId = 5
		AND s.EventType = 1
				/*((bettype < 31 and bettype <> 10) 
				OR bettype between 121 and 999 
				OR (bettype BETWEEN 1201 and 1299 and b.bettype not in (1231, 1232, 1233, 1237, 1238))
				OR bettype BETWEEN 1301 and 1334)	*/
	GROUP BY 
			b.bettype, 
			s.orderkey,
			case when matchcode like '%hedge%' then ' (hedge)' else '' end
	
	    -- Virtual HR
	UNION ALL 
	SELECT	21 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0  VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 5
		AND s.EventType = 3
		--b.bettype in (1231, 1232, 1233, 1237, 1238)	
	GROUP BY b.bettype,s.orderkey			
			
	    -- Casino
	UNION ALL 
	SELECT	30 Num,
			71 bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0 VirtualLineTotal_others,
			SUM(IBCTurnover) IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 6	
		--bettype IN(71, 72) 
		and matchid IN (0, 71) 			
	GROUP BY  s.orderkey

	    -- Vegas Games
	UNION ALL 
	SELECT	31 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0 VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 14	
	GROUP BY b.bettype,s.orderkey

	
	    -- Bingo 
	UNION ALL
	SELECT	40 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			sum(LineTotal) as  LineTotal_others,
			0 VirtualLineTotal_others,
			0 IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 7	
		--bettype = 73	
			and matchid IN (0, 73)
	GROUP BY b.bettype,s.orderkey			
	
	    -- Keno
	UNION ALL
	SELECT	50 Num,
			1501,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 8	
		--b.bettype BETWEEN 1501 AND 1599			
	 GROUP BY s.bettype,s.orderkey

	    -- Number Game
	UNION ALL
	SELECT	60 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			sum(case when b.liveindicator = 1 then LineTotal else 0 end) as LineTotal_others_live,
			sum(case when b.liveindicator = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others_live,		
			sum(case when b.liveindicator = 0 then LineTotal else 0 end) as LineTotal_others,
			sum(case when b.liveindicator = 0 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 3	
		--bettype BETWEEN 81 AND 120			
	GROUP BY b.bettype,s.orderkey
			,s.orderkey
	
	    -- Live Casino
	UNION ALL
	SELECT	70 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 4
		--bettype BETWEEN 1101 AND 1199			
	GROUP BY b.bettype,s.orderkey					
	
	    -- Gold Deluxe
	UNION ALL
	SELECT	71 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 12		
	GROUP BY b.bettype,s.orderkey

	 -- Microgaming Live Casino
	UNION ALL
	SELECT	72 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 13		
	GROUP BY b.bettype,s.orderkey

	 -- Microgaming RNG Casino
	UNION ALL
	SELECT	73 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 17		
	GROUP BY b.bettype,s.orderkey


	 -- AG Casino
	UNION ALL
	SELECT	74 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			0 as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 11
	GROUP BY b.bettype,s.orderkey


	    -- Parlay
	UNION ALL 
	SELECT 	80 Num,
			m1.bettype,
			m1.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			LineTotal_soccer,
			VirtualLineTotal_soccer,
			
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			LineTotal - LineTotal_soccer as LineTotal_others,
			VirtualLineTotal - VirtualLineTotal_soccer as VirtualLineTotal_others,
			
			IBCTurnover
	FROM
		(
			SELECT 	CASE WHEN bettype = 9 OR (bettype = 29 AND betteam = '1') THEN 9 ELSE 29 END bettype,
					17 as orderkey,	
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal_soccer,
					isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate), 0) as VirtualLineTotal_soccer
			FROM	bettrans14 with (nolock)
			WHERE 
					ruben = 1 and
					bettype IN (9, 29) and
					winlostdate = @winlostdate and
					matchid IN (9, 29) and
					statusid NOT IN (101,102,103,121)
					and refno IN (SELECT refno FROM bettransm14 with (nolock) inner join match14 with (nolock) on bettransm14.matchid = match14.matchid WHERE sporttype=1)
			GROUP BY CASE WHEN bettype = 9 OR (bettype = 29 AND betteam = '1') THEN 9 ELSE 29 END
		) m1
		inner join
		(
			SELECT 	CASE WHEN bettype = 9 OR (bettype = 29 AND betteam = '1') THEN 9 ELSE 29 END bettype,
					isnull(sum(LineTotal), 0) as LineTotal,
					isnull(sum(VirtualLineTotal), 0) as VirtualLineTotal,
					isnull(sum(IBCTurnover), 0) as IBCTurnover
			FROM	#tmpBettrans with (nolock)
			WHERE 
					bettype IN (9, 29) and
					matchid IN (9, 29)
			GROUP BY CASE WHEN bettype = 9 OR (bettype = 29 AND betteam = '1') THEN 9 ELSE 29 END
		) m2 on m1.bettype = m2.bettype		
		
	    -- Outright
	UNION ALL 
	SELECT	90 Num,
			10 bettype,	
			17 orderkey,
			'' Hedge,
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,	
			sum(case when sporttype = 1 then LineTotal else 0 end) as LineTotal_soccer,
			sum(case when sporttype = 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,		
			sum(case when sporttype <> 1 then LineTotal else 0 end) as LineTotal_others,
			sum(case when sporttype <> 1 then VirtualLineTotal else 0 end) as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM #tmpBettrans b with (nolock) 
		inner join outright14 o with (nolock) on b.matchid = o.orid
		inner join league l with (nolock) on o.leagueid = l.leagueid	
	WHERE b.bettype = 10 
	
	    -- Racing
	UNION ALL
	SELECT	100 Num,
			bettype,
			17 orderkey,
	        '' Hedge,
	        0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
		    isnull(LineTotal,0) LineTotal,
			0 VirtualLineTotal_others,
			isnull(IBCTurnover,0) as IBCTurnover
	FROM	#Racing with (nolock)
	
	    -- P2P Game - 1000
	UNION ALL
	SELECT	110 Num,
			bettrans14.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 LineTotal_others_live,
			0 VirtualLineTotal_others_live,
			isnull(sum(-1*(odds-scomm)*bettrans14.actualrate),0)  LineTotal_others,
			0  VirtualLineTotal_others,
			0 IBCTurnover
	FROM	bettrans14 with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = bettrans14.bettype  AND bettrans14.liveindicator=s.liveindicator
	WHERE	s.ProductID = 9
			--bettype = 1000
			--and matchid = 1000  
			and winlostdate = @winlostdate
			and ruben = 1
			and statusID not in (101,102,103,121)
	GROUP BY bettrans14.bettype,s.orderkey			
	
		-- Colossus Bets
	UNION ALL
	SELECT	120 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			sum(LineTotal) as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 15		
	GROUP BY b.bettype,s.orderkey
	
	-- Allbet Section 
	UNION ALL
	SELECT 150 Num,
			b.gameID bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal_others,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal_others,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as IBCTurnover
	 
	FROM	bettransLC14 b with (nolock)
			INNER JOIN @SportBettype s ON s.Bettype = b.gameID  
	WHERE	winlostdate = @winlostdate
			AND statusID IN (111,112,113)
			AND s.ProductID = 21
			AND s.liveindicator = 0
	GROUP BY b.gameID,
			s.orderkey
	-- Cock_Fighting Section
	 UNION ALL
	 SELECT	140 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,	
			0 LineTotal_soccer_live,
			0 VirtualLineTotal_soccer_live,
			0 LineTotal_soccer,
			0 VirtualLineTotal_soccer,
			
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,		
			sum(LineTotal) as LineTotal_others,
			sum(VirtualLineTotal) as VirtualLineTotal_others,
			sum(IBCTurnover) as IBCTurnover
	FROM	#tmpBettrans b with (nolock)
	INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
	WHERE	s.ProductId = 19		
	GROUP BY b.bettype,s.orderkey

	-- Macau Games
	UNION ALL
	SELECT	77 Num,
			b.bettype,
			s.orderkey,
			'' Hedge,
			0 as LineTotal_soccer_live,
			0 as VirtualLineTotal_soccer_live,
			0 as LineTotal_soccer,
			0 as VirtualLineTotal_soccer,
			
			0 as LineTotal_others_live,
			0 as VirtualLineTotal_others_live,
			sum(LineTotal) as LineTotal_others,
			sum(VirtualLineTotal) as VirtualLineTotal_others,
			
			sum(IBCTurnover) as IBCTurnover
	FROM 	#tmpBettrans b with (nolock)			
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND s.liveindicator = b.liveindicator
	WHERE  	s.ProductId = 22		
	GROUP BY 
			b.bettype, 
			s.orderkey		
	
	    -- 8RM & BARM
	UNION ALL 		
	SELECT	130 Num,
			bettype,
			17 orderkey,			
			Hedge,	
			LineTotal_soccer_live,
			VirtualLineTotal_soccer_live,
			LineTotal_soccer,
			VirtualLineTotal_soccer,
			LineTotal_others_live,
			VirtualLineTotal_others_live,		
			LineTotal_others,
			VirtualLineTotal_others,
			IBCTurnover
	FROM #R_8RM with (nolock)
	
	ORDER BY 1, bettype, Hedge	
	
	UPDATE #tmpReturn2
	SET orderkey  = 3
	WHERE bettype = 1 AND Hedge =' (hedge)'
	
	UPDATE #tmpReturn2
	SET OrderKey =  CASE  WHEN Bettype =1       THEN 1
						  WHEN Bettype =301     THEN 2
						  WHEN Bettype =3     THEN 5
						  WHEN Bettype =302    THEN 6
						  WHEN Bettype =7    THEN 9
						  WHEN Bettype =303    THEN 10
						  WHEN Bettype =8     THEN 13
					      WHEN Bettype =304    THEN 14
					      ELSE 17
						END
						
	
	SELECT 	Num,
			bettype,
			Hedge,	
			SUM(LineTotal_soccer_live) LineTotal_soccer_live,
			SUM(VirtualLineTotal_soccer_live) VirtualLineTotal_soccer_live,
			SUM(LineTotal_soccer) LineTotal_soccer,
			SUM(VirtualLineTotal_soccer) VirtualLineTotal_soccer,
			SUM(LineTotal_others_live) LineTotal_others_live,
			SUM(VirtualLineTotal_others_live) VirtualLineTotal_others_live,		
			SUM(LineTotal_others) LineTotal_others,
			SUM(VirtualLineTotal_others) VirtualLineTotal_others,
			SUM(IBCTurnover) IBCTurnover
	FROM #tmpReturn2
	GROUP BY Num,
			 bettype,
			 Hedge,
			 OrderKey
	ORDER BY num,OrderKey ASC 
	
	---------------------------	
	DROP TABLE #tmpReturn1
	DROP TABLE #tmpReturn2
    DROP TABLE #tmpBettrans
	DROP TABLE #Racing
	DROP TABLE #R_8RM
END
GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchWinLoss2_New14] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchWinLoss2_New14] TO [bodbAdminNet]
GO 




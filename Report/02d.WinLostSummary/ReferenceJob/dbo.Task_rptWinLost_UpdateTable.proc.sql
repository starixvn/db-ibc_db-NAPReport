/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Task_rptWinLost_UpdateTable]
	@winlostdate smalldatetime  
AS
/*
Name : rpt_WinLost_UpdateTable
Creator : Joe
Created : 2007-01-29 01:30
Task : update summary for winlost report
DB: DBACC/bodb02
Revision:
	- 20110516@Lukas: re-arrange bettype
	- 20120420@Hurri: add tickets of member under agent BARM into IBC winlost
	- 20120626@Elodie: exclude outright, HR from sportbook ( in case of matchid = orid)
	- 20130620@Johnson: copy data to rptWinlost2
	- 20130822@Johnson: change to use rptWinlost instead rptWinlost2
	- 20130917@Johnson: correct real turnover of racing formula
	- 20131203@Daniel: exclude UUS tickets to avoid zero data inserted
	- 20151216@Percy: support new product - Cockfighting [Redmine: #49027]
	- 20160225@Jim: offer  Allbet Live Casino [Redmine:#50921)]
	- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sportype bettype matrix function and change the way to get data MBC-RNG Casino, Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
	- 20160830@Percy:
		1. Using exrisk column to indicate what is System Parlay or Mix parlay of Combo Parlay [RedmineID: #63022]
			- Mix Parlay:	     (bettrans.bettype 29 AND bettrans.betteam = '1')  ---> rptWinLost.bettype = 29 AND rptWinLost.exrisk = 1 
														 OR (bettrans.Bettype = 9) ---> rptWinLost.bettype =  9 AND rptWinLost.exrisk = 0 
			- System Parlay:	(bettrans.bettype 29 and bettrans.betteam <> '1')  ---> rptWinLost.bettype = 29 AND rptWinLost.exrisk = 0 
		2. Remove condition: bettrans.bettype = 29 and bettrans.betid > 0
	- 20160916@Robert: Integrate new product NG2 [RedmindID: #63460]
	- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
	- 20170615@Tom: NAP Reports - Integrate Betradar Virtual Sports[RedmindID: #78495] 
	- 20171020@Dominic: Integrate Bullfighting - #81664
	- 20171214@Kean: Integrate Exchange - #88221
	- 2018.02.27@Tom: Integrate Colossus Bets - Free Play Integration (#90774)
	- 20180319@Cherry: Integrate ONE RNG Jackpot (#91712)
	- 20180507@Tom: Include Exchange Bettype into group bettypes no need ABS() Turnover data (#94736)
	- 20180411@Cherry: Integrate Pragmatic (#92642)
	- 201806185@Tom: Update Logic Bettrans14 (bettype 29) (#97061)
	- 20180702@Tom: add condition generate data BalanceUpDay AND MoveBetsDay	
	- 20180807@Dominic: Integrate Poker Games - #97830
	- 20180920@Tom: modify SP to avoid allocation order scan (#101646)
	- 20190117@Robert: Video Poker - Integrate into NAP Reports (#107706)
	- 20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
	- 20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
    - 20191015@Robert: #121661 - NAP Report - Integrate NPH into reports
    - 20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
    - 20191225@Cherry: Integrate Spadegaming (#125788)
    - 20200313@Ned.Le: NAP Report - Incorporate Virtual Games (#130326)
    - 20200323@Ned.Le: NAP Report - Incorprorate SA Gaming (#129349) | Saba.club (#130776) | Indo 4D (#130845) | Sexy Gaming (#130853)
	- 20200331@Ned.Le: NAP Report - Incorporate new Table Games (#131095)
	- 20200409@Ned.Le: NAP Report - Incorporate BBIN Live Casino (#131357)
	- 20200422@Ned.Le: NAP Report - Incorporate IBCBet Live Casino (#132961)
	- 20200520@Cherry: Nap Report - Integrate ION Live Casino (#132324) & RNG War (#132009)
	- 20200624@Cherry: Archive VSRaceInfo (#136256)
	- 20200710@Jaden: Incorporate Jackpot Games (#137271)
*/

BEGIN	
	SET NOCOUNT ON;

	DECLARE @MoveBetsDay SMALLDATETIME
	DECLARE @BalanceUpDay SMALLDATETIME
	
	SELECT TOP 1 @BalanceUpDay  = winlostdate
	FROM Bettrans WITH (NOLOCK)
	WHERE bettype = 20000 AND matchid = 0 AND custid = 3 
	
	SELECT @MoveBetsDay = max(eventdate)
	FROM [bodb02].dbo.match14 WITH (NOLOCK)

	DECLARE @CommSetting TABLE
	(	MatchID			int,
		IBCFee			bit,
		ToteCommWin		smallmoney,
		ToteCommPlace	smallmoney,
		ToteCommWP		smallmoney,
		ToteFee			smallmoney	
	)
	
	CREATE TABLE #bettransm (
		refno bigint primary key,
		TOIBC	money,
		WLIBC money,
		TOPhum money
	)

	CREATE TABLE #SpecialBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)
	INSERT INTO #SpecialBettypeGroup (BettypeGroupID, Bettype)
	SELECT BettypeGroupID, Bettype FROM DBWH.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID IN (6, 10)

	DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	CREATE TABLE #SportBettype(ProductID INT, Bettype SMALLINT,EventType INT,SubProduct VARCHAR(500), SportType INT) -- using Sporttype column for NG2 (NG2 has not matchid)
	INSERT INTO #SportBettype
	SELECT ProductID,
              Bettype,
              EventType,
              SubProduct,
		    0 SportType
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)		

    UPDATE sb
    SET sb.SportType = s.SportType
    FROM #SportBettype sb
         INNER JOIN SportBettypeMatrix s WITH(NOLOCK) ON sb.BetType = s.BetType 
			AND s.ProductID IN (23, 31, 32, 33, 34, 37, 36, 38, -- NG2, Exchange, Pragmatic, Poker Games, Card Club, Spadegaming, Virtual Games
            39, 42, 43, 45, 40, 47, 46, 52, 50) -- SA Gaming, Saba.club, Indo 4D, Sexy Gaming, Table Games, BBIN, IBCBet Live Casino, ION, RNG War
	IF @winlostdate > @MoveBetsDay
	BEGIN				
		DELETE FROM bodb_Report.dbo.rptWinlost
		WHERE winlostdate = @winlostdate
		
		--calculate racing winlost
		INSERT INTO @CommSetting (MatchID, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
		SELECT	DISTINCT o.orid as matchid, CASE WHEN r.partnerID IN (2,3,4) THEN 0 ELSE 1 END, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
		FROM	outright o WITH (NOLOCK)
				INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.LeagueID AND p.programDate = o.programDate
				INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid				
		WHERE	o.eventdate = @winlostdate 
		
		INSERT INTO #bettransm (refno,TOIBC,WLIBC,TOPhum)
		SELECT refno,
			sum(case when bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end),
			-sum((winlost - stake)*isnull(oddsspread,0)),
			sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <> 0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end)
		FROM bettransm WITH(NOLOCK)
		WHERE winlostdate = @winlostdate	
			AND bettype IN (31,32)
		GROUP BY refno
		
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)			
		SELECT
			winlostdate,
			b.matchid, bettype, liveindicator, Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end ibc,
			sum(case when b.bettype = 33 then bm.TOIBC*actualrate ELSE actual_stake*isnull(b.oddsspread,0)*actualrate END) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realwinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realpos,
			sum((scomm) * actualrate) realcomm,
			-(sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
								- sum( case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(b.oddsspread,0)) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
								+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
													when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
													when 33 then bm.TOPhum*cs.ToteCommWP  
													else 0 end)*b.actualrate) --commIncomeIBC
								- sum(b.scomm*b.actualrate)) as realLineTotal,
			0 as virtualTurnover,
			0 virtualLineTotal,			
			0, 0
		FROM
			bettrans b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
			LEFT JOIN #bettransm bm ON b.transid = bm.refno
		WHERE
			bettype in (31,32,33)
			AND winlostdate = @winlostdate
			AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, b.matchid, bettype, liveindicator, status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end	

		-- Combo Parlay (bettype = 29)
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	
		SELECT
			winlostdate,
			matchid, b.bettype, liveindicator,
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END  Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType,
			CASE WHEN betteam = N'1' THEN 1 ELSE 0 END exrisk
		FROM bettrans b with (nolock)
		WHERE
			bettype = 29
			AND winlostdate = @winlostdate
			AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END ,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end,
			CASE WHEN betteam = N'1' THEN 1 ELSE 0 END

		--other products in bettrans (exclude products of Sportbook + Colosusbet + bettransRng + bettransLC ) 
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	
		SELECT
			winlostdate,
			matchid, b.bettype, liveindicator,  
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END Status,
			0 as ibc,
			sum(case 
					when b.bettype IN (71 , 73, 1000) then 0 
					when sb.ProductID = 33 THEN 0 --Poker Games
					else (1-tpositiontaking)*CASE WHEN sb.ProductID = 1 THEN abs(stake) ELSE stake END*actualrate 
			end) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)
					*CASE 
							WHEN b.bettype IN (71,73,1000) THEN 0 
							when sb.ProductID = 33 THEN 0 --Poker Games
							WHEN sb.ProductID = 1 THEN abs(stake) 
							ELSE stake 
			END*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType,			
			0 exrisk
		FROM
			bettrans b with (nolock)
			inner join #SportBettype sb on b.bettype = sb.Bettype
		WHERE
			(b.bettype < 19999 and b.bettype not in (29,31,32,33,1003,2799))
			AND sb.ProductID NOT IN (1, 15, 6, 17, 21, 22, 24, 32, 34, 36, 39, 42, 45, 46, 52, 50)
			AND winlostdate = @winlostdate
			AND statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
			AND sb.SportType <> 165
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator,  
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END;

				

		--Colosusbet
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	
		SELECT
			winlostdate,
			matchid, b.bettype, liveindicator, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END Status,
			0 as ibc,
			sum((1-tpositiontaking)*stake*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType,			
			CASE WHEN b.Bettype = 18000 AND ISNULL(b.currency2,0) = 1 THEN 1 ELSE 0 END exrisk
		FROM
			bettrans b with (nolock)
		WHERE
			EXISTS(SELECT TOP 1 1 FROM #SportBettype sb 
						WHERE sb.ProductID =  15
							AND sb.Bettype = b.bettype
							)
			AND winlostdate = @winlostdate
			AND statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator,
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END,
			CASE WHEN b.Bettype = 18000 AND ISNULL(b.currency2,0) = 1 THEN 1 ELSE 0 END	;

		-- calculate Sportbooks
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	
		SELECT
			winlostdate,
			matchid, b.bettype, liveindicator, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType,			
			0 exrisk
		FROM
			bettrans b with (nolock)
		WHERE
			EXISTS(SELECT TOP 1 1 FROM #SportBettype sb 
						WHERE sb.ProductID =  1
							AND sb.Bettype = b.bettype
							AND sb.bettype not in (29)
							)
			----(b.bettype < 19999 and b.bettype not in (29,31,32,33,1003,2799))
			AND winlostdate = @winlostdate
			AND statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end
	    
	     -- calculate Virtual Sports Parlay
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	
		SELECT
			winlostdate,
			sm.matchid, b.bettype, liveindicator,
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END Status,
			0 as ibc,
			sum((1-tpositiontaking)*stake*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType, 0 exrisk
		FROM
			bettrans b with (nolock) 
			 LEFT JOIN (
				SELECT refno,MIN(matchid) matchid
				FROM dbo.bettransm b (NOLOCK)
				    inner join #SportBettype sb on b.bettype = sb.Bettype
				WHERE sb.ProductID IN (27)
				GROUP BY refno
			 ) sm	ON b.refno = sm.refno
		WHERE
			(b.bettype =2799)
			AND sm.refno IS NOT NULL
			AND winlostdate = @winlostdate
			AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, sm.matchid, b.bettype, liveindicator, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END

		-- calculate RNG casino products from bettransRnG
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)	

		 SELECT
			winlostdate,
			0 matchid, b.gameID, 0 liveindicator,
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END  Status,
			0 as ibc,
			sum((1-tpositiontaking)*stake*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Bettype Group
					  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + awinlost + mwinlost + swinlost + scomm --Contribution Bettype Group
				      ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm 
				 END) * actualrate) realLineTotal,
			sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
			sum((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Bettype Group
					  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + awinlost + mwinlost + swinlost + scomm --Contribution Bettype Group
				      ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm 
				 END) * virtualrate) virtualLineTotal,

			0 SportType, 0 exrisk
		FROM
			bettransRnG b with (nolock)
			inner join #SportBettype sb on b.gameID = sb.Bettype
			LEFT JOIN #SpecialBettypeGroup bg ON b.gameID = bg.Bettype
		WHERE
			sb.ProductID IN (6, 17, 22, 24, 32, 33, 34, 36, 42, 50) -- MBC-RNG Casino, Microgaming-RNG Casino, Voidbridge, Fishing World, Pragmatic, Spadegaming, Saba.club, RNG War
			AND winlostdate = @winlostdate
			AND b.statusID IN (111,112,113) --(/Won/lose/Draw)	
			AND currency <> 20
		GROUP BY
			winlostdate, b.gameID, 
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END;

		-- calculate Live casino products from bettransLC
		INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)
		SELECT
			winlostdate,
			b.productID,
			gameID,
			0 as liveindicator,			
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END Status,
			0 ibc,
			SUM((1-tpositiontaking)*stake*actualrate) as realturnover,
			SUM((winlost-actual_stake)* actualrate)  realWinlost,
			SUM((awinlost+mwinlost+swinlost)* actualrate) realPos,
			SUM((scomm) * actualrate) realComm,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
			SUM((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			211 SportType,
			0 exrisk
		FROM
			dbo.bettransLC b WITH (NOLOCK)
			 INNER JOIN #SportBettype sb on b.gameID = sb.Bettype
		WHERE
			sb.ProductID IN (21, 39, 45, 46, 52) -- Allbet, SA Gaming, Sexy Gaming, IBCBet Live Casino, ION
			AND winlostdate = @winlostdate
			AND statusID   IN (111,112,113) --(/Won/lose/Draw)
			AND currency <> 20
		GROUP BY
			winlostdate,
			b.productID,
			gameID,			
			CASE WHEN StatusID = 111 THEN 'DRAW'
				WHEN StatusID = 112 THEN 'WON'
				WHEN StatusID = 113 THEN 'LOSE' END;

		-- Update Sport

		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END
			, exrisk = m.exrisk
		FROM match m with (nolock)
			inner join league l with (nolock) ON m.leagueid = l.leagueid
		WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
			AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType <> 5)
			AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype not in (10,31,32,33,2799) 

		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = l.sporttype 
			, exrisk = m.exrisk
			,bodb_Report.dbo.rptWinlost.matchid = 0
		FROM match m with (nolock)
			inner join league l with (nolock) ON m.leagueid = l.leagueid
		WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
			AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype = 2799

		--3rd Product
		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = l.sporttype
		FROM Match3rd m with (nolock)
			inner join League3rd l with (nolock) ON m.League3rdId = l.League3rdId
		WHERE bodb_Report.dbo.rptWinlost.matchid = m.Match3rdId
		AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType = 5)
		AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate

		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END
		FROM outright o with (nolock) INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
		WHERE bodb_Report.dbo.rptWinlost.matchid = o.orid
		AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
		AND bodb_Report.dbo.rptWinlost.bettype = 10
		
		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END
		FROM outright o with (nolock) INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
		WHERE bodb_Report.dbo.rptWinlost.matchid = o.orid
		AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
		AND bodb_Report.dbo.rptWinlost.bettype BETWEEN 31 AND 33
		
		--Virtual Racing
		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = r.sporttype
		FROM VSRaceInfo r with (nolock)
		WHERE bodb_Report.dbo.rptWinlost.matchid = r.EventID
		AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
		AND bodb_Report.dbo.rptWinlost.bettype in (1231, 1232, 1233, 1237, 1238)			

		--NG2, Exchange, Pragmatic, Poker Games
		UPDATE rpt
		SET rpt.SportType = sb.SportType
		FROM bodb_Report.dbo.rptWinlost rpt WITH(NOLOCK)
		  INNER JOIN #SportBettype sb on  rpt.bettype = sb.Bettype
		WHERE sb.ProductID IN (23, 31, 32, 33, 34, 37, 36, 38, 39, 42, 43, 45, 40, 47, 46, 52, 50)
		AND rpt.winlostdate =  @winlostdate
	END
	ELSE IF @winlostdate BETWEEN @BalanceUpDay AND @MoveBetsDay 
	BEGIN -- check from BetTrans14
		SELECT distinct winlostdate FROM bettrans14 with (nolock) WHERE winlostdate = @winlostdate AND bettype < 19999

		IF @@ROWCOUNT = 1
		BEGIN
			DELETE FROM bodb_Report.dbo.rptWinlost
			WHERE winlostdate = @winlostdate
		
			-- calculate racing winlost
			INSERT INTO @CommSetting (MatchID, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
			SELECT	DISTINCT o.orid as matchid, CASE WHEN r.partnerID IN (2,3,4) THEN 0 ELSE 1 END, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
			FROM	outright14 o WITH (NOLOCK)
					INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.LeagueID AND p.programDate = o.programDate
					INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid				
			WHERE	o.eventdate = @winlostdate 
			
			INSERT INTO #bettransm (refno,TOIBC,WLIBC,TOPhum)
			SELECT refno,
				sum(case when bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end),
				-sum((winlost - stake)*isnull(oddsspread,0)),
				sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <> 0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end)
			FROM bettransm14 WITH(NOLOCK)
			WHERE winlostdate = @winlostdate
				AND bettype IN (31,32)
			GROUP BY refno
			
			INSERT INTO bodb_Report.dbo.rptWinlost
			(
				[winlostdate]
			   ,[matchid]
			   ,[bettype]
			   ,[liveindicator]
			   ,[Status]
			   ,[IBC]
			   ,[RealTurnover]
			   ,[RealWinLost]
			   ,[RealPosition]
			   ,[RealCommission]
			   ,[RealLineTotal]
			   ,[VirtualTurnover]
			   ,[VirtualLineTotal]
			   ,[SportType]
			   ,[exrisk]
			)			
			SELECT
				winlostdate,
				b.matchid, bettype, liveindicator, Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end ibc,
				sum(case when b.bettype = 33 then bm.TOIBC*actualrate ELSE actual_stake*isnull(b.oddsspread,0)*actualrate END) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realwinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realpos,
				sum((scomm) * actualrate) realcomm,
				-(sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
									- sum( case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(b.oddsspread,0)) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
									+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
														when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
														when 33 then bm.TOPhum*cs.ToteCommWP  
														else 0 end)*b.actualrate) --commIncomeIBC
									- sum(b.scomm*b.actualrate)) as realLineTotal,
				0 as virtualTurnover,
				0 virtualLineTotal,			
				0, 0
			FROM
				bettrans14 b with (nolock)
				INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
				LEFT JOIN #bettransm bm ON b.transid = bm.refno
			WHERE
				bettype in (31,32,33)
				AND winlostdate = @winlostdate
				AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, b.matchid, bettype, liveindicator, status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end

			-- Combo Parlay (bettype = 29)
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	
			SELECT
				winlostdate,
				matchid, b.bettype, liveindicator,
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END  Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
				sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType,
				CASE WHEN betteam = N'1' THEN 1 ELSE 0 END exrisk
			FROM dbo.bettrans14 b with (nolock)
			WHERE
				bettype = 29
				AND winlostdate = @winlostdate
				AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, matchid, b.bettype, liveindicator, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END ,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end,
				CASE WHEN betteam = N'1' THEN 1 ELSE 0 END

			--other products in bettrans (exclude products of Sportbook + Colosusbet + bettransRng + bettransLC ) 
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	
			SELECT
				winlostdate,
				matchid, b.bettype, liveindicator,  
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END Status,
				0 as ibc,
				sum(case 
						when b.bettype IN (71,73,1000) then 0 
						when sb.ProductID = 33 THEN 0 --Poker Games
						else (1-tpositiontaking)*CASE WHEN sb.ProductID = 1 THEN abs(stake) ELSE stake END*actualrate 
				end) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)
						*CASE 
								WHEN b.bettype IN (71,73,1000) THEN 0 
								when sb.ProductID = 33 THEN 0 --Poker Games
								WHEN sb.ProductID = 1 THEN abs(stake) 
								ELSE stake 
				END*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType,			
				0 exrisk
			FROM
				dbo.bettrans14 b with (nolock)
				inner join #SportBettype sb on b.bettype = sb.Bettype
			WHERE
				(b.bettype < 19999 and b.bettype not in (29,31,32,33,1003,2799))
				AND sb.ProductID NOT IN (1, 15, 6, 17, 21, 22, 24, 32, 34, 36, 39, 42, 45, 46, 52, 50)
				AND sb.SportType <> 165
				AND winlostdate = @winlostdate
				AND statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, matchid, b.bettype, liveindicator,  
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END;

			--Colosusbet
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	
			SELECT
				winlostdate,
				matchid, b.bettype, liveindicator, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END Status,
				0 as ibc,
				sum((1-tpositiontaking)*stake*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType,			
				CASE WHEN b.Bettype = 18000 AND ISNULL(b.currency2,0) = 1 THEN 1 ELSE 0 END exrisk
			FROM
				dbo.bettrans14 b with (nolock)
			WHERE
				EXISTS(SELECT TOP 1 1 FROM #SportBettype sb 
							WHERE sb.ProductID =  15
								AND sb.Bettype = b.bettype
								)
				AND winlostdate = @winlostdate
				AND statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, matchid, b.bettype, liveindicator,
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END,
				CASE WHEN b.Bettype = 18000 AND ISNULL(b.currency2,0) = 1 THEN 1 ELSE 0 END	;

			-- calculate Sportbooks
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	
			SELECT
				winlostdate,
				matchid, b.bettype, liveindicator, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
				sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType,			
				0 exrisk
			FROM
				dbo.bettrans14 b with (nolock)
			WHERE
				EXISTS(SELECT TOP 1 1 FROM #SportBettype sb 
							WHERE sb.ProductID =  1
								AND sb.Bettype = b.bettype
								AND sb.bettype not in (29)
								)
				----(b.bettype < 19999 and b.bettype not in (29,31,32,33,1003,2799))
				AND winlostdate = @winlostdate
				AND statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, matchid, b.bettype, liveindicator, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end
	    
			 -- calculate Virtual Sports Parlay
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	
			SELECT
				winlostdate,
				sm.matchid, b.bettype, liveindicator,
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END Status,
				0 as ibc,
				sum((1-tpositiontaking)*stake*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType, 0 exrisk
			FROM
				dbo.bettrans14 b with (nolock) 
				 LEFT JOIN (
					SELECT refno,MIN(matchid) matchid
					FROM dbo.bettransm14 b (NOLOCK)
						inner join #SportBettype sb on b.bettype = sb.Bettype
					WHERE sb.ProductID IN (27)
					GROUP BY refno
				 ) sm	ON b.refno = sm.refno
			WHERE
				(b.bettype =2799)
				AND sm.refno IS NOT NULL
				AND winlostdate = @winlostdate
				AND b.statusID IN (111,112,113) --(/Won/lose/Draw)
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, sm.matchid, b.bettype, liveindicator, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END

			-- calculate RNG casino products from bettransRnG
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)	

			 SELECT
				winlostdate,
				0 matchid, b.gameID, 0 liveindicator,
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END  Status,
				0 as ibc,
				sum((1-tpositiontaking)*stake*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Bettype Group
						  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + awinlost + mwinlost + swinlost + scomm --Contribution Bettype Group
						  ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm 
					 END) * actualrate) realLineTotal,
				sum((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
				sum((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Bettype Group
						  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + awinlost + mwinlost + swinlost + scomm --Contribution Bettype Group
						  ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm 
					 END) * virtualrate) virtualLineTotal,

				0 SportType, 0 exrisk
			FROM
				dbo.bettransRnG14 b with (nolock)
				inner join #SportBettype sb on b.gameID = sb.Bettype
				LEFT JOIN #SpecialBettypeGroup bg ON b.gameID = bg.Bettype
			WHERE
				sb.ProductID IN (6, 17, 22, 24, 32, 33, 34, 36, 42, 50) -- MBC-RNG Casino, Microgaming-RNG Casino, Voidbridge, Fishing World, Pragmatic, Spadegaming, Saba.club, RNG War
				AND winlostdate = @winlostdate
				AND b.statusID IN (111,112,113) --(/Won/lose/Draw)	
				AND currency <> 20
			GROUP BY
				winlostdate, b.gameID, 
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END;

			-- calculate Live casino products from bettransLC
			INSERT INTO bodb_Report.dbo.rptWinlost
				(
					[winlostdate]
				   ,[matchid]
				   ,[bettype]
				   ,[liveindicator]
				   ,[Status]
				   ,[IBC]
				   ,[RealTurnover]
				   ,[RealWinLost]
				   ,[RealPosition]
				   ,[RealCommission]
				   ,[RealLineTotal]
				   ,[VirtualTurnover]
				   ,[VirtualLineTotal]
				   ,[SportType]
				   ,[exrisk]
				)
			SELECT
				winlostdate,
				b.productID,
				gameID,
				0 as liveindicator,			
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END Status,
				0 ibc,
				SUM((1-tpositiontaking)*stake*actualrate) as realturnover,
				SUM((winlost-actual_stake)* actualrate)  realWinlost,
				SUM((awinlost+mwinlost+swinlost)* actualrate) realPos,
				SUM((scomm) * actualrate) realComm,
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
				SUM((1-tpositiontaking)*stake*virtualrate) as virtualTurnover,
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				211 SportType,
				0 exrisk
			FROM
				dbo.bettransLC14 b WITH (NOLOCK)
				 INNER JOIN #SportBettype sb on b.gameID = sb.Bettype
			WHERE
				sb.ProductID IN (21, 39, 45, 46, 52) -- Allbet, SA Gaming, Sexy Gaming, IBCBet Live Casino, ION
				AND winlostdate = @winlostdate
				AND statusID   IN (111,112,113) --(/Won/lose/Draw)
				AND currency <> 20
			GROUP BY
				winlostdate,
				b.productID,
				gameID,			
				CASE WHEN StatusID = 111 THEN 'DRAW'
					WHEN StatusID = 112 THEN 'WON'
					WHEN StatusID = 113 THEN 'LOSE' END;
			
			-- Update Sport

			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = CASE
				WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
				WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
				ELSE l.sporttype END
				,exrisk = m.exrisk				
			FROM match14 m with (nolock)
				inner join league l with (nolock) ON m.leagueid = l.leagueid
			WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
				AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType <> 5)
				AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
				AND bodb_Report.dbo.rptWinlost.bettype not in (10,31,32,33,2799) 
			
			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = l.sporttype 
				,exrisk = m.exrisk
				,bodb_Report.dbo.rptWinlost.matchid = 0
			FROM match14 m with (nolock)
				inner join league l with (nolock) ON m.leagueid = l.leagueid
			WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
				AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
				AND bodb_Report.dbo.rptWinlost.bettype = 2799
			
			--3rd Product
			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = l.sporttype
			FROM Match3rd14 m with (nolock)
				inner join League3rd l with (nolock) ON m.League3rdId = l.League3rdId
			WHERE bodb_Report.dbo.rptWinlost.matchid = m.Match3rdId
			AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType = 5)
			AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate

			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = CASE
				WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
				WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
				ELSE l.sporttype END
			FROM outright14 o with (nolock) INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
			WHERE bodb_Report.dbo.rptWinlost.matchid = o.orid
			AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype = 10
			
			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = CASE
				WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
				WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
				ELSE l.sporttype END
			FROM outright14 o with (nolock) INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
			WHERE bodb_Report.dbo.rptWinlost.matchid = o.orid
			AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype BETWEEN 31 AND 33	
			
			--Virtual Racing
			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = r.sporttype
			FROM VSRaceInfo14 r with (nolock)
			WHERE bodb_Report.dbo.rptWinlost.matchid = r.EventID
			AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype in (1231, 1232, 1233, 1237, 1238)	

		     --NG2 & Exchange, Pragmatic
		    UPDATE rpt
		    SET rpt.SportType = sb.SportType
		    FROM bodb_Report.dbo.rptWinlost rpt
			 INNER JOIN #SportBettype sb on  rpt.bettype = sb.Bettype
		    WHERE sb.ProductID IN (23, 31, 32, 33, 34, 37, 36, 38, 39, 42, 43, 45, 40, 47, 46, 52, 50)
		    AND rpt.winlostdate =  @winlostdate
		END
	END
	
	DROP TABLE #bettransm
	DROP TABLE #SportBettype
	DROP TABLE #SpecialBettypeGroup
END


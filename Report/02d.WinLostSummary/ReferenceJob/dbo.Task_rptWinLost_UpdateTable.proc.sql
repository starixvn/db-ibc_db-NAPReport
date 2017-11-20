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
*/

BEGIN	
	SET NOCOUNT ON;

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

	DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500), SportType INT) -- using Sporttype column for NG2 (NG2 has not matchid)
	INSERT INTO @SportBettype
	SELECT ProductID,
              Bettype,
              EventType,
              SubProduct,
		    0 SportType
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)

    UPDATE sb
    SET sb.SportType = s.SportType
    FROM @SportBettype sb
	   INNER JOIN SportBettypeMatrix s WITH(NOLOCK) ON sb.BetType = s.BetType AND s.ProductID IN (23) -- NG2

	SELECT distinct winlostdate cnt FROM bettrans with (nolock) WHERE winlostdate = @winlostdate AND bettype < 19999
	IF @@ROWCOUNT = 1
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
			AND statusID NOT IN (101,102,103,121)--('VOID','REJECT','DONE','REFUND')
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
			matchid, b.bettype, liveindicator, Status,
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
			AND statusID NOT IN (101, 102,103,121) --('VOID','REJECT','DONE','REFUND')
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator, status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end,
			CASE WHEN betteam = N'1' THEN 1 ELSE 0 END

		-- calculate Sportbooks + other products in bettrans (exclude products of bettransRng + bettransLC) 
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
			matchid, b.bettype, liveindicator, Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
			sum(case when b.bettype IN (71,73,1000) then 0 else (1-tpositiontaking)*CASE WHEN b.bettype IN (1700,1800,1900) THEN stake ELSE abs(stake) END*actualrate end) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*CASE WHEN b.bettype IN (71,73,1000) THEN 0 WHEN b.bettype IN (1700,1800,1900) THEN stake ELSE abs(stake) END*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType, 0 exrisk
		FROM
			bettrans b with (nolock)
			inner join @SportBettype sb on b.bettype = sb.Bettype
		WHERE
			(b.bettype < 19999 and b.bettype not in (29,31,32,33,1003,2799))
			AND sb.ProductID NOT IN (6, 17, 21, 22, 24)
			AND winlostdate = @winlostdate
			AND statusID NOT IN (101, 102,103,121) --('VOID','REJECT','DONE','REFUND')
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, matchid, b.bettype, liveindicator, status,
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
			sm.matchid, b.bettype, liveindicator, Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType, 0 exrisk
		FROM
			bettrans b with (nolock) 
			 LEFT JOIN (
				SELECT refno,MIN(matchid) matchid
				FROM dbo.bettransm b (NOLOCK)
				    inner join @SportBettype sb on b.bettype = sb.Bettype
				WHERE sb.ProductID IN (27)
				GROUP BY refno
			 ) sm	ON b.refno = sm.refno
		WHERE
			(b.bettype =2799)
			AND sm.refno IS NOT NULL
			AND winlostdate = @winlostdate
			AND statusID NOT IN (101, 102,103,121) --('VOID','REJECT','DONE','REFUND')
			AND ruben = 1
			AND currency <> 20
		GROUP BY
			winlostdate, sm.matchid, b.bettype, liveindicator, status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end


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
			0 matchid, b.gameID, 0 liveindicator, Status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
			sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
			sum((winlost-actual_stake)* actualrate)  realWinlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
			sum((scomm) * actualrate) realComm,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
			sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			0 SportType, 0 exrisk
		FROM
			bettransRnG b with (nolock)
			inner join @SportBettype sb on b.gameID = sb.Bettype
		WHERE
			sb.ProductID IN (6, 17, 22, 24) -- MBC-RNG Casino, Microgaming-RNG Casino, Voidbridge, Fishing World
			AND winlostdate = @winlostdate
			AND statusID NOT IN (0, 1, 101, 102,103,121) --('VOID','REJECT','DONE','REFUND')			
			AND currency <> 20
		GROUP BY
			winlostdate, b.gameID, status,
			case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end


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
			0 asliveindicator,
			Status,
			CASE WHEN recommend = 52466   THEN 1 
				 WHEN recommend = 5707545 THEN 2 ELSE 0
				 END AS ibc,
			SUM((1-tpositiontaking)*ABS(stake)*actualrate) as realturnover,
			SUM((winlost-actual_stake)* actualrate)  realWinlost,
			SUM((awinlost+mwinlost+swinlost)* actualrate) realPos,
			SUM((scomm) * actualrate) realComm,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
			SUM((1-tpositiontaking)*ABS(stake)*virtualrate) as virtualTurnover,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
			211 SportType,
			0 exrisk
		FROM
			dbo.bettransLC b WITH (NOLOCK)
			 INNER JOIN @SportBettype sb on b.gameID = sb.Bettype
		WHERE
			sb.ProductID = 21
			AND winlostdate = @winlostdate
			AND statusID   IN (111,112,113) --(/Won/lose/Draw)
			AND currency <> 20
		GROUP BY
			winlostdate,
			b.productID,
			gameID,
			status,
			CASE WHEN recommend = 52466   THEN 1 
				 WHEN recommend = 5707545 THEN 2 ELSE 0
				 END		



		-- Update Sport

		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END
			, exrisk = m.exrisk
			,bodb_Report.dbo.rptWinlost.matchid = CASE WHEN bodb_Report.dbo.rptWinlost.bettype = 2799 THEN 0 ELSE bodb_Report.dbo.rptWinlost.matchid END
		FROM match m with (nolock)
			inner join league l with (nolock) ON m.leagueid = l.leagueid
		WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
		AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType <> 5)
		AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
		AND bodb_Report.dbo.rptWinlost.bettype not in (10,31,32,33) --20120626@Elodie: exclude outright from sportbook

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

		--NG2
		UPDATE rpt
		SET rpt.SportType = sb.SportType
		FROM bodb_Report.dbo.rptWinlost rpt WITH(NOLOCK)
		  INNER JOIN @SportBettype sb on  rpt.bettype = sb.Bettype
		WHERE sb.ProductID IN (23) 
		AND rpt.winlostdate =  @winlostdate
	END
	ELSE
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
				AND statusID NOT IN (101,102,103,121)--('VOID','REJECT','DONE','REFUND')
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
				matchid, 
				b.bettype, liveindicator, Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end ibc,
				sum(abs(stake)*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*CASE WHEN b.bettype IN (1700,1800,1900) THEN stake ELSE abs(stake) END*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType,
				CASE WHEN betteam = N'1' THEN 1 ELSE 0 END exrisk
			FROM
				bettrans14 b with (nolock)
			WHERE
				bettype = 29
				AND winlostdate = @winlostdate
				AND statusID NOT IN (101, 102,103,121) ----('VOID','REJECT','DONE','REFUND')
				AND ruben = 1
				AND currency <> 20
			GROUP BY
				winlostdate, 
				matchid, 
				b.bettype, liveindicator, status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end,
				CASE WHEN betteam = N'1' THEN 1 ELSE 0 END
			

			-- calculate Sportbooks + other products in bettrans (exclude products of bettransRng + bettransLC) 
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
				CASE WHEN b.bettype = 1003 THEN b.betdaqid ELSE matchid END matchid, 
				b.bettype, liveindicator, Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end ibc,
				sum(case when b.bettype IN (71,73,1000) then 0 else (1-tpositiontaking)*CASE WHEN b.bettype IN (1700,1800,1900) THEN stake ELSE abs(stake) END*actualrate end) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*CASE WHEN b.bettype IN (71,73,1000) THEN 0 WHEN b.bettype IN (1700,1800,1900) THEN stake ELSE abs(stake) END*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType, 0 exrisk
			 FROM
				bettrans14 b with (nolock)
				    INNER JOIN @SportBettype sb on b.bettype = sb.Bettype
			 WHERE
				(b.bettype < 19999 and b.bettype not in (29,31,32,33,2799))
				AND sb.ProductID NOT IN (6, 17, 21, 22, 24)
				AND winlostdate = @winlostdate
				AND statusID NOT IN (101, 102,103,121) ----('VOID','REJECT','DONE','REFUND')
				AND ruben = 1
				AND currency <> 20
			 GROUP BY
				winlostdate, 
				CASE WHEN b.bettype = 1003 THEN b.betdaqid ELSE matchid END, 
				b.bettype, liveindicator, status,
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
				sm.matchid, b.bettype, liveindicator, Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end as ibc,
				sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((case when b.bettype = 1000 then -1*(odds-scomm) else winlost-actual_stake+awinlost+mwinlost+swinlost+scomm end)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType, 0 exrisk
			 FROM
			    bettrans14 b with (nolock) 
				LEFT JOIN (
				    SELECT refno,MIN(matchid) matchid
				    FROM dbo.bettransm14 b (NOLOCK)
					   inner join @SportBettype sb on b.bettype = sb.Bettype
				    WHERE sb.ProductID IN (27)
				    GROUP BY refno
				) sm	ON b.refno = sm.refno
			 WHERE
				(b.bettype =2799 )
				AND sm.refno IS NOT NULL
				AND winlostdate = @winlostdate
				AND statusID NOT IN (101, 102,103,121) --('VOID','REJECT','DONE','REFUND')
				AND ruben = 1
				AND currency <> 20
			 GROUP BY
				winlostdate, sm.matchid, b.bettype, liveindicator, status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end


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
				0 matchid, b.gameID, 0 liveindicator, Status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end ibc,
				sum((1-tpositiontaking)*abs(stake)*actualrate) as realturnover,
				sum((winlost-actual_stake)* actualrate)  realWinlost,
				sum((awinlost+mwinlost+swinlost)* actualrate) realPos,
				sum((scomm) * actualrate) realComm,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
				sum((1-tpositiontaking)*abs(stake)*virtualrate) as virtualTurnover,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				0 SportType, 0 exrisk
			FROM
				bettransRnG14 b with (nolock)
				    INNER JOIN @SportBettype sb on b.gameID = sb.Bettype
			WHERE
				sb.ProductID IN (6, 17, 22,24)
				AND winlostdate = @winlostdate
				AND statusID NOT IN (0, 1, 101, 102,103,121) ----('VOID','REJECT','DONE','REFUND')
				AND currency <> 20
			GROUP BY
				winlostdate, b.gameID, status,
				case when recommend = 52466 then 1 when recommend = 5707545 then 2 else 0 end


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
				0 asliveindicator,
				Status,
				CASE WHEN recommend = 52466   THEN 1 
					 WHEN recommend = 5707545 THEN 2 ELSE 0
					 END AS ibc,
				SUM((1-tpositiontaking)*ABS(stake)*actualrate) as realturnover,
				SUM((winlost-actual_stake)* actualrate)  realWinlost,
				SUM((awinlost+mwinlost+swinlost)* actualrate) realPos,
				SUM((scomm) * actualrate) realComm,
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) realLineTotal,
				SUM((1-tpositiontaking)*ABS(stake)*virtualrate) as virtualTurnover,
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) as virtualLineTotal,
				211 SportType,
				0 exrisk
			FROM
				dbo.bettransLC14 b WITH (NOLOCK)
				    INNER JOIN @SportBettype sb on b.gameID = sb.Bettype
			WHERE
				sb.ProductID = 21
				AND winlostdate = @winlostdate
				AND statusID IN (111,112,113) --(/Won/lose/Draw)
				AND currency <> 20
			GROUP BY
				winlostdate,
				b.productID,
				gameID,
				status,
				CASE WHEN recommend = 52466   THEN 1 
					 WHEN recommend = 5707545 THEN 2 ELSE 0
					 END

			
			-- Update Sport

			UPDATE bodb_Report.dbo.rptWinlost
			SET SportType = CASE
				WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
				WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
				ELSE l.sporttype END
				,exrisk = m.exrisk				
				,bodb_Report.dbo.rptWinlost.matchid = CASE WHEN bodb_Report.dbo.rptWinlost.bettype = 2799 THEN 0 ELSE bodb_Report.dbo.rptWinlost.matchid END
			FROM match14 m with (nolock)
				inner join league l with (nolock) ON m.leagueid = l.leagueid
			WHERE bodb_Report.dbo.rptWinlost.matchid = m.matchid
			AND bettype IN (SELECT bettype FROM bodb02.dbo.SportBettypeMatrix (NOLOCK) WHERE EventType <> 5)
			AND m.eventdate = @winlostdate AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype not in (10,31,32,33) --20120626@Elodie: exclude outright from sportbook
			
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
			FROM VSRaceInfo r with (nolock)
			WHERE bodb_Report.dbo.rptWinlost.matchid = r.EventID
			AND bodb_Report.dbo.rptWinlost.winlostdate = @winlostdate
			AND bodb_Report.dbo.rptWinlost.bettype in (1231, 1232, 1233, 1237, 1238)	

		     --NG2 & Fishing World
		    UPDATE rpt
		    SET rpt.SportType = sb.SportType
		    FROM bodb_Report.dbo.rptWinlost rpt WITH(NOLOCK)
			 INNER JOIN @SportBettype sb on  rpt.bettype = sb.Bettype
		    WHERE sb.ProductID IN (23, 24) 
		    AND rpt.winlostdate =  @winlostdate
		END
	END
	
	DROP TABLE #bettransm
END
GO 
 GRANT VIEW DEFINITION ON [dbo].[Task_rptWinLost_UpdateTable] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Task_rptWinLost_UpdateTable] TO [bodbAdminNet]
GO
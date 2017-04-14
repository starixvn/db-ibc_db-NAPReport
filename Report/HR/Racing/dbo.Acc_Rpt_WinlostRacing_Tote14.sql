ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacing_Tote14]
	@ReportType		TINYINT,
	@winlostdate	DATETIME
AS
/*	Created by: Johnson
	Date: 2011-03-16
	Task: Racing Daily Report 
	DB: DBACC/BODB02

	Revisions:
		- 20110531@Johnson: Add horse racing for SA Tote
		- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
		- 20111226@Jamie: 
			+ Amend formula of amount due to for Greyhound UK
			+ Optimze the way to calculate IBC Net Income & Amount Due to Partner
		- 20130527@Johnson: Add group NSW to Aus racing
	Parameter's Explanation:
		- @ReportType = 1: Horse Racing Daily Report for UK
					 = 2: Horse Racing Daily Report for AU
					 = 3: Greyhound Daily Report for UK
					 = 4: Greyhound Daily Report for AU
					 = 5: Harness Daily Report for AU
					 = 6: Horse Racing Daily Report for SA Tote
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @tmpPartner TABLE(PartnerID INT)

	DECLARE @IBCNetIncomeAddToteFee INT, -- IBC Net Income add Tote Fee or not 
									     -- [0]: Not include Tote Fee; [1]: Plus Tote Fee; [-1]: Minus Tote Fee 
			@AmountDueToAddToteFee	INT  

	DECLARE @CommSetting TABLE
	(	MatchID int,
		PartnerID INT,
		PartnerName varchar(50),
		ToteCommWin smallmoney,
		ToteCommPlace smallmoney,
		ToteCommWP smallmoney,
		ToteFee smallmoney	
	)
	
	IF (@ReportType = 1) --Horse Racing for UK/Irish  
	BEGIN
		INSERT INTO @tmpPartner
			SELECT 2 -- RACE-ATRUK
		UNION ALL
			SELECT 3 -- RACE-ATRIRLcs
		UNION ALL
			SELECT 4 -- RACE-RUK
		
		SELECT	@IBCNetIncomeAddToteFee = 0,
				@AmountDueToAddToteFee = -1
		
	END
	ELSE IF (@ReportType =2) -- Horse Racing for Aust 
	BEGIN
		INSERT INTO @tmpPartner
			SELECT 5 -- RACE-TABCORP
		UNION ALL
			SELECT 6 -- RACE-TABCORPNSW
			
		SELECT	@IBCNetIncomeAddToteFee = -1,
				@AmountDueToAddToteFee = 1
	END
	ELSE IF (@ReportType =3) --Greyhound for UK 
	BEGIN
		INSERT INTO @tmpPartner
			SELECT 101 -- GREY-DTOTEUK
		UNION ALL
			SELECT 102 -- GREY-DTOTEIRL

		SELECT	@IBCNetIncomeAddToteFee = -1,
				@AmountDueToAddToteFee = 0
	END
	ELSE IF (@ReportType =4) --Greyhound for Aust 
	BEGIN
		INSERT INTO @tmpPartner
			SELECT 103-- GREY-TABCORP
		UNION ALL
			SELECT 104-- GREY-TABCORPNSW
			
		SELECT	@IBCNetIncomeAddToteFee = -1,
				@AmountDueToAddToteFee = 1
	END
	ELSE IF (@ReportType = 5) --Harness for Aust 
	BEGIN
		INSERT INTO @tmpPartner
			SELECT 201 -- HAR-TABCORP
		UNION ALL
			SELECT 202 -- HAR-TABCORPNSW
			
		SELECT	@IBCNetIncomeAddToteFee = -1,
				@AmountDueToAddToteFee = 1
	END
	ELSE IF (@ReportType = 6) -- Horse Racing for SA 
	BEGIN
		INSERT INTO @TmpPartner
			SELECT 1 -- RACE-PHU
		
		SELECT	@IBCNetIncomeAddToteFee = -1,
				@AmountDueToAddToteFee = 1
			
	END
	
	INSERT INTO @CommSetting (
			MatchID,PartnerID, PartnerName,  
			ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee
	)
	SELECT	DISTINCT o.orid as matchid,r.partnerID, r.PartnerName,
			p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright14 o WITH (NOLOCK)
			INNER JOIN RacingMeeting m WITH (NOLOCK) ON m.meetingID = o.leagueid			
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.MeetingID = p.leagueID AND p.programDate = o.programDate
			INNER JOIN RacingPartner r WITH(NOLOCK) ON m.partnerID = r.partnerID 
	WHERE	o.eventdate = @winlostdate  
			AND m.partnerID IN (SELECT PartnerID FROM @tmpPartner)
	
	SELECT	t.partnerID,
			t.PartnerName,
			t.PoolCurrency,
			t.currencyName,
			t.currency,
			ISNULL(t.winTO_Agency_Origin,0)			winTO_Agency_Origin,
			ISNULL(t.placeTO_Agency_Origin,0)		placeTO_Agency_Origin,
			ISNULL(t.winplaceTO_Agency_Origin,0)	winplaceTO_Agency_Origin,
			ISNULL(t.winTO_Agency_Origin,0) 
			 + ISNULL(t.placeTO_Agency_Origin,0) 
			 + ISNULL(t.winplaceTO_Agency_Origin,0) totalTO_Agency_Origin,
			ISNULL(t.commIncomeAgency_Origin,0)		commIncome_Agency_Origin,
			ISNULL(t.PTWLAgency_Origin,0)			PTWL_Agency_Origin,

			ISNULL(t.winTO_Agency,0)				winTO_Agency,
			ISNULL(t.placeTO_Agency,0)				placeTO_Agency,
			ISNULL(t.winplaceTO_Agency,0)			winplaceTO_Agency,
			ISNULL(t.winTO_Agency,0) 
			 + ISNULL(t.placeTO_Agency,0) 
			 + ISNULL(t.winplaceTO_Agency,0)		totalTO_Agency,
			ISNULL(t.commIncomeAgency,0)			commIncome_Agency,
			ISNULL(t.PTWLAgency,0)					PTWL_Agency,

			ISNULL(t.winTO_Agency_PoolCurr,0)				winTO_Agency_PoolCurr,
			ISNULL(t.placeTO_Agency_PoolCurr,0)				placeTO_Agency_PoolCurr,
			ISNULL(t.winplaceTO_Agency_PoolCurr,0)			winplaceTO_Agency_PoolCurr,
			ISNULL(t.winTO_Agency_PoolCurr,0) 
			 + ISNULL(t.placeTO_Agency_PoolCurr,0) 
			 + ISNULL(t.winplaceTO_Agency_PoolCurr,0)		totalTO_Agency_PoolCurr,
			ISNULL(t.commIncomeAgency_PoolCurr,0)			commIncome_Agency_PoolCurr,
			ISNULL(t.PTWLAgency_PoolCurr,0)					PTWL_Agency_PoolCurr,

			ISNULL(t.winTO_IBC_Origin,0)			winTO_IBC_Origin,
			ISNULL(t.placeTO_IBC_Origin,0)			placeTO_IBC_Origin,
			ISNULL(t.winplaceTO_IBC_Origin,0)		winplaceTO_IBC_Origin,
			ISNULL(t.winTO_IBC_Origin,0) 
			 + ISNULL(t.placeTO_IBC_Origin,0)
			 + ISNULL(t.winplaceTO_IBC_Origin,0)	totalTO_IBC_Origin,

			ISNULL(t.winTO_IBC,0)					winTO_IBC,
			ISNULL(t.placeTO_IBC,0)					placeTO_IBC,
			ISNULL(t.winplaceTO_IBC,0)				winplaceTO_IBC,
			ISNULL(t.winTO_IBC,0)
			 + ISNULL(t.placeTO_IBC,0)	
			 + ISNULL(t.winplaceTO_IBC,0)			totalTO_IBC,

			ISNULL(t.winTO_IBC_PoolCurr,0)			winTO_IBC_PoolCurr,
			ISNULL(t.placeTO_IBC_PoolCurr,0)		placeTO_IBC_PoolCurr,
			ISNULL(t.winplaceTO_IBC_PoolCurr,0)		winplaceTO_IBC_PoolCurr,
			ISNULL(t.winTO_IBC_PoolCurr,0)
			 + ISNULL(t.placeTO_IBC_PoolCurr,0)	
			 + ISNULL(t.winplaceTO_IBC_PoolCurr,0)	totalTO_IBC_PoolCurr,

			ISNULL(t.FeeDue2_origin,0)				FeeDue2_origin,
			ISNULL(t.FeeDue2,0)						FeeDue2,
			ISNULL(t.FeeDue2_PoolCurr,0)			FeeDue2_PoolCurr,


			ISNULL(t.commIncomeIBC_origin,0)		commIncome_IBC_origin,
			ISNULL(t.commIncomeIBC,0)				commIncome_IBC,
			ISNULL(t.commIncomeIBC_PoolCurr,0)		commIncome_IBC_PoolCurr,

			ISNULL(t.PTWLIBC_origin,0)				PTWL_IBC_origin,
			ISNULL(t.PTWLIBC,0)						PTWL_IBC,
			ISNULL(t.PTWLIBC_PoolCurr,0)			PTWL_IBC_PoolCurr,


			ISNULL(t.PTWLIBC_origin,0)
			 + ISNULL(t.commIncomeIBC_origin,0)
			 - ISNULL(t.commIncomeAgency_Origin,0)
			 + (@IBCNetIncomeAddToteFee*ISNULL(t.FeeDue2_origin,0)) netIncome_IBC_Origin,

			ISNULL(t.PTWLIBC,0)
			 + ISNULL(t.commIncomeIBC,0)
			 - ISNULL(t.commIncomeAgency,0)	
			 + (@IBCNetIncomeAddToteFee*ISNULL(t.FeeDue2,0)) netIncome_IBC,

			ISNULL(t.PTWLIBC_PoolCurr,0)
			 + ISNULL(t.commIncomeIBC_PoolCurr,0)
			 - ISNULL(t.commIncomeAgency_PoolCurr,0) 
			 + (@IBCNetIncomeAddToteFee*ISNULL(t.FeeDue2_PoolCurr,0)) netIncome_IBC_PoolCurr,

			ISNULL(t.winTOPartner_origin,0)			winTO_Partner_origin,
			ISNULL(t.placeTOPartner_origin,0)		placeTO_Partner_origin,
			ISNULL(t.winplaceTOPartner_origin,0)	winplaceTO_Partner_origin,
			ISNULL(t.winTOPartner_origin,0)
			 + ISNULL(t.placeTOPartner_origin,0)
			 + ISNULL(t.winplaceTOPartner_origin,0)	totalTO_Partner_Origin,

			ISNULL(t.winTOPartner,0)				winTO_Partner,
			ISNULL(t.placeTOPartner,0)				placeTO_Partner,
			ISNULL(t.winplaceTOPartner,0)			winplaceTO_Partner,
			ISNULL(t.winTOPartner,0) 
			 + ISNULL(t.placeTOPartner,0)
			 + ISNULL(t.winplaceTOPartner,0)		totalTO_Partner,


			ISNULL(t.winTOPartner_PoolCurr,0)		winTO_Partner_PoolCurr,
			ISNULL(t.placeTOPartner_PoolCurr,0)		placeTO_Partner_PoolCurr,
			ISNULL(t.winplaceTOPartner_PoolCurr,0)	winplaceTO_Partner_PoolCurr,
			ISNULL(t.winTOPartner_PoolCurr,0) 
			 + ISNULL(t.placeTOPartner_PoolCurr,0)
			 + ISNULL(t.winplaceTOPartner_PoolCurr,0)			totalTO_Partner_PoolCurr,

			ISNULL(t.dividendWon_origin,0)			dividendWon_origin,				
			ISNULL(t.dividendWon,0)					dividendWon,
			ISNULL(t.dividendWon_PoolCurr,0)		dividendWon_PoolCurr,

			ISNULL(t.winTOPartner_origin,0)
			 + ISNULL(t.placeTOPartner_Origin,0)
			 + ISNULL(t.winplaceTOPartner_Origin,0)
			 + (@AmountDueToAddToteFee*ISNULL(t.FeeDue2_origin,0))
			 - ISNULL(t.dividendWon_origin,0)
			 - ISNULL(t.commIncomeIBC_origin,0)		AmountDue_Origin,

			ISNULL(t.winTOPartner,0)
			 + ISNULL(t.placeTOPartner,0)
			 + ISNULL(t.winplaceTOPartner,0)
			 + (@AmountDueToAddToteFee*ISNULL(t.FeeDue2,0))
			 - ISNULL(t.dividendWon,0)
			 - ISNULL(t.commIncomeIBC,0)			AmountDue,

			ISNULL(t.winTOPartner_PoolCurr,0)
			 + ISNULL(t.placeTOPartner_PoolCurr,0)
			 + ISNULL(t.winplaceTOPartner_PoolCurr,0)
			 + (@AmountDueToAddToteFee*ISNULL(t.FeeDue2_PoolCurr,0))
			 - ISNULL(t.dividendWon_PoolCurr,0)
			 - ISNULL(t.commIncomeIBC_PoolCurr,0)	AmountDue_PoolCurr
		
	FROM 
	(	--Agency ---
		SELECT	cs.partnerID, cs.PartnerName,  b.currency2 PoolCurrency, b.currency, b.currencyName, 
				SUM(CASE WHEN b.bettype =31 THEN b.stake*b.tpositiontaking ELSE 0 END) winTO_Agency_Origin,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*b.tpositiontaking ELSE 0 END) placeTO_Agency_Origin,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking ELSE 0 END) winplaceTO_Agency_Origin,
				SUM(b.scomm) commIncomeAgency_Origin,		
				SUM(b.awinlost + b.mwinlost + b.swinlost) PTWLAgency_Origin,

				SUM(CASE WHEN b.bettype =31 THEN b.stake*b.tpositiontaking*b.actualrate ELSE 0 END) winTO_Agency,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*b.tpositiontaking*b.actualrate ELSE 0 END) placeTO_Agency,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking*b.actualrate ELSE 0 END) winplaceTO_Agency,
				SUM(b.scomm*b.actualrate) commIncomeAgency,
				SUM((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) PTWLAgency,	

				SUM(CASE WHEN b.bettype =31 THEN b.stake*b.tpositiontaking*b.virtualrate ELSE 0 END) winTO_Agency_PoolCurr,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*b.tpositiontaking*b.virtualrate ELSE 0 END) placeTO_Agency_PoolCurr,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking*b.virtualrate ELSE 0 END) winplaceTO_Agency_PoolCurr,
				SUM(b.scomm*b.virtualrate) commIncomeAgency_PoolCurr,
				SUM((b.awinlost + b.mwinlost + b.swinlost)*b.virtualrate) PTWLAgency_PoolCurr,
			
				--IBC --- 
				SUM(CASE WHEN b.bettype =31 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) winTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) placeTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0) ELSE 0 END) winplaceTO_IBC_Origin,

				SUM(CASE WHEN b.bettype =31 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winTO_IBC,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) placeTO_IBC,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winplaceTO_IBC,

				SUM(CASE WHEN b.bettype =31 THEN b.stake*isnull(b.oddsspread,0)*b.virtualrate ELSE 0 END) winTO_IBC_PoolCurr,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*isnull(b.oddsspread,0)*b.virtualrate ELSE 0 END) placeTO_IBC_PoolCurr,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0)*b.virtualrate ELSE 0 END) winplaceTO_IBC_PoolCurr,

				SUM((CASE WHEN b.bettype =33 THEN bm.TOPartner ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee) FeeDue2_origin,
				SUM((CASE WHEN b.bettype =33 THEN bm.TOPartner ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee*b.actualrate ) FeeDue2,
				SUM((CASE WHEN b.bettype =33 THEN bm.TOPartner ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee*b.virtualrate) FeeDue2_PoolCurr,

				SUM(CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END) PTWLIBC_Origin,
				SUM((CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END)*b.actualrate) PTWLIBC,
				SUM((CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END)*b.virtualrate) PTWLIBC_PoolCurr,

				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPartner*cs.ToteCommWP
						 WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						 WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace ELSE 0 END) commIncomeIBC_origin,

				SUM((CASE WHEN b.bettype = 33 THEN bm.TOPartner*cs.ToteCommWP 
						  WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						  WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace ELSE 0 END)*b.actualrate) commIncomeIBC,

				SUM((CASE WHEN b.bettype = 33 THEN bm.TOPartner*cs.ToteCommWP 
						  WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						  WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace ELSE 0 END)*b.virtualrate) commIncomeIBC_PoolCurr,
				--Partner
				SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)winTOPartner_origin,
				SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)placeTOPartner_origin,	
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPartner ELSE 0 END)winplaceTOPartner_origin,

				SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)winTOPartner,
				SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)placeTOPartner,	
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPartner*b.actualrate ELSE 0 END) winplaceTOPartner,

				SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.virtualrate ELSE 0 END)winTOPartner_PoolCurr,
				SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.virtualrate ELSE 0 END)placeTOPartner_PoolCurr,	
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPartner*b.virtualrate ELSE 0 END) winplaceTOPartner_PoolCurr,

				SUM(CASE WHEN b.bettype = 33 THEN bm.DividendWonPartner ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END) DividendWon_Origin,
				SUM((CASE WHEN b.bettype = 33 THEN bm.DividendWonPartner ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0))END)*b.actualrate) DividendWon,
				SUM((CASE WHEN b.bettype = 33 THEN bm.DividendWonPartner ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0))END)*b.virtualrate) DividendWon_PoolCurr

		FROM	bettrans14 b WITH (NOLOCK) 
				INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
				LEFT JOIN (
					SELECT	refno,
							-SUM((winlost - stake)*isnull(oddsspread,0)) PTWLIBC,
							SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOPartner,
							SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE winlost*(1 -tpositiontaking - isnull(oddsspread,0))END) DividendWonPartner
					FROM	bettransm14 WITH (NOLOCK)
					GROUP BY refno
				)bm ON b.transid = bm.refno 
		WHERE	b.ruben = 1 AND 
				b.bettype IN (31,32,33) AND 
				b.winlostdate = @winlostdate AND 
				--b.status NOT IN ('VOID','REJECT','DONE','REFUND')
				b.statusID NOT IN (101,102,103,121)
		GROUP BY cs.PartnerName, cs.partnerID, b.currency2, b.currencyName, b.currency
	) t 
	ORDER BY t.PartnerName, t.PoolCurrency, t.currency
	
END 

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacing_Tote14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacing_Tote14] TO [vnteam]
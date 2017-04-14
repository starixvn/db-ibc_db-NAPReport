ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHR_OpenTote_Details14]
	@winlostdate	DATETIME,
	@partnerType	INT,
	@poolCurrency	INT 
AS
/*	Created by: Jamie
	Date: 2010-04-03
	Task: Horse Racing OpenTote Daily Report by Partner 
	DB: DB06.BODB02
	Revisions:
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20100615@Jamie: Exclude the Fees in Amount Due to
		- 20110301@Johnson: - change to use RacingMeeting instead HorseMeeting table 
							- change parameter's type of @PartnerType from VARCHAR to INT
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @CommSetting TABLE
	(	MatchID int,
		MeetingID int,
		RaceNo varchar(10),
		ToteCommWin smallmoney,
		ToteCommPlace smallmoney,
		ToteCommWP smallmoney,
		ToteFee smallmoney	
	)
	INSERT INTO @CommSetting (
			MatchID, MeetingID, RaceNo,
			ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee
	)
	SELECT	DISTINCT o.orid as matchid, o.leagueID, o.groupmatch,
			p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright14 o WITH (NOLOCK)
			INNER JOIN RacingMeeting m WITH (NOLOCK) ON m.meetingID = o.leagueid
			INNER JOIN RacingPartner r WITH(NOLOCK) ON r.partnerID = m.partnerID
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.MeetingID = p.leagueID 			
	WHERE	o.eventdate = @winlostdate
			AND p.programDate = @winlostdate
			AND m.PartnerID = @PartnerType 
			--AND isnumeric(o.programID) = 1 	

	SELECT	t.currencyName,
			t.currency,
			t.MeetingID,
			t.RaceNo, 
			ISNULL(t.winTO_Agency_Origin,0)			winTO_Agency_Origin,
			ISNULL(t.placeTO_Agency_Origin,0)		placeTO_Agency_Origin,
			ISNULL(t.winplaceTO_Agency_Origin,0)	winplaceTO_Agency_Origin,
			ISNULL(t.winTO_Agency_Origin,0) 
			 + ISNULL(t.placeTO_Agency_Origin,0) 
			 + ISNULL(t.winplaceTO_Agency_Origin,0) totalTOAgency_Origin,
			ISNULL(t.commIncomeAgency_Origin,0)		commIncomeAgency_Origin,
			ISNULL(t.PTWLAgency_Origin,0)			PTWLAgency_Origin,

			ISNULL(t.winTO_Agency,0)				winTO_Agency,
			ISNULL(t.placeTO_Agency,0)				placeTO_Agency,
			ISNULL(t.winplaceTO_Agency,0)			winplaceTO_Agency,
			ISNULL(t.winTO_Agency,0) 
			 + ISNULL(t.placeTO_Agency,0) 
			 + ISNULL(t.winplaceTO_Agency,0)		totalTOAgency,
			ISNULL(t.commIncomeAgency,0)			commIncomeAgency,
			ISNULL(t.PTWLAgency,0)					PTWLAgency,

			ISNULL(t.winTO_Agency_PoolCurr,0)				winTO_Agency_PoolCurr,
			ISNULL(t.placeTO_Agency_PoolCurr,0)				placeTO_Agency_PoolCurr,
			ISNULL(t.winplaceTO_Agency_PoolCurr,0)			winplaceTO_Agency_PoolCurr,
			ISNULL(t.winTO_Agency_PoolCurr,0) 
			 + ISNULL(t.placeTO_Agency_PoolCurr,0) 
			 + ISNULL(t.winplaceTO_Agency_PoolCurr,0)		totalTOAgency_PoolCurr,
			ISNULL(t.commIncomeAgency_PoolCurr,0)			commIncomeAgency_PoolCurr,
			ISNULL(t.PTWLAgency_PoolCurr,0)					PTWLAgency_PoolCurr,

			ISNULL(t.winTO_IBC_Origin,0)			winTO_IBC_Origin,
			ISNULL(t.placeTO_IBC_Origin,0)			placeTO_IBC_Origin,
			ISNULL(t.winplaceTO_IBC_Origin,0)		winplaceTO_IBC_Origin,
			ISNULL(t.winTO_IBC_Origin,0) 
			 + ISNULL(t.placeTO_IBC_Origin,0)
			 + ISNULL(t.winplaceTO_IBC_Origin,0)	totalTOIBC_Origin,

			ISNULL(t.winTO_IBC,0)					winTO_IBC,
			ISNULL(t.placeTO_IBC,0)					placeTO_IBC,
			ISNULL(t.winplaceTO_IBC,0)				winplaceTO_IBC,
			ISNULL(t.winTO_IBC,0)
			 + ISNULL(t.placeTO_IBC,0)	
			 + ISNULL(t.winplaceTO_IBC,0)			totalTOIBC,

			ISNULL(t.winTO_IBC_PoolCurr,0)			winTO_IBC_PoolCurr,
			ISNULL(t.placeTO_IBC_PoolCurr,0)		placeTO_IBC_PoolCurr,
			ISNULL(t.winplaceTO_IBC_PoolCurr,0)		winplaceTO_IBC_PoolCurr,
			ISNULL(t.winTO_IBC_PoolCurr,0)
			 + ISNULL(t.placeTO_IBC_PoolCurr,0)	
			 + ISNULL(t.winplaceTO_IBC_PoolCurr,0)	totalTOIBC_PoolCurr,

			ISNULL(t.FeeDue2_origin,0)				FeeDue2_origin,
			ISNULL(t.FeeDue2,0)						FeeDue2,
			ISNULL(t.FeeDue2_PoolCurr,0)			FeeDue2_PoolCurr,


			ISNULL(t.commIncomeIBC_origin,0)		commIncomeIBC_origin,
			ISNULL(t.commIncomeIBC,0)				commIncomeIBC,
			ISNULL(t.commIncomeIBC_PoolCurr,0)		commIncomeIBC_PoolCurr,

			ISNULL(t.PTWLIBC_origin,0)				PTWLIBC_origin,
			ISNULL(t.PTWLIBC,0)						PTWLIBC,
			ISNULL(t.PTWLIBC_PoolCurr,0)			PTWLIBC_PoolCurr,


			ISNULL(t.PTWLIBC_origin,0)
			 + ISNULL(t.commIncomeIBC_origin,0)
			 - ISNULL(t.commIncomeAgency_Origin,0) 	netIncomeIBC_Origin,

			ISNULL(t.PTWLIBC,0)
			 + ISNULL(t.commIncomeIBC,0)
			 - ISNULL(t.commIncomeAgency,0) 	netIncomeIBC,

			ISNULL(t.PTWLIBC_PoolCurr,0)
			 + ISNULL(t.commIncomeIBC_PoolCurr,0)
			 - ISNULL(t.commIncomeAgency_PoolCurr,0) netIncomeIBC_PoolCurr,

			ISNULL(t.winTOPartner_origin,0)			winTOPartner_origin,
			ISNULL(t.placeTOPartner_origin,0)		placeTOPartner_origin,
			ISNULL(t.winplaceTOPartner_origin,0)	winplaceTOPartner_origin,
			ISNULL(t.winTOPartner_origin,0)
			 + ISNULL(t.placeTOPartner_origin,0)
			 + ISNULL(t.winplaceTOPartner_origin,0)	totalTOPartner_Origin,

			ISNULL(t.winTOPartner,0)				winTOPartner,
			ISNULL(t.placeTOPartner,0)				placeTOPartner,
			ISNULL(t.winplaceTOPartner,0)			winplaceTOPartner,
			ISNULL(t.winTOPartner,0) 
			 + ISNULL(t.placeTOPartner,0)
			 + ISNULL(t.winplaceTOPartner,0)		totalTOPartner,


			ISNULL(t.winTOPartner_PoolCurr,0)		winTOPartner_PoolCurr,
			ISNULL(t.placeTOPartner_PoolCurr,0)		placeTOPartner_PoolCurr,
			ISNULL(t.winplaceTOPartner_PoolCurr,0)	winplaceTOPartner_PoolCurr,
			ISNULL(t.winTOPartner_PoolCurr,0) 
			 + ISNULL(t.placeTOPartner_PoolCurr,0)
			 + ISNULL(t.winplaceTOPartner_PoolCurr,0)			totalTOPartner_PoolCurr,

			ISNULL(t.dividendWon_origin,0)			dividendWon_origin,				
			ISNULL(t.dividendWon,0)					dividendWon,
			ISNULL(t.dividendWon_PoolCurr,0)		dividendWon_PoolCurr,

			ISNULL(t.winTOPartner_origin,0)
			 + ISNULL(t.placeTOPartner_Origin,0)
			 + ISNULL(t.winplaceTOPartner_Origin,0)
			 - ISNULL(t.FeeDue2_origin,0)
			 - ISNULL(t.dividendWon_origin,0)
			 - ISNULL(t.commIncomeIBC_origin,0)		AmountDue_Origin,

			ISNULL(t.winTOPartner,0)
			 + ISNULL(t.placeTOPartner,0)
			 + ISNULL(t.winplaceTOPartner,0)
			 - ISNULL(t.FeeDue2,0)
			 - ISNULL(t.dividendWon,0)
			 - ISNULL(t.commIncomeIBC,0)			AmountDue,

			ISNULL(t.winTOPartner_PoolCurr,0)
			 + ISNULL(t.placeTOPartner_PoolCurr,0)
			 + ISNULL(t.winplaceTOPartner_PoolCurr,0)
			 - ISNULL(t.FeeDue2_PoolCurr,0)
			 - ISNULL(t.dividendWon_PoolCurr,0)
			 - ISNULL(t.commIncomeIBC_PoolCurr,0)	AmountDue_PoolCurr
		
	FROM 
	(	--Agency ---
		SELECT	cs.MeetingID, b.currency, b.currencyName, cs.RaceNo,
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
				--b.status NOT IN ('VOID','REJECT','DONE','REFUND') AND
				b.statusID NOT IN (101,102,103,121) AND 
				b.currency2 = @poolCurrency
		GROUP BY cs.MeetingID, b.currencyName, b.currency, cs.RaceNo
	) t 
	ORDER BY t.currency,t.MeetingID, CAST(t.RaceNo AS TINYINT)
	
END 
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR_OpenTote_Details14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR_OpenTote_Details14] TO [vnteam]
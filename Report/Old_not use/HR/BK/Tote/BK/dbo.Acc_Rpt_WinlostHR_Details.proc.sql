ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHR_Details]
	@winlostdate	datetime
AS
	/*	Creator: Phuong Dao
		Date: 2008-12-01
		Task: Horse Racing Detailed Report
		DB: DB06.BODB02
		
		History:
			- 20090305@PhuongDao: Add one colum for calculating total turnover
			- 20090329@Thien: fix the sorting problem for Race No
			- 20090602@PhuongDao: Report with PT for Tote HR 
				+  FreeDue2 = AmtoteFee + PGIFee with AmtoteFee = 0.0033 PGIFee = 0.005
			- 20090722@Kiwi: Improve peformance by using table variable
			- 20100331@Jamie: arrange the new structure for HR meetings 
				+ Remove hard-code for FeeDue2
			- 20100508@Jamie: exclude OpenTote 
			-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20110224@Johnson: get report for Tote by Partner in RacingMeeting table
			- 20110706@Johnson: exclude test tickets pool currency
	*/

	SET NOCOUNT ON
	--insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @CommSetting TABLE
	(	MatchID int,
		MeetingID int, 
		RaceNO varchar(10), 
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
	FROM	outright o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID 
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON p.leagueid = r.meetingid
	WHERE	o.eventdate = @winlostdate AND p.programDate = @winlostdate --AND isnumeric(o.programID) = 0 
			AND r.partnerID = 1 -- RACE-PHU
	
	SELECT	t.currencyName,
			t.currency,
			t.meetingID leagueid, 
			t.raceNO groupmatch,
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
			ISNULL(t.FeeDue2_origin,0)				FeeDue2_origin,
			ISNULL(t.FeeDue2,0)						FeeDue2,
			ISNULL(t.commIncomeIBC_origin,0)		commIncomeIBC_origin,
			ISNULL(t.commIncomeIBC,0)				commIncomeIBC,
			ISNULL(t.PTWLIBC_origin,0)				PTWLIBC_origin,
			ISNULL(t.PTWLIBC,0)						PTWLIBC,
			ISNULL(t.PTWLIBC_origin,0)
			 + ISNULL(t.commIncomeIBC_origin,0)
			 - ISNULL(t.commIncomeAgency_Origin,0)
			 - ISNULL(t.FeeDue2_origin,0)		 	netIncomeIBC_Origin,
			ISNULL(t.PTWLIBC,0)
			 + ISNULL(t.commIncomeIBC,0)
			 - ISNULL(t.commIncomeAgency,0)
			 - ISNULL(t.FeeDue2,0)					netIncomeIBC,
			ISNULL(t.winTOPhum_origin,0)			winTOPhum_origin,
			ISNULL(t.placeTOPhum_origin,0)			placeTOPhum_origin,
			ISNULL(t.winplaceTOPhum_origin,0)		winplaceTOPhum_origin,
			ISNULL(t.winTOPhum_origin,0)
			 + ISNULL(t.placeTOPhum_origin,0)
			 + ISNULL(t.winplaceTOPhum_origin,0)	totalTOPhum_Origin,
			ISNULL(t.winTOPhum,0)					winTOPhum,
			ISNULL(t.placeTOPhum,0)					placeTOPhum,
			ISNULL(t.winplaceTOPhum,0)				winplaceTOPhum,
			ISNULL(t.winTOPhum,0) 
			 + ISNULL(t.placeTOPhum,0)
			 + ISNULL(t.winplaceTOPhum,0)			totalTOPhum,
			ISNULL(t.dividendWon_origin,0)			dividendWon_origin,				
			ISNULL(t.dividendWon,0)					dividendWon,
			ISNULL(t.winTOPhum_origin,0)
			 + ISNULL(t.placeTOPhum_Origin,0)
			 + ISNULL(t.winplaceTOPhum_Origin,0)
			 + ISNULL(t.FeeDue2_origin,0)
			 - ISNULL(t.dividendWon_origin,0)
			 - ISNULL(t.commIncomeIBC_origin,0)		AmountDue_Origin,
			ISNULL(t.winTOPhum,0)
			 + ISNULL(t.placeTOPhum,0)
			 + ISNULL(t.winplaceTOPhum,0)
			 + ISNULL(t.FeeDue2,0)
			 - ISNULL(t.dividendWon,0)
			 - ISNULL(t.commIncomeIBC,0)			AmountDue
		
	FROM 
	(	--Agency ---
		SELECT	b.currency, cs.meetingID, cs.RaceNo, b.currencyName, 
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
			
				--IBC --- 
				SUM(CASE WHEN b.bettype =31 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) winTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) placeTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0) ELSE 0 END) winplaceTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =31 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winTO_IBC,
				SUM(CASE WHEN b.bettype =32 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) placeTO_IBC,
				SUM(CASE WHEN b.bettype =33 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winplaceTO_IBC,
				SUM((CASE WHEN b.bettype =33 THEN bm.TOPhum ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee) FeeDue2_origin,
				SUM((CASE WHEN b.bettype =33 THEN bm.TOPhum ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee*b.actualrate ) FeeDue2,
				SUM(CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END) PTWLIBC_Origin,
				SUM((CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END)*b.actualrate) PTWLIBC,
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPhum*cs.ToteCommWP
						 WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						 WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace ELSE 0 END) commIncomeIBC_origin,
				SUM((CASE WHEN b.bettype = 33 THEN bm.TOPhum*cs.ToteCommWP 
						  WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						  WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace ELSE 0 END)*b.actualrate) commIncomeIBC,
				--Phum
				SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)winTOPhum_origin,
				SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)placeTOPhum_origin,	
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPhum ELSE 0 END)winplaceTOPhum_origin,
				SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)winTOPhum,
				SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)placeTOPhum,	
				SUM(CASE WHEN b.bettype = 33 THEN bm.TOPhum*b.actualrate ELSE 0 END) winplaceTOPhum,
				SUM(CASE WHEN b.bettype = 33 THEN bm.DividendWonPhum ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END) DividendWon_Origin,
				SUM((CASE WHEN b.bettype = 33 THEN bm.DividendWonPhum ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0))END)*b.actualrate) DividendWon

		FROM	bettrans b WITH (NOLOCK) 
				INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
				LEFT JOIN (
					SELECT	refno,
							-SUM((winlost - stake)*isnull(oddsspread,0)) PTWLIBC,
							SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOPhum,
							SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE winlost*(1 -tpositiontaking - isnull(oddsspread,0))END) DividendWonPhum
					FROM	bettransm WITH (NOLOCK)
					GROUP BY refno
				)bm ON b.transid = bm.refno 
		WHERE	b.ruben = 1 AND 
				b.bettype IN (31,32,33) AND 
				b.winlostdate = @winlostdate AND 
				b.currency2 IS NULL AND 
				--b.status NOT IN ('VOID','REJECT','DONE','REFUND')
				b.statusID NOT IN (101,102,103,121)
		GROUP BY b.currencyName, b.currency, cs.meetingID, cs.raceNo
	) t 
	ORDER BY t.currency, t.meetingID, CAST(t.raceNO AS TINYINT)

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR_Details] TO [VNTeam]
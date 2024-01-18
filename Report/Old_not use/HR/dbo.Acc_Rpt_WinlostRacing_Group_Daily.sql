ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacing_Group_Daily]
	@winlostdate	datetime
AS 
/*
	Created by: Henry
	Date: 20100506
	Task: Group Horse Racing Report
	DB: DB06.BODB02
	Original: [Acc_Rpt_WinlostHR_Group_Daily]

	History:
		- 20100506@Henry: Copy from Acc_Rpt_WinlostHR_Group_Daily + exclude istest=1 out of the report
		- 20100508@Henry: Define partner
			+ 1: PHU
			+ 2: RUK
			+ 3: ATR
			+ 4: ATRIRE
			+ 5: AUS
		- 20100508@Henry: Remove the restriction of the betting currency of 12BET (fully allow all currency)
		- 20100508@Jamie: Change to call f_DepSuper_1 instead of f_DepSuperAllowedHR
		- 20100527@Jamie: Add one more section for Partner [DividendWon, Expense Comm, Fees]
			Amount Due to: PHU: include Fees and Others Partner exclude Fees 
		- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20101112@Henry: Add partner ATRIRE
		- 20110115@Amy: Not exclude fees of I-Neda's meetings to IBC Net Comm
		- 20110304@Johnson: - use RacingMeeting instead HorseMeeting
							- get partnerID from RacingMeeting instead use HRType
		- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight 
		- 20111226@Jamie: Change the Amount Due To for Greyhound UK/Irish 

	Explanation's Param:
		- AmountDueToPartner: 
			+ HR For UK/Irish: Minus Tote Fee ( -ToteFee)
			+ Greyhound for UK/Irish: Not Including ToteFee (0)
			+ Others: Plus ToteFee ( + ToteFee)


*/
BEGIN
	SET NOCOUNT ON 
	--insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @CommSetting TABLE
	(	
		PartnerID int,
		PartnerName		varchar(50),
		MatchID			int,
		ToteCommWin		smallmoney,
		ToteCommPlace	smallmoney,
		ToteCommWP		smallmoney,
		ToteFee			smallmoney	
	)
	INSERT INTO @CommSetting (PartnerID,PartnerName,MatchID, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
	SELECT	DISTINCT  --CASE isnumeric(o.programID) WHEN 0 THEN 1 ELSE (CASE m.partnerType WHEN 'RUK' THEN 2 WHEN 'ATR' THEN 3 WHEN 'ATRIRE' THEN 4 WHEN 'AUS' THEN 5 END) END AS PartnerType,
			r.partnerID , r.PartnerName, o.orid as matchid, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee  
	FROM	outright o WITH (NOLOCK)
			INNER JOIN RacingMeeting m WITH (NOLOCK) ON o.leagueID = m.MeetingID 
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.meetingID = p.leagueID AND p.programDate = o.programDate
			INNER JOIN RacingPartner r WITH(NOLOCK) ON m.partnerID = r.partnerID
	WHERE	o.eventdate = @winlostdate 
	
	SELECT	t1.winlostdate,
			t1.PartnerName ,			
			ISNULL(t1.TOAgents,0)				turnoverAgents,
			ISNULL(t1.TOIBC,0)					turnoverHouse,--turnoverIBC-> turnoverHouse
			ISNULL(t1.TOAgents,0)
			 + ISNULL(t1.TOIBC,0)	
			 + ISNULL(t1.TO3rd,0)				totalTurnover, --IBC + Agents + Partner
			ISNULL(t1.incomeIBCPT,0)			incomeHousePT, --incomeIBCPT -> incomeHousePT
			ISNULL(t1.incomeIBCNetComm,0)		incomeHouseNetComm, -- incomeIBCNetComm -> incomeHouseNetComm
			ISNULL(t1.incomeIBCPT,0)
			 + ISNULL(t1.incomeIBCNetComm,0)	totalHouseIncome, -- totalIBCIncome -> totalHouseIncome
			ISNULL(t2.income12BETPT,0)			income12BETPT,
			ISNULL(t2.income12BETComm,0)		income12BETComm,
			ISNULL(t2.income12BETPT,0)
			 + ISNULL(t2.income12BETComm,0)		total12BETIncome,
			ISNULL(t1.incomeIBCPT,0)
			 + ISNULL(t1.incomeIBCNetComm,0)
			 + ISNULL(t2.income12BETPT,0)
			 + ISNULL(t2.income12BETComm,0)		groupTotalIncome,
			ISNULL(t1.TO3rd,0)					turnover3rd,
			ISNULL(t1.DividendWon3rd,0)			DividendWon3rd,
			ISNULL(t1.ExpComm3rd,0)				ExpComm3rd,
			ISNULL(t1.Fees3rd,0)				Fees3rd,
			ISNULL(t1.TO3rd,0)
			 - ISNULL(t1.DividendWon3rd,0)
			 - ISNULL(t1.ExpComm3rd,0)
			 + (CASE	WHEN t1.PartnerID IN (2,3,4) THEN -ISNULL(t1.Fees3rd,0) -- HR for UK/Irish: -- RACE-ATRUK ,RACE-ATRIRL ,RACE-RUK
						WHEN t1.PartnerID IN (101,102) THEN 0					-- Greyhound for UK/Irish: GREY-DTOTEUK, GREY-DTOTEIRL
						ELSE ISNULL(t1.Fees3rd,0) END) AmountDue23rd			-- Others
	FROM 
	(	SELECT	b.winlostdate,
				cs.PartnerID,
				cs.PartnerName,				
				--Turnover 
				SUM((CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking*b.actualrate) TOAgents,
				SUM((CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0)*b.actualrate ) TOIBC,
				SUM(CASE WHEN b.bettype = 33 THEN bm.TO3rd*b.actualrate 
						 ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate END) TO3rd,

				--IBC Income 
				SUM((CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END)*b.actualrate) incomeIBCPT,				
				SUM((CASE WHEN b.bettype = 33 THEN bm.TO3rd*cs.ToteCommWP 
						  WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
						  WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace 
						  ELSE 0 END)*b.actualrate )
				- SUM(b.scomm*b.actualrate) 
				- SUM(CASE WHEN cs.PartnerID IN (2,3,4) THEN 0
						ELSE (CASE WHEN b.bettype = 33 THEN bm.TO3rd WHEN bettype IN (31,32) THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)*cs.ToteFee*b.actualrate END) incomeIBCNetComm,
				-- 3rd party
				SUM((CASE WHEN b.bettype = 33 THEN bm.DividendWon3rd ELSE b.winlost*(1 - tpositiontaking - isnull(b.oddsspread,0)) END)*b.actualrate) DividendWon3rd,
				SUM((CASE WHEN b.bettype = 33 THEN bm.TO3rd*cs.ToteCommWP 
					  WHEN b.bettype = 31 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommWin 
					  WHEN b.bettype = 32 THEN b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))*cs.ToteCommPlace 
					  ELSE 0 END)*b.actualrate ) ExpComm3rd,
				SUM((CASE WHEN b.bettype =33 THEN bm.TO3rd ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END)*cs.ToteFee*b.actualrate ) Fees3rd
						
		FROM	bettrans b WITH (NOLOCK) 
				INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
				LEFT JOIN (
					SELECT	refno,
							-SUM((winlost - stake)*isnull(oddsspread,0)) PTWLIBC,
							SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 WHEN bettype = 31 OR (bettype = 32 AND liveawayscore <> 0) THEN stake*(1 -tpositiontaking - isnull(oddsspread,0)) ELSE 0 END) TO3rd,
							SUM(CASE WHEN bettype = 32 AND liveawayscore =0 THEN 0 ELSE winlost*(1-tpositiontaking - isnull(oddsspread,0)) END) DividendWon3rd									
					FROM	bettransm WITH (NOLOCK)
					GROUP BY refno
				)bm ON b.transid = bm.refno 
				
		WHERE	b.ruben = 1 AND 
				b.bettype IN (31,32,33) AND 
				b.winlostdate = @winlostdate AND 
				--b.status NOT IN ('VOID','REJECT','DONE','REFUND')
				b.statusID NOT IN (101,102,103,121)
		GROUP BY b.winlostdate  , cs.PartnerID ,cs.PartnerName
	) t1 
	LEFT JOIN (
		-- 12BET 
		SELECT	b.winlostdate, cs.partnerID, 
				SUM((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) income12BETPT,
				SUM(b.scomm*b.actualrate) income12BETComm
		FROM	bettrans b WITH (NOLOCK) 
				INNER JOIN @CommSetting cs ON b.matchid = cs.matchid
		WHERE	b.winlostdate = @winlostdate AND 
				b.bettype in (31,32,33) AND 
				--b.status not in ('VOID','REJECT','DONE','Refund') AND 
				b.statusID NOT IN (101,102,103,121) AND
				b.ruben = 1 AND 
				b.srecommend in (SELECT custid FROM f_DepSuper_1('12BET'))
		GROUP BY b.winlostdate, cs.partnerID					
	) t2 ON t1.winlostdate = t2.winlostdate AND t1.partnerID = t2.partnerID 
	ORDER BY t1.winlostdate, t1.partnerName 
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacing_Group_Daily] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacing_Group_Daily] TO [VNTeam]


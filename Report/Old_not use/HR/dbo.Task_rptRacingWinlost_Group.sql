ALTER PROCEDURE [dbo].[Task_rptRacingWinlost_Group]
	@winlostdate	datetime
AS
/*
	Created by: Jamie
	Date: 2009-06-30
	Task: Group Racing Report
	DB: DB06.BODB02	
	Original: [Task_rptHRWinlost_Group]

	History:
		- 20100505@Henry: Copy from Task_rptHRWinlost_Group + exclude istest=1 out of the report. This is run at 15/May/2010
		- 20100508@Jamie: Change to call f_DepSuper_1 instead of f_DepSuperAllowedHR
		- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20100527@Jamie: Add one more section for Partner [DividendWon, Expense Comm, Fees]
		- 20101112@Henry: Add partner ATRIRE
		- 20110115@Amy: Not exclude fees of I-Neda's meetings to IBC Net Comm
		- 20110303@Johnson: - Include Greyhound, Harness racing
							- insert parnerID from RacingPartner table to rptRacingWinlost
							- IBCNetComm exclude Tote's fees from AU meeting		
		- 20110705@Johnson: change the programdate in LeagueDetail is the programdate in OutRight			

*/
BEGIN
	SET NOCOUNT ON

	IF EXISTS(SELECT 1 FROM bettrans WITH (NOLOCK) WHERE winlostdate = @winlostdate AND bettype in (31,32,33))
	BEGIN

		--remove row if exists
		IF EXISTS(SELECT 1 FROM bodb_Report.dbo.rptRacingWinlost WITH (NOLOCK) WHERE winlostdate = @winlostdate)
		BEGIN
			delete from bodb_Report.dbo.rptRacingWinlost where winlostdate = @winlostdate
		END

	--insert company's comm setting that is recieved from Phumelela into this temp table.
		DECLARE @CommSetting TABLE
		(	PartnerID		smallint,
			MatchID			int,
			ToteCommWin		smallmoney,
			ToteCommPlace	smallmoney,
			ToteCommWP		smallmoney,
			ToteFee			smallmoney
		)
		INSERT INTO @CommSetting (PartnerID, MatchID, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
		SELECT DISTINCT --CASE isnumeric(o.programID) WHEN 0 THEN 1 ELSE (CASE m.partnerType WHEN 'RUK' THEN 2 WHEN 'ATR' THEN 3 WHEN 'ATRIRE' THEN 4  ELSE 5 END) END ,
				m.partnerID,o.orid as matchid, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee
		FROM	outright o WITH (NOLOCK)
				INNER JOIN RacingMeeting m WITH (NOLOCK) ON o.leagueID = m.MeetingID 				
				INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.meetingID = p.leagueID AND p.programDate = o.programDate
		WHERE	o.eventdate = @winlostdate 

		INSERT INTO bodb_Report.dbo.rptRacingWinlost(	winlostdate, 
													PartnerID, --HRType
													turnoverAgents, 
													turnoverHouse, 
													turnover3rd, 
													incomeHousePT, 
													incomeHouseNetComm, 
													income12BETPT, 
													income12BETComm,
													DividendWon3rd,
													ExpComm3rd,
													Fees3rd
												)
		
		SELECT	t1.winlostdate,
				t1.partnerID PartnerID,
				ISNULL(t1.TOAgents,0)				turnoverAgents,
				ISNULL(t1.TOIBC,0)					turnoverHouse,
				ISNULL(t1.TO3rd,0)					turnover3rd,
				ISNULL(t1.incomeIBCPT,0)			incomeHousePT,
				ISNULL(t1.incomeIBCNetComm,0)		incomeHouseNetComm,
				ISNULL(t2.income12BETPT,0)			income12BETPT,
				ISNULL(t2.income12BETComm,0)		income12BETComm,
				ISNULL(t1.DividendWon3rd,0)			dividendWon3rd,
				ISNULL(t1.ExpComm3rd,0)				ExpComm3rd,
				ISNULL(t1.Fees3rd,0)				Fees3rd
		FROM 
		(	SELECT	b.winlostdate, cs.partnerID,
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
					- SUM(CASE WHEN cs.partnerID IN (2,3,4) THEN 0--RACE-ATRUK, RACE-ATRIRL, RACE-RUK  <> 1 THEN 0
							ELSE(CASE WHEN b.bettype = 33 THEN bm.TO3rd WHEN bettype IN (31,32) THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)*cs.ToteFee*b.actualrate END) incomeIBCNetComm,
					--3rd party 
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
			GROUP BY b.winlostdate, cs.partnerID
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
		) t2 ON t1.winlostdate = t2.winlostdate  AND t1.partnerID = t2.partnerID 
		ORDER BY t1.winlostdate, t1.partnerID
	END
END
GO
GRANT EXECUTE ON [dbo].[Task_rptRacingWinlost_Group] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_rptRacingWinlost_Group] TO [vnteam]
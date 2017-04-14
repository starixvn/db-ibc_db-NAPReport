ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacingLicensee_Details14]
	@winlostdate	DATETIME,
	@site			VARCHAR(50) = ''
	
AS 
/*
	Created by: Johnson
	Date: 2011-04-14
	Task: Racing Detailed Report 
	DB: DB06.BODB02
	
	Revisions:
		- 20110721@Johnson: Add Licensee winlost
		- 20120326@Johnson: Include IBC win/loss
	Param's Explanation:
		- @site : Licensee's Site
*/
BEGIN
	SET NOCOUNT ON 
	
	DECLARE @CommSetting TABLE
	(	MatchID int,	
		leagueid int,
		groupmatch varchar(100),	
		IBCCommIncomeAddToteFee INT, -- IBC Comm Income add Tote Fee or not 
									     -- [0]: Not include Tote Fee; [1]: Plus Tote Fee; [-1]: Minus Tote Fee 
		ToteCommWin smallmoney,
		ToteCommPlace smallmoney,
		ToteCommWP smallmoney,
		ToteFee smallmoney	
	)
	
	INSERT INTO @CommSetting (
			MatchID,leagueid,groupmatch,IBCCommIncomeAddToteFee,ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee
	)
	SELECT	DISTINCT o.orid as matchid, o.leagueid,	o.groupmatch,
				CASE WHEN m.partnerID IN (2,3,4) THEN 0 ELSE -1 END,
				p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright14 o WITH (NOLOCK)
			INNER JOIN RacingMeeting m WITH (NOLOCK) ON m.meetingID = o.leagueid 
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.MeetingID = p.leagueID and p.programDate = o.programDate	 
	WHERE	o.eventdate = @winlostdate 
	
	SELECT	currencyName,
			currency,
			leagueid,
			groupmatch,
			ISNULL(hr.winTOMem_Origin,0)			winTOMem_Origin,
			ISNULL(hr.winTOMem,0)					winTOMem,
			ISNULL(hr.placeTOMem_Origin,0)			placeTOMem_Origin,
			ISNULL(hr.placeTOMem,0)					placeTOMem,
			ISNULL(hr.winplaceTOMem_Origin,0)		winplaceTOMem_Origin,
			ISNULL(hr.winplaceTOMem,0)				winplaceTOMem,
			ISNULL(hr.winTOMem_Origin,0) 
			  + ISNULL(hr.placeTOMem_Origin,0)
			  + ISNULL(hr.winplaceTOMem_Origin,0)	totalTOMem_Origin,
			ISNULL(hr.winTOMem,0)
			  + ISNULL(hr.placeTOMem,0)
			  + ISNULL(hr.winplaceTOMem,0)			totalTOMem,			
			  
			ISNULL(hr.DividendWonMem_Origin,0)		DividendWonMem_Origin,	
			ISNULL(hr.DividendWonMem,0)				DividendWonMem,	
			
			ISNULL(hr.winTOLicensee_Origin,0)		winTOLicensee_Origin,
			ISNULL(hr.winTOLicensee,0)				winTOLicensee,
			ISNULL(hr.placeTOLicensee_Origin,0)		placeTOLicensee_Origin,
			ISNULL(hr.placeTOLicensee,0)			placeTOLicensee,
			ISNULL(hr.winplaceTOLicensee_Origin,0)	winplaceTOLicensee_Origin,
			ISNULL(hr.winplaceTOLicensee,0)			winplaceTOLicensee,
			ISNULL(hr.winTOLicensee_Origin,0)
				+ ISNULL(hr.placeTOLicensee_Origin,0)
				+ ISNULL(hr.winplaceTOLicensee_Origin,0) totalTOLicensee_Origin,
			ISNULL(hr.winTOLicensee,0)
				+ ISNULL(hr.placeTOLicensee,0)
				+ ISNULL(hr.winplaceTOLicensee,0)	totalTOLicensee,
				
			ISNULL(PTWLLicensee_Origin,0)			PTWLLicensee_Origin,
			ISNULL(PTWLLicensee,0)					PTWLLicensee,	
			
			ISNULL(hr.commIncomeLicensee_Origin,0)	commIncomeLicensee_Origin,		
			ISNULL(hr.commIncomeLicensee,0)			commIncomeLicensee,
			
			ISNULL(hr.PTWLIBC_Origin,0) PTWLIBC_Origin,
			ISNULL(hr.PTWLIBC,0) PTWLIBC,
			
			ISNULL(hr.CommIncomeIBC_Origin,0) CommIncomeIBC_Origin,
			ISNULL(hr.CommIncomeIBC,0) CommIncomeIBC,
			
			ISNULL(hr.winTOMem_Origin,0)
			  + ISNULL(hr.placeTOMem_Origin,0)
			  + ISNULL(hr.winplaceTOMem_Origin,0)
			  - ISNULL(hr.DividendWonMem_Origin,0)
			  - ISNULL(hr.PTWLLicensee_Origin,0)
			  - ISNULL(hr.commIncomeLicensee_Origin,0) AmountDue2IBC_Origin,
 			ISNULL(hr.winTOMem,0)
			  + ISNULL(hr.placeTOMem,0)
			  + ISNULL(hr.winplaceTOMem,0)
			  - ISNULL(hr.DividendWonMem,0)
			  - ISNULL(hr.PTWLLicensee,0)
			  - ISNULL(hr.commIncomeLicensee,0)		AmountDue2IBC	

	FROM (
			SELECT	cs.leagueid,
					cs.groupmatch,
					b.currency,
					b.currencyName,
					-- Turnover Member 
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake ELSE 0 END) winTOMem_Origin,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake ELSE 0 END) placeTOMem_Origin,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END) ELSE 0 END) winplaceTOMem_Origin,
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.actualrate ELSE 0 END) winTOMem,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.actualrate ELSE 0 END) placeTOMem,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.actualrate ELSE 0 END) winplaceTOMem,
					-- DividendWon Member 
					SUM(CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost -b.actual_stake/2 ELSE b.winlost END) DividendWonMem_Origin,
					SUM(CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN (b.winlost -b.actual_stake/2)*b.actualrate ELSE b.winlost*b.actualrate END) DividendWonMem,
					
					--Turnover Licensee
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.tpositiontaking ELSE 0 END) winTOLicensee_Origin,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.tpositiontaking ELSE 0 END) placeTOLicensee_Origin,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE WHEN b.liveawayscore = 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.tpositiontaking ELSE 0 END) winplaceTOLicensee_Origin,
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.tpositiontaking*b.actualrate ELSE 0 END) winTOLicensee,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.tpositiontaking*b.actualrate ELSE 0 END) placeTOLicensee,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE WHEN b.liveawayscore = 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.tpositiontaking*b.actualrate ELSE 0 END) winplaceTOLicensee,
					
					-- commission Licensee 	
					SUM(b.comm - b.playercomm) commIncomeLicensee_Origin,
					SUM((b.comm - b.playercomm)*b.actualrate) commIncomeLicensee,
					
					--PT Winloss Licensee 
					SUM(b.awinlost + b.mwinlost + b.swinlost) PTWLLicensee_Origin,
					SUM((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) PTWLLicensee,
					
					--PT Winloss of IBC	
					SUM(CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost - b.actual_stake)*(-ISNULL(b.oddsspread,0)) END) PTWLIBC_Origin,
					SUM((CASE WHEN b.bettype = 33 THEN bm.PTWLIBC ELSE (b.winlost - b.actual_stake)*(-ISNULL(b.oddsspread,0)) END )*b.actualrate) PTWLIBC,
					
					--Commission IBC
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*(1- b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommWin + cs.ToteFee*cs.IBCCommIncomeAddToteFee)
							WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommPlace + cs.ToteFee*cs.IBCCommIncomeAddToteFee)
							WHEN b.bettype = 33 THEN bm.TOPartner*((cs.ToteCommWin + cs.ToteCommPlace)/2 + cs.ToteFee*cs.IBCCommIncomeAddToteFee) 
						ELSE 0 END - b.scomm
					) CommIncomeIBC_Origin,
					SUM((CASE WHEN b.bettype = 31 THEN b.actual_stake*(1- b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommWin + cs.ToteFee*cs.IBCCommIncomeAddToteFee)
							WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommPlace + cs.ToteFee*cs.IBCCommIncomeAddToteFee)
							WHEN b.bettype = 33 THEN bm.TOPartner*((cs.ToteCommWin + cs.ToteCommPlace)/2 + cs.ToteFee*cs.IBCCommIncomeAddToteFee) 
						ELSE 0 END - b.scomm)*actualrate
					) CommIncomeIBC
							
			FROM	bettrans14 b WITH (NOLOCK,INDEX(IX_bettrans14)) 
					INNER JOIN @CommSetting cs ON b.matchid = cs.matchid
					LEFT JOIN (SELECT refno, 
									-SUM((winlost - stake)*isnull(oddsspread,0)) PTWLIBC,
									SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOPartner
								FROM bettransm14 bm WITH(NOLOCK) 
								GROUP BY refno
								) bm ON b.transid = bm.refno
			WHERE	b.winlostdate = @winlostdate 
					AND b.bettype in (31,32,33)
					--AND b.status not in ('VOID','REJECT','DONE','Refund')
					AND b.statusID NOT IN (101,102,103,121)
					AND b.ruben = 1
					AND b.srecommend  in (SELECT custid FROM f_DepSuper_1(@site))
			GROUP BY cs.leagueid, cs.groupmatch, b.currency, b.currencyName					  		
	)hr
	ORDER BY currencyName, leagueid, CAST (groupmatch AS TINYINT)
END
GO


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_Details14] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_Details14] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacingLicensee_Details14] TO [vnteam]


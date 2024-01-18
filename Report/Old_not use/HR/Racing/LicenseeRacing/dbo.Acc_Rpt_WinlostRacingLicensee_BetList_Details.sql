ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacingLicensee_BetList_Details]
	@leagueid		INT,
	@raceNo			VARCHAR(10), 
	@currency		INT,
	@winlostdate	DATETIME,
	@site			varchar(50)
AS
/*
	Created by: Johnson
	Date: 2011-04-14
	Task: Racing Detailed Bet List
	DB: DB06.BODB02

	Revisions:
		- 20110711@Johnson: show exchange rate for SA Tote(Pool Currency)
		- 20110721@Johnson: Add Licensee winlost
		- 20120327@Johnson: Include IBC win/loss
	Param's Explanation:
		+ @site: Licensee's Site 
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @str_compare varchar (30)
	
	SELECT @str_compare = @site + '$'
	
	DECLARE @CommSetting TABLE
	(	MatchID int,	
		teamid int,
		matchcode varchar(100),	
		IBCCommIncomeAddToteFee INT, -- IBC Comm Income add Tote Fee or not 
									     -- [0]: Not include Tote Fee; [1]: Plus Tote Fee; [-1]: Minus Tote Fee 
		ToteCommWin smallmoney,
		ToteCommPlace smallmoney,
		ToteCommWP smallmoney,
		ToteFee smallmoney	
	)
	
	INSERT INTO @CommSetting (
			MatchID,teamid,matchcode,IBCCommIncomeAddToteFee,ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee
	)
	SELECT	o.orid as matchid, o.teamid, o.matchcode,
				CASE WHEN m.partnerID IN (2,3,4) THEN 0 ELSE -1 END,
				p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright o WITH (NOLOCK)
			INNER JOIN RacingMeeting m WITH (NOLOCK) ON m.meetingID = o.leagueid 
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON m.MeetingID = p.leagueID and p.programDate = o.programDate	 
	WHERE	o.eventdate = @winlostdate 
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
	
		
	SELECT	b.username,
			REPLACE(c.username2, @str_compare, '') username2,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,			
			b.stake,
			(b.winlost - b.actual_stake) winlost,
			(b.awinlost + b.mwinlost + b.swinlost) AS WLPTLicensee,
			(b.winlost - b.actual_stake)*(-ISNULL(b.oddsspread,0)) as WLPTIBC,
			CASE WHEN b.bettype = 31 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0))*(cs.ToteCommWin + cs.IBCCommIncomeAddToteFee*cs.ToteFee) - b.scomm
				WHEN b.bettype = 32 THEN b.actual_stake*(1 - b.tpositiontaking - ISNULL(b.oddsspread,0)) * (cs.ToteCommPlace + cs.IBCCommIncomeAddToteFee*cs.ToteFee)- b.scomm
				WHEN b.bettype = 33 THEN bm.TOPartner*((cs.ToteCommWin + cs.ToteCommPlace)/2 + cs.IBCCommIncomeAddToteFee*cs.ToteFee) - b.scomm END as CommIncomeIBC, 
			b.playercomm,
			CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END dividend,
			(b.comm - b.playercomm) AS commIncomeLicensee,
			CASE b.livehomescore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE '' END winStatus,
			CASE b.liveawayscore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE 'Refund' END placeStatus,
			b.status,
			cs.teamid, 
			cs.matchcode,
			b.virtualrate,
			--isnumeric(o.programID) isShowOTExRate
			CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END AS isShowOTExRate
	FROM	bettrans b (NOLOCK)
			INNER JOIN @CommSetting cs ON b.matchid = cs.matchid
			LEFT JOIN (
					SELECT refno,						
						SUM(CASE WHEN bettype = 32 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOPartner								
					FROM bettransm WITH(NOLOCK)
					GROUP BY refno
				) bm ON b.transid = bm.refno
			INNER JOIN customer c (NOLOCK) ON b.custid = c.custid
	WHERE	b.ruben = 1 
			AND b.bettype in (31,32,33) 
			--AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.statusID NOT IN (101,102,103,121)
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate			
			AND b.srecommend in (SELECT custid FROM f_DepSuper_1(@site))
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_BetList_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_BetList_Details] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacingLicensee_BetList_Details] TO [VNTeam]
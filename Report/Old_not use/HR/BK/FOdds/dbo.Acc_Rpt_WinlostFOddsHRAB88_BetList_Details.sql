 ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFOddsHRAB88_BetList_Details]
	@leagueid		INT,
	@raceNo			VARCHAR(10), 
	@currency		INT,
	@winlostdate	DATETIME
AS
/*
	Created by: Jamie
	Date: 2009-09-29
	Task: AsiaBet88 Fixed Odds Horse Racing Detailed Bet List
	DB: DB06.BODB02, DB02.BODB02	

	Revisions:
		- 20091008@Jamie: Get the supers allowed to bet HR from the function
		- 20091023@Simon: Displays Odds at Bet/Settle time
	Param's Explanation:
		+ AB88 HR Agent: PT = 0 , Comm = 4% 
*/

BEGIN
	SET NOCOUNT ON
	SELECT	b.username,
			REPLACE(c.username2, 'asiabet88$', '') username2,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,		
			b.modds,
			bmOdd.finalodds,
			bmOdd.finalodds2,		
			b.stake,
			(b.winlost - b.actual_stake) winlost,
			b.playercomm,
			CASE WHEN b.bettype = 43 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END dividend,
			b.scomm commIncomeAgency,
			CASE b.livehomescore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE '' END winStatus,
			CASE b.liveawayscore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE 'Refund' END placeStatus,
			b.status,
			o.teamid, 
			o.matchcode
	FROM	bettrans b (NOLOCK)
			INNER JOIN outright o (NOLOCK) ON b.matchid = o.orid 
			INNER JOIN customer c (NOLOCK) ON b.custid = c.custid
			LEFT JOIN (			
				SELECT	t.refno, t.finalodds, f.finalodds finalodds2
				FROM	bettransm t WITH (NOLOCK)
						INNER JOIN bettransm f WITH (NOLOCK) ON t.refno = f.refno 
				WHERE	t.bettype = 41 AND f.bettype = 42
			)bmOdd on b.transid = bmOdd.refno 
	WHERE	b.ruben = 1 
			AND b.bettype in (41,42,43) 
			AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
			AND b.srecommend in (SELECT custid FROM f_DepSuperAllowedHR('Asiabet88'))
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHRAB88_BetList_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHRAB88_BetList_Details] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFOddsHRAB88_BetList_Details] TO [VNTeam]
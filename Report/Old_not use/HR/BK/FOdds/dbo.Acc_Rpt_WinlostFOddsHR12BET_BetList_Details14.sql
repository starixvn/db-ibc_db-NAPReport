ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFOddsHR12BET_BetList_Details14]
	@leagueid		INT,
	@raceNo			VARCHAR(10), 
	@currency		INT,
	@winlostdate	DATETIME
AS
/*
	Created by: Jamie
	Date: 2009-08-15
	Task: 12BET Fixed Odds Horse Racing Detailed bet list History
	DB: DB06.BODB02

	History:
		- 20091008@Jamie: Get the list of supers from the function			
		- 20091023@Simon: Displays Odds at Bet/Settle time
	Explanation's Param:
	
*/
BEGIN
	SET NOCOUNT ON

	SELECT	b.username,
			replace(c.username2, '12bet$', '') as username2,
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
			(b.winlost - b.actual_stake) as winlost,
			b.playercomm,
			(b.awinlost + b.mwinlost + b.swinlost) as WLPTAgency,
			CASE WHEN b.bettype = 43 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END as dividend,
			b.scomm as commIncomeAgency,
			case b.livehomescore when 2 then 'WON' when 4 then 'LOSE' else '' end winStatus,
			case b.liveawayscore when 2 then 'WON' when 4 then 'LOSE' else 'Refund' end placeStatus,
			b.status,
			o.teamid, 
			o.matchcode
	FROM	bettrans14 b (nolock)
			INNER JOIN outright14 o (nolock) on b.matchid = o.orid 
			INNER JOIN customer c (nolock) on b.custid = c.custid
			LEFT JOIN (			
				SELECT	t.refno, t.finalodds, f.finalodds finalodds2
				FROM	bettransm14 t WITH (NOLOCK)
						INNER JOIN bettransm14 f WITH (NOLOCK) ON t.refno = f.refno 
				WHERE	t.bettype = 41 AND f.bettype = 42
			)bmOdd on b.transid = bmOdd.refno 
	WHERE	b.bettype in (41,42,43) 
			AND b.ruben = 1 
			AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
			AND b.srecommend in (SELECT custid FROM f_DepSuperAllowedHR('12BET'))
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHR12BET_BetList_Details14] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHR12BET_BetList_Details14] TO [dot_member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFOddsHR12BET_BetList_Details14] TO [VNTeam]

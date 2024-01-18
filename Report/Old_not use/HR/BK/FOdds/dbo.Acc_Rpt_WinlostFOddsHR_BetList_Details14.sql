ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFOddsHR_BetList_Details14]
	@leagueid		INT,
	@raceNo			VARCHAR(10), 
	@currency		INT,
	@winlostdate	DATETIME
AS
/*
	Created by: Jamie
	Date: 2009-08-15
	Task: Bet List for Fixed Odds HR History 
	DB: DB06.BODB02
	Revisions:
		- 20091023@Simon: Displays Odds at Bet/Settle time
*/
BEGIN
	SET NOCOUNT ON
	-- == Betting World Commission Rate == ------ 
	DECLARE	@BWComRate	SMALLMONEY
	SELECT	@BWComRate	= 0.06 	

	SELECT	b.username,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,
			b.modds,
			bmOdd.finalodds,
			bmOdd.finalodds2,
			b.stake ,
			(b.winlost - b.actual_stake) as winlost,
			b.playercomm, 
			b.scomm as commIncomeAgency,
			(b.awinlost + b.mwinlost + b.swinlost) as WLPTAgency,	
			CASE b.bettype WHEN 43 THEN bm.WLPTIBC ELSE -(b.winlost - b.actual_stake)*isnull(b.oddsspread,0) END as WLPTIBC,
			(CASE b.bettype WHEN 43 THEN bm.TOIBC ELSE b.actual_stake*(1 - b.tpositiontaking - isnull(oddsspread,0)) END)*@BWComRate as commIncomeIBC, 		
			(case when b.bettype = 43 and b.liveawayscore =0 then b.winlost - b.actual_stake/2 else b.winlost end)  as dividend,
			case b.livehomescore when 2 then 'WON' when 4 then 'LOSE' else '' end winStatus,
			case b.liveawayscore when 2 then 'WON' when 4 then 'LOSE' else 'Refund' end placeStatus,
			b.status,
			o.teamid, 
			o.matchcode
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN outright14 o WITH (NOLOCK) ON b.matchid = o.orid 
			LEFT JOIN (
				SELECT	refno,	
						-sum((winlost -stake)*isnull(oddsspread,0)) WLPTIBC,
						sum(case when bettype = 42 and liveawayscore = 0 then 0 else stake*(1 - tpositiontaking - isnull(oddsspread,0)) end) TOIBC
				FROM	bettransm14 WITH (NOLOCK)
				GROUP BY refno 
			)bm ON bm.refno = b.transid 
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
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHR_BetList_Details14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFOddsHR_BetList_Details14] TO [VNTeam]



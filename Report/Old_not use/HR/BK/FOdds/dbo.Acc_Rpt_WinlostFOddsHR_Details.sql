ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFOddsHR_Details]
	@winlostdate	DATETIME
AS
	/*	Created by: Jamie
		Date: 2009-08-15
		Task: Fixed Odds Horse Racing Detailed Report
		DB: DB02.BODB02, DB06.BODB02
		
		History:

		Explanation's Param:
		+ @BWComRate = 0.06: Betting World Commission Rate 
	*/

	SET NOCOUNT ON
	DECLARE	@BWComRate	SMALLMONEY
	SELECT	@BWComRate	= 0.06 
	SELECT	t.currencyName,
			t.currency,
			t.leagueid, 
			t.groupmatch,
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
			ISNULL(t.commIncomeIBC_origin,0)		commIncomeIBC_origin,
			ISNULL(t.commIncomeIBC,0)				commIncomeIBC,
			ISNULL(t.PTWLIBC_origin,0)				PTWLIBC_origin,
			ISNULL(t.PTWLIBC,0)						PTWLIBC,
			ISNULL(t.PTWLIBC_origin,0)
			 + ISNULL(t.commIncomeIBC_origin,0)
			 - ISNULL(t.commIncomeAgency_Origin,0) 	netIncomeIBC_Origin,
			ISNULL(t.PTWLIBC,0)
			 + ISNULL(t.commIncomeIBC,0)
			 - ISNULL(t.commIncomeAgency,0)			netIncomeIBC,
			ISNULL(t.winTOBW_origin,0)				winTOBW_origin,
			ISNULL(t.placeTOBW_origin,0)			placeTOBW_origin,
			ISNULL(t.winplaceTOBW_origin,0)			winplaceTOBW_origin,
			ISNULL(t.winTOBW_origin,0)
			 + ISNULL(t.placeTOBW_origin,0)
			 + ISNULL(t.winplaceTOBW_origin,0)		totalTOBW_Origin,
			ISNULL(t.winTOBW,0)						winTOBW,
			ISNULL(t.placeTOBW,0)					placeTOBW,
			ISNULL(t.winplaceTOBW,0)				winplaceTOBW,
			ISNULL(t.winTOBW,0) 
			 + ISNULL(t.placeTOBW,0)
			 + ISNULL(t.winplaceTOBW,0)				totalTOBW,
			ISNULL(t.payoutBW_origin,0)				payoutBW_origin,				
			ISNULL(t.payoutBW,0)					payoutBW,
			ISNULL(t.winTOBW_origin,0)
			 + ISNULL(t.placeTOBW_Origin,0)
			 + ISNULL(t.winplaceTOBW_Origin,0)
			 - ISNULL(t.payoutBW_origin,0)
			 - ISNULL(t.commIncomeIBC_origin,0)		AmountDue_Origin,
			ISNULL(t.winTOBW,0)
			 + ISNULL(t.placeTOBW,0)
			 + ISNULL(t.winplaceTOBW,0)
			 - ISNULL(t.payoutBW,0)
			 - ISNULL(t.commIncomeIBC,0)			AmountDue
		
	FROM 
	(			
		SELECT	b.currency, o.leagueid, o.groupmatch, b.currencyName, 
				--Agency ---
				SUM(CASE WHEN b.bettype =41 THEN b.stake*b.tpositiontaking ELSE 0 END) winTO_Agency_Origin,
				SUM(CASE WHEN b.bettype =42 THEN b.stake*b.tpositiontaking ELSE 0 END) placeTO_Agency_Origin,
				SUM(CASE WHEN b.bettype =43 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking ELSE 0 END) winplaceTO_Agency_Origin,
				SUM(b.scomm) commIncomeAgency_Origin,
				SUM(b.awinlost + b.mwinlost + b.swinlost) PTWLAgency_Origin,
				SUM(CASE WHEN b.bettype =41 THEN b.stake*b.tpositiontaking*b.actualrate ELSE 0 END) winTO_Agency,
				SUM(CASE WHEN b.bettype =42 THEN b.stake*b.tpositiontaking*b.actualrate ELSE 0 END) placeTO_Agency,
				SUM(CASE WHEN b.bettype =43 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*b.tpositiontaking*b.actualrate ELSE 0 END) winplaceTO_Agency,
				SUM(b.scomm*b.actualrate) commIncomeAgency,
				SUM((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) PTWLAgency,	
			
				--IBC --- 
				SUM(CASE WHEN b.bettype =41 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) winTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =42 THEN b.stake*isnull(b.oddsspread,0) ELSE 0 END) placeTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =43 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0) ELSE 0 END) winplaceTO_IBC_Origin,
				SUM(CASE WHEN b.bettype =41 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winTO_IBC,
				SUM(CASE WHEN b.bettype =42 THEN b.stake*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) placeTO_IBC,
				SUM(CASE WHEN b.bettype =43 THEN (CASE b.liveawayscore WHEN 0 THEN b.stake/2 ELSE b.stake END)*isnull(b.oddsspread,0)*b.actualrate ELSE 0 END) winplaceTO_IBC,
				SUM(CASE WHEN b.bettype = 43 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END) PTWLIBC_Origin,
				SUM((CASE WHEN b.bettype = 43 THEN bm.PTWLIBC ELSE (b.winlost-b.actual_stake)*(-isnull(b.oddsspread,0)) END)*b.actualrate) PTWLIBC,
				SUM((CASE WHEN b.bettype = 43 THEN bm.TOBW ELSE b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0))END)*@BWComRate) commIncomeIBC_origin,
				SUM((CASE WHEN b.bettype = 43 THEN bm.TOBW ELSE b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0)) END)*@BWComRate*b.actualrate) commIncomeIBC,
				
				--Betting World ---
				SUM(CASE WHEN b.bettype = 41 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)winTOBW_origin,
				SUM(CASE WHEN b.bettype = 42 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) ELSE 0 END)placeTOBW_origin,	
				SUM(CASE WHEN b.bettype = 43 THEN bm.TOBW ELSE 0 END)winplaceTOBW_origin,
				SUM(CASE WHEN b.bettype = 41 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)winTOBW,
				SUM(CASE WHEN b.bettype = 42 THEN b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0))*b.actualrate ELSE 0 END)placeTOBW,	
				SUM(CASE WHEN b.bettype = 43 THEN bm.TOBW*b.actualrate ELSE 0 END) winplaceTOBW,
				SUM(CASE WHEN b.bettype = 43 THEN bm.PayoutBW ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0)) END) PayoutBW_Origin,
				SUM((CASE WHEN b.bettype = 43 THEN bm.PayoutBW ELSE b.winlost*(1 - b.tpositiontaking - isnull(b.oddsspread,0))END)*b.actualrate) PayoutBW

		FROM	bettrans b WITH (NOLOCK) 
				INNER JOIN outright o WITH (NOLOCK) ON b.matchid = o.orid 
				LEFT JOIN (
					SELECT	refno,
							-SUM((winlost - stake)*isnull(oddsspread,0)) PTWLIBC,
							SUM(CASE WHEN bettype = 42 AND liveawayscore = 0 THEN 0 ELSE stake*(1 -tpositiontaking - isnull(oddsspread,0))END) TOBW,
							SUM(CASE WHEN bettype = 42 AND liveawayscore = 0 THEN 0 ELSE winlost*(1 -tpositiontaking - isnull(oddsspread,0))END) PayoutBW
					FROM	bettransm WITH (NOLOCK)
					GROUP BY refno
				)bm ON b.transid = bm.refno 
		WHERE	b.ruben = 1 AND 
				b.bettype IN (41,42,43) AND 
				b.winlostdate = @winlostdate AND 
				b.status NOT IN ('VOID','REJECT','DONE','REFUND')
		GROUP BY b.currencyName, b.currency, o.leagueid, o.groupmatch
	) t 
	ORDER BY t.currency, t.leagueid, CAST(t.groupmatch AS TINYINT)

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFOddsHR_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFOddsHR_Details] TO [VNTeam]


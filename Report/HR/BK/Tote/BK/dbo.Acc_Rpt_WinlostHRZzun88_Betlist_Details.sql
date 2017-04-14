    CREATE PROCEDURE [dbo].[Acc_Rpt_WinlostHRZzun88_BetList_Details]
	@leagueid		INT,
	@raceNo			VARCHAR(10), 
	@currency		INT,
	@winlostdate	DATETIME
AS
/*
	Created by: Johnson
	Date: 2011-01-22
	Task: Zzun88 Tote Horse Racing Detailed Bet List
	DB: DB06.BODB02, DB02.BODB02	

	Revisions:
		
	Param's Explanation:
		+ Zzun88 HR Agent: PT = 0 , Comm = 0% 
*/

BEGIN
	SET NOCOUNT ON
	SELECT	b.username,
			REPLACE(c.username2, 'Zzun88$', '') username2,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,			
			b.stake,
			(b.winlost - b.actual_stake) winlost,
			b.playercomm,
			CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END dividend,
			b.scomm commIncomeAgency,
			CASE b.livehomescore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE '' END winStatus,
			CASE b.liveawayscore WHEN 2 THEN 'WON' WHEN 4 THEN 'LOSE' ELSE 'Refund' END placeStatus,
			b.status,
			o.teamid, 
			o.matchcode,
			b.virtualrate,
			isnumeric(o.programID) isShowOTExRate
	FROM	bettrans b (NOLOCK)
			INNER JOIN outright o (NOLOCK) ON b.matchid = o.orid 
			INNER JOIN customer c (NOLOCK) ON b.custid = c.custid
	WHERE	b.ruben = 1 
			AND b.bettype in (31,32,33) 
			--AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.statusID NOT IN (101,102,103,121)
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
			AND b.srecommend in (SELECT custid FROM f_DepSuper_1('Zzun88'))
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHRZzun88_BetList_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHRZzun88_BetList_Details] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHRZzun88_BetList_Details] TO [VNTeam]
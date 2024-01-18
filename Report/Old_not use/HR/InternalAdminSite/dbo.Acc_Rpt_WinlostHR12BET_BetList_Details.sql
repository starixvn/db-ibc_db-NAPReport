ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details]
	@leagueid		int,
	@raceNo			varchar(10), 
	@currency		int,
	@winlostdate	datetime
AS
/*
	Created by: Daniel
	Date: 2009-05-09
	Task: 12BET Horse Racing Detailed bet list
	DB: DB06.BODB02, DB02.BODB02	

	History:
		- 20090509@Daniel: Add
		- 20090513@Khoa: add column username2
		- 20090603@PhuongDao: Add PT WinLoss Agency, commIncomeAgency
		- 20091008@Jamie: 
			+ Allow the members under currency IN to bet HR 
			+ Get the list of supers from the function
		- 20100508@Jamie: Change to call f_DepSuper_1 instead of f_DepSuperAllowedHR
		- 20100525@Jamie: Show OpenTote ExRate 
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20110727@Johnson: show exchange rate 2 with HR SA (Pool currency)
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
			b.stake,
			(b.winlost - b.actual_stake) as winlost,
			b.playercomm,
			(b.awinlost + b.mwinlost + b.swinlost) as WLPTAgency,
			CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END as dividend,
			b.scomm as commIncomeAgency,
			case b.livehomescore when 2 then 'WON' when 4 then 'LOSE' else '' end winStatus,
			case b.liveawayscore when 2 then 'WON' when 4 then 'LOSE' else 'Refund' end placeStatus,
			b.status,
			o.teamid, 
			o.matchcode,
			b.virtualrate,
			--isnumeric(o.programID) isShowOTExRate 
			CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END AS isShowOTExRate
	FROM	bettrans b (nolock)
			INNER JOIN outright o (nolock) on b.matchid = o.orid 
			INNER JOIN customer c (nolock) on b.custid = c.custid
	WHERE	b.bettype in (31,32,33) 
			AND b.ruben = 1 
			--AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.statusID NOT IN (101,102,103,121)
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
			AND b.srecommend in (SELECT custid FROM f_DepSuper_1('12BET'))
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details] TO [dot_member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details] TO [VNTeam]
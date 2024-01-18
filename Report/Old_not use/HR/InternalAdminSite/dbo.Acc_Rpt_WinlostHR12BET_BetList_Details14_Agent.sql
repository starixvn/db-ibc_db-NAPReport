 ALTER PROC [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent]
	@leagueid		int,
	@raceNo			varchar(10), 
	@currency		int,
	@winlostdate	DATETIME,
	@agentid NVARCHAR(3500)
AS
/*
	
	Revisions:
		- 20110727@Johnson: show exchange rate 2 with HR SA (Pool currency)
*/

	SET NOCOUNT ON

	SELECT	c.username,
			CASE WHEN CHARINDEX('12bet$', c.username2) > 0 THEN replace(c.username2, '12bet$', '') 
			 WHEN CHARINDEX('asiabet88$', c.username2) > 0 THEN replace(c.username2, 'asiabet88$', '')
			 WHEN CHARINDEX('mansion88$', c.username2) > 0 THEN replace(c.username2, 'mansion88$', '') 
			END as username2,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,
			b.stake as stake,
			(b.winlost - b.actual_stake) as winlost,
			b.playercomm,
			(b.awinlost + b.mwinlost + b.swinlost) as WLPTAgency,
			b.scomm  as commIncomeAgency,
			CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost - b.actual_stake/2 ELSE b.winlost END as dividend,
			case b.livehomescore when 2 then 'WON' when 4 then 'LOSE' else '' end winStatus,
			case b.liveawayscore when 2 then 'WON' when 4 then 'LOSE' else 'Refund' end placeStatus,
			b.status,
			o.teamid,
			o.matchcode,
			CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END AS isShowOTExRate
	FROM	bettrans14 b (nolock)
			INNER JOIN customer c (nolock) on b.custid = c.custid 
			INNER JOIN outright14 o (nolock) on b.matchid = o.orid
	WHERE	b.bettype in (31,32,33) 
			AND b.ruben = 1 
			AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND o.leagueid = @leagueid 
			AND o.groupmatch = @raceNo
			and b.recommend in (SELECT val FROM strSplit(@agentid,','))
	ORDER BY c.username

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent] TO [Dot_Admin]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent] TO [RDTim]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR12BET_BetList_Details14_Agent] TO [vnteam]
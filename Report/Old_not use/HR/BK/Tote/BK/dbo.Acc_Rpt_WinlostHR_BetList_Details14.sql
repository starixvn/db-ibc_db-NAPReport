ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHR_BetList_Details14]
	@leagueid		int,
	@raceNo			varchar(10), 
	@currency		int,
	@winlostdate	datetime
AS
/*
	Created by: Phuong Dao
	Date: []
	Task: BetList for Tote HR 
	DB: DB06.BODB02
	Revisions:
		- 20090602@PhuongDao: Add PT for HR	
		- 20100401@Jamie: Arrange new structure for HR Meetings 
		- 20100525@Jamie: Show OpenTote ExRate 
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement

*/
BEGIN
	SET NOCOUNT ON

--insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @CommSetting TABLE
	(	MatchID int,
		MeetingID int,
		HorseID int,
		Race varchar(10),
		HorseNo varchar(10),
		ToteCommWin smallmoney,
		ToteCommPlace smallmoney,
		ToteCommWP smallmoney,
		isShowOTExRate bit	
	)
	INSERT INTO @CommSetting (
			MatchID, MeetingID, HorseID, Race, HorseNo, 
			ToteCommWin, ToteCommPlace, ToteCommWP,
			isShowOTExRate
	)
	SELECT	DISTINCT o.orid as matchid, o.leagueID , o.teamid, o.groupmatch, o.matchcode,
			p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP,
			isnumeric(o.programID)
	FROM	outright14 o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID  
	WHERE	o.eventdate = @winlostdate AND p.programDate = @winlostdate 

	SELECT	b.username,
			b.transid,
			b.transdate,
			b.bettype,
			b.hdp1 winOdds,
			b.hdp2 placeOdds,
			b.odds,
			b.stake ,
			(b.winlost - b.actual_stake) as winlost,
			b.playercomm, 
			b.scomm as commIncomeAgency,
			(b.awinlost + b.mwinlost + b.swinlost) as WLPTAgency,	
			case b.bettype when 33 then bm.WLPTIBC else -(b.winlost - b.actual_stake)*isnull(b.oddsspread,0) end as WLPTIBC,
			(case b.bettype when 31 then cs.ToteCommWin when 32 then cs.ToteCommPlace when 33 then cs.ToteCommWP else 0 end)
				*(case b.bettype when 33 then bm.TOIBC else b.actual_stake*(1 - b.tpositiontaking - isnull(oddsspread,0)) end) as commIncomeIBC, 		
			(case when b.bettype = 33 and b.liveawayscore =0 then b.winlost - b.actual_stake/2 else b.winlost end)  as dividend,
			case b.livehomescore when 2 then 'WON' when 4 then 'LOSE' else '' end winStatus,
			case b.liveawayscore when 2 then 'WON' when 4 then 'LOSE' else 'Refund' end placeStatus,
			b.status,
			cs.HorseID teamid, 
			cs.HorseNo matchcode,
			b.virtualrate,
			cs.isShowOTExRate
	FROM	bettrans14 b (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid
			LEFT JOIN (
				SELECT	refno,	
						-sum((winlost -stake)*isnull(oddsspread,0)) WLPTIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*(1 - tpositiontaking - isnull(oddsspread,0)) end) TOIBC
				FROM	bettransm14 WITH (NOLOCK)
				GROUP BY refno 
			)bm ON bm.refno = b.transid 
	WHERE	b.bettype in (31,32,33) 
			AND b.ruben = 1 
			--AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.statusID NOT IN (101,102,103,121)
			AND b.currency = @currency 
			AND b.currency2 IS NULL
			AND b.winlostdate = @winlostdate
			AND cs.Race = @raceNo
			AND cs.meetingID = @leagueID 
	ORDER BY b.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR_BetList_Details14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR_BetList_Details14] TO [VNTeam]

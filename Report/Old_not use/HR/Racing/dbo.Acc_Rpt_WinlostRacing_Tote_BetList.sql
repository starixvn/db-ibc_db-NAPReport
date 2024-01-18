ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacing_Tote_BetList]
	@leagueid		int,
	@raceNo			varchar(10), 
	@currency		int,
	@winlostdate	datetime
AS
/*
	Created by: Johnson
	Date: 2011-03-16
	Task: BetList for Racing 
	DB: DB06.BODB02
		- 20110531@Johnson: show Exchange currency2 for SA Tote
		- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
		- 20141226@Dom: Apply bettype matrix
	Revisions:
		
*/
BEGIN
	SET NOCOUNT ON

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode=4

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
	SELECT	DISTINCT o.orid as matchid, o.leagueID, o.teamid, o.groupmatch, o.matchcode,
			p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP,1
	FROM	outright o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID AND p.programDate = o.programDate
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON p.leagueid = r.meetingid
	WHERE	o.eventdate = @winlostdate 


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
			cs.HorseID , 
			cs.HorseNo,
			b.virtualrate,
			cs.isShowOTExRate
	FROM	bettrans b (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid
			LEFT JOIN (
				SELECT	refno,	
						-sum((winlost -stake)*isnull(oddsspread,0)) WLPTIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*(1 - tpositiontaking - isnull(oddsspread,0)) end) TOIBC
				FROM	bettransm WITH (NOLOCK)
				GROUP BY refno 
			)bm ON bm.refno = b.transid 
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
	WHERE	--b.bettype in (31,32,33) 
			s.ProductID = 2
			AND b.ruben = 1 
			--AND b.status NOT in ('VOID','REJECT','DONE','REFUND')
			AND b.statusID NOT in (101,102,103,121)
			AND b.currency = @currency 
			AND b.winlostdate = @winlostdate
			AND cs.Race = @raceNo
			AND cs.MeetingID = @leagueID 
	ORDER BY b.username
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacing_Tote_BetList] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacing_Tote_BetList] TO [vnteam]
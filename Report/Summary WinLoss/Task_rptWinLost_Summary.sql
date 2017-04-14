
ALTER PROCEDURE [dbo].[Task_rptWinLost_Summary]
	@MatchID int
/*
	Original: rpt_WinLost_UpdateTable
	Creator: 
	Created: 
	Task: update summary for winlost report
	This SP is unused
*/
AS
SET NOCOUNT ON
		
		IF (EXISTS (SELECT TOP 1 MatchID from bodb_Report.dbo.rptWinlost with (nolock) where matchid = @MatchID))
		DELETE FROM bodb_Report.dbo.rptWinlost
		WHERE matchid = @MatchID

		INSERT INTO bodb_Report.dbo.rptWinlost
		SELECT
			winlostdate,
			matchid,
			bettype, 
			liveindicator, 
			Status,
			case recommend when 52466 then 1 else 0 end ibc,
			sum((winlost-actual_stake)* actualrate)  winlost,
			sum((awinlost+mwinlost+swinlost)* actualrate) pos,
			sum((scomm) * actualrate) comm,
			0, --SportType
			0, --exrisk
			sum((1-tpositiontaking)*actual_stake*virtualrate) Turnover,
			sum((scomm)*virtualrate) VirtualComm,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate) as LineTotal,
			sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate) as VirtualLineTotal			
		FROM
			bettrans b with (nolock)
		WHERE
			bettype < 99
			AND matchid = @matchid
			AND status NOT IN ('VOID', 'REJECT', 'REFUND')
			AND ruben = 1
		GROUP BY
			winlostdate, matchid, bettype, liveindicator, status,
			case recommend when 52466 then 1 else 0 end

		--Update Sporttype, exrisk
		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END, exrisk = m.exrisk
		FROM match m with (nolock)
			inner join league l with (nolock) ON m.leagueid = l.leagueid
		WHERE	bodb_Report.dbo.rptWinlost.matchid = m.matchid
				AND bodb_Report.dbo.rptWinlost.matchid = @MatchID

		--Update Sporttype for Outright
		UPDATE bodb_Report.dbo.rptWinlost
		SET SportType = CASE
			WHEN leaguename LIKE '%NFL%' AND l.sporttype = 2 THEN 3
			WHEN (leaguename LIKE '%NHL%' OR leaguename LIKE '%hockey%') AND l.sporttype = 2 THEN 4
			ELSE l.sporttype END
		FROM outright o with (nolock) INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
		WHERE	bodb_Report.dbo.rptWinlost.matchid = o.orid
				AND bodb_Report.dbo.rptWinlost.matchid = @MatchID
				AND bodb_Report.dbo.rptWinlost.bettype = 10

		---Update HR Turnover, LineTotal
		DECLARE @FeeDue2Rate smallmoney
		Set @FeeDue2Rate = 0.0083

		DECLARE @CommSetting TABLE
		(	MatchID int,
			MaxStake float,
			MaxStakeou float,
			MaxStakeoe float	
		)
		INSERT INTO @CommSetting (MatchID, MaxStake, MaxStakeou, MaxStakeoe)
		SELECT DISTINCT o.orid as matchid, l.maxstake, l.maxstakeou, (l.maxstake + l.maxstakeou)/2 maxstakeoe
		FROM outright o WITH (NOLOCK)
		INNER JOIN league l WITH (NOLOCK) ON l.leagueid = o.leagueid
		WHERE o.eventdate = @winlostdate
			
		UPDATE bodb_Report.dbo.rptWinlost
		SET Turnover = t.Turnover, LineTotal = t.LineTotal
		FROM ( SELECT	cs.matchid,
						b.bettype,
						sum(case when bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) as Turnover,
						(sum((case bettype when 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
							- sum((case when b.bettype = 33 then bm.TOPhum else b.actual_stake*(1 -b.tpositiontaking - isnull(b.oddsspread,0)) end)*b.actualrate*@FeeDue2Rate) --FeeDue2 
							+ sum((case bettype when 31 then b.actual_stake*cs.maxstake*(1 - b.tpositiontaking - isnull(oddsspread,0))
												when 32 then b.actual_stake*cs.maxstakeou*(1 - b.tpositiontaking - isnull(oddsspread,0))
												when 33 then bm.TOPhum*cs.maxstakeoe end)*b.actualrate)
							- sum(b.scomm*b.actualrate)) as LineTotal
				FROM	bettrans b with (nolock)
						INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
						 left join (
							select	refno,
									sum(case when bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
									-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
									sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*(1 -tpositiontaking - isnull(oddsspread,0)) end) TOPhum
							from	bettransm with (nolock)
							group by refno
						 )bm on b.transid = bm.refno 
				WHERE	b.ruben =1 
						and b.bettype in (31,32,33)
						and b.matchid = @matchid
						and b.status not in ('VOID','REJECT','DONE','REFUND')
				group by cs.matchid, b.bettype) t
		WHERE	bodb_Report.dbo.rptWinlost.bettype = t.bettype
				AND bodb_Report.dbo.rptWinlost.sporttype = 151 
				AND bodb_Report.dbo.rptWinlost.matchid = @MatchID
	END
			
GO
GRANT EXECUTE ON [dbo].[Task_rptWinLost_Summary] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_rptWinLost_Summary] TO [vnteam]
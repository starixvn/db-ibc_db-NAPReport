ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Result]
	@MatchID int,
	@Bettype int,	
	@TraderName nvarchar(100) OUTPUT
AS
/*
Created: Elodie
Task: Get result in report 2h
DB: DBACC/bodb02
Original: Acc_BetList_SelMatchResult

Revisions:    
 - 20141021@Sophia: Get data of ResultDetail (Sporting Solution) 
 - 20140414@Sophia: Support Bet Radar
	
*/
SET NOCOUNT ON

DECLARE @Sporttype TINYINT

IF EXISTS(SELECT 1 FROM match WITH(NOLOCK) WHERE matchid = @matchid)
BEGIN	
	SELECT 
		m.betstatus, 
		m.hthomescore,
		m.htawayscore,
		datediff(minute,kickofftime,CURRENT_TIMESTAMP) playtime,
		m.LeagueID,
		m.homeID,
		m.awayID,
		m.matchcode,
		m.kickofftime,
		m.eventdate,
		m.finalhomescore,
		m.finalawayscore,
		CASE m.Sporttype WHEN 5 THEN CASE ISNULL(R.SettlementStatusID,0)	 
										WHEN 1 THEN 'Refund' 
										WHEN 2 THEN 'Refund HT'
										WHEN 3 THEN 'Refund FT'
									ELSE m.eventstatus END 
								ELSE 
									CASE  WHEN m.betstatus like 'Refund FT%' THEN 'Refund FT' 
										  WHEN m.betstatus like 'Refund HT%' THEN 'Refund HT'
										  WHEN m.betstatus like 'Refund%' THEN 'Refund' 
									ELSE m.eventstatus END 
						END AS eventstatus, 

		isnull(mr.refund,0) IsRefund, 
		isnull(mr.calrefund,0) IsCalRefund,
		isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
		m.goalrecord,
		ISNULL(mr.IsHTCal,0) as IsHTCal,
		ISNULL(mr.calculate,0) as calculate,
		ISNULL(mr.IsPending,0) as IsPending,
		m.showtime	
	FROM match m WITH(NOLOCK)
		LEFT OUTER JOIN match_remark mr WITH(NOLOCK) ON m.matchid = mr.matchid
		LEFT JOIN dbo.ResultDetail R WITH (NOLOCK) ON R.matchID = M.MatchID AND R.ResourceId = '00'
	WHERE m.matchid = @matchid
	
	SELECT @TraderName = c.username
	FROM  Dot_Admin_Assignment_Operator o WITH (NOLOCK)
		INNER JOIN customer c with(nolock) on o.OperatorID = c.custid
	WHERE matchid = @MatchID 
		AND @Bettype = CASE WHEN bettype IN (1,5) AND OperatorType = 1 THEN 1
							WHEN bettype = 1 AND OperatorType = 2 THEN 7
							WHEN bettype = 2 AND OperatorType = 1 THEN 3
							WHEN bettype = 2 AND OperatorType = 2 THEN 8
							WHEN bettype = 3 AND OperatorType = 1 THEN 5
							WHEN bettype = 3 AND OperatorType = 2 THEN 15
							WHEN bettype = 4 AND OperatorType = 1 THEN 2
							WHEN bettype = 4 AND OperatorType = 2 THEN 12
							END

		SELECT @Sporttype = Sporttype FROM dbo.Match m WITH (NOLOCK) WHERE MatchId = @matchid


		SELECT	D.MatchId,
				D.ResourceId,
				D.HomeValue,
				D.AwayValue,
				D.ResultStatusID,
				D.SettlementStatusID,
				D.OtherInfo
		FROM	dbo.ResultDetail D WITH (NOLOCK)			
		WHERE	D.MatchId = @MatchId	
				AND D.SettlementStatusID > 0
				AND ((@Sporttype = 1 AND D.ResourceId NOT IN ( '00', '01', '08'))
						OR @Sporttype = 5
						)
		ORDER BY  D.MatchID, D.ResourceId 


END
ELSE IF exists(SELECT 1 FROM match14 WITH(NOLOCK) WHERE matchid = @matchid)	
BEGIN	
	SELECT 
		m.betstatus, 
		m.hthomescore,
		m.htawayscore,
		datediff(minute,kickofftime,CURRENT_TIMESTAMP) playtime,
		m.LeagueID,
		m.homeID,
		m.awayID,
		m.matchcode,
		m.kickofftime,
		m.eventdate,
		m.finalhomescore,
		m.finalawayscore,
		CASE m.Sporttype WHEN 5 THEN CASE ISNULL(R.SettlementStatusID,0)	 
										WHEN 1 THEN 'Refund' 
										WHEN 2 THEN 'Refund HT'
										WHEN 3 THEN 'Refund FT'
									ELSE m.eventstatus END 
								ELSE 
									CASE  WHEN m.betstatus like 'Refund FT%' THEN 'Refund FT' 
										  WHEN m.betstatus like 'Refund HT%' THEN 'Refund HT'
										  WHEN m.betstatus like 'Refund%' THEN 'Refund' 
									ELSE m.eventstatus END 
						END AS eventstatus,
		isnull(mr.refund,0) IsRefund, 
		isnull(mr.calrefund,0) IsCalRefund,
		isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
		m.goalrecord,
		ISNULL(mr.IsHTCal,0) as IsHTCal,
		ISNULL(mr.calculate,0) as calculate,
		ISNULL(mr.IsPending,0) as IsPending,
		m.showtime	
	FROM match14 m WITH(NOLOCK)
		LEFT OUTER JOIN match_remark mr WITH(NOLOCK) ON m.matchid = mr.matchid
		LEFT JOIN dbo.ResultDetail14 R WITH (NOLOCK) ON R.matchID = M.MatchID AND R.ResourceId = '00'
	WHERE m.matchid = @matchid
	
	SELECT @TraderName = c.username
	FROM  DBARC.bodb_archive.dbo.Dot_Admin_Assignment_Operator_bk o WITH (NOLOCK)
		INNER JOIN customer c with(nolock) on o.OperatorID = c.custid
	WHERE matchid = @MatchID 
		AND @Bettype = CASE WHEN bettype IN (1,5) AND OperatorType = 1 THEN 1
							WHEN bettype = 1 AND OperatorType = 2 THEN 7
							WHEN bettype = 2 AND OperatorType = 1 THEN 3
							WHEN bettype = 2 AND OperatorType = 2 THEN 8
							WHEN bettype = 3 AND OperatorType = 1 THEN 5
							WHEN bettype = 3 AND OperatorType = 2 THEN 15
							WHEN bettype = 4 AND OperatorType = 1 THEN 2
							WHEN bettype = 4 AND OperatorType = 2 THEN 12
							END

		SELECT @Sporttype = Sporttype FROM dbo.Match14 m WITH (NOLOCK) WHERE MatchId = @matchid

		SELECT	D.MatchId,
				D.ResourceId,
				D.HomeValue,
				D.AwayValue,
				D.ResultStatusID,
				D.SettlementStatusID,
				D.OtherInfo
		FROM	dbo.ResultDetail14 D WITH (NOLOCK)			
		WHERE	D.MatchId = @MatchId	
				AND D.SettlementStatusID > 0	
				AND ((@Sporttype = 1 AND D.ResourceId NOT IN ( '00', '01', '08'))
						OR @Sporttype = 5
						)
		ORDER BY  D.MatchID, D.ResourceId 	
	 

END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Result] TO [bodbExtAccNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Result] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Result] TO [vnteam]
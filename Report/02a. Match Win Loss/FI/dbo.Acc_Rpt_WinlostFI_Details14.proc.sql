ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFI_Details14]
	@fromdate	datetime,
	@todate	datetime
AS

	/*	Creator: Phuong Dao
		Date: 2009-01-19
		Task: Detailed Finance Report  
		DB: DB06.BODB02
		
		History:
			- 20090224@PhuongDao: display Index Name from matchcode column of Match table instead of homeid 
			- 20090418@PhuongDao: Get IndexName from RemoteRef via homeid 
			- 20100120@KhoaTran : Offer date range selection
			-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	*/
	SET NOCOUNT ON
	DECLARE	@RateForTrader smallmoney, @RateForIBC smallmoney

	SELECT	@RateForTrader = 0.15 , @RateForIBC = 1 - @RateForTrader	

	SELECT	m.homeid, -- IndexName, 
			b.bettype,
			isnull(sum(b.actual_stake * b.actualrate),0) Turnover,
			isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost)* b.actualrate),0) Winlost,
			isnull(sum(scomm * b.actualrate),0) scomm,
			isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) NetWinlost,
			isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForTrader  BetsForTrader,
			isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForIBC  IBCWinlost

	FROM	bettrans14 b (nolock)
			INNER JOIN match14 m (nolock) on b.matchid = m.matchid 
	WHERE	b.winlostdate between @fromdate and @todate
			AND b.ruben =1 
			AND b.bettype between 51 and 66 
			AND b.matchid > 0 
			--AND b.status not in ('VOID','REJECT','done')
			AND b.statusID not in (101,102,121)
	GROUP BY m.homeid, b.bettype 
	ORDER BY m.homeid, b.bettype 
	
	GO
	GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFI_Details14] TO [bodbAdminNet]
	GO
	GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFI_Details14] TO [VNTeam]

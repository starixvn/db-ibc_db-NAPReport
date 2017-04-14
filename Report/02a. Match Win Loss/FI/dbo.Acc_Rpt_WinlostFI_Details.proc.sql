ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostFI_Details]
	@fromdate	datetime,
	@todate		datetime,
	@movebetsday datetime = ''
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
	DECLARE @tmpFIWL TABLE(homeid int, bettype int, Turnover money, Winlost money, scomm money, NetWinlost money, BetsForTrader money, IBCWinlost money)

	SELECT	@RateForTrader = 0.15 , @RateForIBC = 1 - @RateForTrader	

	IF @todate <= @movebetsday -- Old Data
	BEGIN		
		INSERT INTO @tmpFIWL
		SELECT	m.homeid , -- IndexName, 
				b.bettype,
				isnull(sum(b.actual_stake * b.actualrate),0) Turnover,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost)* b.actualrate),0) Winlost,
				isnull(sum(scomm * b.actualrate),0) scomm,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) NetWinlost,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForTrader  BetsForTrader,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForIBC  IBCWinlost

		FROM	bettrans14 b (nolock)
				INNER JOIN match14 m (nolock) on b.matchid = m.matchid 
		WHERE	b.winlostdate between @fromdate and  @todate
				AND b.ruben =1 
				AND b.matchid > 0 
				AND b.bettype between 51 and 66
				--AND b.status not in ('VOID','REJECT','done', 'refund')
				AND b.statusID not in (101,102,103, 121)
		GROUP BY m.homeid, b.bettype 		
	END
	ELSE IF @fromdate > @movebetsday -- Current Data
	BEGIN		
		INSERT INTO @tmpFIWL 
		SELECT	m.homeid , -- IndexName, 
				b.bettype,
				isnull(sum(b.actual_stake * b.actualrate),0) Turnover,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost)* b.actualrate),0) Winlost,
				isnull(sum(scomm * b.actualrate),0) scomm,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) NetWinlost,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForTrader  BetsForTrader,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForIBC  IBCWinlost

		FROM	bettrans b (nolock)
				INNER JOIN match m (nolock) on b.matchid = m.matchid 
		WHERE	b.winlostdate between @fromdate and  @todate
				AND b.ruben =1 
				AND b.matchid > 0 
				AND b.bettype between 51 and 66
				--AND b.status not in ('VOID','REJECT','done', 'refund')
				AND b.statusID not in (101,102,103,121)
		GROUP BY m.homeid, b.bettype 		
	END
	ELSE -- Cross days
	BEGIN		
		INSERT INTO @tmpFIWL -- Old Data
		SELECT	m.homeid , -- IndexName, 
				b.bettype,
				isnull(sum(b.actual_stake * b.actualrate),0) Turnover,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost)* b.actualrate),0) Winlost,
				isnull(sum(scomm * b.actualrate),0) scomm,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) NetWinlost,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForTrader  BetsForTrader,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForIBC  IBCWinlost

		FROM	bettrans14 b (nolock)
				INNER JOIN match14 m (nolock) on b.matchid = m.matchid 
		WHERE	b.winlostdate between @fromdate and  @movebetsday
				AND b.ruben =1 
				AND b.matchid > 0 
				AND b.bettype between 51 and 66
				--AND b.status not in ('VOID','REJECT','done', 'refund')
				AND b.statusID NOT IN (101,102,103,121)
		GROUP BY m.homeid, b.bettype 		
		------------------------------
		INSERT INTO @tmpFIWL -- Current Data
		SELECT	m.homeid , -- IndexName, 
				b.bettype,
				isnull(sum(b.actual_stake * b.actualrate),0) Turnover,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost)* b.actualrate),0) Winlost,
				isnull(sum(scomm * b.actualrate),0) scomm,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) NetWinlost,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForTrader  BetsForTrader,
				isnull(sum((b.winlost - b.actual_stake + awinlost + mwinlost + swinlost + scomm)* b.actualrate),0) * @RateForIBC  IBCWinlost

		FROM	bettrans b (nolock)
				INNER JOIN match m (nolock) on b.matchid = m.matchid 
		WHERE	b.winlostdate between dateadd(dd, 1, @movebetsday) and  @todate
				AND b.ruben =1 
				AND b.matchid > 0 
				AND b.bettype between 51 and 66
				--AND b.status not in ('VOID','REJECT','done', 'refund')
				AND b.statusID NOT IN (101,102,103,121)
		GROUP BY m.homeid, b.bettype 		
	END


	SELECT 
		homeid, bettype,
		isnull(SUM(Turnover),0) as Turnover,
		isnull(SUM(Winlost),0) as Winlost,
		isnull(SUM(scomm),0) as scomm,
		isnull(SUM(NetWinlost),0) as NetWinlost,
		isnull(SUM(BetsForTrader),0) as BetsForTrader,
		isnull(SUM(IBCWinlost),0) as IBCWinlost
	FROM @tmpFIWL
	GROUP BY homeid, bettype
	ORDER BY homeid, bettype

	GO
	GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostFI_Details] TO [bodbAdminNet]
	GO
	GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostFI_Details] TO [VNTeam]

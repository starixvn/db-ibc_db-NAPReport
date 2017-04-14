ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGameWinlossByDate]
	@fromdate smalldatetime,
	@todate smalldatetime
AS
/*
Created: 20101217@Viet
Task: Get Number Game report w/l by date  
DB: DBDW2.bodb02
  
Revisions:
	- 18Dec2010@Viet: Add Virtual Line Total
*/  
  
SET NOCOUNT ON  

IF @@SERVERNAME = 'DWDBG1S' -- FOR LOCAL TESTING PURPOSE (server 214)
BEGIN
	select *, 
		linetotal+(Rand()*linetotal/10)-(Rand()*linetotal/10) virtuallinetotal 
	from bodb_account.dbo.VIETTEST_NUbyDate with(nolock)
	where date between @fromdate and @todate
	order by date, islive, bettype
END
ELSE
BEGIN
	select date, islive, bettype,
		-(linetotal-position) winlost,
		position position,
		commission commission,
		linetotal linetotal,
		turnover turnover,
		virtuallinetotal virtuallinetotal,
		isnull(linetotal*100/NULLIF(turnover, 0),0) margin
	FROM (
		select rptdate date, islive, bettype,
			sum(r.winlostS+winlostM+winlostA) position,
			sum(commission) commission,
			sum(r.winlostIBC) linetotal,
			sum(r.WinlossIBCVirtual) virtuallinetotal,
			sum(r.turnoverIBC) Turnover
		from bodb_account.dbo.rptmatch r with(nolock)
			inner join bodb_staging.dbo.match m with(nolock) on r.matchid=m.matchid
		where rptdate between @fromdate and @todate
			and m.sporttype=161
			and r.bettype between 81 and 87
			and status in (3,4,8)
		group by rptdate, islive, bettype
	) a
	order by date, islive, bettype
END
  
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGameWinlossByDate] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGameWinlossByDate] TO [vnteam]
GO
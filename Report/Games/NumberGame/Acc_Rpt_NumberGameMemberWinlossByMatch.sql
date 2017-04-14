ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch]
 @date smalldatetime
AS
/*
Created: 20101217@Viet
Task: Get Number Game report - member w/l by match  
DB: DBDW2.bodb02
  
Revisions:
	- 18Dec2010@Viet: Add Virtual Line Total
*/  
  
SET NOCOUNT ON  
-- for testing purpose
IF @@SERVERNAME = 'DWDBG1S' -- FOR LOCAL TESTING PURPOSE (server 214)
BEGIN
	select matchcode, 
		matchid,
		islive,
		bettype,
		winlost,
		position,
		commission,
		linetotla linetotal,
		linetotla+(Rand()*linetotla/10)-(Rand()*linetotla/10) virtuallinetotal,
		turnover,
		margin
	from bodb_account.dbo.VIETTEST_NUbyMatch r with(nolock)
	where date = @date
END
ELSE
BEGIN
	select matchcode, 
		matchid,
		islive,
		bettype,
		-(linetotal-position) winlost,
		position position,
		commission commission,
		linetotal linetotal,
		virtuallinetotal virtuallinetotal,
		turnover turnover,
		isnull(linetotal*100/NULLIF(turnover, 0),0) margin
	FROM (
		select m.matchcode matchcode, m.matchid, islive, bettype,
			sum(r.winlostS+winlostM+winlostA) position,
			sum(commission) commission,
			sum(r.winlostIBC) linetotal,
			sum(r.winlossIBCVirtual) virtuallinetotal,
			sum(r.turnoverIBC) Turnover
		from bodb_account.dbo.rptmatch r with(nolock)
			inner join bodb_staging.dbo.match m with(nolock) on r.matchid=m.matchid
		where rptdate = @date
			and m.sporttype=161
			and r.bettype between 81 and 87
			and status in (3,4,8)
		group by m.matchcode,m.matchid,islive,bettype
	) a
	order by matchcode, bettype
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch] TO [vnteam]
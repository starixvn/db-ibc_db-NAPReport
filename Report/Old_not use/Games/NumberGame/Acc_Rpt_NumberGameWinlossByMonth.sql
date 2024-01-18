ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGameWinlossByMonth]
	@month tinyint,
	@year int
AS
/*
Created: 20110324@Viet
Task: Get Number Game report w/l by month.
NOTE: Only need to have data of RMB, RM, SGD and THB
DB: DBDW2.bodb02
    
Revisions:
	
*/  
  
SET NOCOUNT ON  

declare @date datetime
select @date = dateadd(mm,(@year-1900)* 12 + @month - 1,0)
	
IF @@SERVERNAME = 'DWDBG1S' -- FOR LOCAL TESTING PURPOSE (server 214)
BEGIN
	select -1371933.4172 winlost,
		-1025750.1216 position,
		0 commission,
		346183.2956 linetotal,
		9306134.0896 turnover,
		3.71 margin
END
ELSE
BEGIN
	SELECT -(linetotal - position) winlost,
		position position,
		commission commission,
		linetotal linetotal,
		Turnover Turnover,
		isnull(linetotal/nullif(Turnover,0)*100,0) margin
	FROM (
		select 
			isnull(sum(winlossS+winlossM+winlossA),0) position,
			isnull(sum(commission),0) commission,
			isnull(sum(winlossIBC),0) linetotal,
			isnull(sum(turnoverIBC),0) turnover
		from bodb_account.dbo.rptCube with(nolock)
		where datediff(mm, @date, rptdate) = 0
			and bettype between 81 and 87
			and status in (3,4,8)
			and currency in (13,2,1,43)
	) x
END
  
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGameWinlossByMonth] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGameWinlossByMonth] TO [vnteam]
GO
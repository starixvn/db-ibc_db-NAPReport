CREATE PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Keno_Bettype14]
	@winlostdate datetime
	
 AS
 
 /*	Creator: Dom
	Date: 2014-03-04
	Task: Keno WinLost Summary report
	DB: DBACC/bodb02
	
	Revisions:
		
	
	*/
 SET NOCOUNT ON

CREATE TABLE #DepAgent (custid int primary key)
	
INSERT INTO #DepAgent 
SELECT custid
FROM custInfo with(NOLOCK)
WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
	AND roleid = 2	
UNION
SELECT 5707545--BARM
	
SELECT		
		b.bettype bettype,
		case when dep.custid is null then 1 else 2 end as site,
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
		sum((1-tpositiontaking)*stake*actualrate) Turnover
FROM	bettrans14 b WITH (NOLOCK)
	LEFT JOIN (SELECT custid FROM #DepAgent) dep ON b.recommend = dep.custid
WHERE	b.winlostdate = @winlostdate
		AND b.bettype BETWEEN 1501 AND 1599
		AND b.ruben = 1		
		--AND b.status != 'DONE'			
		AND b.statusID not in (101,102,103,121)
GROUP BY b.Bettype, case when dep.custid is null then 1 else 2 end
ORDER BY b.Bettype, site

DROP TABLE #DepAgent



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Keno_Bettype14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Keno_Bettype14] TO [vnteam]
 
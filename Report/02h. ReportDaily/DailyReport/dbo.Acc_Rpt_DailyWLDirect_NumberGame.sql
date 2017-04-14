ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_NumberGame]
	@winlostdate datetime
AS

/*	Creator: Johnson
	Date: 2010-12-04
	Task: Number Game WinLost Summary report
	DB: DBACC/bodb02
	
	Revisions:
		04Dec2010@Viet: separate LIVE and NON-LIVE data.
		16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
		- 20110801@Johnson: add more bettype for number game
		- 20110824@Johnson: remove check winlostdate with '16 Dec 2010' for sumary turnover, get from stake instead actual_stake
		- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
		- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
		- 20130731@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)			
		- 20150108@Dom: Apply sport bettype matrix	 
	
*/
SET NOCOUNT ON

----Get Sport Bettype Matrix------
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
INSERT INTO @SportBettype
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode=4,@ProductId=3

CREATE TABLE #DepAgent (custid int primary key)
	
INSERT INTO #DepAgent 
SELECT custid
FROM custInfo with(NOLOCK)
WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
	AND roleid = 2	
UNION
SELECT 5707545--BARM
	
SELECT		
		b.liveindicator,
		b.bettype bettype,
		case when dep.custid is null then 1 else 2 end as site,
		sum((winlost-actual_stake)*virtualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
		sum(scomm*virtualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,		
		sum((1-tpositiontaking)*stake*actualrate) RealTurnover,
		sum((1-tpositiontaking)*stake*virtualrate) VirtualTurnover
FROM	bettrans b WITH (NOLOCK)
	LEFT JOIN (SELECT custid FROM #DepAgent) dep ON b.recommend = dep.custid
	INNER JOIN @SportBettype s ON s.bettype = b.bettype
WHERE	b.winlostdate = @winlostdate
		--AND b.bettype BETWEEN 81 AND 120	
		AND b.ruben = 1		
		--AND b.status != 'DONE'			
		AND b.statusID not in (101,102,103,121)
GROUP BY b.liveindicator,b.Bettype, case when dep.custid is null then 1 else 2 end
ORDER BY b.liveindicator,b.Bettype, site

DROP TABLE #DepAgent

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_NumberGame] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_NumberGame] TO [vnteam]
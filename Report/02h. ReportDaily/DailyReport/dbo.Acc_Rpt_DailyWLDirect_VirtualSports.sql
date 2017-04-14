ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_VirtualSports]
	@winlostdate	datetime
AS
SET NOCOUNT ON

/*	Creator: Elodie
	Date: 2012-09-19
	Task: Winloss Summary of Virtual sports
	DB: DBACC/bodb02
	
	Revisions: 
		- 20121102@Elodie: Use actual rate instead of virtural rate for Virtual sport		
		- 20130225@Elodie: Add Virtual Horse Racing report
		- 20130801@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)		
		- 20150109@Dom: Apply sport bettype matrix			   
*/
BEGIN
	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode=4,@ProductId=5

	CREATE TABLE #DepAgent (custid int primary key)
	
	INSERT INTO #DepAgent 
	SELECT custid
	FROM custInfo with(NOLOCK)
	WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
		AND roleid = 2
	UNION
	SELECT 5707545--BARM
	
	SELECT
			m.sporttype SportType,
			case when dep.custid is null then 1 else 2 end as site,
			sum((winlost-actual_stake)*actualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
			sum((1-tpositiontaking)*stake*actualrate) Turnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN match m on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
			LEFT JOIN (select custid from #DepAgent) dep ON b.recommend = dep.custid
	WHERE
			b.winlostdate = @winlostdate
			AND s.EventType=1
			--AND b.bettype BETWEEN 1201 AND 1299 and b.bettype not in (1231, 1232, 1233, 1237, 1238)
			AND b.matchid > 0 		
			AND b.statusID NOT IN (101, 102,103) --('VOID', 'REJECT','REFUND') 
			AND b.ruben = 1		
	GROUP BY m.sporttype,case when dep.custid is null then 1 else 2 end

	-- Virtual HR
	UNION ALL
	SELECT
			r.SportType SportType,
			case when dep.custid is null then 1 else 2 end as site,
			sum((winlost-actual_stake)*actualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
			sum((1-tpositiontaking)*stake*actualrate) Turnover
	FROM	bettrans b WITH (NOLOCK)		
			INNER JOIN VSRaceInfo r ON b.matchid = r.EventID
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
			LEFT JOIN (select custid from #DepAgent) dep ON b.recommend = dep.custid
	WHERE
			b.winlostdate = @winlostdate
			AND s.EventType=3
			--AND b.bettype in (1231, 1232, 1233, 1237, 1238)
			AND b.matchid > 0 		
			AND b.statusID NOT IN (101, 102,103) --('VOID', 'REJECT','REFUND') 
			AND b.ruben = 1	
			
	GROUP BY r.sporttype,case when dep.custid is null then 1 else 2 end
	ORDER BY SportType, site		

	DROP TABLE #DepAgent

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_VirtualSports] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_VirtualSports] TO [vnteam]

 
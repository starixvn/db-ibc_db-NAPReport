USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_LiveCasino]
	@winlostdate datetime
AS

/*	Creator: Sophia
	Date: 2012-02-31
	Task: Live Casino WinLost Summary report
	DB: DBACC/bodb02
	
	Revisions:
		- 20130731@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)				
		- 20150109@Dom: Apply sport bettype matrix
		- 20150522@Sophia: Apply Gold Deluxe and revise Sport Betype Matrix [#35359] 
		- 20150702@Sophia: Apply Microgaming and SuperBalance [#38168]
		- 20151111@Percy: Change the sport type: MGC-RNG to MGC and RNG [RedmineID: #46576]
		- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
		- 20160308@Jim: Incorporate Extra PT into 2h report [#53194]
	
*/
SET NOCOUNT ON

----Get Sport Bettype Matrix------
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
INSERT INTO @SportBettype
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5

CREATE TABLE #DepAgent (custid int primary key)

INSERT INTO #DepAgent 
SELECT custid
FROM custInfo with(NOLOCK)
WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
	AND roleid = 2
UNION
SELECT 5707545--BARM


SELECT	s.ProductID, b.bettype ,
		case when dep.custid is null then 1 else 2 end as site,
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
		sum((1-tpositiontaking)*stake*actualrate) Turnover,
		SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost-actual_stake)*actualrate*e.ExtraPT END) AS ExtraPT
		 
FROM	bettrans b WITH (NOLOCK)
	INNER JOIN @SportBettype s ON s.bettype = b.bettype
	LEFT JOIN (select custid from #DepAgent) dep ON b.recommend = dep.custid
	LEFT JOIN  (SELECT DISTINCT ProductID,SuperID,SUM(ExtraPT) ExtraPT FROM bodb_ACC.dbo.Acc_GroupExtraPTSetting   WITH(NOLOCK)  WHERE ProductID IN (4,12,11,13) AND @winlostdate BETWEEN FromDate AND ToDate
				GROUP BY ProductID,SuperID
				) e  ON s.ProductId = e.ProductId and b.srecommend = e.superID 
WHERE	b.winlostdate = @winlostdate
		AND s.ProductId IN (4,12,11,13) -- Live Casino, AG Casino, Gold Deluxe, Microgaming - Live Casino
		AND b.ruben = 1		
		AND b.statusID not in (101,102,103,121)
GROUP BY s.ProductID, b.Bettype, case when dep.custid is null then 1 else 2 end 

UNION ALL -- AllBet Data

SELECT	s.ProductID, b.gameId,
		case when dep.custid is null then 1 else 2 end as site,
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
		sum((1-tpositiontaking)*stake*actualrate) Turnover,
		0 AS ExtraPT
FROM	bettransLC b WITH (NOLOCK)
	INNER JOIN @SportBettype s ON s.bettype = b.gameID
	LEFT JOIN (select custid from #DepAgent) dep ON b.recommend = dep.custid
WHERE	b.winlostdate = @winlostdate
		AND s.ProductId IN (21) -- AllBet		
		AND b.statusID not in (0,1,101,102,103,121)
GROUP BY s.ProductID, b.gameID, case when dep.custid is null then 1 else 2 end 
ORDER BY b.Bettype, site

DROP TABLE #DepAgent


GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_LiveCasino] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_LiveCasino] TO [vnteam] AS [dbo]
GO
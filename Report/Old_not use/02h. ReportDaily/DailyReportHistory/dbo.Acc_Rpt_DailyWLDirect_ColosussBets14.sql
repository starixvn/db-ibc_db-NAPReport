CREATE PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_ColosussBets14]
	@WinlostDate	DATETIME

AS
/*	Creator: 20150828@Sophia
	Task:  2h/ Colossus Bets Winlost Summary Report
	DB: DBACC/bodb02
	
	Revisions: 
		 
		
*/


BEGIN 
SET NOCOUNT ON


----Get Sport Bettype Matrix------
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT, SubProduct VARCHAR(500))
INSERT INTO @SportBettype
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5 


CREATE TABLE #DepAgent (custid int primary key)

INSERT INTO #DepAgent 
SELECT	custid
FROM	dbo.custInfo with(NOLOCK)
WHERE	srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
		AND roleid = 2
UNION
SELECT 5707545--BARM

SELECT	b.bettype
		,CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END AS site
		,SUM ((winlost - actual_stake) * actualrate) WinLost
		,SUM ((awinlost + mwinlost + swinlost) * actualrate) Position
		,SUM (scomm * actualrate) Commission
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) LineTotal
		,SUM ((1 - tpositiontaking) * stake * actualrate) Turnover
	FROM dbo.bettrans14 b WITH (NOLOCK)
		INNER JOIN @SportBettype s
			ON s.bettype = b.bettype
		LEFT JOIN (SELECT custid FROM #DepAgent ) dep
			ON b.recommend = dep.custid
	WHERE	b.winlostdate = @winlostdate
		AND b.ruben = 1
		AND b.statusID NOT IN (101, 102, 103, 121)
		AND s.ProductID = 15
	GROUP BY b.Bettype
			,CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END
	ORDER BY b.Bettype
			,Site


DROP TABLE #DepAgent

END		
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_ColosussBets14] TO [bodbAdminNet]
GO 
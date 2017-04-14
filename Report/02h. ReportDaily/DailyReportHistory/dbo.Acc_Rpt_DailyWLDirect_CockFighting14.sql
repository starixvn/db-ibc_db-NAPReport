ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_CockFighting14]
	@WinlostDate	DATETIME
AS
BEGIN 
SET NOCOUNT ON

/*	Creator: Percy
	Date: 2015-12-16
	Task: Report 2H Winlost Daily for Cock Fighting
	DB: DBACC/bodb02
	
	Revisions:
		- 20151216@Percy: Support new products - Cock Fighting [Redmine: #49027]
		
*/


----Get Sport Bettype Matrix------
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))
INSERT INTO @SportBettype
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5, @ProductID = 19


CREATE TABLE #DepAgent (custid int primary key)

INSERT INTO #DepAgent 
SELECT	custid
FROM	dbo.custInfo with(NOLOCK)
WHERE	srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
		AND roleid = 2
UNION
SELECT 5707545--BARM

SELECT   b.liveindicator
		,b.bettype
		,CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END AS [Site]
		,SUM ((winlost - actual_stake) * actualrate) WinLoss
		,SUM ((awinlost + mwinlost + swinlost) * actualrate) Position
		,SUM (scomm * actualrate) Commission
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualLineTotal
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealLineTotal
		,SUM ((1 - tpositiontaking) * stake * virtualrate) VirtualTurnover
		,SUM ((1 - tpositiontaking) * stake * actualrate) RealTurnover
	FROM dbo.bettrans14 b WITH (NOLOCK)
		INNER JOIN @SportBettype s
			ON s.bettype = b.bettype
		LEFT JOIN (SELECT custid FROM #DepAgent ) dep
			ON b.recommend = dep.custid
	WHERE b.winlostdate = @winlostdate
		AND b.ruben = 1
		AND b.statusID NOT IN (101, 102, 103, 121)
	GROUP BY b.liveindicator
		,b.Bettype
		,CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END
	ORDER BY b.Bettype
		,Site


DROP TABLE #DepAgent


END
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_CockFighting14] TO [bodbAdminNet]
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_CockFighting_Bettype_Site] 
	@winlostdate DATETIME
	,@site TINYINT
AS
/*
	Creator: Percy
	Date: 2015-12-16
	Task: Report 2H Winlost Daily by Site for Cockfighting
	DB: DBACC/bodb02 
		
	Revisions:
		- 20151216@Percy: Support new products - Cockfighting [Redmine: #49027]
			
	Parameter's Explanation:
		- @site: 1: credit
				 2: deposit
*/
----Get Sport Bettype Matrix------
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))
INSERT INTO @SportBettype
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5, @ProductID = 19

BEGIN	
	SET NOCOUNT ON
	CREATE TABLE #DepAgent (custid INT PRIMARY KEY, site VARCHAR(50))
	
	INSERT INTO #DepAgent (custid, site)
	SELECT	c.custid, site
	FROM	dbo.customer c WITH(NOLOCK)
		LEFT JOIN (SELECT custid FROM f_DepSuper_1('All')) dep 
			ON c.srecommend = dep.custid
	WHERE	roleid = 2
			AND 1 = CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
						 WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
			AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid, site)
	SELECT 52466,'XYZBET' WHERE @site = 1--8RM
	UNION
	SELECT 5707545,'BEST-ODDS' WHERE @site =2 --BARM
		
	SELECT ag.site
		,SUM ((winlost - actual_stake) * actualrate) WinLost
		,SUM ((awinlost + mwinlost + swinlost) * actualrate) Position
		,SUM (scomm * actualrate) Commission
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealLineTotal
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualLineTotal
		,SUM ((1 - tpositiontaking) * stake * actualrate) RealTurnover
		,SUM ((1 - tpositiontaking) * stake * actualrate) VirtualTurnover
	FROM dbo.bettrans b WITH (NOLOCK)
		INNER JOIN @SportBettype s
			ON s.bettype = b.bettype
		INNER JOIN #DepAgent ag
		ON b.recommend = ag.custid
	WHERE b.winlostdate = @winlostdate
		AND b.ruben = 1
		AND b.statusID NOT IN (101, 102, 103, 121)
	GROUP BY site
	ORDER BY site


	DROP TABLE #DepAgent
END
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_CockFighting_Bettype_Site] TO [bodbAdminNet]
GO
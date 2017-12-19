CREATE PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_ColosussBets_Site14] 
	@winlostdate DATETIME
	,@site TINYINT

AS
/*
	Creator: 20150828@Sophia
	Task: 2h report/ ColosussBets by site
	DB: DBACC/bodb02 
		
	Revisions:
			
	Parameter's Explanation:
		- @site: 1: credit
				2: deposit	
*/
BEGIN	
	SET NOCOUNT ON

	
	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT, SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5 


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
		,SUM ((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) VirtualLineTotal
		,SUM ((1 - tpositiontaking) * stake * actualrate)  AS RealTurnover
		,SUM ((1 - tpositiontaking) * stake * actualrate) VirtualTurnover
	FROM dbo.bettrans14 b WITH (NOLOCK)
		INNER JOIN @SportBettype s
			ON s.bettype = b.bettype
		INNER JOIN #DepAgent ag
			ON b.recommend = ag.custid
	WHERE b.winlostdate = @winlostdate
		AND b.ruben = 1
		AND b.statusID NOT IN (101, 102, 103, 121)
		AND s.ProductId = 15
	GROUP BY site
	ORDER BY site


	DROP TABLE #DepAgent
END


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_ColosussBets_Site14] TO [bodbAdminNet]
	
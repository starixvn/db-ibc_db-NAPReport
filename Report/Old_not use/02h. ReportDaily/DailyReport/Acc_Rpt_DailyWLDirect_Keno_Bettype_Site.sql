ALTER PROCEDURE Acc_Rpt_DailyWLDirect_Keno_Bettype_Site
	@winlostdate	datetime,	
	@site			TINYINT,
	@bettype		INT
AS

/*	Creator: Dom
	Date: 2014-03-04
	Task: Keno WinLost Summary report
	DB: DBACC/bodb02
	
	Revisions:
			- 2014-03-04@Dom: add param @bettype
			- 20150122@Dom: Apply sport bettype matrix
*/
BEGIN
	SET NOCOUNT ON;

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
	INSERT INTO @SportBettype
	EXEC Acc_SportBettypeMatrix_Sel @mode=4

	CREATE TABLE #DepAgent (custid int primary key , site varchar(50))
	
	INSERT INTO #DepAgent (custid, site)
	SELECT c.custid, site
	FROM customer c WITH(NOLOCK)
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid, site)
	SELECT 52466,'XYZBET' WHERE @site = 1--8RM
	UNION
	SELECT 5707545,'BEST-ODDS' WHERE @site =2 --BARM

	SELECT	
		ag.site,	
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) VirtualLineTotal,		
		sum((1-tpositiontaking)*stake*actualrate) RealTurnover,
		sum((1-tpositiontaking)*stake*actualrate) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE	b.winlostdate = @winlostdate
		--AND b.bettype BETWEEN 1501 AND 1599
		AND s.ProductId=8
		AND b.bettype = @bettype
		AND b.ruben = 1		
		--AND b.status != 'DONE'			
		AND b.statusID not in (101,102,103,121)
	GROUP BY ag.site
	ORDER BY ag.site

	DROP TABLE #DepAgent
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Keno_Bettype_Site] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Keno_Bettype_Site] TO [vnteam]
ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Casino_Bettype_Site]
	@winlostdate DATETIME
	,@ProductId TINYINT
	,@site TINYINT
	,@bettype INT

AS
	/*	Creator: Johnson
		Date: 2013-08-01
		Task: Casino WinLost Summary report by site
		DB: DBACC/bodb02
		
		Revisions: 
			- 20130906@Johnson: get virtual values by virtual rate instead of actual rate
			- 20150703@Sophia: Apply Microgaming and SuperBalance [#38168]
			- 20150806@Sophia: Get Turnover of Macau and Microgaming - RNG Casino (Group Casino)
			- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
			- 20160108@Percy: Calculate turnover for new RNG Casino [Redmine: #49134]
			- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sporttype, bettye matrix function, change the way to get data Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
		Parameter's Explanation:
			- @site: 1: credit
					2: deposit	
			- @ProductId: ProductId of SportBettypeMatrix
			- @bettype : No need now, will enhance later
	*/
BEGIN
	SET NOCOUNT ON

	----Get Sport Bettype Matrix------
     DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	SELECT ProductID,
              Bettype,
              EventType,
              SubProduct
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);

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
		site,
		SUM(WinLost) WinLost,
		SUM(Position) Position,
		SUM(Commission) Commission,
		SUM(RealLineTotal) RealLineTotal,
		SUM(VirtualLineTotal) VirtualLineTotal,
		SUM(RealTurnover) RealTurnover,
		SUM(VirtualTurnover) VirtualTurnover
	FROM (
		SELECT		
				ag.site,
				isnull(sum((winlost-actual_stake)*actualrate),0) WinLost,
				isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
				isnull(sum(scomm*actualrate),0) Commission,	
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate),0) RealLineTotal,
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate),0) VirtualLineTotal,
				isnull(sum((1-tpositiontaking)*(stake)*actualrate),0) AS RealTurnover,
				isnull(sum((1-tpositiontaking)*(stake)*virtualrate),0) AS VirtualTurnover
		FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
			INNER JOIN #DepAgent ag ON b.recommend = ag.custid
		WHERE	b.winlostdate = @winlostdate
				AND s.ProductId = @ProductId
				AND s.ProductId IN (14) -- Macau				
				AND b.statusID NOT IN (102, 101,121,103)  ---('VOID', 'REJECT','done','REFUND') 
				AND b.ruben = 1		
		GROUP BY ag.site
		UNION ALL
		SELECT		
				ag.site,
				isnull(sum((winlost-actual_stake)*actualrate),0) WinLost,
				isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
				isnull(sum(scomm*actualrate),0) Commission,	
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate),0) RealLineTotal,
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate),0) VirtualLineTotal,
				isnull(sum((1-tpositiontaking)*(stake)*actualrate),0) AS RealTurnover,
				isnull(sum((1-tpositiontaking)*(stake)*virtualrate),0) AS VirtualTurnover
		FROM	bettransRnG b WITH (NOLOCK)
			INNER JOIN @SportBettype s ON s.bettype = b.gameID
			INNER JOIN #DepAgent ag ON b.recommend = ag.custid
		WHERE	b.winlostdate = @winlostdate
				AND s.ProductId = @ProductId
				AND s.ProductId IN (6, 17, 22) -- Casino, MGC-RNG, Voidbridge				
				AND b.statusID NOT IN (0, 1, 102, 101,121,103)  ---('VOID', 'REJECT','done','REFUND') 
		GROUP BY ag.site		
	) AS A
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
 GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Casino_Bettype_Site] TO [bodbAdminNet]
GO
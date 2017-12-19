USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Casino]
	@winlostdate	datetime 
AS
	/*	Creator: Phuong Dao
		Date: 2009-05-14
		Task: Casino WinLost Summary report
		DB: DBACC/bodb02
		
		Revisions:
			- 20090731@Jamie: Not to view data in range of date, but only one date at once 
			-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20120405@Hurri: Exclude bettype 72 (P2P bet ticket) in the calculation of Casino
			- 20130703@Kathy: Update matchid for RnG Casino (71)
			- 20130717@Kathy: Apply Progressive Bonus: add bettype 72 for Casino
			- 20130801@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)					   
			- 20150109@Dom: Apply sport bettype matrix
			- 20150702@Sophia: Apply Microgaming and SuperBalance [#38168]
			- 20150806@Sophia: Get Turnover of Macau and Microgaming - RNG Casino (Group Casino)
			- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
			- 20160108@Percy: Calculate turnover for new RNG Casino [Redmine: #49134]
			- 20160308@Jim: Incorporate Extra PT into 2h report [#53194]
			- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sporttype, bettye matrix function, change the way to get data Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
			- 20160722@Percy: Incorporate Macau Games into ExtraPT [RedmineID: #60883]
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


	CREATE TABLE #DepAgent (custid int primary key)
	
	INSERT INTO #DepAgent 
	SELECT custid
	FROM custInfo with(NOLOCK)
	WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
	AND roleid = 2
	UNION
	SELECT 5707545--BARM	
	
	;WITH CTE AS
	(
		SELECT	ProductID, SportType, SubProduct, SuperId, SUM(ExtraPT) AS ExtraPT 
		FROM	bodb_ACC.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
		WHERE	@winlostdate BETWEEN FromDate AND Todate AND ProductID IN (6, 22)
		GROUP BY ProductID, SportType, SubProduct, SuperId
	)
	SELECT
		a.ProductId,
		bettype,
		site,
		SUM(WinLost) WinLost,
		SUM(Position) Position,
		SUM(Commission) Commission,
		SUM(LineTotal) LineTotal,
		SUM(Turnover) Turnover,
		SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE ISNULL(WinLost,0)*e.ExtraPT END) AS ExtraPT  
		 
	FROM (
		SELECT	s.ProductId,	
				b.srecommend,
				1900	AS bettype,
				case when dep.custid is null then 1 else 2 end as site,
				isnull(sum((winlost-actual_stake)*actualrate), 0 ) WinLost,
				isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
				isnull(sum(scomm*actualrate),0) Commission,	
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate),0) LineTotal,
				isnull(sum((1-tpositiontaking)*(CASE WHEN s.ProductID = 6 THEN 0 ELSE stake END)*actualrate),0) AS Turnover
		FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
			left join (select custid from #DepAgent) dep ON b.recommend = dep.custid
		WHERE	b.winlostdate = @winlostdate
				AND s.ProductId IN (14) -- Macau
				AND b.statusID NOT IN (102, 101,121,103)  ---('VOID', 'REJECT','done','REFUND') 
				AND b.ruben = 1		
		GROUP BY s.ProductId, 
				b.srecommend,
				case when dep.custid is null then 1 else 2 end
		UNION ALL
		SELECT	s.ProductId,	
				b.srecommend,
				CASE s.ProductId WHEN 6 THEN 71
								 WHEN 17 THEN 2008
								 WHEN 22 THEN 4001
								 END AS bettype,
				case when dep.custid is null then 1 else 2 end as site,
				isnull(sum((winlost-actual_stake)*actualrate), 0 ) WinLost,
				isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
				isnull(sum(scomm*actualrate),0) Commission,	
				isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate),0) LineTotal,
				isnull(sum((1-tpositiontaking)*(stake)*actualrate),0) AS Turnover			
		FROM	bettransRnG b WITH (NOLOCK)
			INNER JOIN @SportBettype s ON s.bettype = b.gameID
			left join (select custid from #DepAgent) dep ON b.recommend = dep.custid
		WHERE	b.winlostdate = @winlostdate
				AND s.ProductId IN (6, 17, 22) -- Casino, MGC-RNG, Voidbridge
				AND b.statusID NOT IN (0, 1, 102, 101,121,103)  ---('VOID', 'REJECT','done','REFUND') 
		GROUP BY s.ProductId, 
				b.srecommend,
				case when dep.custid is null then 1 else 2 end,
				CASE s.ProductId WHEN 6 THEN 71
								 WHEN 17 THEN 2008
								 WHEN 22 THEN 4001
								 END	
	) AS A
	LEFT JOIN CTE e ON A.ProductId = e.ProductId and a.srecommend = e.superID
	GROUP BY a.ProductId, site, bettype
	ORDER BY a.ProductId, site	
	
	DROP TABLE #DepAgent
END

GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Casino] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Casino] TO [bodbAdminNet]
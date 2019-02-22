/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MGC_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20161206@Harper  
    Task :		House month-to-date Net Income report for MicroGaming
    DB:			DBEXT/bodb02  
   
    Revisions:  
	   - 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures

	Param's Explanation:   
		- 20160315@Harper: PayToSupplier using GMT +0 [RedmindID: #67062]
		- 20170518@Harper: Fixing PayToSupplier [RedmineID: #76695]

	EXEC Acc_Rpt_HouseNetIncome_MGC_Deposit_xtest '20161201', '20161210'
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get list of Products Ref
	DECLARE @ProductsRef AS TABLE (ProductId INT, BettypeRef INT, BettypeId INT, GameTypeName VARCHAR(100))

	INSERT INTO @ProductsRef (ProductId, BettypeId, BettypeRef, GameTypeName)
	SELECT CASE WHEN sp.Sporttype = 203 THEN 14
				WHEN sp.Sporttype = 205 THEN 17 
				ELSE 0 END AS ProductId, 
			sp.Bettype, pr.BettypeRef,
			CASE WHEN pr.BettypeRef = 2001
					THEN 'Generic Games' 
					ELSE 'Branded Games' 
			END AS GameTypeName
	FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
	WHERE pr.BettypeRef IN (2001, 2005) -- 2001 - Generic; 2005 - Branded
	GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef
	-- End Region
	
	-- Region: Get Product Codes -- MGCLC,MGCRNG
	DECLARE @ProductCodes VARCHAR(50)
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + prd.ProductPrefix 
	FROM @ProductsRef pr
		INNER JOIN (
					SELECT Productid, ProductPrefix 
					FROM bodb_licensee..Product3rd WITH (NOLOCK) 
					WHERE Productid IN (SELECT [@ProductsRef].ProductId FROM @ProductsRef)
					) prd ON pr.ProductId = prd.Productid
	GROUP BY prd.Productid, prd.ProductPrefix
	-- End Region

	-- Region: Active Licensee
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT)

	INSERT INTO @tmpParty (PartyID, IsDeposit)	
	SELECT DISTINCT ci.FromParty, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci.ProductID = ci2.ProductID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef
	WHERE p.PartyType = 1
		AND ci.ProductID IN (SELECT DISTINCT ProductId FROM @ProductsRef)
		AND EXISTS (SELECT 1 
					FROM bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) 
					WHERE map.ChargeID = ci.ChargeID and map.SystemID = 2)
			AND ((cis.FromDate BETWEEN @FDate AND @TDate)
				OR (cis.ToDate BETWEEN @FDate AND @TDate)
				OR (cis.FromDate < @FDate AND @TDate < cis.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty where IsDeposit = 1
	-- End region	

	-- Region: ChargeInfo	
	DECLARE @PartyChargeInfo AS TABLE (
		ChargeId			INT,
		PartyId				INT,		
		LicenseeId			INT,
		ProductId			INT,
		BettypeRef			INT,
		Rate				MONEY,
		FromDate			DATE,
		ToDate				DATE)

	INSERT INTO @PartyChargeInfo (ChargeId, PartyId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	SELECT DISTINCT ci.ChargeID, ci.PartyID, LicenseeID, ci.ProductID, ci.Bettype, DI_Rate, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci 	
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange		(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA(ExchangeDate DATE, ExchangeID INT, USD FLOAT, MYR FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate		

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, USD, MYR)
	SELECT ExchangeDate, ExchangeID, CompareCurrencyRate1, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailyForSpecRange(@FDate, @TDate, 'USD', 'USD', 'MYR')
	-- End region	
	
	CREATE TABLE #TempDataMGC(
		RptDate				DATE,
		BettypeRef			INT, 
		GameTypeName		VARCHAR(20),
		PartyId				INT, 		
		CurrencyId			INT, 
		ProductId			INT,	
		LicenseeWinLoss		MONEY,
		LicenseeNetWin		MONEY,
		ProgresCont			MONEY,		
		HouseIncomeDaily	MONEY)

	INSERT INTO #TempDataMGC (RptDate, BettypeRef, GameTypeName, PartyId, CurrencyId, ProductId,
							 LicenseeWinLoss, LicenseeNetWin, ProgresCont, HouseIncomeDaily)
	SELECT d.RptDate, d.BetTypeRef, d.GameTypeName, pci.PartyId, d.CurrencyId, d.ProductId,			
			SUM(LicenseeWinLoss) AS LicenseeWinLoss,
			SUM(LicenseeWinLoss - ProgresCont) AS LicenseeNetWin,
			SUM(ProgresCont) AS ProgresCont,
			SUM((LicenseeWinLoss - ProgresCont) * pci.Rate * e.Rate) AS HouseIncomeDaily
	FROM (
			SELECT rpt.RptDate, SiteId, pr.ProductId, pr.BettypeRef, pr.GameTypeName, CurrencyId, 				
				-SUM(ISNULL(Winloss, 0)) AS LicenseeWinLoss,
				CASE WHEN pr.ProductId = 17 THEN SUM(ISNULL(ProgressiveContribution, 0)) ELSE 0 END  AS ProgresCont -- IF RNG: Contr <> 0, else = 0
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rpt WITH (NOLOCK)
				INNER JOIN @ProductsRef pr ON rpt.BetTypeId = pr.BettypeId
			WHERE rpt.RptDate BETWEEN @FromDate AND @ToDate
				  AND rpt.SiteId IN (SELECT DISTINCT LicenseeId FROM @PartyChargeInfo)
				  AND CurrencyID <> 20
				  AND StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY rpt.RptDate, SiteId, pr.ProductId, pr.BettypeRef, CurrencyId, pr.GameTypeName
			) d
		INNER JOIN @PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BettypeRef = pci.BettypeRef AND pci.ProductId = d.ProductId
		INNER JOIN #Exchange e ON e.ExchangeDate = d.RptDate AND e.ExchangeID = d.CurrencyId
	WHERE d.RptDate BETWEEN pci.Fromdate AND pci.ToDate
	GROUP BY d.RptDate, d.GameTypeName, d.BettypeRef, pci.PartyId, d.ProductId, d.CurrencyId
		
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataMGC (PartyId)

	-- Region: Caculate PayToSupplier value
	DECLARE @ProductChargeInfo AS TABLE (
			ParentId		INT, 			
			BettypeRef		INT, 
			ChargeType		INT, 
			Rate			MONEY, 
			MinAmount		MONEY, 
			MaxAmount		MONEY, 
			CurrencyId		INT, 
			CurrencyCode	VARCHAR(3),
			FromDate		DATE,
			ToDate			DATE)
	
	INSERT INTO @ProductChargeInfo (ParentId, BettypeRef, ChargeType, Rate, MinAmount, MaxAmount, CurrencyId, CurrencyCode, FromDate, ToDate)
	SELECT DISTINCT a.FromParty, a.BettypeRef, a.ChargeType, a.Rate, 
					CASE WHEN a.ChargeType = 4 THEN a.MinAmount * ex.MYR ELSE 0 END MinAmount,
					CASE WHEN a.ChargeType = 4 THEN a.MaxAmount * ex.MYR ELSE 0 END MaxAmount,
					2, 'MYR', -- Convert to MYR to compare
					a.FromDate, a.ToDate
	FROM (
			SELECT DISTINCT ci2.ChargeID, cis.FromParty, cis.BettypeRef, cis.ChargeType, 
							cis.Rate, ISNULL(cis.MinAmount, 0) AS MinAmount, ISNULL(cis.MaxAmount, 0) AS MaxAmount, cis.BaseCurrencyId, cis.FromDate, cis.ToDate
			FROM @PartyChargeInfo tp
				INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON tp.ChargeId = ci.ChargeID
				LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci2.ProductID = tp.ProductID
				LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef
			WHERE tp.ChargeId > 0
		) a	
	LEFT JOIN #ExchangeOANDA ex ON a.BaseCurrencyId = ex.ExchangeID
			
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)

	DECLARE @HouseNetIncome MONEY
	SELECT @HouseNetIncome = SUM(CASE WHEN s.SumByProduct <= 0 THEN 0 ELSE s.SumByProduct END) 
	FROM ( 
			SELECT SUM (HouseIncomeDaily) AS SumByProduct 
			FROM #TempDataMGC GROUP BY ProductId, BettypeRef
		) s
									   								
	INSERT INTO #FinalResult (RptDate, LicenseeWL)
	SELECT 'FullRange', @HouseNetIncome	

	-- Processing daily data
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(HouseIncomeDaily), 0) FROM #TempDataMGC WHERE RptDate = @tmpDate) -- LicenseeWL		

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	
	-- PayToSupplier Using 	
	CREATE TABLE #TempDataMGC3rd(
		RptDate3rd			DATE,
		BettypeRef			INT, 
		GameTypeName		VARCHAR(20),
		PartyId				INT, 		
		CurrencyId			INT, 
		ProductId			INT,	
		LicenseeWinLoss		MONEY,
		LicenseeNetWin		MONEY,
		ProgresCont			MONEY,		
		HouseIncomeDaily	MONEY)

	INSERT INTO #TempDataMGC3rd (RptDate3rd, BettypeRef, GameTypeName, PartyId, CurrencyId, ProductId,
							 LicenseeWinLoss, LicenseeNetWin, ProgresCont, HouseIncomeDaily)
	SELECT d.RptDate3rd, d.BetTypeRef, d.GameTypeName, pci.PartyId, d.CurrencyId, d.ProductId,			
			SUM(LicenseeWinLoss) AS LicenseeWinLoss,
			SUM(LicenseeWinLoss - ProgresCont) AS LicenseeNetWin,
			SUM(ProgresCont) AS ProgresCont,
			SUM((LicenseeWinLoss - ProgresCont) * pci.Rate * e.Rate) AS HouseIncomeDaily
	FROM (
			SELECT rpt.RptDate3rd, SiteId, pr.ProductId, pr.BettypeRef, pr.GameTypeName, CurrencyId, 				
				-SUM(ISNULL(Winloss, 0)) AS LicenseeWinLoss,
				CASE WHEN pr.ProductId = 17 THEN SUM(ISNULL(ProgressiveContribution, 0)) ELSE 0 END  AS ProgresCont -- IF RNG: Contr <> 0, else = 0
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rpt WITH (NOLOCK)
				INNER JOIN @ProductsRef pr ON rpt.BetTypeId = pr.BettypeId
			WHERE rpt.RptDate3rd BETWEEN @FromDate AND @ToDate
				  AND rpt.SiteId IN (SELECT DISTINCT LicenseeId FROM @PartyChargeInfo)
				  AND CurrencyID <> 20
				  AND StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY rpt.RptDate3rd, SiteId, pr.ProductId, pr.BettypeRef, CurrencyId, pr.GameTypeName
			) d
		INNER JOIN @PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BettypeRef = pci.BettypeRef AND pci.ProductId = d.ProductId
		INNER JOIN #Exchange e ON e.ExchangeDate = d.RptDate3rd AND e.ExchangeID = d.CurrencyId
	WHERE d.RptDate3rd BETWEEN pci.Fromdate AND pci.ToDate
	GROUP BY d.RptDate3rd, d.GameTypeName, d.BettypeRef, pci.PartyId, d.ProductId, d.CurrencyId
		
	; WITH sums AS 
				(	SELECT b.BettypeRef, CONVERT(VARCHAR(2), b.RptDate3rd, 106) AS RptDate3rd, b.RptDate3rd AS FullDate
						, SUM(b.LicenseeNetWin * e.MYR) AS LicenseeNetWin
					FROM #TempDataMGC3rd b
						INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate3rd AND e.ExchangeID = b.CurrencyId	
					GROUP BY b.BettypeRef, CONVERT(VARCHAR(2), b.RptDate3rd, 106), b.RptDate3rd
				),
	MicrogamingFee AS
	(
		SELECT s.BettypeRef, s.RptDate3rd, s.FullDate,		 
				CASE 
					WHEN (ChargeType = 4 AND (s.LicenseeNetWin < 0 AND r.MinAmount = 0) OR (s.LicenseeNetWin BETWEEN r.MinAmount AND r.MaxAmount)) 
					THEN CASE 						
							WHEN MinAmount = 0 THEN s.LicenseeNetWin * r.Rate
							WHEN MinAmount > 0 THEN ((s.LicenseeNetWin - MinAmount) * Rate) + (r.MinAmount * 0.1)
							ELSE 0 END
					ELSE 0 END +			
				CASE 
					WHEN ChargeType = 1 THEN s.LicenseeNetWin * Rate ELSE 0 END
				AS PayToSupplier
		FROM sums s INNER JOIN  @ProductChargeInfo r
				ON s.BettypeRef = r.BettypeRef AND s.FullDate BETWEEN r.FromDate AND r.ToDate
	),
	AmtByDate AS
	(
		SELECT f.RptDate3rd, SUM(f.PayToSupplier) AS PayToSupplierByDate
		FROM MicrogamingFee f
		GROUP BY f.RptDate3rd
	)
	UPDATE r
	SET r.PayToSupplier = (-1) * m.PayToSupplierByDate
	FROM AmtByDate m 
		INNER JOIN #FinalResult r ON r.RptDate = m.RptDate3rd	
		
	-- Monthly
	; WITH sums AS 
				(	SELECT b.BettypeRef
						, SUM(b.LicenseeNetWin * e.MYR) AS LicenseeNetWin
						, ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount, ci.MaxAmount, ci.ChargeType
					FROM #TempDataMGC3rd b
						INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate3rd AND e.ExchangeID = b.CurrencyId
						INNER JOIN @ProductChargeInfo ci ON b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate AND b.BettypeRef = ci.BettypeRef	
					GROUP BY b.BettypeRef, ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount, ci.MaxAmount, ci.ChargeType
				),
	AmtByMonth AS
	(
		SELECT s.BettypeRef,
			CASE 
					WHEN (ChargeType = 4 AND (s.LicenseeNetWin BETWEEN s.MinAmount AND s.MaxAmount)) 
					THEN CASE 						
							WHEN MinAmount = 0 THEN s.LicenseeNetWin * s.Rate
							WHEN MinAmount > 0 THEN ((s.LicenseeNetWin - MinAmount) * Rate) + (s.MinAmount * 0.1)
							ELSE 0 END
					ELSE 0 END +
				CASE 
					WHEN ChargeType = 1 AND s.LicenseeNetWin > 0 THEN s.LicenseeNetWin * Rate ELSE 0 END
				AS PayToSupplier
		FROM sums s
	)
	UPDATE #FinalResult
	SET PayToSupplier = (SELECT (-1) * SUM(PayToSupplier) FROM AmtByMonth)
	WHERE RptDate LIKE 'FullRange'

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''MGC'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''MGC'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #TempDataMGC
	DROP TABLE #FinalResult
	DROP TABLE #TempDataMGC3rd
END
GO

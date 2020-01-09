/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_AGC_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of NonSport product margin
    Source : Acc_Rpt_HouseNetIncome_AGC_Deposit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_AGC_Deposit '2018-04-01', '2018-04-30'
  
*/   
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Active licensees	
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, ParentID INT, AGCRate FLOAT)

	INSERT INTO @tmpParty (PartyID, IsDeposit, ParentID)	
	SELECT DISTINCT ci.FromParty, pd.IsDeposit, ci.ToParty
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
	WHERE	p.PartyType = 1
			AND ci.ProductId = 10 -- AG Casino (in Product3rd)
			AND EXISTS (SELECT 1 
						FROM bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) 
						WHERE map.ChargeID = ci.ChargeID and map.SystemID = 2)
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty
	-- End region

	-- Region: ChargeInfo
	DECLARE @PartyChargeInfo AS TABLE (
			ChargeId		INT,
			PartyId			INT,
			LicenseeId		INT,
			IsDeposit		BIT,
			ProductID		INT,
			Rate			MONEY,
			FromDate		SMALLDATETIME,
			ToDate			SMALLDATETIME,
			Bettype			INT)

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT	ci.ChargeId, ci.PartyID, ci.LicenseeID, ci.isDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'AGC', 'OA', 1) ci
			LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange		(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA(ExchangeDate DATE, ExchangeID INT, CNY FLOAT, USD FLOAT, MYR FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate		

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, CNY, USD, MYR)
	SELECT ExchangeDate, ExchangeID, CompareCurrencyRate1, CompareCurrencyRate2, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailyForSpecRange(@FDate, @TDate, 'CNY', 'USD', 'MYR')
	-- End region	
	
	CREATE	TABLE #TempDataAGC (
			PartyId			INT,
			RptDate		DATETIME,
			CurrencyId		INT,
			WinLoss			MONEY,	
			LicenseeWL		MONEY,
			AmountToCompany MONEY)

	INSERT INTO #TempDataAGC (PartyId, RptDate, CurrencyId, WinLoss, LicenseeWL, AmountToCompany)
	(
		SELECT	p.PartyId,
				b.rptdate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)),
				SUM(-ISNULL(b.MemberWL, 0)),
				SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate)
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, p.PartyId, b.CurrencyID		
	)
	
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataAGC (PartyId)
		
	-- Region: Get Rate, using Compare rate to get charge rate
	; WITH sums AS 
				(	SELECT t.ParentID,
						SUM(CASE WHEN t.ParentID = 1 THEN b.LicenseeWL * cny.CNY ELSE b.LicenseeWL * usd.USD END) AS SumApplyValue
					FROM #TempDataAGC b
						INNER JOIN @tmpParty t ON b.PartyId = t.PartyID
						INNER JOIN #ExchangeOANDA cny ON b.CurrencyId = cny.ExchangeID AND cny.ExchangeDate = b.RptDate
						INNER JOIN #ExchangeOANDA usd ON b.CurrencyId = usd.ExchangeID AND usd.ExchangeDate = b.RptDate
					GROUP BY ParentID
				)	 
	 UPDATE t	 
	 SET t.AGCRate = CASE WHEN t.ParentId = 1
						THEN
							CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
						ELSE
							CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END
						END
	 FROM @tmpParty t
		INNER JOIN sums s ON t.ParentID = s.ParentID			
	-- End Region

	-- Region: Result	
	CREATE TABLE #FinalResult (
		RptDate			VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)
	
	-- Pay to Supplier using OANDA rate (CurrencyID = 2 => MYR)
	DECLARE @DailyPayAmt TABLE (RptDate DATE, ParentID INT, AmountDaily MONEY, 
								LicenseeWL MONEY, AGCRate FLOAT)
	
	INSERT INTO @DailyPayAmt (RptDate, ParentID, AmountDaily, LicenseeWL, AGCRate)
	SELECT d.RptDate, p.ParentID, SUM(d.WinLoss * oanda.MYR * p.AGCRate), SUM(d.LicenseeWL * oanda.MYR), p.AGCRate
	FROM #TempDataAGC d
		INNER JOIN @tmpParty p ON p.PartyID = d.PartyId
		INNER JOIN #ExchangeOANDA oanda ON d.RptDate = oanda.ExchangeDate AND d.CurrencyId = oanda.ExchangeID
	GROUP BY d.RptDate, p.ParentID, p.AGCRate
	
	INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, 0

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #TempDataAGC WHERE RptDate = @tmpDate),	-- LicenseeWL
			(SELECT ISNULL(SUM(AmountDaily), 0) FROM @DailyPayAmt WHERE RptDate = @tmpDate)		-- PayToSupplier			

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''AGC'', 1, ''House Income'', LicenseeWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''AGC'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataAGC
	DROP TABLE #FinalResult
	--DROP TABLE #FeeData
END
GO
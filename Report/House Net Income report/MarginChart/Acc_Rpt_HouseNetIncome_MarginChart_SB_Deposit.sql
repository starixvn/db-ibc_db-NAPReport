/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_SB_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Deposit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only

	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_SB_Credit '2017-12-01', '2017-12-31'
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, IsDeposit)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
	WHERE	p.PartyType = 1
			AND ci.ProductId = 0 -- SB
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty WHERE IsDeposit = 1
	-- End region

	DECLARE @PartyChargeInfo AS TABLE (
			ChargeId	INT,
			PartyId		INT,
			LicenseeId	INT,
			IsDeposit	BIT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT	ci.ChargeId, ci.PartyID, ci.LicenseeID, ci.isDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'SB,BA', 'OA', 1) ci
			LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End region

	-- Region: Fee Data
	CREATE TABLE #FeeData (
		PartyId			INT,
		ProductID		INT,
		AComm			MONEY,
		MinFeeApplied	MONEY,
		WLFeeApplied	MONEY,
		AmountToCompany	MONEY
	)

	INSERT INTO #FeeData(PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
	EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = 'SB,BA'

	-- Region: HAIFA - Adding more discount rate
	CREATE TABLE #DiscountGroup(DiscountGroupId		SMALLINT,
								DiscountGroupType	TINYINT,
								FromAmount			MONEY,
								ToAmount			MONEY,
								Rate				MONEY,
								PartyId				INT,
								ProductId			TINYINT,
								BaseCurrency		INT)

	INSERT INTO #DiscountGroup( DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId, BaseCurrency)
	EXEC Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA @FromDate = @FDate, @ToDate = @TDate, @ProductCodes = 'SB'

	-- Apply discount & rebate
	;WITH t AS(
			SELECT SUM(s.AmountToCompany) Total, s.PartyId, d.DiscountGroupId
			FROM #FeeData s
			INNER JOIN (SELECT DISTINCT DiscountGroupId,PartyId,ProductId FROM #DiscountGroup WHERE DiscountGroupType = 1) AS d
				ON s.PartyId=d.PartyId AND s.ProductId=d.ProductId
			GROUP BY s.PartyId, d.DiscountGroupId
		)
		DELETE d
		FROM #DiscountGroup d
			INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId AND t.PartyId = d.PartyId
		WHERE d.DiscountGroupType = 1 AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount
	
	-- End Region: HAIFA

	CREATE	TABLE #TempDataSB (
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			WinLoss			MONEY,
			AComm			MONEY,
			ProductId		TINYINT,
			AmountToCompany MONEY,
			IsApplyMinFee	BIT,
			DiscountAmount	MONEY,
			TurnOver		MONEY)

	INSERT INTO #TempDataSB (PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,AmountToCompany, IsApplyMinFee, DiscountAmount, TurnOver)
	(
		SELECT	p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(CASE WHEN b.customercategory NOT IN (27, 28) THEN ISNULL(b.MemberWL, 0) ELSE 0 END * e.Rate),
				SUM(CASE WHEN b.customercategory NOT IN (27, 28) THEN ISNULL(b.CommissionA, 0) ELSE 0 END * e.Rate),
				p.ProductId,
				SUM(CASE WHEN b.customercategory NOT IN (27, 28) THEN -ISNULL(b.MemberWL, 0) ELSE 0 END * ISNULL(lc.Rate, p.Rate) * e.Rate),
				1 AS IsApplyMinFee,
				SUM(CASE WHEN b.customercategory NOT IN (27, 28) THEN -ISNULL(b.MemberWL, 0) ELSE 0 END * ISNULL(d.Rate, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate),
				SUM(ISNULL(b.Turnover, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate) - SUM(ISNULL(b.Turnover, 0) * ISNULL(d.Rate, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate)
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
				LEFT JOIN #DiscountGroup d ON d.PartyId = p.PartyId AND d.ProductId = p.ProductID
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyID <> 20
				--AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904)
				AND b.StatusId NOT IN (-1, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId--, e.Rate, d.Rate
	)
		
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataSB (PartyId, ProductId)	

	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		DiscountWL			MONEY,
		MinFee				MONEY,
		BAComm				MONEY,
		PayToMuayThai		MONEY,
		PayToMetricGaming	MONEY,
		TurnOver			MONEY
	)

	DECLARE @BAComm MONEY = 0, @BAWinloss MONEY = 0
	SELECT	@BAComm = ISNULL(-SUM(AComm), 0),
			@BAWinloss = ISNULL(SUM(AmountToCompany), 0)
	FROM #FeeData WHERE ProductId = 3

	DECLARE @TurnOver MONEY = 0
	SELECT @TurnOver = ISNULL(SUM(TurnOver), 0) FROM #TempDataSB WHERE ProductId IN (0, 3)

	INSERT INTO #FinalResult (rptDate, LicenseeWL, DiscountWL, MinFee, BAComm, PayToMuayThai, PayToMetricGaming, TurnOver)
	SELECT 'FullRange', ISNULL(SUM(WLFeeApplied) + @BAWinloss, 0), 0, ISNULL(SUM(MinFeeApplied), 0), ISNULL(@BAComm, 0), 0, 0, @TurnOver
	FROM #FeeData
	WHERE ProductID = 0

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, DiscountWL, MinFee, BAComm, PayToMuayThai, PayToMetricGaming, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #TempDataSB WHERE ProductId IN (0, 3) AND rptDate = @tmpDate), -- LicenseeWL + BA Winloss
			(SELECT -ISNULL(SUM(DiscountAmount), 0) FROM #TempDataSB WHERE ProductId = 0 AND rptDate = @tmpDate),
			0 AS MinFee,
			(SELECT ISNULL(-SUM(AComm), 0) FROM #TempDataSB WHERE ProductId = 3 AND rptDate = @tmpDate), -- BA Commission
			0, 0,
			(SELECT ISNULL(SUM(TurnOver), 0) FROM #TempDataSB WHERE ProductId IN (0, 3) AND rptDate = @tmpDate) -- TurnOver

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Pay to Metric Gaming -------------------------------------------------------
	-- Get Party list, including credit licensees
	SET @PartyIDs = NULL
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty

	DELETE FROM @PartyChargeInfo
	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	SELECT	ChargeId, PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
	FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)
	WHERE	DI_Rate > 0

	CREATE TABLE #MetricGamingData (LicenseeID INT, PartyID INT, RptDate DATE, CurrencyID INT, LicenseeWL MONEY, AmtLicensee MONEY)
	INSERT INTO #MetricGamingData (LicenseeID, PartyId, RptDate, CurrencyId, LicenseeWL, AmtLicensee)
	SELECT	b.SiteID,
			p.PartyId,
			b.rptDate,
			b.CurrencyID,
			SUM(CASE WHEN p.IsDeposit = 0 
						THEN (-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS)
						ELSE -b.WinLoss
				END) LicenseeWL,
			SUM(CASE WHEN p.IsDeposit = 0 
						THEN (-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS) * ISNULL(lc.Rate, p.Rate)
						ELSE -b.WinLoss * ISNULL(lc.Rate, p.Rate)
				END) AmtLicensee
	FROM	bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteID = p.LicenseeId  AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
	WHERE	b.rptDate BETWEEN @FDate AND @TDate
			AND (b.CurrencyID <> 20)
			AND b.[Status] BETWEEN 111 AND 113
			AND b.customercategory NOT IN (27, 28)
			AND b.Bettype BETWEEN 800 AND 899 -- Metric Gaming Bettype In Sportsbook
	GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId

	-- Apply currency rate
	UPDATE b
	SET LicenseeWL = LicenseeWL * e.Rate,
		AmtLicensee = AmtLicensee * e.Rate
	FROM #MetricGamingData b
		INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate AND e.ExchangeID = b.CurrencyID

	-- Get Metric Gaming charge info
	DECLARE @ProductChargeInfo TABLE (
			Rate FLOAT,
			FromDate SMALLDATETIME,
			ToDate SMALLDATETIME,
			MinAmount MONEY,
			MaxAmount MONEY)

	INSERT INTO @ProductChargeInfo(Rate, FromDate, ToDate, MinAmount, MaxAmount)
	SELECT	ci.Rate,
			CASE WHEN @FDate >= ci.FromDate THEN @FDate ELSE ci.FromDate END AS FromDate,
			CASE WHEN @TDate < ci.ToDate THEN @TDate ELSE ci.ToDate END AS ToDate,
			ci.MinAmount * ex.Rate,
			ci.MaxAmount * ex.Rate
	FROM bodb_licensee.dbo.OAS_ChargeInfo ci
	INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate
	WHERE ci.ProductID = 0 AND ci.FromParty = 1 AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming
		AND ((ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	; WITH WLAmount AS
	(
		SELECT CONVERT(VARCHAR(2), RptDate, 106) rptDate,
			rptDate FullDate,
			SUM(AmtLicensee) AS AmtLicensee
		FROM #MetricGamingData
		GROUP BY CONVERT(VARCHAR(2), RptDate, 106), rptDate
	),
	MetricGamingFee AS
	(
		SELECT wl.*, ci.MinAmount, ci.MaxAmount, ci.Rate, 
			CASE 
				WHEN (AmtLicensee < 0 AND ci.MinAmount = 0) OR (AmtLicensee >= ci.MinAmount) THEN 
					CASE 
						WHEN AmtLicensee > MaxAmount THEN ci.MaxAmount - ci.MinAmount
						ELSE AmtLicensee - ci.MinAmount
					END
				ELSE 0
			END * ci.Rate AS AmtByRange
		FROM WLAmount wl
			INNER JOIN @ProductChargeInfo ci ON wl.FullDate BETWEEN ci.FromDate AND ci.ToDate
	),
	AmtByDate AS
	(
		SELECT m.rptDate, SUM(AmtByRange) AS AmtByDate	
		FROM MetricGamingFee m
		GROUP BY m.rptDate
	)
	UPDATE r
	SET PayToMetricGaming = -AmtByDate
	FROM AmtByDate m
		INNER JOIN #FinalResult r ON r.RptDate = m.rptDate

	-- Calculate Pay to Metric gaming amount
	;WITH WLAmount AS
	(
		SELECT ci.*, SUM(d.AmtLicensee) AS AmtLicensee
		FROM @ProductChargeInfo ci
			INNER JOIN #MetricGamingData d ON d.RptDate BETWEEN ci.FromDate AND ci.ToDate
		GROUP BY ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount, ci.MaxAmount
	),
	AmtByRange AS
	(
		SELECT wl.*, 
			CASE 
				WHEN AmtLicensee>MinAmount THEN 
					CASE 
						WHEN AmtLicensee > MaxAmount THEN MaxAmount - MinAmount 
						ELSE AmtLicensee - MinAmount 
					END
				ELSE 0 
			END * Rate AS AmtDue
		FROM WLAmount wl
	)
	UPDATE #FinalResult
	SET PayToMetricGaming = -(SELECT SUM(AmtDue) FROM AmtByRange)
	WHERE RptDate LIKE 'FullRange'

	---------------------------------------------------- Pay to Muay Thai -------------------------------------------------------

	DELETE FROM @PartyChargeInfo
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
	FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)

	DECLARE @MuayThaiData TABLE (rptDate DATE, AmtDueMuayThai MONEY)
	DECLARE @ShareRate MONEY = 0.03
	DECLARE @CutOfDate		SMALLDATETIME,
			@TmpFromDate	SMALLDATETIME,
			@TmpToDate		SMALLDATETIME 

	SELECT @CutOfDate = '2017-09-30' -- New formula when caculate muaythai ticket be applied	

	IF @FDate < @CutOfDate -- Old Data: incase when handle script by hand for regen past email
	BEGIN
		INSERT INTO @MuayThaiData
		SELECT	b.rptDate,
				SUM(ISNULL(b.WLShare * e.Rate, 0) + ISNULL(b.CommShare * e.Rate, 0)) AmtDueMuayThai
		FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
												AND b.SiteID = p.LicenseeId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.rptDate AND e.ExchangeID = b.CurrencyId
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND (b.CurrencyID <> 20)
				AND b.StatusId BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.SportType = 44 -- Muay Thai
		GROUP BY b.rptdate
	END
	ELSE
	BEGIN
		INSERT INTO @MuayThaiData
		SELECT	b.rptDate,
				SUM(ISNULL(b.AdjustedCustomerWL * e.Rate * (-@ShareRate), 0) + ISNULL(b.AdjustedCommShare * e.Rate, 0)) AmtDueMuayThai
		FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
												AND b.SiteID = p.LicenseeId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.rptDate AND e.ExchangeID = b.CurrencyId
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND (b.CurrencyID <> 20)
				AND b.StatusId BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.SportType = 44 -- Muay Thai
		GROUP BY b.rptdate
	END

	-- Update Full range value
	UPDATE #FinalResult 
	SET PayToMuayThai = -(SELECT ISNULL(SUM(AmtDueMuayThai), 0) FROM @MuayThaiData)
	WHERE RptDate LIKE 'FullRange'

	-- Update daily amount
	UPDATE r
	SET PayToMuayThai = -d.AmtDueMuayThai
	FROM #FinalResult r
		INNER JOIN @MuayThaiData d ON r.RptDate = CONVERT(VARCHAR(2), d.RptDate, 106)

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SB'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 2, ''Licensing Minimum Fee'', MinFee' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 4, ''Rebate & Discount'', DiscountWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 5, ''BA Commission'', BAComm' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 6, ''Pay to Muay Thai'', PayToMuayThai' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 8, ''Turn Over'', TurnOver' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 7, ''Pay to Metric Gaming'', PayToMetricGaming) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataSB
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #DiscountGroup
	DROP TABLE #MetricGamingData
END
GO
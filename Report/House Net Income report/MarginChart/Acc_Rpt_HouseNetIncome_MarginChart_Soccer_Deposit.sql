/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Soccer [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit '2018-04-01', '2018-04-30'
  
*/    
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Handle data of Soccer
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),		
		PayToMetricGaming	MONEY
	)

	INSERT INTO #FinalResult (rptDate, PayToMetricGaming)
	SELECT 'FullRange', 0

	-- Date list to draw chart
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, PayToMetricGaming)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Region: Get exchange rate info	
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End region	
	
	---------------------------------------------------- Pay to Metric Gaming ----------------------------------------------------
	
	-- Region: Get Party list, including credit licensees	
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
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty

	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			IsDeposit	BIT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)
	
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
	FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)
	WHERE	DI_Rate > 0
	-- End Region: Get Party list, including credit licensees	

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
						THEN (-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS) * p.Rate
						ELSE -b.WinLoss * p.Rate 
				END) AmtLicensee
	FROM	bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteID = p.LicenseeId 
			AND b.rptDate BETWEEN p.FromDate AND p.ToDate
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
		
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''Soccer'', 7, ''Pay to Metric Gaming'', PayToMetricGaming) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop temp table
	DROP TABLE #ExchangeOANDA
	DROP TABLE #MetricGamingData
	DROP TABLE #FinalResult

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit] TO vnteam
GO
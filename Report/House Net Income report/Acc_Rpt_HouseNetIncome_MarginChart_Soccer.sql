/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer]
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

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer '2017-12-01', '2017-12-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
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

	-- Region: Handle data of Soccer
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		HouseWL				MONEY,
		ExtraPT				MONEY,
		TurnOver			MONEY,
		ExtraTO				MONEY,
		PayToMetricGaming	MONEY,
	)

	-- Date list to draw chart
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver, ExtraTO, PayToMetricGaming)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.ExtraWLAfterComm_RM) AS ExtraPT, SUM(b.ExtraTO_RM) AS ExtraTO
		FROM bodb_account.dbo.rptExtraPTBySite b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 1
				AND b.statusid <> 14
		GROUP BY b.rptDate
	)
	UPDATE f
	SET f.ExtraPT = e.ExtraPT,
		f.ExtraTO = e.ExtraTO
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL of Soccer + Parlay + Metrix Gaming
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, TurnOver MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, TurnOver)
	SELECT 
		b.rptDate,
		ISNULL(-SUM(CASE WHEN b.SiteID NOT IN (-2, -4)THEN (winlossP + winlossS + winlossM + winlossA + commissionS) ELSE 0 END * ex.rate), 0) HouseWL,
		ISNULL(SUM(b.TurnoverIBC * ex.Rate), 0) TurnOver
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
		INNER JOIN #SportBettypeMatrix s ON b.bettype = s.Bettype -- Get all data of SB		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND b.status <> 14	
		AND (
				b.bettype IN (9, 29) -- Parlay
				OR (s.EventType IN (1, 2, 4) AND s.SubProduct = 'MG-SuperLive') -- Metrix Gaming
				OR (s.EventType IN (1, 2, 4) AND s.SubProduct <> 'MG-SuperLive' 
					AND EXISTS (SELECT 1 
								FROM bodb_Account.dbo.League l  WITH(NOLOCK)
								WHERE b.LeagueId = l.LeagueId AND l.sportid = 1)
								) -- Soccer
			)
	GROUP BY b.rptDate	
	OPTION (RECOMPILE)
	
	UPDATE f
	SET HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0),
		f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0) - ISNULL(f.ExtraTO, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate		


	---------------------------------------------------- Pay to Metric Gaming -------------------------------------------------------
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

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT	ci.PartyID, ci.LicenseeID, ci.isDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'SB,BA', 'OA', 1) ci
			LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)

	DELETE FROM @PartyChargeInfo
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
							'(SELECT ''SB'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
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

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #Exchange
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer] TO vnteam
GO
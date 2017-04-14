USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_LicenseeFee]
	@FromDate DATE,
	@ToDate	DATE,
	@Products VARCHAR(100)
AS  
/*  
	Created: Victor  
	Date: 2016-06-24  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions:
	Param's Explanation:   
*/  
BEGIN  
	SET NOCOUNT ON  
	DECLARE @ProductList TABLE (ProductID INT, ProductCode VARCHAR(10))

	INSERT INTO @ProductList (ProductID, ProductCode)
	SELECT CASE WHEN pl.val = 'SB' THEN 0 ELSE p.Productid END ProductID, val
	FROM dbo.Lrf_f_StringSplit(@Products, ',') pl
		LEFT JOIN bodb_licensee.dbo.Product3rd p WITH (NOLOCK) ON p.ProductPrefix = pl.val

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
	WHERE	p.PartyType = 1 AND
			ci.ProductId IN (SELECT ProductID FROM @ProductList)
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty WHERE IsDeposit = 1
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	-- End region

	-- Region: Party charge info
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
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, @Products, 'OA', 1) ci
			LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region
	
	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
	-- Region: MinfeeGroup Date range
	DECLARE @Month TINYINT = MONTH(@FDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT)
	INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
	(
		SELECT	PartyGroupId, PartyId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
									FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
									WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @tmpParty p2))
	)

	DECLARE @MinFeeGroup TABLE(
			FeeType			TINYINT,
			PartyId			INT,
			ProductId		INT,
			CurrencyId		INT,
			FeeAmount		MONEY,
			FromDate		DATETIME,
			ToDate			DATETIME,
			MinFeeProrate	MONEY,
			WaivedAmount	MONEY,
			TotalAmount		MONEY,
			MinFeeAmount	MONEY,
			AmountToCompany	MONEY)

	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT	mf.FeeTypeId,
				mf.PartyId,
				mf.ProductId,
				mf.CurrencyId,
				mf.FeeAmount,
				CASE WHEN @FDate >= mf.FromDate THEN @FDate ELSE mf.FromDate END AS FromDate,
				CASE WHEN @TDate < mf.ToDate THEN @TDate ELSE mf.ToDate END AS ToDate
		FROM	bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE	((mf.FeeTypeId = 1)
					OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId
													FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
													WHERE	m.FeeTypeId = 1
															AND m.PartyId = mf.PartyId
															AND m.ProductId = mf.ProductId
															AND ((m.FromDate BETWEEN @FirstDate AND @LastDate)
																OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
																OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
															)
													)
				)
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
				)
	)

	-- End region

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
		INNER JOIN #Exchange e ON e.ExchangeDate = @TDate AND m.CurrencyId = e.ExchangeID

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			WinLoss			MONEY,
			AComm			MONEY,
			ProductId		TINYINT,
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	INSERT INTO #TempData (PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,AmountToCompany, IsApplyMinFee)
	(
		SELECT	p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)) * e.Rate,
				SUM(ISNULL(b.CommissionA, 0)) * e.Rate,
				p.ProductId,
				SUM(-ISNULL(b.MemberWL, 0) * p.Rate) * e.Rate,
				1 AS IsApplyMinFee
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904)
				AND b.StatusId NOT IN (-1, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.

	UPDATE  t
	SET		t.IsApplyMinFee = 0
	FROM	#TempData t 
		INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
			AND t.ProductId = m.ProductId
			AND t.PartyId = m.PartyId
	WHERE	m.FeeType=2
	-- End region

	-- Region: Check min fee group
	--- calculate waived prorate (*)
	UPDATE	amf
	SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
								FROM	@MinFeeGroup mfg
								WHERE	mfg.FeeType = 1
										AND mfg.PartyId = amf.PartyId
										AND mfg.ProductId = amf.ProductId)
							/ @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
	FROM	@MinFeeGroup amf
	WHERE	FeeType = 2

	--- sum amount under waived
	UPDATE	amf
	SET		amf.WaivedAmount = ISNULL((	SELECT	SUM(td.AmountToCompany)
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND amf.ProductId = td.ProductId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 2

	--- calculate min fee prorate (fee amount in month - waived amount (*))
	UPDATE	amf
	SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) -
										ISNULL((SELECT	SUM(f.MinFeeProrate)
												FROM	@MinFeeGroup f
												WHERE	f.FeeType = 2
														AND amf.PartyId = f.PartyId
														AND amf.ProductId = f.ProductId), 0), 2),
			amf.WaivedAmount =  ISNULL((SELECT	CASE WHEN SUM(f.WaivedAmount) < 0 THEN 0 ELSE SUM(f.WaivedAmount) END
										FROM	@MinFeeGroup f
										WHERE	f.FeeType = 2
												AND amf.PartyId = f.PartyId
												AND amf.ProductId = f.ProductId), 0),
			amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
												AND td.IsApplyMinFee = 1
												AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1

	--- sum min fee amount
	UPDATE	amf
	SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	
	DECLARE @TotalMinFees TABLE(
		PartyGroupId		INT,
		ProductId			INT,
		TotalMinFee			MONEY,
		TotalMinFeeAmount	MONEY
	)
	INSERT	INTO @TotalMinFees(PartyGroupId, ProductId, TotalMinFee, TotalMinFeeAmount)
	SELECT	pg.PartyGroupId, mf.ProductId,
			SUM(mf.MinFeeProrate),
			SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END)
	FROM	@MinFeeGroup mf
	INNER JOIN @PartyGroup pg ON mf.PartyId = pg.PartyId
	WHERE	mf.FeeType = 1
	GROUP BY pg.PartyGroupId,mf.ProductId

	-- update minfee group
	UPDATE	amf
	SET		amf.AmountToCompany =	CASE
										WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
											THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									END
	FROM	@MinFeeGroup amf
	INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
	INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId AND t.PartyGroupId = pg.PartyGroupId
	WHERE	amf.FeeType = 1
		
	-- update minfee non-group
	UPDATE	amf
	SET		amf.AmountToCompany =	CASE WHEN amf.MinFeeAmount < amf.MinFeeProrate
											THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									END
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1 AND amf.AmountToCompany IS NULL

	-- Sum products

	CREATE TABLE #SumByProducts (
		PartyId			INT,
		WinLoss			MONEY,
		AComm			MONEY,
		MinFeeApplied	MONEY,
		WLFeeApplied	MONEY,
		AmountToCompany	MONEY,
		ProductId		INT
	)
	-- sum by product
	INSERT INTO #SumByProducts (PartyId,ProductId,WinLoss,AComm,MinFeeApplied,WLFeeApplied,AmountToCompany)
	SELECT	PartyId
			,ProductId
			,SUM(WinLoss) WinLoss
			,SUM(AComm) AComm
			,0
			,SUM(AmountToCompany) WLFeeApplied
			,SUM(AmountToCompany) AmountToCompany
	FROM #TempData
	GROUP BY PartyId, ProductId, CASE WHEN MONTH(rptDate) = MONTH(@FDate) THEN 1 ELSE 0 END

	-- Include parties that didn't have any tickets in the selected date range
	INSERT INTO #SumByProducts (PartyId,ProductId,WinLoss,AComm,MinFeeApplied,WLFeeApplied,AmountToCompany)
	SELECT mf.PartyId
		,ProductID
		,0 Winloss
		,0 AComm
		,0 MinFeeApplied
		,0 WLFeeApplied
		,0 AmountToCompany
	FROM @MinFeeGroup mf
		INNER JOIN @tmpParty p ON p.PartyID = mf.PartyId
	WHERE mf.PartyId NOT IN (SELECT PartyId FROM #TempData WHERE ProductId = mf.ProductId)
		AND mf.FeeType = 1

	-- merge to minfee group
	UPDATE s 
	SET AmountToCompany = m.AmountToCompany
		, MinFeeApplied = CASE WHEN m.AmountToCompany=m.TotalAmount THEN 0 ELSE m.MinFeeProrate END
		, WLFeeApplied = CASE WHEN m.AmountToCompany=m.TotalAmount THEN m.TotalAmount ELSE m.WaivedAmount END
	FROM #SumByProducts s
		INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
	WHERE m.FeeType = 1 -- min fee

	-- Update negative amount
	UPDATE #SumByProducts
	SET WLFeeApplied = CASE WHEN WLFeeApplied > 0 THEN WLFeeApplied ELSE 0 END,
		AmountToCompany = CASE WHEN AmountToCompany > 0 OR ProductId = 3 THEN AmountToCompany ELSE 0 END
	

	-- Region: Result
	SELECT PartyId, ProductId, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany
	FROM #SumByProducts

	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #SumByProducts
END
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_HouseNetIncome_LicenseeFee] TO vnteam
USE bodb02
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplierGMT]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductList	VARCHAR(MAX) = 'all'
	,@DepositType	TINYINT = 2
	,@IsOldView		BIT = 0
AS

/*
	Created: 20200521@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pay to supplier for some products (using diff GMT-4)
	
	Revisions:
		- 20200521@Percy: Initiliaze SP [RedmineID: #134533]
*/

BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @FDate_GMT DATETIME, @TDate_GMT DATETIME
	SELECT  @FDate_GMT = DATEADD(DAY, -1, @FromDate), @TDate_GMT = DATEADD(DAY, 1, @ToDate)

	DECLARE @LastDay DATE, @ExDate SMALLDATETIME
	SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
	
	DECLARE @ProductCodes VARCHAR(MAX)

	-- Product list
	DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
	INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
	SELECT ProductId, ProductPrefix FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK)

	DECLARE @Products TABLE (ProductId INT, VendorId SMALLINT, Product3rdId INT, AliasProductId INT, ProductCode VARCHAR(50), SubProductCode VARCHAR(50))
	INSERT INTO @Products (ProductId, VendorId, Product3rdId, AliasProductId, ProductCode, SubProductCode)
	SELECT DISTINCT s.ProductId, p.VendorId, CASE WHEN s.ProductId = 1 THEN 0 ELSE p3.Product3rdId END, s.AliasProductId, p.ProductPrefix, s.ProductPrefix
	FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
		INNER JOIN dbo.Products p WITH (NOLOCK) ON s.ProductId = p.ProductId
		LEFT JOIN @Product3rd p3 ON p.ProductPrefix = p3.ProductPrefix
	WHERE s.Figure = 'Pay to supplier'
		--AND s.LogicCode = 3 -- GMT
		AND (
			@DepositType = 2
			OR @DepositType = s.isDeposit
		)
		AND (
			s.EndOfSupportDate IS NULL AND s.isEnable = 1
			OR s.EndOfSupportDate < @FDate
		)
		AND (
			@ProductList = 'all'
			OR s.ProductId = 1 AND ',' + @ProductList + ',' LIKE '%,SB,%'
			OR ',' + @ProductList + ',' LIKE '%,' + s.ProductPrefix + ',%'
		)

	;WITH CTE_Product AS (SELECT DISTINCT ProductCode FROM @Products)
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

	-- Global Setting (default setting)
	CREATE TABLE #__tmpVendorGlobalSetting (IsDeposit BIT, VendorId SMALLINT, Product3rdId INT, ChargeRate3rd DECIMAL(19, 8))
	INSERT INTO #__tmpVendorGlobalSetting (IsDeposit, VendorId, ChargeRate3rd)
	SELECT CASE WHEN VName = '3rdCashWLShareRate' THEN 1 ELSE 0 END, VendorId, NumberValue
	FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
	WHERE
		(
			@DepositType = 2
			OR (@DepositType = 1 AND VName = '3rdCashWLShareRate')
			OR (@DepositType = 0 AND VName = '3rdCreditWLShareRate')
		)
		AND VName IN ('3rdCashWLShareRate', '3rdCreditWLShareRate')

	UPDATE v
	SET v.Product3rdId = p.Product3rdId
	FROM #__tmpVendorGlobalSetting v
		INNER JOIN @Products p ON v.VendorId = p.VendorId

	-- Active licensees
	DECLARE @tmpAllParty TABLE (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
	INSERT INTO @tmpAllParty (PartyId, ParentId, LicenseeId, IsDeposit)
	SELECT PartyId, ParentId, OldRefID, IsDeposit
	FROM (
		SELECT ci.FromParty AS PartyId, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END AS ParentId, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END AS OldRefId, pd.IsDeposit
			,ROW_NUMBER() OVER(PARTITION BY ci.FromParty, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END ORDER BY ci.FromDate DESC) AS RowNum
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyId = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeId = ci.ChargeId AND map.SystemID = 2
			LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeId
		WHERE p.PartyType = 1
			AND 1 = CASE WHEN @DepositType = 2 OR @DepositType = pd.IsDeposit THEN 1 ELSE 0 END
			AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98))
	) AS r
	WHERE r.RowNum = 1

	DECLARE @tmpParty TABLE (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyId, ParentId, LicenseeId, IsDeposit)
	SELECT DISTINCT p.PartyId, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyId = ci.FromParty
		INNER JOIN @Products pro ON ci.ProductID = pro.Product3rdId
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeId = ci.ChargeId AND map.SystemID = 2
		LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeId
	WHERE p.PartyType = 1
		AND (
			(ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)
		AND 1 = CASE WHEN @DepositType = 2 OR @DepositType = pd.IsDeposit THEN 1 ELSE 0 END
		AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98))

	-- Charge rate
	-- Rate by MinAmount, MaxAmount
	DECLARE @AmountRM MONEY = 0
	CREATE TABLE #__PartyCharge3rdInfoByAmount
	(
		IsDeposit		BIT
		,Product3rdId	INT
		,CurrencyId		INT
		,Rate			MONEY
		,MinAmount		MONEY
		,MaxAmount		MONEY
		,FromDate		DATE
		,ToDate			DATE
	)
	INSERT INTO #__PartyCharge3rdInfoByAmount (IsDeposit, Product3rdId, CurrencyId, Rate, MinAmount, MaxAmount, FromDate, ToDate)
	SELECT DISTINCT ci.IsDeposit, ci.ProductId, c.BaseCurrencyId, ci.DI_Rate, c.MinAmount, c.MaxAmount, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'PP', 'OA') ci
		INNER JOIN @tmpParty p ON p.ParentId = ci.PartyId
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeId = c.ChargeId
	WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0

	CREATE TABLE #__PartyCharge3rdInfo
	(
		ParentId		INT
		,PartyId		INT
		,LicenseeId		INT
		,IsDeposit		BIT
		,Product3rdId	INT
		,ChargeType		INT
		,Rate			MONEY
		,FromDate		SMALLDATETIME
		,ToDate			SMALLDATETIME
	)
	INSERT INTO #__PartyCharge3rdInfo (ParentId, PartyId, LicenseeId, IsDeposit, Product3rdId, ChargeType, Rate, FromDate, ToDate)
	SELECT DISTINCT p.ParentId, p.PartyId, p.LicenseeId, ci.IsDeposit, ci.ProductId, ci.ChargeType, CASE WHEN pa.Product3rdId IS NOT NULL THEN 0 ELSE ci.DI_Rate END, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductCodes, 'OA') ci
		INNER JOIN @tmpParty p ON p.ParentId = ci.PartyId
		LEFT JOIN #__PartyCharge3rdInfoByAmount pa ON ci.IsDeposit = pa.IsDeposit AND ci.ProductID = pa.Product3rdId
	WHERE
		(
			(ci.ProductID IN (11, 21) AND ci.ChargeType IN (9, 10)) -- GD & AB
			OR (ci.ProductID NOT IN (11, 21) AND ci.ChargeType = 1)
		)

	-- Exchange
	DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT)
	SELECT @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		
	IF @ExDate > @LastDay
		SELECT @ExDate = @LastDay

	INSERT INTO @ExchangeOANDA (ExchangeId, Rate)
	SELECT ExchangeId, MYR FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate

	-- Region: Get Sum data
	CREATE TABLE #__tempDataGMT
	(
		rptDate			DATE
		,ParentId		INT
		,IsDeposit		BIT
		,Product3rdId	INT
		,Bettype		INT
		,CurrencyId		INT
		,PlayCurrency	INT
		,PayDaily		MONEY
		,PayDailyRate	MONEY
		,PayMonth		MONEY
		,PayMonthRate	MONEY
		,MemberWLRate	MONEY -- For calculate pay to supplier of some products base on setting min max amount
	)

	CREATE TABLE #__Bettype (Product3rdId INT, ProductCode VARCHAR(50), BetType INT)
	INSERT INTO #__Bettype (Product3rdId, ProductCode, BetType)
	SELECT DISTINCT p.Product3rdId, p.ProductCode, s.BetType FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
		INNER JOIN @Products p ON s.ProductId = p.ProductId
	WHERE s.BetType NOT IN (4298, 4299, 4300)

	-- Use validbetamount
	CREATE TABLE #__ValidBetAmount (IsDeposit BIT, Product3rdId INT, FromDate DATE, ToDate DATE, CommRate FLOAT)

	-- For Allbet
	CREATE TABLE #__PlayCurrencySettings
	(
		SiteId          INT
		,MemberCurrency	INT
		,PlayCurrency   INT
		,FromDate       DATETIME
		,ToDate         DATETIME
	)

	IF ',' + @ProductCodes + ',' LIKE '%,AB,%'
	BEGIN
		INSERT INTO #__PlayCurrencySettings (SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate)
		SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate
		FROM OPENQUERY(DBACC, 'SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType = 211')
		
		DELETE #__PlayCurrencySettings
		WHERE ToDate < @FromDate OR FromDate > @ToDate
	END

	IF @DepositType IN (0, 2) AND (',' + @ProductCodes + ',' LIKE '%,AB,%' OR ',' + @ProductCodes + ',' LIKE '%,SAG,%')
	BEGIN
		INSERT INTO #__ValidBetAmount (IsDeposit, Product3rdId, FromDate, ToDate, CommRate)
		SELECT DISTINCT IsDeposit, ProductId, FromDate, ToDate, DI_Rate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'AB,SAG', 'OA')
		WHERE ChargeType = 11 AND IsDeposit = 0
	END

	INSERT INTO #__tempDataGMT (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate, PayMonth, PayMonthRate, MemberWLRate)
	SELECT b.RptDate3rd, tp.ParentId, tp.IsDeposit, bt.Product3rdId, CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
		,SUM((CASE WHEN b.BetTypeId = 4297 THEN b.ProgressiveContribution ELSE b.Winloss END + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * ISNULL(p.Rate, vs.ChargeRate3rd)) AS PayDaily
		,SUM((CASE WHEN b.BetTypeId = 4297 THEN b.ProgressiveContribution ELSE b.Winloss END + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * e.Rate * ISNULL(p.Rate, vs.ChargeRate3rd)) AS PayDailyRate
		,SUM((CASE WHEN b.BetTypeId = 4297 THEN b.ProgressiveContribution ELSE b.Winloss END + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * ISNULL(p.Rate, 0)) AS PayMonth
		,SUM((CASE WHEN b.BetTypeId = 4297 THEN b.ProgressiveContribution ELSE b.Winloss END + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * e.Rate * ISNULL(p.Rate, 0)) AS PayMonthRate
		,SUM(CASE WHEN b.BetTypeId = 4297 THEN b.ProgressiveContribution ELSE b.Winloss END * e.Rate) AS MemberWLRate
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN #__Bettype bt ON b.BetTypeId = bt.BetType
		INNER JOIN @tmpAllParty tp ON tp.LicenseeId = b.SiteID
		LEFT JOIN #__PartyCharge3rdInfo p ON tp.LicenseeId = p.LicenseeId AND bt.Product3rdId = p.Product3rdId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate AND ((b.BetTypeId <> 3007 AND p.ChargeType <> 12) OR (b.BetTypeId = 3007 AND p.ChargeType = 12))
		LEFT JOIN #__tmpVendorGlobalSetting vs ON vs.IsDeposit = tp.IsDeposit AND vs.Product3rdId = bt.Product3rdId
		INNER JOIN bodb_licensee.dbo.view_site_list s WITH (NOLOCK) ON b.SiteId = s.SiteID
		INNER JOIN @ExchangeOANDA e ON b.CurrencyId = e.ExchangeId
		LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteId AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
		LEFT JOIN #__ValidBetAmount v ON tp.IsDeposit = v.IsDeposit AND bt.Product3rdId = v.Product3rdId AND b.RptDate3rd BETWEEN v.FromDate AND v.ToDate
	WHERE b.RptDate BETWEEN @FDate_GMT AND @TDate_GMT
		AND b.RptDate3rd BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
	GROUP BY
		b.RptDate3rd
		,tp.ParentId
		,tp.IsDeposit
		,bt.Product3rdId
		,CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END
		,b.CurrencyId
		,ISNULL(pc.PlayCurrency, b.CurrencyId)

	-- Special PayToSupplier
	IF @DepositType IN (0, 2) AND @IsOldView = 0
	BEGIN
		CREATE TABLE #__Special_PayToSupplier (rptDate DATE, ParentId INT, IsDeposit BIT, Product3rdId INT, Bettype INT, CurrencyId INT, PlayCurrency INT, PayDaily MONEY, PayDailyRate MONEY)
		INSERT INTO #__Special_PayToSupplier (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate)
		SELECT b.RptDate3rd, tp.ParentId, tp.IsDeposit, b.ProductId, CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
			,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * (1 - p.Rate)) AS PayDaily
			,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * e.Rate * (1 - p.Rate)) AS PayDailyRate
		FROM bodb_LicenseeReport.dbo.rpt_CustomerWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #__Bettype bt ON b.BetTypeId = bt.BetType
			INNER JOIN @tmpAllParty tp ON tp.LicenseeId = b.SiteID
			LEFT JOIN #__PartyCharge3rdInfo p ON tp.LicenseeId = p.LicenseeId AND b.ProductId = p.Product3rdId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
			INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
			INNER JOIN @ExchangeOANDA e ON b.CurrencyId = e.ExchangeId
			LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
			LEFT JOIN #__ValidBetAmount v ON tp.IsDeposit = v.IsDeposit AND b.ProductId = v.Product3rdId AND b.RptDate3rd BETWEEN v.FromDate AND v.ToDate
		WHERE b.RptDate BETWEEN @FDate_GMT AND @TDate_GMT
			AND b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY
			b.RptDate3rd
			,tp.ParentId
			,tp.IsDeposit
			,b.ProductId
			,CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END
			,b.CurrencyId
			,ISNULL(pc.PlayCurrency, b.CurrencyId)

		UPDATE t
		SET t.PayDaily = t.PayDaily + s.PayDaily
			,t.PayDailyRate = t.PayDailyRate + s.PayDailyRate
			,t.PayMonth = t.PayMonth + s.PayDaily
			,t.PayMonthRate = t.PayMonthRate + s.PayDailyRate
		FROM #__tempDataGMT t
			INNER JOIN #__Special_PayToSupplier s
				ON t.rptDate = s.rptDate
					AND t.ParentId = s.ParentId
					AND t.IsDeposit = s.IsDeposit
					AND t.Product3rdId = s.Product3rdId
					AND t.Bettype = s.Bettype
					AND t.CurrencyId = s.CurrencyId
					AND t.PlayCurrency = s.PlayCurrency

		DROP TABLE #__Special_PayToSupplier
	END

	DROP TABLE #__tmpVendorGlobalSetting

	CREATE TABLE #__DailyPayToSupplier (IsDeposit BIT, Product3rdId INT, rptDate DATE, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))
	CREATE TABLE #__FullRangePayToSupplier (IsDeposit BIT, Product3rdId INT, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))

	-- Pragmatic for Credit
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE Product3rdId = 32 AND IsDeposit = 0)
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier)
		SELECT 0, 32, wl.rptDate
			,(CASE
				WHEN
					(MemberWLRate < 0 AND (ci.MinAmount * ex.Rate) = 0)
					OR (MemberWLRate >= (ci.MinAmount * ex.Rate))
				THEN 
					CASE
						WHEN MemberWLRate > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
						ELSE MemberWLRate - (ci.MinAmount * ex.Rate) END
				ELSE 0 END
			) * ci.Rate AS PayToSupplier
		FROM
		(
			SELECT rptDate, SUM(MemberWLRate) AS MemberWLRate
			FROM #__tempDataGMT
			WHERE Product3rdId = 32 AND IsDeposit = 0
			GROUP BY RptDate
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId
		WHERE ci.Product3rdId = 32 AND IsDeposit = 0
	END

	-- SA Gaming for Deposit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE Product3rdId = 39 AND IsDeposit = 1)
	BEGIN
		SELECT @AmountRM = 10000000 * Rate FROM @ExchangeOANDA WHERE ExchangeId = 13 -- CNY

		;WITH CTE_SA AS
		(
			SELECT ParentId, CASE WHEN ParentId IN (1, 11) THEN CASE WHEN Amount < @AmountRM THEN 0.06 ELSE 0.05 END ELSE 0 END AS Rate
			FROM
			(
				SELECT CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END AS ParentId, SUM(-MemberWLRate) AS Amount
				FROM #__tempDataGMT
				WHERE BetType = 0 AND Product3rdId = 39 AND IsDeposit = 1
				GROUP BY CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END
			) a
		)
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier)
		SELECT 1, 39, d.rptDate, SUM(d.MemberWLRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END)
		FROM #__tempDataGMT d
			INNER JOIN CTE_SA t ON t.ParentId = d.ParentId
		WHERE d.Product3rdId = 39 AND IsDeposit = 1
		GROUP BY d.rptDate
	END

	-- Check by MemberWL
	BEGIN
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier)
		SELECT IsDeposit, Product3rdId, SUM(PayToSupplier)
		FROM (
			SELECT IsDeposit, Product3rdId, ParentId, SUM(PayMonthRate) AS PayToSupplier
			FROM #__tempDataGMT
			WHERE Product3rdId IN (10, 24)
			GROUP BY IsDeposit, Product3rdId, ParentId
			HAVING SUM(PayMonthRate) < 0
		) t
		GROUP BY IsDeposit, Product3rdId
	END

	-- Others
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier)
		SELECT IsDeposit, Product3rdId, rptDate, SUM(PayDailyRate)
		FROM #__tempDataGMT
		WHERE
			(IsDeposit = 0 AND Product3rdId <> 32)
			OR (IsDeposit = 1 AND Product3rdId <> 39)
		GROUP BY IsDeposit, Product3rdId, rptDate

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier)
		SELECT IsDeposit, Product3rdId, SUM(PayMonthRate)
		FROM #__tempDataGMT
		WHERE Product3rdId NOT IN (10, 24)
		GROUP BY IsDeposit, Product3rdId
	END

	-- Play Currency
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE Product3rdId = 21 AND IsDeposit = 0)
	BEGIN
		;WITH CTE_AB AS
		(
			SELECT b.rptDate, SUM(b.PayDaily * (pe.Rate - oe.Rate)) AS CurrencyPlay
			FROM #__tempDataGMT b
				INNER JOIN @ExchangeOANDA oe ON oe.ExchangeID = b.CurrencyId
				INNER JOIN @ExchangeOANDA pe ON pe.ExchangeID = b.PlayCurrency
			WHERE Product3rdId = 21 AND IsDeposit = 0
			GROUP BY b.rptDate
		)
		UPDATE d
		SET d.CurrencyPlay = c.CurrencyPlay
		FROM #__DailyPayToSupplier d
			INNER JOIN CTE_AB c ON d.rptDate = c.rptDate
		WHERE d.Product3rdId = 21 AND d.IsDeposit = 0

		DECLARE @AB_CurrencyPlay_Month MONEY
		SELECT  @AB_CurrencyPlay_Month = SUM(b.PayMonth * (pe.Rate - oe.Rate))
		FROM #__tempDataGMT b
			INNER JOIN @ExchangeOANDA oe ON oe.ExchangeID = b.CurrencyId
			INNER JOIN @ExchangeOANDA pe ON pe.ExchangeID = b.PlayCurrency
		WHERE Product3rdId = 21 AND IsDeposit = 0

		UPDATE f
		SET f.CurrencyPlay = ISNULL(@AB_CurrencyPlay_Month, 0)
		FROM #__FullRangePayToSupplier f
		WHERE Product3rdId = 21 AND IsDeposit = 0
	END
	-- End Region

	DROP TABLE #__PartyCharge3rdInfo
	DROP TABLE #__PlayCurrencySettings
	DROP TABLE #__PartyCharge3rdInfoByAmount
	DROP TABLE #__tempDataGMT
	DROP TABLE #__ValidBetAmount
	-- End region

	CREATE TABLE #__FinalResult (Product3rdId INT, ProductCode VARCHAR(50), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	
	;WITH CTE_Product AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM #__Bettype
	)
	INSERT INTO #__FinalResult (Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT p.Product3rdId, p.ProductCode, 'Monthly', SUM(ISNULL(f.PayToSupplier, 0)), SUM(ISNULL(f.CurrencyPlay, 0))
	FROM CTE_Product p
		LEFT JOIN #__FullRangePayToSupplier f ON p.Product3rdId = f.Product3rdId
	GROUP BY p.Product3rdId, p.ProductCode

	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode, @FDate AS rptDate FROM #__Bettype
		UNION ALL
		SELECT Product3rdId, ProductCode, DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #__FinalResult (Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT d.Product3rdId, d.ProductCode, 'MTD', SUM(ISNULL(t.PayToSupplier, 0)), SUM(ISNULL(t.CurrencyPlay, 0))
	FROM CTE_RptDate d
		LEFT JOIN #__DailyPayToSupplier t ON d.rptDate = t.rptDate AND d.Product3rdId = t.Product3rdId
	GROUP BY d.Product3rdId, d.ProductCode
	OPTION (MAXRECURSION 0)
	
	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode, @FDate AS rptDate FROM #__Bettype
		UNION ALL
		SELECT Product3rdId, ProductCode, DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #__FinalResult (Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT d.Product3rdId, d.ProductCode, CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.PayToSupplier, 0)), SUM(ISNULL(t.CurrencyPlay, 0))
	FROM CTE_RptDate d
		LEFT JOIN #__DailyPayToSupplier t ON d.rptDate = t.rptDate AND d.Product3rdId = t.Product3rdId
	GROUP BY d.Product3rdId, d.ProductCode, CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

	DECLARE @DateList VARCHAR(2000), @SQL VARCHAR(MAX)
	;WITH CTE_Date AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_Date
		WHERE rptDate < @TDate
	)
	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(2), rptDate, 106) + ']' FROM CTE_Date ORDER BY rptDate

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT ProductCode, Figure, Monthly, MTD, ' + @DateList + '
		FROM (
			SELECT ProductCode, Value, Figure, rptDate
			FROM #__FinalResult r
			CROSS APPLY (
				SELECT PayToSupplier AS Value, ''Pay to supplier'' AS Figure WHERE PayToSupplier IS NOT NULL
				UNION ALL SELECT CurrencyPlay, ''Currency Play'' WHERE CurrencyPlay IS NOT NULL
			) f
		) t
		PIVOT (
			MAX(Value)
			FOR rptDate IN (Monthly, MTD, ' + @DateList + ')
		) p
	)
	SELECT
		s.isDeposit, s.OrderByProduct, s.OrderByFigure, ''Licensee'' AS SiteGroup, s.ProductGroup, s.ProductName, s.ProductShortName
		,r.Figure, r.Monthly, r.MTD, ' + @DateList + '
	FROM CTE_Result r
		INNER JOIN bodb_Account.dbo.HNISettings s WITH (NOLOCK) ON r.ProductCode = s.ProductPrefix AND r.Figure = s.Figure
	WHERE s.isDeposit = 1
	ORDER BY s.OrderByProduct, s.OrderByFigure'

	EXEC (@SQL)

	DROP TABLE #__Bettype
	DROP TABLE #__FinalResult
	DROP TABLE #__DailyPayToSupplier
	DROP TABLE #__FullRangePayToSupplier
END
GO
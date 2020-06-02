/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_PayToSupplier]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductCodes	VARCHAR(MAX)
	,@DepositType	TINYINT = 2
	,@Site			VARCHAR(20) = ''
	,@IsOldView		BIT = 0
AS

/*
	Created: 20200521@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pay to supplier for some products (using diff GMT-4)
	
	Revisions:
		- 20200521@Percy: Initiliaze SP [RedmineID: #134553]
		- 20200529@Percy: Special members for AB [RedmineID: #134867]
    
	Param's Explanation:
		- @@ProductCodes: List of Product Code
		- @DepositType:
						= 0 Credit Only
						= 1 Deposit Only
						= 2 All
		- @Site:
						= '': all sites
						= '789y': 789y
*/

BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @GMTFDate DATETIME, @GMTTDate DATETIME
	SELECT  @GMTFDate = DATEADD(DAY, -1, @FromDate), @GMTTDate = DATEADD(DAY, 1, @ToDate)

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT, LicenseeID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, ParentID, LicenseeID, IsDeposit)
	SELECT DISTINCT p.PartyID, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefID ELSE lb.LabelID END, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.Products pro WITH (NOLOCK) ON ci.ProductID = pro.ProductID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
		LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE p.PartyType = 1
		AND ',' + @ProductCodes + ',' LIKE '%,' + pro.ProductPrefix + ',%'
		AND (
			(ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)
		AND 1 = CASE WHEN @DepositType = 2 OR @DepositType = pd.IsDeposit THEN 1 ELSE 0 END
	-- End region

	-- Region: Get charge rate
	CREATE TABLE #__PartyCharge3rdInfo
	(
		ParentId	INT
		,LicenseeId	INT
		,IsDeposit	BIT
		,ProductId	INT
		,ChargeType	INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
	)
	INSERT INTO #__PartyCharge3rdInfo (ParentId, LicenseeId, IsDeposit, ProductId, ChargeType, Rate, FromDate, ToDate)
	SELECT DISTINCT p.ParentId, p.LicenseeId, ci.IsDeposit, ci.ProductId, ci.ChargeType, ci.DI_Rate, ci.FromDate, ci.ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductCodes, 'OA') ci
		INNER JOIN @tmpParty p ON p.ParentID = ci.PartyID
	WHERE
		(
			(ci.ProductID IN (11, 21) AND ci.ChargeType IN (9, 10)) -- GD & AB
			OR (ci.ProductID NOT IN (11, 21) AND ci.ChargeType = 1)
		)

	-- Rate by MinAmount, MaxAmount
	DECLARE @AmountRM MONEY = 0

	CREATE TABLE #__PartyCharge3rdInfoByAmount
	(
		IsDeposit	BIT
		,ProductId	INT
		,CurrencyId	INT
		,Rate		MONEY
		,MinAmount	MONEY
		,MaxAmount	MONEY
		,FromDate	DATE
		,ToDate		DATE
	)
	INSERT INTO #__PartyCharge3rdInfoByAmount (IsDeposit, ProductId, CurrencyId, Rate, MinAmount, MaxAmount, FromDate, ToDate)
	SELECT DISTINCT ci.IsDeposit, ci.ProductId, c.BaseCurrencyId, ci.DI_Rate, c.MinAmount, c.MaxAmount, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, @ProductCodes, 'OA') ci
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID
	WHERE ci.ChargeType = 1
	-- End Region

	-- Region: Get Exchange
	CREATE TABLE #__ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #__ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #__tempDataGMT
	(
		rptDate			DATE
		,ParentId		INT
		,IsDeposit		BIT
		,ProductId		INT
		,Bettype		INT
		,CurrencyId		INT
		,PlayCurrency	INT
		,PayDaily		MONEY
		,PayDailyRate	MONEY
		,MemberWLRate	MONEY -- For calculate pay to supplier of some products base on setting min max amount
	)

	CREATE TABLE #__Bettype (ProductId INT, BetType INT)
	INSERT INTO #__Bettype (ProductId, BetType)
	SELECT DISTINCT s.ProductId, s.BetType FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
		INNER JOIN dbo.Products p WITH (NOLOCK) ON s.ProductID = p.ProductID
	WHERE ',' + @ProductCodes + ',' LIKE '%,' + p.ProductPrefix + ',%'
		AND s.BetType NOT IN (4299, 4300)

	-- Use validbetamount
	CREATE TABLE #__ValidBetAmount (IsDeposit BIT, ProductId INT, FromDate DATE, ToDate DATE, CommRate FLOAT)

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
		INSERT INTO #__ValidBetAmount (IsDeposit, ProductId, FromDate, ToDate, CommRate)
		SELECT DISTINCT IsDeposit, ProductId, FromDate, ToDate, DI_Rate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'AB,SAG', 'OA')
		WHERE ChargeType = 11
	END

	INSERT INTO #__tempDataGMT (rptDate, ParentId, IsDeposit, ProductID, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate, MemberWLRate)
	SELECT b.RptDate3rd, p.ParentId, p.IsDeposit, p.ProductID, CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
		,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * p.Rate) AS PayDaily
		,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * e.Rate * p.Rate) AS PayDailyRate
		,SUM(b.Winloss * e.Rate) AS MemberWLRate
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN #__Bettype bt ON b.BetTypeId = bt.BetType
		LEFT JOIN #__PartyCharge3rdInfo p ON p.LicenseeID = b.SiteID AND bt.ProductId = p.ProductId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
		INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
		INNER JOIN #__ExchangeOANDA e ON b.RptDate3rd = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
		LEFT JOIN #__ValidBetAmount v ON p.IsDeposit = v.IsDeposit AND p.ProductId = v.ProductId AND b.RptDate3rd BETWEEN v.FromDate AND v.ToDate
	WHERE b.RptDate BETWEEN @GMTFDate AND @GMTTDate
		AND b.RptDate3rd BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		AND (@Site = '' OR s.SiteName = @Site)
		AND (
			(b.BetTypeId <> 3007 AND p.ChargeType <> 12)
			OR (b.BetTypeId = 3007 AND p.ChargeType = 12)
		)
	GROUP BY
		b.RptDate3rd
		,p.ParentId
		,p.IsDeposit
		,p.ProductId
		,CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END
		,b.CurrencyId
		,ISNULL(pc.PlayCurrency, b.CurrencyId)

	-- Special PayToSupplier
	IF @DepositType IN (0, 2) AND @IsOldView = 0
	BEGIN
		CREATE TABLE #__Special_PayToSupplier (rptDate DATE, ParentId INT, IsDeposit BIT, ProductId INT, Bettype INT, CurrencyId INT, PlayCurrency INT, PayDaily MONEY, PayDailyRate MONEY)
		INSERT INTO #__Special_PayToSupplier (rptDate, ParentId, IsDeposit, ProductId, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate)
		SELECT b.RptDate3rd, p.ParentId, p.IsDeposit, p.ProductID, CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END, b.CurrencyId, ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency
			,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * (1 - p.Rate)) AS PayDaily
			,SUM((b.Winloss + ISNULL(b.ValidBetAmount * v.CommRate, 0)) * e.Rate * (1 - p.Rate)) AS PayDailyRate
		FROM bodb_LicenseeReport.dbo.rpt_CustomerWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #__PartyCharge3rdInfo p ON p.LicenseeID = b.SiteID AND b.ProductId = p.ProductId AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
			INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
			INNER JOIN #__ExchangeOANDA e ON b.RptDate3rd = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			LEFT JOIN #__PlayCurrencySettings pc ON pc.SiteId = s.IbcSiteID AND b.CurrencyId = pc.MemberCurrency AND b.RptDate3rd BETWEEN pc.FromDate AND pc.ToDate
			LEFT JOIN #__ValidBetAmount v ON p.IsDeposit = v.IsDeposit AND p.ProductId = v.ProductId
		WHERE b.RptDate BETWEEN @GMTFDate AND @GMTTDate
			AND b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY
			b.RptDate3rd
			,p.ParentId
			,p.IsDeposit
			,p.ProductId
			,CASE WHEN b.BetTypeId = 3007 THEN 3007 ELSE 0 END
			,b.CurrencyId
			,ISNULL(pc.PlayCurrency, b.CurrencyId)

		UPDATE t
		SET t.PayDaily = t.PayDaily + s.PayDaily
			,t.PayDailyRate = t.PayDailyRate + s.PayDailyRate
		FROM #__tempDataGMT t
			INNER JOIN #__Special_PayToSupplier s
				ON t.rptDate = s.rptDate
					AND t.ParentId = s.ParentId
					AND t.IsDeposit = s.IsDeposit
					AND t.ProductId = s.ProductId
					AND t.Bettype = s.Bettype
					AND t.CurrencyId = s.CurrencyId
					AND t.PlayCurrency = s.PlayCurrency

		DROP TABLE #__Special_PayToSupplier
	END

	CREATE TABLE #__DailyPayToSupplier (IsDeposit BIT, ProductId INT, rptDate DATE, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))
	CREATE TABLE #__FullRangePayToSupplier (IsDeposit BIT, ProductId INT, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))

	-- Pragmatic for Credit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE ProductId = 22)
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, ProductId, rptDate, PayToSupplier)
		SELECT 0, 22, wl.rptDate
			,(CASE
				WHEN
					(LicenseeWLRate < 0 AND (ci.MinAmount * ex.Rate) = 0)
					OR (LicenseeWLRate >= (ci.MinAmount * ex.Rate))
				THEN 
					CASE
						WHEN LicenseeWLRate > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
						ELSE LicenseeWLRate - (ci.MinAmount * ex.Rate) END
				ELSE 0 END
			) * ci.Rate AS PayToSupplier
		FROM
		(
			SELECT rptDate, SUM(-MemberWLRate) AS LicenseeWLRate
			FROM #__tempDataGMT
			WHERE ProductId = 22
			GROUP BY RptDate
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #__ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId AND ex.ExchangeDate = @TDate
		WHERE ci.ProductId = 22

		IF ISNULL((SELECT SUM(MemberWLRate) FROM #__tempDataGMT WHERE ProductId = 22), 0) > 0
			INSERT INTO #__FullRangePayToSupplier (IsDeposit, ProductId, PayToSupplier)
			SELECT 0, 22, SUM(PayToSupplier)
			FROM #__DailyPayToSupplier
		ELSE
			INSERT INTO #__FullRangePayToSupplier (IsDeposit, ProductId, PayToSupplier)
			SELECT 0, 22, 0
	END
	
	-- SA Gaming for Deposit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE ProductId = 39)
	BEGIN
		SELECT @AmountRM = 10000000 * Rate
		FROM #__ExchangeOANDA
		WHERE ExchangeDate = @TDate
			AND ExchangeID = 13 -- CNY

		;WITH CTE_SA AS
		(
			SELECT ParentId, CASE WHEN ParentId IN (1, 11) THEN CASE WHEN Amount < @AmountRM THEN 0.06 ELSE 0.05 END ELSE 0 END AS Rate
			FROM
			(
				SELECT CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END AS ParentId, SUM(-MemberWLRate) AS Amount
				FROM #__tempDataGMT
				WHERE BetType = 0 AND ProductId = 39 -- SA
				GROUP BY CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END
			) a
		)
		INSERT INTO #__DailyPayToSupplier (IsDeposit, ProductId, rptDate, PayToSupplier)
		SELECT 1, 39, d.rptDate, SUM(d.MemberWLRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END)
		FROM #__tempDataGMT d
			INNER JOIN CTE_SA t ON t.ParentId = d.ParentId
		WHERE d.ProductId = 39
		GROUP BY d.rptDate
	END

	-- Spadegaming and Sexy Gaming for Deposit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE ProductId IN (36, 45))
	BEGIN
		;WITH CTE_SXG AS
		(
			SELECT ProductId, CASE WHEN ProductId = 36 AND ParentId <> 1 THEN -1 ELSE ParentId END AS ParentId
				,SUM(PayDailyRate) AS PayToSupplier
			FROM #__tempDataGMT
			WHERE ProductId IN (36, 45)
			GROUP BY ProductId, CASE WHEN ProductId = 36 AND ParentId <> 1 THEN -1 ELSE ParentId END
			HAVING SUM(MemberWLRate) <= 0
		)
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, ProductId, PayToSupplier)
		SELECT 1, ProductId, SUM(PayToSupplier)
		FROM CTE_SXG
		GROUP BY ProductId
	END

	-- Other products
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, ProductId, rptDate, PayToSupplier)
		SELECT IsDeposit, ProductId, rptDate, SUM(PayDailyRate)
		FROM #__tempDataGMT
		WHERE
			(IsDeposit = 0 AND ProductId <> 22)
			OR (IsDeposit = 1 AND ProductId <> 39)
		GROUP BY IsDeposit, ProductId, rptDate

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, ProductId, PayToSupplier)
		SELECT IsDeposit, ProductId, SUM(PayToSupplier)
		FROM #__DailyPayToSupplier
		WHERE (IsDeposit = 0 AND ProductId <> 22)
			OR (IsDeposit = 1 AND ProductId NOT IN (36, 45))
		GROUP BY IsDeposit, ProductId
	END

	-- Play Currency
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempDataGMT WHERE ProductId = 21)
	BEGIN
		;WITH CTE_AB AS
		(
			SELECT b.rptDate, SUM(b.PayDaily * (pe.Rate - oe.Rate)) AS CurrencyPlay
			FROM #__tempDataGMT b
				INNER JOIN #__ExchangeOANDA oe ON oe.ExchangeDate = b.rptDate AND oe.ExchangeID = b.CurrencyId
				INNER JOIN #__ExchangeOANDA pe ON pe.ExchangeDate = b.rptDate AND pe.ExchangeID = b.PlayCurrency
			GROUP BY b.rptDate
		)
		UPDATE d
		SET d.CurrencyPlay = c.CurrencyPlay
		FROM #__DailyPayToSupplier d
			INNER JOIN CTE_AB c ON d.rptDate = c.rptDate
		WHERE d.ProductId = 21 AND d.IsDeposit = 0

		UPDATE f
		SET f.CurrencyPlay = ISNULL((
								SELECT SUM(CurrencyPlay) AS CurrencyPlay
								FROM #__DailyPayToSupplier
								WHERE ProductId = 21 AND IsDeposit = 0
								HAVING SUM(PayToSupplier) < 0
								), 0)
		FROM #__FullRangePayToSupplier f
		WHERE ProductId = 21 AND IsDeposit = 0
	END
	-- End Region

	DROP TABLE #__PartyCharge3rdInfo
	DROP TABLE #__PlayCurrencySettings
	DROP TABLE #__PartyCharge3rdInfoByAmount
	DROP TABLE #__ExchangeOANDA
	DROP TABLE #__tempDataGMT
	DROP TABLE #__ValidBetAmount
	-- End region

	CREATE TABLE #__FinalResult (ProductId INT, rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	
	INSERT INTO #__FinalResult (ProductId, rptDate, PayToSupplier, CurrencyPlay)
	SELECT DISTINCT ProductId, 'FullRange', 0, 0 FROM #__Bettype
	
	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT ProductId, @FDate AS rptDate FROM #__Bettype
		UNION ALL
		SELECT ProductId, DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #__FinalResult (ProductId, rptDate, PayToSupplier, CurrencyPlay)
	SELECT d.ProductId, CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.PayToSupplier, 0)), SUM(ISNULL(t.CurrencyPlay, 0))
	FROM CTE_RptDate d
		LEFT JOIN #__DailyPayToSupplier t ON d.rptDate = t.rptDate AND d.ProductId = t.ProductId
	GROUP BY d.ProductId, CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

	SELECT p.ProductPrefix AS ProductCode, r.rptDate, r.PayToSupplier, r.CurrencyPlay
	FROM #__FinalResult r
		INNER JOIN dbo.Products p WITH (NOLOCK) ON r.ProductId = p.ProductID
	ORDER BY ProductCode, rptDate

	DROP TABLE #__Bettype
	DROP TABLE #__FinalResult
	DROP TABLE #__DailyPayToSupplier
	DROP TABLE #__FullRangePayToSupplier
END
GO
GO
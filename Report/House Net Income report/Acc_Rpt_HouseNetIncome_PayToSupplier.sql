/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductList	VARCHAR(MAX) = 'all'
	,@DepositType	TINYINT = 2
	,@IsOldView		BIT = 0
AS

/*
	Created: 20201201@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Pay to supplier for some products
	
	Revisions:
		- 20201201@Percy: Initiliaze SP [RedmineID: #143208]
		- 20200112@Percy: Return ProductCategory column [RedmineID: #146539]
		- 20210125@Percy: Return SubFigure column [RedmineID: #149267]
*/

BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @FDate_GMT DATETIME, @TDate_GMT DATETIME
	SELECT  @FDate_GMT = DATEADD(DAY, -1, @FromDate), @TDate_GMT = DATEADD(DAY, 1, @ToDate)

	DECLARE @LastDay DATE, @ExDate SMALLDATETIME
	SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))

	DECLARE @f_date VARCHAR(10), @t_date VARCHAR(10), @SQL VARCHAR(MAX) -- use for dynamic query
	SELECT  @f_date = CONVERT(VARCHAR(10), @FromDate, 120), @t_date = CONVERT(VARCHAR(10), @ToDate, 120)

	DECLARE @ProductCodes VARCHAR(MAX), @Product3rdIds VARCHAR(MAX)
	DECLARE @PartyIds VARCHAR(MAX)

	-- Get list of product
	BEGIN
		DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
		INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
		SELECT ProductId, ProductPrefix FROM DBLIC.bodb_Licensee.dbo.Product3rd WITH (NOLOCK)

		DECLARE @Products TABLE (ProductId INT, VendorId INT, Product3rdId INT, AliasProductId INT, ProductCode VARCHAR(50), SubProductCode VARCHAR(50))
		INSERT INTO @Products (ProductId, VendorId, Product3rdId, AliasProductId, ProductCode, SubProductCode)
		SELECT DISTINCT s.ProductId, p.VendorId, CASE WHEN s.ProductId = 1 THEN 0 ELSE p3.Product3rdId END, s.AliasProductId, p.ProductPrefix, s.ProductPrefix
		FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Products p WITH (NOLOCK) ON s.ProductId = p.ProductId
			LEFT JOIN @Product3rd p3 ON p.ProductPrefix = p3.ProductPrefix
		WHERE s.LogicCode = 3
			AND (
				s.EndOfSupportDate IS NULL AND s.isEnable = 1
				OR s.EndOfSupportDate >= @TDate
			)
			AND (
				@ProductList = 'all'
				OR s.ProductId = 1 AND ',' + @ProductList + ',' LIKE '%,SB,%'
				OR ',' + @ProductList + ',' LIKE '%,' + s.ProductPrefix + ',%'
			)
			AND (
				@DepositType = 2
				OR s.isDeposit = @DepositType
			)

		;WITH CTE_Product AS (SELECT DISTINCT ProductCode FROM @Products)
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

		;WITH CTE_Product AS (SELECT DISTINCT Product3rdId FROM @Products)
		SELECT @Product3rdIds = COALESCE(@Product3rdIds + ',', '') + CONVERT(VARCHAR(3), Product3rdId) FROM CTE_Product
	END

	-- Get Exchange
	BEGIN
		DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		SELECT  @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate
	END

	-- Get Licensees
	BEGIN
		-- All licensees
		CREATE TABLE #AllParties (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
		SELECT @SQL = '	SELECT PartyId, ParentId, LicenseeId, IsDeposit
						FROM OPENQUERY (DBLIC, ''	SELECT PartyId, ParentId, LicenseeId, IsDeposit
													FROM (
														SELECT ci.FromParty AS PartyId, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END AS ParentId, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END AS LicenseeId, pd.IsDeposit
															,ROW_NUMBER() OVER(PARTITION BY ci.FromParty, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END ORDER BY ci.FromDate DESC) AS RowNum
														FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
															INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
															INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyId = ci.FromParty
															INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeId = ci.ChargeId AND map.SystemID = 2
															LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeId
														WHERE p.PartyType = 1
															AND 1 = CASE WHEN ' + CONVERT(VARCHAR(3), @DepositType) + ' = 2 OR ' + CONVERT(VARCHAR(3), @DepositType) + ' = pd.IsDeposit THEN 1 ELSE 0 END
															AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98))
													) AS r
													WHERE r.RowNum = 1'')'
		INSERT INTO #AllParties (PartyId, ParentId, LicenseeId, IsDeposit)
		EXEC (@SQL)

		-- Licensees have setting
		CREATE TABLE #Party (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
		SELECT @SQL = '	SELECT PartyId, ParentId, LicenseeId, IsDeposit
						FROM OPENQUERY (DBLIC, ''	SELECT DISTINCT p.PartyId, CASE WHEN pd.IsDeposit = 0 THEN 999 ELSE ci.ToParty END AS ParentId, CASE WHEN pd.IsDeposit = 1 THEN p.OldRefId ELSE lb.LabelId END AS LicenseeId, pd.IsDeposit
													FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
														INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
														INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyId = ci.FromParty
														INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeId = ci.ChargeId AND map.SystemID = 2
														LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeId
													WHERE p.PartyType = 1
														AND ci.ProductId IN (' + @Product3rdIds + ')
														AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + '''''
														AND 1 = CASE WHEN ' + CONVERT(VARCHAR(3), @DepositType) + ' = 2 OR ' + CONVERT(VARCHAR(3), @DepositType) + ' = pd.IsDeposit THEN 1 ELSE 0 END
														AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98))'')'
		INSERT INTO #Party (PartyId, ParentId, LicenseeId, IsDeposit)
		EXEC (@SQL)

		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Party
	END

	-- Get charge rate
	BEGIN
		CREATE TABLE #__PartyChargeInfo (LicenseeId INT, IsDeposit BIT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
		SELECT @SQL = '	SELECT LicenseeId, IsDeposit, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.LicenseeId, ci.IsDeposit, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.ChargeType
								,CASE WHEN ci.ProductId = 0 THEN -1 ELSE ISNULL(sbr.Bettype, ci.Bettype) END AS Bettype
								,CASE WHEN ci.IsDeposit = 0 AND ci.ProductId = 32 THEN 0 ELSE ci.DI_Rate END AS Rate
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
							WHERE ci.DI_Rate > 0
								AND (
									ci.ChargeType = 1
									OR ci.ChargeType IN (9, 10, 11, 12) AND ci.ProductId IN (11, 21, 39) -- GD
									OR ci.ChargeType IN (6, 7) AND ci.ProductId = 15 -- CB
									OR ci.ChargeType = 5 AND ci.ProductId = 25 -- CO
								)'')'
		INSERT INTO #__PartyChargeInfo (LicenseeId, IsDeposit, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		CREATE TABLE #__Party3rdInfo (PartyId INT, Product3rdId INT, ChargeId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate MONEY)
		SELECT @SQL = '	SELECT PartyId, ProductId, ChargeId, ChargeType, FromDate, ToDate, Rate
						FROM OPENQUERY (DBLIC, ''SELECT DISTINCT PartyId, ProductId, ChargeId, ChargeType, FromDate, ToDate, DI_Rate AS Rate FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''')
												 WHERE (
														(ProductID IN (11, 21, 39) AND ChargeType IN (9, 10, 11)) -- GD, AB, SAG
														OR (ProductID NOT IN (11, 21, 39) AND ChargeType = 1)
													)'')'
		INSERT INTO #__Party3rdInfo (PartyId, Product3rdId, ChargeId, ChargeType, FromDate, ToDate, Rate)
		EXEC (@SQL)

		CREATE TABLE #__PartyCharge3rdInfo (ParentId INT, PartyId INT, LicenseeId INT, IsDeposit BIT, Product3rdId INT, ChargeId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate MONEY)
		INSERT INTO #__PartyCharge3rdInfo (ParentId, PartyId, LicenseeId, IsDeposit, Product3rdId, ChargeId, ChargeType, FromDate, ToDate, Rate)
		SELECT p.ParentId, p.PartyId, p.LicenseeId, p.IsDeposit, p3.Product3rdId, p3.ChargeId, p3.ChargeType, p3.FromDate, p3.ToDate, p3.Rate
		FROM #__Party3rdInfo p3
			INNER JOIN #Party p ON p3.PartyId = p.ParentId

		CREATE TABLE #__PartyCharge3rdInfoByAmount (IsDeposit BIT, Product3rdId INT, CurrencyId INT, Rate MONEY, MinAmount MONEY, MaxAmount MONEY, FromDate DATE, ToDate DATE)
		INSERT INTO #__PartyCharge3rdInfoByAmount (IsDeposit, Product3rdId, CurrencyId, Rate, MinAmount, MaxAmount, FromDate, ToDate)
		SELECT DISTINCT p.IsDeposit, p.Product3rdId, c.BaseCurrencyId, p.Rate, c.MinAmount, c.MaxAmount, p.FromDate, p.ToDate
		FROM #__PartyCharge3rdInfo p
			INNER JOIN DBLIC.bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON p.ChargeId = c.ChargeId
		WHERE p.ChargeType = 1 AND p.IsDeposit = 0 AND p.Product3rdId = 32 -- PP
		
		UPDATE p
		SET p.Rate = 0
		FROM #__PartyCharge3rdInfo p
			INNER JOIN #__PartyCharge3rdInfoByAmount pa ON p.IsDeposit = pa.IsDeposit AND p.Product3rdId = pa.Product3rdId

		DELETE t
		FROM (
			SELECT ROW_NUMBER() OVER(PARTITION BY ParentId, PartyId, LicenseeId, IsDeposit, Product3rdId, ChargeType, FromDate, ToDate, Rate ORDER BY ChargeId) AS RN
			FROM #__PartyCharge3rdInfo
		) t
		WHERE RN > 1

		CREATE TABLE #MetricChargeInfo (FromDate DATE, ToDate DATE, BaseCurrencyId INT, MinAmount MONEY, MaxAmount MONEY, Rate FLOAT)
		SELECT @SQL = '	SELECT FromDate, ToDate, BaseCurrencyId, MinAmount, MaxAmount, Rate
						FROM OPENQUERY(DBLIC, ''SELECT
													CASE WHEN ''''' + @f_date + ''''' >= ci.FromDate THEN ''''' + @f_date + ''''' ELSE ci.FromDate END AS FromDate
													,CASE WHEN ''''' + @t_date + ''''' <= ci.ToDate THEN ''''' + @t_date + ''''' ELSE ci.ToDate END AS ToDate
													,ci.BaseCurrencyId, ci.MinAmount, ci.MaxAmount, ci.Rate
												FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
												WHERE ci.ProductId = 0
													AND ci.FromParty = 1
													AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming
													AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + ''''''')'
		INSERT INTO #MetricChargeInfo (FromDate, ToDate, BaseCurrencyId, MinAmount, MaxAmount, Rate)
		EXEC (@SQL)

		UPDATE m
		SET m.MinAmount = m.MinAmount * e.Rate, m.MaxAmount = m.MaxAmount * e.Rate
		FROM #MetricChargeInfo m
			INNER JOIN @ExchangeOANDA e ON m.BaseCurrencyId = e.ExchangeId

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
	END

	-- Get mapping site
	BEGIN
		DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO @tmpSite (LicenseeId, SiteName)
		SELECT SiteId, RTRIM(LTRIM(SiteName)) FROM DBLIC.bodb_licensee.dbo.view_site_list WITH (NOLOCK)

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM @tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempResult (rptDate DATE, ParentId INT, IsDeposit BIT, Product3rdId INT, Bettype INT, CurrencyId INT, PlayCurrency INT, PayDaily MONEY, PayDailyRate MONEY, PayMonth MONEY, PayMonthRate MONEY, MemberWLDailyRate MONEY, MemberWLMonthRate MONEY)

		CREATE TABLE #__Bettype (Product3rdId INT, ProductCode VARCHAR(50), BetType INT)
		INSERT INTO #__Bettype (Product3rdId, ProductCode, BetType)
		SELECT DISTINCT p.Product3rdId, p.ProductCode, s.BetType FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
			INNER JOIN @Products p ON s.ProductId = p.ProductId AND p.Product3rdId <> 0
		WHERE s.BetType NOT IN (4298, 4299, 4300)

		-- Use Valid Bet Amount
		CREATE TABLE #__ValidBetRate (IsDeposit BIT, Product3rdId INT, FromDate DATE, ToDate DATE, CommRate FLOAT)

		-- For Allbet
		CREATE TABLE #__PlayCurrencySettings (SiteId INT, MemberCurrency INT, PlayCurrency INT, FromDate DATETIME, ToDate DATETIME)

		IF ',' + @ProductCodes + ',' LIKE '%,AB,%'
		BEGIN
			INSERT INTO #__PlayCurrencySettings (SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate)
			SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate
			FROM OPENQUERY (DBACC, 'SELECT s.SiteId, pc.MemberCurrency, pc.PlayCurrency, pc.FromDate, pc.ToDate
									FROM bodb02.dbo.PlayCurrencySetting pc WITH(NOLOCK)
										INNER JOIN bodb_licensee.dbo.view_site_list s WITH (NOLOCK) ON pc.SiteId = s.IbcSiteId
									WHERE pc.SportType = 211')
		
			DELETE #__PlayCurrencySettings WHERE ToDate < @FromDate OR FromDate > @ToDate
		END

		IF @DepositType IN (0, 2) AND (',' + @ProductCodes + ',' LIKE '%,AB,%' OR ',' + @ProductCodes + ',' LIKE '%,SAG,%')
		BEGIN
			INSERT INTO #__ValidBetRate (IsDeposit, Product3rdId, FromDate, ToDate, CommRate)
			SELECT DISTINCT IsDeposit, Product3rdId, FromDate, ToDate, Rate
			FROM #__PartyCharge3rdInfo
			WHERE ChargeType = 11 AND IsDeposit = 0
		END

		CREATE TABLE #__tempData (rptDate DATE, SiteId INT, BetTypeId INT, CurrencyId INT, Winloss MONEY, ValidBetAmount MONEY, ProgressiveContribution MONEY)
		
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
		BEGIN
			DELETE #__tempData

			-- Metric Gaming, Bet Builder
			INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
			SELECT f.rptDate, s.LicenseeId, CASE WHEN f.BetType = 38 THEN -3 ELSE -1 END, f.CurrencyId, SUM(CASE WHEN f.BetType = 38 THEN winlossP + commissionS ELSE winlossP + winlossA + winlossM + winlossS + commissionS END)
			FROM bodb_Account.dbo.FactSiteWinloss f WITH (NOLOCK)
				INNER JOIN @tmpSite s ON f.SiteId = s.SiteId_DW
			WHERE f.rptDate BETWEEN @FDate AND @TDate
				AND f.TicketStatus NOT IN (-1, 18, 9, 10, 14)
				AND f.CurrencyId <> 20
				AND (f.BetType = 38 OR f.BetType BETWEEN 801 AND 899)
			GROUP BY f.rptDate, s.LicenseeId, CASE WHEN f.BetType = 38 THEN -3 ELSE -1 END, f.CurrencyId

			-- Muay Thai
			INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
			SELECT rptDate, SiteId, -2, CurrencyId, SUM(ISNULL(AdjustedCustomerWL * 0.03, 0) - ISNULL(AdjustedCommShare, 0))
			FROM DBLIC.bodb_LicenseeReport.dbo.rpt_BettingBySport WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND CurrencyId <> 20
				AND StatusId IN (111, 112, 113)
				AND customercategory NOT IN (27, 28)
				AND SportType = 44
				AND (
					@DepositType = 2
					OR (@DepositType = 0 AND SiteId > 1000)
					OR (@DepositType = 1 AND SiteId < 1000)
				)
			GROUP BY rptDate, SiteId, CurrencyId

			INSERT INTO #__tempResult (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDailyRate)
			SELECT d.rptDate, 0, a.IsDeposit, 0, d.BetTypeId, d.CurrencyId, d.CurrencyId
				,SUM(CASE 
						WHEN d.BetTypeId = -2 THEN Winloss * e.Rate
						WHEN d.BetTypeId = -3 THEN Winloss * e.Rate * 0.04
						WHEN (-d.Winloss * p.Rate * e.Rate < 0 AND m.MinAmount = 0) OR -d.Winloss * p.Rate * e.Rate >= m.MinAmount
								THEN CASE WHEN -d.Winloss * p.Rate * e.Rate > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(-d.Winloss * p.Rate * e.Rate - m.MinAmount) END * m.Rate 
						ELSE 0 END)
			FROM #__tempData d
				INNER JOIN #AllParties a ON d.SiteId = a.LicenseeId
				INNER JOIN @ExchangeOANDA e ON d.CurrencyId = e.ExchangeId
				LEFT JOIN #__PartyChargeInfo p ON p.LicenseeId = d.SiteId AND p.Product3rdId = 0 AND d.rptDate BETWEEN p.FromDate AND p.ToDate AND d.BetTypeId = -1
				LEFT JOIN #MetricChargeInfo m ON d.rptDate BETWEEN m.FromDate AND m.ToDate AND d.BetTypeId = -1
			GROUP BY d.rptDate, a.IsDeposit, d.BetTypeId, d.CurrencyId

			UPDATE r
			SET r.PayMonthRate = r.PayDailyRate
				,r.PayDaily = CASE WHEN e.Rate = 0 THEN 0 ELSE r.PayDailyRate / e.Rate END
				,r.PayMonth = CASE WHEN e.Rate = 0 THEN 0 ELSE r.PayDailyRate / e.Rate END
			FROM #__tempResult r
				INNER JOIN @ExchangeOANDA e ON r.CurrencyId = e.ExchangeId
		END

		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId <> 0)
		BEGIN
			DELETE #__tempData

			INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss, ValidBetAmount, ProgressiveContribution)
			SELECT RptDate3rd, SiteId, BetTypeId, CurrencyId, SUM(Winloss), SUM(ValidBetAmount), SUM(ProgressiveContribution)
			FROM DBLIC.bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT WITH (NOLOCK)
			WHERE RptDate BETWEEN @FDate_GMT AND @TDate_GMT
				AND RptDate3rd BETWEEN @FDate AND @TDate
				AND CurrencyID <> 20
				AND StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND (
					@DepositType = 2
					OR (@DepositType = 0 AND SiteId > 1000)
					OR (@DepositType = 1 AND SiteId < 1000)
				)
			GROUP BY RptDate3rd, SiteId, BetTypeId, CurrencyId

			IF @DepositType IN (0, 2) AND @IsOldView = 0
				INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss, ValidBetAmount, ProgressiveContribution)
				SELECT RptDate3rd, SiteId, BetTypeId, CurrencyId, SUM(Winloss), SUM(ValidBetAmount), SUM(ProgressiveContribution)
				FROM DBLIC.bodb_LicenseeReport.dbo.rpt_CustomerWL_ExtraGMT WITH (NOLOCK)
				WHERE RptDate BETWEEN @FDate_GMT AND @TDate_GMT
					AND RptDate3rd BETWEEN @FDate AND @TDate
					AND CurrencyID <> 20
					AND StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
					AND (
						@DepositType = 2
						OR (@DepositType = 0 AND SiteId > 1000)
						OR (@DepositType = 1 AND SiteId < 1000)
					)
				GROUP BY RptDate3rd, SiteId, BetTypeId, CurrencyId

			INSERT INTO #__tempResult (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate, PayMonth, PayMonthRate, MemberWLDailyRate, MemberWLMonthRate)
			SELECT d.rptDate, tp.ParentId, tp.IsDeposit, bt.Product3rdId, CASE WHEN d.BetTypeId = 3007 THEN 3007 ELSE 0 END, d.CurrencyId, ISNULL(pc.PlayCurrency, d.CurrencyId) AS PlayCurrency
				,SUM((CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * ISNULL(ISNULL(p3.Rate, vs.ChargeRate3rd), 0)) AS PayDaily
				,SUM((CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * e.Rate * ISNULL(ISNULL(p3.Rate, vs.ChargeRate3rd), 0)) AS PayDailyRate
				,SUM((CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * CASE WHEN p.LicenseeId IS NULL OR p3.LicenseeId IS NULL THEN 0 ELSE p3.Rate END) AS PayMonth
				,SUM((CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * e.Rate * CASE WHEN p.LicenseeId IS NULL OR p3.LicenseeId IS NULL THEN 0 ELSE p3.Rate END) AS PayMonthRate
				,SUM( CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END * e.Rate) AS MemberWLDailyRate
				,SUM( CASE WHEN d.BetTypeId = 4297 THEN d.ProgressiveContribution ELSE d.Winloss END * e.Rate * CASE WHEN p.LicenseeId IS NULL THEN 0.0 ELSE 1.0 END) AS MemberWLMonthRate
			FROM #__tempData d
				INNER JOIN #__Bettype bt ON d.BetTypeId = bt.BetType
				INNER JOIN #AllParties tp ON tp.LicenseeId = d.SiteId
				INNER JOIN @ExchangeOANDA e ON d.CurrencyId = e.ExchangeId
				LEFT JOIN #__PartyChargeInfo p ON tp.LicenseeId = p.LicenseeId AND bt.Product3rdId = p.Product3rdId AND d.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ChargeType <> 11 AND ((d.BetTypeId <> 3007 AND p.ChargeType <> 12) OR (d.BetTypeId = 3007 AND p.ChargeType = 12))
				LEFT JOIN #__PartyCharge3rdInfo p3 ON tp.LicenseeId = p3.LicenseeId AND bt.Product3rdId = p3.Product3rdId AND d.rptDate BETWEEN p3.FromDate AND p3.ToDate AND p3.ChargeType <> 11 AND ((d.BetTypeId <> 3007 AND p3.ChargeType <> 12) OR (d.BetTypeId = 3007 AND p3.ChargeType = 12))
				LEFT JOIN #__tmpVendorGlobalSetting vs ON vs.IsDeposit = tp.IsDeposit AND vs.Product3rdId = bt.Product3rdId
				LEFT JOIN #__PlayCurrencySettings pc ON d.SiteId = pc.SiteId AND d.CurrencyId = pc.MemberCurrency AND d.rptDate BETWEEN pc.FromDate AND pc.ToDate
				LEFT JOIN #__ValidBetRate v ON tp.IsDeposit = v.IsDeposit AND bt.Product3rdId = v.Product3rdId AND d.rptDate BETWEEN v.FromDate AND v.ToDate
			GROUP BY d.rptDate, tp.ParentId, tp.IsDeposit, bt.Product3rdId, CASE WHEN d.BetTypeId = 3007 THEN 3007 ELSE 0 END, d.CurrencyId, ISNULL(pc.PlayCurrency, d.CurrencyId)
		END
	END

	CREATE TABLE #__DailyPayToSupplier (IsDeposit BIT, Product3rdId INT, Bettype INT DEFAULT(0), rptDate DATE, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))
	CREATE TABLE #__FullRangePayToSupplier (IsDeposit BIT, Product3rdId INT, Bettype INT DEFAULT(0), PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0))

	-- Pragmatic for Credit
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId = 32 AND IsDeposit = 0)
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
			SELECT rptDate, SUM(MemberWLDailyRate) AS MemberWLRate
			FROM #__tempResult
			WHERE Product3rdId = 32 AND IsDeposit = 0
			GROUP BY RptDate
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId
		WHERE ci.Product3rdId = 32 AND IsDeposit = 0

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier)
		SELECT 0, 32
			,SUM((CASE
				WHEN
					(MemberWLRate < 0 AND (ci.MinAmount * ex.Rate) = 0)
					OR (MemberWLRate >= (ci.MinAmount * ex.Rate))
				THEN 
					CASE
						WHEN MemberWLRate > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
						ELSE MemberWLRate - (ci.MinAmount * ex.Rate) END
				ELSE 0 END
			) * ci.Rate) AS PayToSupplier
		FROM
		(
			SELECT rptDate, SUM(MemberWLMonthRate) AS MemberWLRate
			FROM #__tempResult
			WHERE Product3rdId = 32 AND IsDeposit = 0
			GROUP BY RptDate
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId
		WHERE ci.Product3rdId = 32 AND IsDeposit = 0
	END

	-- SA Gaming for Deposit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId = 39 AND IsDeposit = 1)
	BEGIN
		DECLARE @AmountRM MONEY
		SELECT  @AmountRM = 10000000 * Rate FROM @ExchangeOANDA WHERE ExchangeId = 13 -- CNY

		;WITH CTE_SA AS
		(
			SELECT ParentId, CASE WHEN ParentId IN (1, 11) THEN CASE WHEN Amount < @AmountRM THEN 0.06 ELSE 0.05 END ELSE 0 END AS Rate
			FROM
			(
				SELECT CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END AS ParentId, SUM(-MemberWLDailyRate) AS Amount
				FROM #__tempResult
				WHERE BetType = 0 AND Product3rdId = 39 AND IsDeposit = 1
				GROUP BY CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END
			) a
		)
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier)
		SELECT 1, 39, d.rptDate, SUM(d.MemberWLDailyRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END)
		FROM #__tempResult d
			INNER JOIN CTE_SA t ON t.ParentId = d.ParentId
		WHERE d.Product3rdId = 39 AND IsDeposit = 1
		GROUP BY d.rptDate

		;WITH CTE_SA AS
		(
			SELECT ParentId, CASE WHEN ParentId IN (1, 11) THEN CASE WHEN Amount < @AmountRM THEN 0.06 ELSE 0.05 END ELSE 0 END AS Rate
			FROM
			(
				SELECT CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END AS ParentId, SUM(-MemberWLMonthRate) AS Amount
				FROM #__tempResult
				WHERE BetType = 0 AND Product3rdId = 39 AND IsDeposit = 1
				GROUP BY CASE WHEN ParentId = 98 THEN 11 ELSE ParentId END
			) a
		)
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier)
		SELECT 1, 39, SUM(d.MemberWLMonthRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END)
		FROM #__tempResult d
			INNER JOIN CTE_SA t ON t.ParentId = d.ParentId
		WHERE d.Product3rdId = 39 AND IsDeposit = 1
	END

	-- Check by MemberWL
	BEGIN
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, Bettype, PayToSupplier)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN -1 ELSE 0 END, SUM(PayToSupplier)
		FROM (
			SELECT IsDeposit, Product3rdId, ParentId, SUM(PayMonthRate) AS PayToSupplier
			FROM #__tempResult
			WHERE Product3rdId IN (10, 24) OR (Product3rdId = 0 AND Bettype = -1)
			GROUP BY IsDeposit, Product3rdId, ParentId
			HAVING SUM(PayMonthRate) < 0
		) t
		GROUP BY IsDeposit, Product3rdId
	END

	-- Others
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, Bettype, rptDate, PayToSupplier)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, rptDate, SUM(PayDailyRate)
		FROM #__tempResult
		WHERE
			(IsDeposit = 0 AND Product3rdId <> 32)
			OR (IsDeposit = 1 AND Product3rdId <> 39)
		GROUP BY IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, rptDate

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, Bettype, PayToSupplier)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, SUM(PayMonthRate)
		FROM #__tempResult
		WHERE Product3rdId NOT IN (10, 24)
			AND (Product3rdId <> 0 OR Bettype <> -1)
			AND (IsDeposit = 1 OR Product3rdId <> 32)
			AND (IsDeposit = 0 OR Product3rdId <> 39)
		GROUP BY IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END
	END

	-- Play Currency
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId = 21 AND IsDeposit = 0)
	BEGIN
		;WITH CTE_AB AS
		(
			SELECT b.rptDate, SUM(b.PayDaily * (pe.Rate - oe.Rate)) AS CurrencyPlay
			FROM #__tempResult b
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
		FROM #__tempResult b
			INNER JOIN @ExchangeOANDA oe ON oe.ExchangeID = b.CurrencyId
			INNER JOIN @ExchangeOANDA pe ON pe.ExchangeID = b.PlayCurrency
		WHERE Product3rdId = 21 AND IsDeposit = 0

		UPDATE f
		SET f.CurrencyPlay = ISNULL(@AB_CurrencyPlay_Month, 0)
		FROM #__FullRangePayToSupplier f
		WHERE Product3rdId = 21 AND IsDeposit = 0
	END

	CREATE TABLE #__FinalResult (IsDeposit BIT, Product3rdId INT, ProductCode VARCHAR(50), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	
	;WITH CTE_Product AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT f.IsDeposit, p.Product3rdId, p.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, 'Monthly', SUM(ISNULL(f.PayToSupplier, 0)), SUM(ISNULL(f.CurrencyPlay, 0))
	FROM CTE_Product p
		INNER JOIN #__FullRangePayToSupplier f ON p.Product3rdId = f.Product3rdId
	GROUP BY f.IsDeposit, p.Product3rdId, p.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END

	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, 'MTD', SUM(ISNULL(t.PayToSupplier, 0)), SUM(ISNULL(t.CurrencyPlay, 0))
	FROM CTE_RptDate d
		INNER JOIN #__DailyPayToSupplier t ON d.Product3rdId = t.Product3rdId
	GROUP BY t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END
	OPTION (MAXRECURSION 0)
	
	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	SELECT t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, CONVERT(VARCHAR(2), t.rptDate, 106), SUM(ISNULL(t.PayToSupplier, 0)), SUM(ISNULL(t.CurrencyPlay, 0))
	FROM CTE_RptDate d
		INNER JOIN #__DailyPayToSupplier t ON d.Product3rdId = t.Product3rdId
	GROUP BY t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, CONVERT(VARCHAR(2), t.rptDate, 106)

	DECLARE @DateList VARCHAR(2000)
	;WITH CTE_Date AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_Date
		WHERE rptDate < @TDate
	)
	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(2), rptDate, 106) + ']' FROM CTE_Date ORDER BY rptDate
	OPTION (MAXRECURSION 0)

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT IsDeposit, ProductCode, Figure, Monthly, MTD, ' + @DateList + '
		FROM (
			SELECT r.IsDeposit, f.ProductCode, Value, Figure, rptDate
			FROM #__FinalResult r
			CROSS APPLY (
				SELECT ProductCode, PayToSupplier AS Value, ''Pay to supplier'' AS Figure WHERE ProductCode NOT LIKE ''SB%''
				UNION ALL SELECT ProductCode, CurrencyPlay, ''Currency Play'' WHERE ProductCode NOT LIKE ''SB%''
				UNION ALL SELECT ''Soccer'', PayToSupplier, ''Pay to Metric Gaming'' WHERE ProductCode = ''SB-1''
				UNION ALL SELECT ''OS'', PayToSupplier, ''Pay to Muay Thai'' WHERE ProductCode = ''SB-2''
				UNION ALL SELECT ''Soccer'', PayToSupplier, ''Pay to Bet Genius'' WHERE ProductCode = ''SB-3''
			) f
		) t
		PIVOT (
			MAX(Value)
			FOR rptDate IN (Monthly, MTD, ' + @DateList + ')
		) p
	)
	SELECT
		s.IsDeposit, s.OrderByProduct, s.OrderByFigure, CASE WHEN s.IsDeposit = 0 THEN ''Credit'' ELSE ''Licensee'' END AS SiteGroup, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName
		,s.Figure, s.SubFigure, r.Monthly, r.MTD, ' + @DateList + '
	FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
		LEFT JOIN CTE_Result r ON r.ProductCode = s.ProductPrefix AND r.IsDeposit = s.IsDeposit AND r.Figure = s.Figure
	WHERE s.LogicCode = 3
		AND (
				s.EndOfSupportDate IS NULL AND s.isEnable = 1
				OR s.EndOfSupportDate >= ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''
		)
		AND (
			''' + @ProductList + ''' = ''all''
			OR s.ProductId = 1 AND '',' + @ProductList + ','' LIKE ''%,SB,%''
			OR '',' + @ProductList + ','' LIKE ''%,'' + s.ProductPrefix + '',%''
		)
		AND (
			' + CONVERT(VARCHAR(1), @DepositType) + ' = 2
			OR s.isDeposit = ' + CONVERT(VARCHAR(1), @DepositType) + '
		)
	ORDER BY s.OrderByProduct, s.OrderByFigure'

	EXEC (@SQL)

	DROP TABLE #__Bettype
	DROP TABLE #__DailyPayToSupplier
	DROP TABLE #__FinalResult
	DROP TABLE #__FullRangePayToSupplier
	DROP TABLE #__Party3rdInfo
	DROP TABLE #__PartyCharge3rdInfo
	DROP TABLE #__PartyCharge3rdInfoByAmount
	DROP TABLE #__PartyChargeInfo
	DROP TABLE #__PlayCurrencySettings
	DROP TABLE #__tempData
	DROP TABLE #__tempResult
	DROP TABLE #__tmpVendorGlobalSetting
	DROP TABLE #__ValidBetRate
	DROP TABLE #AllParties
	DROP TABLE #MetricChargeInfo
	DROP TABLE #Party
END
GO
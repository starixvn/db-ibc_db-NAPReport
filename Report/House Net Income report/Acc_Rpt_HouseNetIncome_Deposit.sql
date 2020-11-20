USE bodb_dwrs
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Deposit]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductList	VARCHAR(MAX) = 'all'
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

	IF @FromDate > @ToDate OR DATEDIFF(MONTH, @FromDate, @ToDate) <> 0
		RETURN

	DECLARE
		@FDate DATE, @TDate DATE, @LastDay DATE
		,@FromExDate SMALLDATETIME, @ToExDate SMALLDATETIME, @ExDate SMALLDATETIME
		,@f_date VARCHAR(10), @t_date VARCHAR(10), @SQL VARCHAR(MAX) -- use for dynamic query
		,@tmpDate DATE

	SELECT
		@FDate = @FromDate
		,@TDate = @ToDate
		,@FromExDate = @FromDate, @ToExDate = @ToDate
		,@f_date = CONVERT(VARCHAR(10), @FromDate, 120)
		,@t_date = CONVERT(VARCHAR(10), @ToDate, 120)
		,@LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))

	DECLARE @ProductIds VARCHAR(MAX), @Product3rdIds VARCHAR(MAX), @ProductCodes VARCHAR(MAX), @SubProducts VARCHAR(MAX), @PartyIds VARCHAR(MAX)

	-- Get list of product
	BEGIN
		DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
		INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
		SELECT ProductId, ProductPrefix FROM DBLIC.bodb_Licensee.dbo.Product3rd WITH (NOLOCK)

		DECLARE @Products TABLE (ProductId INT, Product3rdId INT, AliasProductId INT, SporttypeGroup INT DEFAULT (-1), ProductCode VARCHAR(50), SubProductCode VARCHAR(50))
		INSERT INTO @Products (ProductId, Product3rdId, AliasProductId, ProductCode, SubProductCode)
		SELECT DISTINCT s.ProductId, CASE WHEN s.ProductId = 1 THEN 0 ELSE p3.Product3rdId END, s.AliasProductId, p.ProductPrefix, s.ProductPrefix
		FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Products p WITH (NOLOCK) ON s.ProductId = p.ProductId
			LEFT JOIN @Product3rd p3 ON p.ProductPrefix = p3.ProductPrefix
		WHERE isDeposit = 1
			AND (
				s.EndOfSupportDate IS NULL AND s.isEnable = 1
				OR s.EndOfSupportDate < @FDate
			)
			AND (
				@ProductList = 'all'
				OR s.ProductId = 1 AND ',' + @ProductList + ',' LIKE '%,SB,%'
				OR ',' + @ProductList + ',' LIKE '%,' + s.ProductPrefix + ',%'
			)

		IF EXISTS (SELECT 1 FROM @Products WHERE ProductId = 1)
			INSERT INTO @Products (ProductId, Product3rdId, AliasProductId, ProductCode, SubProductCode)
			VALUES (0, 3, 0, 'BA', 'BA')

		;WITH CTE_Product AS (SELECT DISTINCT Product3rdId FROM @Products)
		SELECT @Product3rdIds = COALESCE(@Product3rdIds + ',', '') + CONVERT(VARCHAR(3), Product3rdId) FROM CTE_Product
		
		;WITH CTE_Product AS (SELECT DISTINCT ProductCode FROM @Products)
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

		;WITH CTE_Product AS (SELECT DISTINCT ProductId FROM @Products)
		SELECT @ProductIds = COALESCE(@ProductIds + ',', '') + CONVERT(VARCHAR(3), ProductId) FROM CTE_Product

		;WITH CTE_Product AS (SELECT DISTINCT SubProductCode FROM @Products)
		SELECT @SubProducts = COALESCE(@SubProducts + ',', '') + SubProductCode FROM CTE_Product
	END

	-- Get Exchange
	BEGIN
		DECLARE @Exchange TABLE (FromDate DATE, ToDate DATE, ExchangeId INT, Rate FLOAT)
		DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		
		-- System Rate
		DECLARE @tmpExchange TABLE (ExchangeDate DATE, ExchangeId INT, Rate FLOAT, PRIMARY KEY (ExchangeDate, ExchangeId))
		INSERT INTO @tmpExchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @FromExDate AND @ToExDate

		SELECT @tmpDate = @FDate
		WHILE @tmpDate <= @TDate
		BEGIN
			UPDATE e
			SET e.ToDate = t.ExchangeDate
			FROM @Exchange e
				INNER JOIN @tmpExchange t ON e.ExchangeId = t.ExchangeId AND e.ToDate = DATEADD(DAY, -1, t.ExchangeDate)
			WHERE t.ExchangeDate = @tmpDate
				AND e.Rate = t.Rate

			INSERT INTO @Exchange (FromDate, ToDate, ExchangeId, Rate)
			SELECT ExchangeDate, ExchangeDate, ExchangeId, Rate
			FROM @tmpExchange t
			WHERE NOT EXISTS (SELECT 1 FROM @Exchange e WHERE t.ExchangeDate = e.ToDate AND t.ExchangeId = e.ExchangeId)

			SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
		END

		-- Oanda Rate
		SELECT @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate
	END

	-- Get Deposit Licensees
	BEGIN
		-- All Deposit Licensees
		CREATE TABLE #AllLicensees (LicenseeId INT, PartyId INT, ParentId INT)
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
		SELECT OldRefId, PartyId, ParentId
		FROM OPENQUERY (DBLIC, '
			SELECT OldRefId, PartyId, ParentId
			FROM (
				SELECT ci.FromParty AS PartyId, ci.ToParty AS ParentId, p.OldRefId
					,ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
				FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
					INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
					INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
					INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
				WHERE ci.ChargeType = 1
					AND p.PartyType = 1
					AND pd.IsDeposit = 1
					AND ci.ToParty IN (1, 9, 11, 98)
			) r
			WHERE RowNum = 1'
		)

		-- Deposit Licensees have setting
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT, ParentId INT)
		SELECT @SQL = '
			SELECT OldRefId, PartyId, ToParty
			FROM OPENQUERY (DBLIC, '' 
				SELECT DISTINCT p.OldRefId, p.PartyId, ci.ToParty
				FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
					INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
					INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
					INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
				WHERE p.PartyType = 1
					AND pd.IsDeposit = 1
					AND ci.ToParty IN (1, 9, 11, 98)
					AND ci.ProductId IN (' + @Product3rdIds + ')
					AND ci.FromDate <= ''''' + @t_Date + ''''' AND ci.ToDate >= ''''' + @f_Date + '''''''
			)'

		INSERT INTO #Licensees
		EXEC (@SQL)
	END

	-- Get charge rate
	BEGIN
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees

		CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, LicenseeId INT, LicenseeName VARCHAR(200), SiteId_DW INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
		SELECT @SQL = '	SELECT ChargeId, PartyId, LicenseeId, LicenseeName, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY(DBLIC, ''SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.LicenseeId, LTRIM(RTRIM(s.SiteName)) AS LicenseeName, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.ChargeType
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
													LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
													INNER JOIN bodb_licensee.dbo.view_site_list s with (nolock) on ci.LicenseeId = s.SiteId
												WHERE
													(
														ci.ChargeType = 1
														OR ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11 -- GD
														OR ci.ChargeType = 12 AND ci.ProductId = 39 -- SAG
													)
													AND ci.DI_Rate > 0''
										)'
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, LicenseeName, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		UPDATE p
		SET p.SiteId_DW = s.SiteId
		FROM #PartyChargeInfo p
			INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON p.LicenseeName = LTRIM(RTRIM(s.site))

		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)
		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1
													AND ci.DI_Rate > 0''
										)'
		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)

		CREATE TABLE #PartyCharge3rdInfo (ChargeType INT, LicenseeId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		SELECT @SQL = '	SELECT ChargeType, LicenseeId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT DISTINCT ci.ChargeType, ci.LicenseeId, ci.ProductId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1
													AND ci.DI_Rate > 0''
										)'
		INSERT INTO #PartyCharge3rdInfo (ChargeType, LicenseeId, Rate)
		EXEC (@SQL)

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
													AND ci.FromDate <= ''''' + @t_Date + ''''' AND ci.ToDate >= ''''' + @f_Date + '''''''
										)'

		INSERT INTO #MetricChargeInfo (FromDate, ToDate, BaseCurrencyId, MinAmount, MaxAmount, Rate)
		EXEC (@SQL)

		UPDATE m
		SET m.MinAmount = m.MinAmount * ISNULL(oa.Rate, 0), m.MaxAmount = m.MaxAmount * ISNULL(oa.Rate, 0)
		FROM #MetricChargeInfo m
			LEFT JOIN @ExchangeOANDA oa ON m.BaseCurrencyId = oa.ExchangeId

		-- Get default setting 3rd
		CREATE TABLE #tempVendorGlobalSetting (Product3rdId INT, Bettype INT, ChargeRate3rd DECIMAL(19, 8))
		INSERT INTO #tempVendorGlobalSetting (Bettype, ChargeRate3rd)
		SELECT Bettype, NumberValue
		FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
		WHERE VName LIKE '3rdCashWLShareRate%'
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData
		(
			rptDate				DATE
			,LicenseeId			INT
			,CurrencyId			INT
			,Product3rdId		INT
			,AliasProductId		INT
			,SportTypeGroup		INT
			,BetTypeGroup		INT
			,IsPayToSupplierGMT	BIT DEFAULT(0)
			,ValidBetAmount		MONEY DEFAULT(0) -- GD
			,OddsSpread			MONEY DEFAULT(0) -- SB
			,MemberWL			MONEY DEFAULT(0) -- CO: include AWinloss, PP: exclude LicenseeContribution
			,HouseWL			MONEY DEFAULT(0)
			,HouseTO			MONEY DEFAULT(0)
			,Comm				MONEY DEFAULT(0) -- SB: AComm, Exchange: AComm + PComm
			,HouseContribution	MONEY DEFAULT(0) -- FullContribution - LicenseeContribution
			,FullContribution	MONEY DEFAULT(0) -- FullContribution
		)

		-- Mapping site
		CREATE TABLE #__tempSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO #__tempSite (SiteId_DW, SiteName)
		SELECT SiteId, RTRIM(LTRIM(Site)) FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE IsDeposit = 1

		UPDATE s
		SET s.LicenseeId = l.LicenseeId
		FROM #__tempSite s
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(l.LicenseeName))

		-- SB
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
		BEGIN
			-- Saba League
			CREATE TABLE #__SabaLeague (LeagueId INT, LeagueGroupId INT)
			INSERT INTO #__SabaLeague (LeagueId, LeagueGroupId)
			SELECT LeagueId, LeagueGroupId FROM bodb02.dbo.League WITH (NOLOCK) WHERE sporttype IN (1, 2, 50) AND LeagueGroupId IN (42, 74, 108)

			CREATE TABLE #__tempSB (rptDate DATE, SiteId INT, CurrencyId INT, ProductId INT, LeagueId INT, Sporttype INT, MemberWL MONEY, AWL MONEY, AComm MONEY)
			INSERT INTO #__tempSB (rptDate, SiteId, CurrencyId, ProductId, LeagueId, Sporttype, MemberWL, AWL, AComm)
			SELECT rptDate, SiteId, CurrencyId, ProductId, LeagueId
				,CASE
					WHEN BetType IN (9, 29) THEN -2 -- Parlay
					WHEN SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
					ELSE 99 -- Other Sports
					END AS Sporttype
				,SUM(MemberWinloss) AS MemberWL
				,SUM(CASE WHEN bettype = 999 THEN AgentWinloss ELSE 0 END) AS AWL -- Odds Spread Adjustment
				,SUM(AgentComm) AS AComm
			FROM bodb_Account.dbo.FactLADailyWinloss WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND SiteId NOT IN(-2, -4)
				AND ProductId IN (10001, 10004)
				AND Bettype NOT IN (901, 902, 903, 904)
				AND CurrencyId <> 20
				AND TicketStatus NOT IN(-1, 18, 9, 10, 14)
			GROUP BY rptDate, SiteId, CurrencyId, ProductId, LeagueId
				,CASE
					WHEN BetType IN (9, 29) THEN -2 -- Parlay
					WHEN SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
					ELSE 99 -- Other Sports
					END
			OPTION (RECOMPILE)

			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, Product3rdId, SporttypeGroup, BettypeGroup, MemberWL, HouseWL, Comm)
			SELECT t.rptDate, s.LicenseeId, t.CurrencyId
				,CASE
					WHEN t.ProductId = 10001 THEN 0 -- SB
					ELSE 3 -- BA
					END AS ProductId
				,CASE
					WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -4 -- Saba Basketball
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -5 -- Saba Cricket
					WHEN t.SportType IN (-2, 1, 2, 5, 43) THEN t.SportType
					ELSE 99
					END AS SporttypeGroup
				,-1 AS BettypeGroup
				,SUM(t.MemberWL) AS MemberWL
				,SUM(t.AWL) AS HouseWL -- Odds Spread Adjustment
				,SUM(t.AComm) AS AComm
			FROM #__tempSB t
				INNER JOIN #__tempSite s ON t.SiteId = s.SiteId_DW
				LEFT JOIN #__SabaLeague l ON t.LeagueId = l.LeagueId
			GROUP BY t.rptDate, s.LicenseeId, t.CurrencyId
				,CASE
					WHEN t.ProductId = 10001 THEN 0 -- SB
					ELSE 3 -- BA
					END
				,CASE
					WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -4 -- Saba Basketball
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -5 -- Saba Cricket
					WHEN t.SportType IN (-2, 1, 2, 5, 43) THEN t.SportType
					ELSE 99
					END

			DROP TABLE #__SabaLeague
			DROP TABLE #__tempSB
		END

		-- CB
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (10, 11, 15, 31))
		BEGIN
			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, Product3rdId, BetTypeGroup, ValidBetAmount, MemberWL, Comm)
			SELECT
				rptDate, SiteId, CurrencyId, ProductId
				,BetTypeGroup	= CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END
				,ValidBetAmount	= SUM(CASE WHEN ProductId = 11 AND bettype = -1 THEN ValidBetAmount ELSE 0 END)
				,MemberWL		= SUM(CASE
										WHEN ProductId = 15 THEN Turnover * 0.0405 + BuyBackAmount * 0.15
										ELSE MemberWL END)
				,Comm			= SUM(CASE
										WHEN ProductId = 31 THEN CommissionP + CommissionA
										ELSE 0 END)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND ProductID IN (SELECT p.Product3rdId FROM @Products p WHERE p.Product3rdId IN (10, 11, 31))
				AND CurrencyId <> 20
				AND CustomerCategory NOT IN (27, 28)
				AND StatusId NOT IN (-1, 101, 102, 103)
				AND SiteId < 1000 -- Deposit only
			GROUP BY rptDate, SiteId, CurrencyId, ProductId
				,CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END
		END

		-- Others + SB for Metric Gaming, Bet Builder
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId NOT IN (10, 11, 15, 31))
		BEGIN
			DECLARE @tmpBetType TABLE (Product3rdId INT, AliasProductId INT, IsPayToSupplierGMT BIT, BetType INT, BettypeGroup INT)
			INSERT INTO @tmpBetType (Product3rdId, AliasProductId, IsPayToSupplierGMT, BetType, BettypeGroup)
			SELECT DISTINCT p.Product3rdId
				,CASE
					WHEN s.bettype BETWEEN 801 AND 899 THEN -1 -- Metric Gaming
					WHEN s.bettype = 38 THEN -2 -- Bet Builder
					ELSE p.AliasProductId
					END AS AliasProductId
				,CASE WHEN s.ProductId IN (1,2,3,4,5,6) THEN 1 ELSE 0 END AS IsPayToSupplierGMT
				,CASE
					WHEN s.ProductId = 22 AND bg.BettypeGroupId = 11 THEN 1 -- VB (Macau Games)
					WHEN s.BetType = 3007 THEN 1 -- SA Gaming
					WHEN s.BetType IN (1902, 1903, 1904, 1905) THEN s.BetType -- CC (Card Club)
					ELSE -1 END AS BettypeGroup
				,s.BetType
			FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
				INNER JOIN @Products p ON s.ProductId = p.ProductId
				LEFT JOIN bodb_Account.dbo.BettypeGroup bg WITH (NOLOCK) ON s.BetType = bg.Bettype
			WHERE s.BetType NOT IN (901, 902, 903, 904, 911, 912, 1700, 1706, 1800, 1906, 4298, 4299, 4300, 8000, 18000)
				AND (
					s.ProductId NOT IN (1, 3)
					OR
					(
						s.ProductId = 1
						AND (
							s.bettype BETWEEN 801 AND 899
							OR s.bettype = 38
						)
					)
					OR
					(
						s.ProductId = 3
						AND (
							p.SubProductCode = 'NG' AND s.bettype NOT BETWEEN 8101 AND 8200
							OR p.SubProductCode = 'H5' AND s.bettype BETWEEN 8101 AND 8200
						)
					)
				)

			IF EXISTS (SELECT 1 FROM @Products WHERE SubProductCode = 'PP-JP')
				INSERT INTO @tmpBetType (Product3rdId, AliasProductId, BetType)
				SELECT p.Product3rdId, p.AliasProductId, b.BetType
				FROM @Products p
					CROSS JOIN (SELECT 4297 AS BetType UNION ALL SELECT 4298) b
				WHERE SubProductCode = 'PP-JP'

			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, Product3rdId, AliasProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, HouseContribution, FullContribution)
			SELECT b.rptDate, s.LicenseeId, b.CurrencyId, bt.Product3rdId, bt.AliasProductId, CASE WHEN b.SportType = 150 THEN b.SportType ELSE -1 END, bt.BetTypeGroup
				,SUM(CASE
						WHEN b.BetType IN (4297) THEN 0
						WHEN b.BetType IN (903, 904, 913, 914) THEN b.WinlossP + b.WinlossA
						WHEN bt.Product3rdId = -1 THEN b.WinlossP + b.WinLossA + b.WinLossS + b.WinLossM + b.CommissionS
						WHEN bt.Product3rdId = -2 THEN b.WinlossP + b.CommissionS
						ELSE b.WinlossP
						END) AS MemberWL
				,SUM(CASE WHEN b.bettype = 4297 THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
				,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC ELSE 0 END) AS HouseContribution
				,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
			FROM bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
				INNER JOIN @tmpBetType bt ON b.BetType = bt.BetType
				INNER JOIN #__tempSite s ON b.SiteId = s.SiteId_DW
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyId <> 20
				AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
			GROUP BY b.rptDate, s.LicenseeId, b.CurrencyId, bt.Product3rdId, bt.AliasProductId, CASE WHEN b.SportType = 150 THEN b.SportType ELSE -1 END, bt.BetTypeGroup
			OPTION (RECOMPILE)
		END

		UPDATE v
		SET v.Product3rdId = s.Product3rdId
		FROM #tempVendorGlobalSetting v
			CROSS APPLY (
				SELECT TOP 1 b.Product3rdId
				FROM @tmpBetType b
				WHERE v.Bettype = b.BetType
			) s

		DELETE #tempVendorGlobalSetting WHERE Product3rdId IS NULL

		UPDATE v
		SET v.Bettype = -1
		FROM #tempVendorGlobalSetting v
			LEFT JOIN @tmpBetType b ON v.Bettype = b.BetTypeGroup
		WHERE b.BetTypeGroup IS NULL

		-- Process data
		DECLARE @BobbetId INT, @TianboId INT
		DECLARE @GDCommissionRate FLOAT = 0
		SELECT  @GDCommissionRate = DI_Rate FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'GD', 'OA') WHERE ChargeType = 11

		CREATE TABLE #__tempResult
		(
			rptDate				DATETIME
			,CurrencyId			INT
			,PartyId			INT
			,ParentId			INT
			,Product3rdId		INT
			,SporttypeGroup		INT
			,OriginalMemberWL	MONEY
			,MemberWL			MONEY
			,AComm				MONEY
			,PayToSupplierDaily	MONEY
			,PayToSupplierMonth	MONEY
			,CurrencyPlay		MONEY
			,FullContribution	MONEY
			,JackpotPrize		MONEY
			,HouseTurnoverDaily	MONEY
			,HouseTurnoverMonth	MONEY
			,HouseIncomeDaily	MONEY
			,HouseIncomeMonth	MONEY
			,IsApplyMinFee		BIT DEFAULT (1) -- for calculate min fee
		)

		INSERT INTO #__tempResult
		(
			rptDate
			,CurrencyId
			,PartyId
			,ParentId
			,Product3rdId
			,SporttypeGroup
			,OriginalMemberWL
			,MemberWL
			,AComm
			,PayToSupplierDaily
			,PayToSupplierMonth
			,FullContribution
			,JackpotPrize
			,HouseIncomeDaily
			,HouseIncomeMonth
		)
		SELECT
			t.rptDate
			,CurrencyId	= CASE WHEN t.Product3rdId = 10 THEN t.CurrencyId END
			,l.PartyId
			,ParentId	= CASE
							WHEN t.Product3rdId IN (11, 22, 34) THEN l.PartyId
							WHEN t.Product3rdId = 10 THEN l.ParentId
							WHEN t.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
							WHEN t.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
							END
			,t.Product3rdId
			,t.SportTypeGroup
			,OriginalMemberWL	= SUM(t.MemberWL)
			,MemberWL			= SUM(t.MemberWL * ISNULL(oa.Rate, 0))
			,AComm				= SUM(t.Comm * ISNULL(e.Rate, 0))
			,PayToSupplierDaily	= SUM((
									(
										t.MemberWL + CASE WHEN rd.Product3rdId = 11 AND rd.ChargeType = 12 THEN t.ValidBetAmount * @GDCommissionRate ELSE 0 END
									)
									*
									(
										CASE
											WHEN t.IsPayToSupplierGMT = 1 THEN 0
											WHEN t.Product3rdId = -4 THEN -1 * ISNULL(lc.Rate, p.Rate) -- Metric Gaming
											WHEN t.Product3rdId = -5 THEN 0.04 -- Bet Builder
											WHEN t.Product3rdId = 27 THEN 0.065 -- VS2
											WHEN t.Product3rdId IN (8, 28) THEN
												CASE
													WHEN t.rptDate >= '2020-07-01' THEN
														CASE WHEN p.LicenseeId IN (@BobbetId, @TianboId) THEN 0.02 ELSE 0.036 END
													WHEN l.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03 ELSE 0.05 END -- KN, LT
											WHEN t.Product3rdId = 22 THEN CASE WHEN t.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
											WHEN t.Product3rdId = 34 AND t.BetTypeGroup <> -1 THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(rd.Rate, v.ChargeRate3rd) -- daily get default rate if not have setting
											END
					
									)
									+
									(
										CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END -- EX
									)
						 
								) * ISNULL(oa.Rate, 0)
								)
			,PayToSupplierMonth	= SUM((
									(
										t.MemberWL + CASE WHEN rd.Product3rdId = 11 AND rd.ChargeType = 12 THEN t.ValidBetAmount * @GDCommissionRate ELSE 0 END
									)
									*
									(
										CASE
											WHEN t.IsPayToSupplierGMT = 1 THEN 0
											WHEN t.Product3rdId = -4 THEN -1 * ISNULL(lc.Rate, p.Rate) -- Metric Gaming
											WHEN t.Product3rdId = -5 THEN 0.04 -- Bet Builder
											WHEN t.Product3rdId = 27 THEN 0.065 -- VS2
											WHEN t.Product3rdId IN (8, 28) THEN
												CASE
													WHEN t.rptDate >= '2020-07-01' THEN
														CASE WHEN p.LicenseeId IN (@BobbetId, @TianboId) THEN 0.02 ELSE 0.036 END
													WHEN l.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03 ELSE 0.05 END -- KN, LT
											WHEN t.Product3rdId = 22 THEN CASE WHEN t.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
											WHEN t.Product3rdId = 34 AND t.BetTypeGroup <> -1 THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(rd.Rate, 0)
											END
					
									)
									+
									(
										CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END -- EX
									)
						 
								) * ISNULL(oa.Rate, 0)
								)
			,FullContribution	= SUM(CASE WHEN t.Product3rdId = -3 THEN t.FullContribution * ISNULL(e.Rate, 0) ELSE 0 END)
			,JackpotPrize		= SUM(CASE WHEN t.Product3rdId = -3 THEN -t.MemberWL * ISNULL(e.Rate, 0) ELSE 0 END)
			,HouseIncomeDaily	= SUM(CASE
										WHEN p.LicenseeId IS NULL THEN -t.HouseWL -- daily get HouseWL if not have setting
										WHEN t.Product3rdId = 37 THEN -t.HouseWL
										WHEN t.SportTypeGroup = 150 THEN -t.MemberWL -- SBC free bets
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) - t.OddsSpread) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * ISNULL(e.Rate, 0))
			,HouseIncomeMonth	= SUM(CASE
										WHEN p.LicenseeId IS NULL THEN 0
										WHEN t.Product3rdId = 37 THEN -t.HouseWL
										WHEN t.SportTypeGroup = 150 THEN -t.MemberWL -- SBC free bets
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) - t.OddsSpread) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * ISNULL(e.Rate, 0))
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.LicenseeId = l.LicenseeId
			LEFT JOIN #PartyChargeInfo p ON p.LicenseeId = t.LicenseeId AND p.Product3rdId = t.Product3rdId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = t.BetTypeGroup)
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND p.ChargeType = 12)
						OR ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND p.ChargeType <> 12)
					)
			LEFT JOIN #PartyCharge3rdInfo rd ON rd.LicenseeId = t.LicenseeId AND rd.Product3rdId = t.Product3rdId AND t.rptDate BETWEEN rd.FromDate AND rd.ToDate
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND rd.ChargeType = 12)
						OR ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND rd.ChargeType <> 12)
					)
			LEFT JOIN #tempVendorGlobalSetting v ON v.Product3rdId = t.Product3rdId AND v.Bettype = t.BetTypeGroup
			LEFT JOIN @Exchange e ON t.rptDate BETWEEN e.FromDate AND e.ToDate AND t.CurrencyId = e.ExchangeId
			LEFT JOIN @ExchangeOANDA oa ON t.CurrencyId = oa.ExchangeId
			LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		WHERE (
			(t.Product3rdId IN (0, 3, -1) AND p.LicenseeId IS NOT NULL)
			OR (t.Product3rdId NOT IN (0, 3, -1))
		)
		GROUP BY
			t.rptDate
			,CASE WHEN t.Product3rdId = 10 THEN t.CurrencyId END
			,l.PartyId
			,CASE
				WHEN t.Product3rdId IN (11, 22, 34) THEN l.PartyId
				WHEN t.Product3rdId = 10 THEN l.ParentId
				WHEN t.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
				WHEN t.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
				END
			,t.Product3rdId
			,t.SportTypeGroup

		CREATE CLUSTERED INDEX CIX_Product3rdId ON #__tempResult (Product3rdId, rptDate)

		-- For special PayToSupplier
			-- 1. NG, H5
		UPDATE #__tempResult
		SET PayToSupplierDaily = -0.5 * HouseIncomeDaily, PayToSupplierMonth = -0.5 * HouseIncomeMonth
		WHERE Product3rdId IN (2, -2) -- NG, H5

			-- 2. AGC
		;WITH CTE_Sum AS
		(
			SELECT ParentId, Product3rdId, CASE WHEN LicenseeWL <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END AS Rate
			FROM
			(
				SELECT r.ParentId, r.Product3rdId, -SUM(r.OriginalMemberWL * CASE WHEN r.ParentId = 1 THEN e.CNY ELSE e.USD END) AS LicenseeWL
				FROM #__tempResult r
					INNER JOIN @ExchangeOANDA e ON r.CurrencyId = e.ExchangeId
				WHERE r.Product3rdId = 10
				GROUP BY ParentId, Product3rdId
			) t
		)
		UPDATE r
		SET r.PayToSupplierDaily = r.MemberWL * s.Rate, r.PayToSupplierMonth = r.MemberWL * s.Rate
		FROM #__tempResult r
			INNER JOIN CTE_Sum s ON r.ParentId = s.ParentId AND r.Product3rdId = s.Product3rdId

			-- 3. Metric Gaming, Muay Thai, Bet Builder
		CREATE TABLE #__PayToSupplierSB (GroupId TINYINT, rptDate DATE, PaytoSupplier MONEY) -- GroupId: 1 = Metric Gaming, 2 = Muay Thai, 3 = Bet Builder
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
		BEGIN
			;WITH CTE_Metric AS (
				SELECT ci.Rate
					,CASE WHEN @FDate >= ci.FromDate THEN @FDate ELSE ci.FromDate END AS FromDate
					,CASE WHEN @TDate <= ci.ToDate THEN @TDate ELSE ci.ToDate END AS ToDate
					,ci.MinAmount * oa.Rate AS MinAmount
					,ci.MaxAmount * oa.Rate AS MaxAmount
				FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
					INNER JOIN @ExchangeOANDA oa ON ci.BaseCurrencyId = oa.ExchangeId
				WHERE ci.ProductId = 0
					AND ci.FromParty = 1
					AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming
					AND (
						ci.FromDate BETWEEN @FDate AND @TDate
						OR ci.ToDate BETWEEN @FDate AND @TDate
						OR ci.FromDate < @FDate
						AND @TDate < ci.ToDate
					)
			)
			INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
			SELECT CASE WHEN r.Product3rdId = -5 THEN 3 ELSE 2 END
				,r.rptDate
				,CASE
					WHEN r.Product3rdId = -5 THEN r.PayToSupplierDaily
					WHEN (r.PayToSupplierDaily < 0 AND m.MinAmount = 0) OR r.PayToSupplierDaily >= m.MinAmount
						THEN CASE WHEN r.PayToSupplierDaily > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(r.PayToSupplierDaily - m.MinAmount) END * m.Rate
					ELSE 0
					END
			FROM #__tempResult r
				LEFT JOIN CTE_Metric m ON r.rptDate BETWEEN m.FromDate AND m.ToDate AND r.Product3rdId = -4
			WHERE r.Product3rdId IN (-4, -5)

			-- Muay Thai
			INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
			SELECT 1, b.rptDate
				,SUM((ISNULL(b.AdjustedCustomerWL * 0.03, 0) - ISNULL(b.AdjustedCommShare, 0)) * ISNULL(oa.Rate, 0))
			FROM bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
			    INNER JOIN #PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			    INNER JOIN @ExchangeOANDA oa ON oa.ExchangeId = b.CurrencyId
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyId <> 20
				AND b.StatusId IN (111, 112, 113)
				AND b.customercategory NOT IN (27, 28)
				AND b.SiteId < 1000
				AND b.SportType = 44
				AND p.Product3rdId = 0
			GROUP BY b.rptdate
		END

		-- Licensee Min Fee
		BEGIN
			DECLARE @FirstDate		DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FDate), 0)
			DECLARE @LastDate		DATETIME = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FirstDate))
			DECLARE @DaysInMonth	INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

			DECLARE @MinFee TABLE
			(
				FeeTypeId			TINYINT -- 1: normal, 2: waive
				,GroupMinFeeId		SMALLINT
				,PartyId			INT
				,IsPrimary			BIT
				,Product3rdId		INT
				,CurrencyId         INT
				,FromDate			DATE
				,ToDate				DATE
				,IndividualMinFee   MONEY -- Setting min fee
				,ProrateMinFee		MONEY
				,WaivedFee			MONEY
				,LicenseeFee		MONEY
				,ActualFee			MONEY
			)
			INSERT INTO @MinFee
			(
				FeeTypeId
				,GroupMinFeeId
				,PartyId
				,IsPrimary
				,Product3rdId
				,CurrencyId
				,IndividualMinFee
				,FromDate
				,ToDate
			)
			SELECT
				FeeTypeId
				,PartyId AS GroupMinFeeId
				,PartyId
				,0 AS IsPrimary
				,ProductId
				,CurrencyId
				,FeeAmount
				,CASE WHEN @FDate > FromDate THEN @FDate ELSE FromDate END AS FromDate
				,CASE WHEN @TDate < ToDate THEN @TDate ELSE ToDate END AS ToDate
			FROM bodb_licensee.dbo.LA_MinFee WITH (NOLOCK)
			WHERE FeeTypeId IN (1, 2)
				AND ProductId IN (SELECT p.Product3rdId FROM #PartyChargeInfo p)
				AND FromDate <= @LastDate AND ToDate >= @FirstDate

			;WITH CTE_GroupMinFee AS (
				SELECT TOP (1) WITH TIES a.PartyId, h.GroupMinFeeId, a.IsPrimary
				FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
					INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
				WHERE @FDate BETWEEN h.FromDate AND h.ToDate
				ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)
			)
			UPDATE m
			SET m.GroupMinFeeId = g.GroupMinFeeId, m.IsPrimary = g.IsPrimary
			FROM @MinFee m
				INNER JOIN CTE_GroupMinFee g ON m.PartyId = g.PartyId

			UPDATE m
			SET m.IndividualMinFee = m.IndividualMinFee * e.Rate
			FROM @MinFee m
				INNER JOIN @ExchangeOANDA e ON m.CurrencyId = e.ExchangeId

			UPDATE t
			SET t.IsApplyMinFee = 0
			FROM #__tempResult t
				INNER JOIN @MinFee m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
					AND t.PartyId = m.PartyId
					AND t.Product3rdId = m.Product3rdId
			WHERE m.FeeTypeId = 2

			UPDATE m1
			SET m1.ProrateMinFee = (
						(
							SELECT TOP 1 m2.IndividualMinFee
							FROM @MinFee m2
							WHERE m2.FeeTypeId = 1
								AND m1.PartyId = m2.PartyId
								AND m1.Product3rdId = m2.Product3rdId
						) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
				,m1.WaivedFee = ISNULL(
						(
							SELECT SUM(r.HouseIncomeMonth)
							FROM #__tempResult r
							WHERE m1.PartyId = r.PartyId
								AND m1.Product3rdId = r.Product3rdId
								AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
						), 0)
			FROM @MinFee m1
			WHERE m1.FeeTypeId = 2

			UPDATE m1
			SET m1.ProrateMinFee = ROUND(
									(m1.IndividualMinFee / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
									- ISNULL((
										SELECT SUM(m2.ProrateMinFee)
										FROM @MinFee m2
										WHERE m2.FeeTypeId = 2
											AND m1.PartyId = m2.PartyId
											AND m1.Product3rdId = m2.Product3rdId
										), 0)
									, 2)
				,m1.WaivedFee = ISNULL((
										SELECT SUM(m2.WaivedFee)
										FROM @MinFee m2
										WHERE m2.FeeTypeId = 2
											AND m1.PartyId = m2.PartyId
											AND m1.Product3rdId = m2.Product3rdId
										HAVING SUM(m2.WaivedFee) > 0
									), 0)
				,m1.LicenseeFee = ISNULL((
										SELECT SUM(r.HouseIncomeMonth)
										FROM #__tempResult r
										WHERE m1.PartyId = r.PartyId
											AND m1.Product3rdId = r.Product3rdId
											AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
											AND r.IsApplyMinFee = 1
									), 0)
			FROM @MinFee m1
			WHERE m1.FeeTypeId = 1

			DELETE @MinFee WHERE FeeTypeId = 2

			UPDATE @MinFee
			SET ActualFee = CASE WHEN LicenseeFee < ProrateMinFee THEN ProrateMinFee ELSE LicenseeFee END + WaivedFee

			-- Group min fee
			DECLARE @TotalMinFees TABLE (GroupMinFeeId INT, Product3rdId INT, TotalGroupMinFee MONEY, TotalFee MONEY)
			INSERT INTO @TotalMinFees (GroupMinFeeId, Product3rdId, TotalGroupMinFee, TotalFee)
			SELECT TOP(1) WITH TIES mfd.GroupMinFeeID, ProductId, mfd.MinimumFee * e.Rate AS TotalMinFee, 0
			FROM bodb_Licensee.dbo.LA_GroupMinFeeDetail mfd WITH (NOLOCK)
				INNER JOIN @ExchangeOANDA e ON e.ExchangeId = mfd.CurrencyId
			WHERE @FDate BETWEEN mfd.FromDate AND mfd.ToDate
			ORDER BY ROW_NUMBER() OVER(PARTITION BY mfd.GroupMinFeeId ORDER BY mfd.ToDate DESC)

			UPDATE t
			SET t.TotalFee = m.TotalFee
			FROM @TotalMinFees t
				CROSS APPLY (
					SELECT SUM(m.LicenseeFee) AS TotalFee
					FROM @MinFee m
					WHERE t.GroupMinFeeId = m.GroupMinFeeId AND t.Product3rdId = m.Product3rdId
						AND m.LicenseeFee > 0
				) m
		
			UPDATE m
			SET m.ActualFee = m.ActualFee + (t.TotalGroupMinFee - t.TotalFee)
			FROM @MinFee m
				INNER JOIN @TotalMinFees t ON t.GroupMinFeeId = m.GroupMinFeeId AND t.Product3rdId = m.Product3rdId
			WHERE m.GroupMinFeeId > 0
				AND t.TotalFee < t.TotalGroupMinFee
				AND m.IsPrimary = 1

			DECLARE @tmpResult TABLE (PartyId INT, Product3rdId INT, LicenseeWL MONEY, HouseTurnover MONEY, HouseIncome MONEY, AComm MONEY, MinFee MONEY, WLFee MONEY)
			INSERT INTO @tmpResult (PartyId, Product3rdId, LicenseeWL, HouseTurnover, HouseIncome, AComm, MinFee, WLFee)
			SELECT PartyId, Product3rdId, SUM(CASE WHEN SporttypeGroup = 150 THEN 0 ELSE -MemberWL END), SUM(HouseTurnoverMonth), SUM(HouseIncomeMonth), SUM(AComm), 0, SUM(HouseIncomeMonth) FROM #__tempResult
			GROUP BY PartyId, Product3rdId

			INSERT INTO @tmpResult (PartyId, Product3rdId, HouseIncome, AComm, MinFee, WLFee)
			SELECT m.PartyId, m.Product3rdId, 0, 0, 0, 0
			FROM @MinFee m
				INNER JOIN #PartyChargeInfo p ON p.PartyId = m.PartyId AND p.Product3rdId = m.Product3rdId
				LEFT JOIN @tmpResult r ON m.PartyId = r.PartyId AND m.Product3rdId = r.Product3rdId
			WHERE r.PartyId IS NULL

			UPDATE s
			SET s.HouseIncome	= m.LicenseeFee
				,s.MinFee		= CASE WHEN m.LicenseeFee = m.ActualFee THEN 0 ELSE m.ProrateMinFee END
				,s.WLFee		= CASE WHEN m.LicenseeFee = m.ActualFee THEN m.ActualFee ELSE m.WaivedFee END
			FROM @tmpResult s
				INNER JOIN @MinFee m ON m.PartyId = s.PartyId AND m.Product3rdId = s.Product3rdId

			UPDATE r
			SET r.HouseIncome = CASE WHEN r.HouseIncome > 0 OR r.Product3rdId = 3 THEN r.HouseIncome ELSE 0 END
				,r.WLFee = CASE
							WHEN r.Product3rdId = 42 THEN CASE WHEN r.LicenseeWL > 0 THEN r.WLFee ELSE 0 END
							WHEN r.WLFee > 0 THEN r.WLFee ELSE 0 END
			FROM @tmpResult r
			WHERE
				r.Product3rdId <> 0
				OR r.PartyId NOT IN (
					SELECT p.PartyId FROM bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)
					WHERE p.PartyName IN ('9wickets', '9Wsports')
				)
		END
	END

	-- Calculate result
	DELETE @Products WHERE Product3rdId = 3 -- BA
	
	IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
	BEGIN
		UPDATE @Products SET SporttypeGroup = 1, ProductCode = 'Soccer' WHERE Product3rdId = 0

		INSERT INTO @Products (ProductId, Product3rdId, SporttypeGroup, ProductCode)
		SELECT p.ProductId, p.Product3rdId, s.SporttypeGroup, s.ProductCode
		FROM @Products p
			CROSS JOIN (
				SELECT 2 AS SubOrder, -3 AS SporttypeGroup, 'SabaSoccer' AS ProductCode
				UNION ALL SELECT 3, 2, 'Basketball'
				UNION ALL SELECT 4, -4, 'SabaBasketball'
				UNION ALL SELECT 5, 5, 'Tennis'
				UNION ALL SELECT 6, 43, 'E-Sports'
				UNION ALL SELECT 7, 99, 'OS'
				UNION ALL SELECT 8, -5, 'SabaCricket'
				UNION ALL SELECT 9, -2, 'Parlay'
			) s
		WHERE p.Product3rdId = 0
	END

	DECLARE @BAComm MONEY, @BAWinloss MONEY
    SELECT  @BAComm = -SUM(AComm), @BAWinloss = SUM(HouseIncome) FROM @tmpResult WHERE Product3rdId = 3
	SELECT  @BAComm = ISNULL(@BAComm, 0), @BAWinloss = ISNULL(@BAWinloss, 0)

	UPDATE #__tempResult SET Product3rdId = 0 WHERE Product3rdId = 3

	CREATE TABLE #Result
	(
		rptDate VARCHAR(10)
		,Product3rdId INT
		,ProductCode VARCHAR(50)
		,HouseTurnover MONEY
		,HouseIncome MONEY
		,MinFee MONEY
		,BAComm MONEY
		,PayToSupplier MONEY
		,PaytoMuayThai MONEY
		,PaytoMetricGaming MONEY
		,PayToBetBuilder MONEY
		,FullContribution MONEY
		,JackpotPrize MONEY
	)
	INSERT INTO #Result
	(
		rptDate
		,Product3rdId
		,ProductCode
		,HouseTurnover
		,HouseIncome
		,MinFee
		,BAComm
		,PayToSupplier
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
		,FullContribution
		,JackpotPrize
	)
	SELECT 'Monthly', p.Product3rdId, p.ProductCode
			,HouseTurnover = SUM(CASE WHEN p.Product3rdId = 0 AND p.SporttypeGroup <> 1 THEN 0 ELSE ISNULL(r.HouseTurnover, 0) END)
			,HouseIncome = SUM(CASE WHEN p.Product3rdId = 0 AND p.SporttypeGroup <> 1 THEN 0 ELSE ISNULL(r.WLFee, 0) END)
			,MinFee = SUM(CASE WHEN p.Product3rdId = 0 AND p.SporttypeGroup = 1 THEN ISNULL(r.MinFee, 0) ELSE 0 END)
			,BAComm = 0
			,PayToSupplier = SUM(CASE WHEN p.Product3rdId IN (2, -2) THEN -0.5 * ISNULL(HouseIncome, 0) ELSE 0 END)
			,PaytoMuayThai = 0
			,PaytoMetricGaming = 0
			,PayToBetBuilder = 0
			,FullContribution = 0
			,JackpotPrize = 0
	FROM @Products p
		LEFT JOIN @tmpResult r ON p.Product3rdId = r.Product3rdId
	GROUP BY p.Product3rdId, p.ProductCode

	-- Update full range
		-- 1. Pay to supplier
		-- 1.1. Base on MemberWL < 0
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(r.PayToSupplier) AS PayToSupplier
			FROM (
				SELECT SUM(t.PayToSupplierMonth) AS PayToSupplier
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId
				GROUP BY t.ParentId
				HAVING SUM(t.MemberWL) < 0
			) r
		) t
	WHERE r.Product3rdId IN (5, 10, 11, 22, 27)

		-- 1.2. Total daily
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.PayToSupplierMonth) AS PayToSupplier FROM #__tempResult t WHERE t.Product3rdId = r.Product3rdId
		) t
	WHERE r.Product3rdId NOT IN (5, 10, 11, 22, 27)

		-- 2. House Income
		-- 2.1. Include BA into SB
	UPDATE #Result SET HouseIncome = HouseIncome + @BAWinloss, BAComm = @BAComm WHERE Product3rdId = 0 AND ProductCode = 'Soccer'

		-- 2.2. Base on AmountToCompany > 0
	UPDATE r
	SET r.HouseIncome = ISNULL(t.HouseIncome, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(r.HouseIncome) AS HouseIncome
			FROM (
				SELECT SUM(t.HouseIncomeMonth) AS HouseIncome
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId
				GROUP BY t.ParentId
				HAVING SUM(t.HouseIncomeMonth) > 0
			) r
		) t
	WHERE r.Product3rdId IN (22)

		-- 2.3. Total daily
	UPDATE r
	SET r.HouseIncome = ISNULL(t.HouseIncome, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.HouseIncomeMonth) AS HouseIncome FROM #__tempResult t WHERE t.Product3rdId = r.Product3rdId
		) t
	WHERE r.Product3rdId IN (13, 15, 25, 31, 37)

		-- 3. FullContribution, JackpotPrize
	UPDATE r
	SET r.FullContribution = ISNULL(t.FullContribution, 0), r.JackpotPrize = ISNULL(t.JackpotPrize, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.FullContribution) AS FullContribution, SUM(t.JackpotPrize) AS JackpotPrize FROM #__tempResult t WHERE t.Product3rdId = r.Product3rdId
		) t
	WHERE r.Product3rdId = -3

	-- Detail daily
	;WITH CTE_rptDate AS
	(
		SELECT CONVERT(DATETIME, @FDate) AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #Result
	(
		rptDate
		,Product3rdId
		,ProductCode
		,HouseTurnover
		,HouseIncome
		,MinFee
		,BAComm
		,PayToSupplier
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
		,FullContribution
		,JackpotPrize
	)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106), p.Product3rdId, p.ProductCode
		,SUM(ISNULL(t.HouseIncomeDaily, 0))
		,SUM(ISNULL(t.HouseTurnoverDaily, 0))
		,0 AS MinFee
		,SUM(ISNULL(-t.AComm, 0))
		,SUM(ISNULL(t.PayToSupplierDaily, 0))
		,0
		,0
		,0
		,SUM(ISNULL(t.FullContribution, 0))
		,SUM(ISNULL(t.JackpotPrize, 0))
	FROM CTE_rptDate r
		CROSS JOIN @Products p
		LEFT JOIN #__tempResult t ON r.rptDate = t.rptDate AND t.Product3rdId = p.Product3rdId AND (t.Product3rdId = 0 AND t.SporttypeGroup = p.SporttypeGroup OR t.Product3rdId <> 0)
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106), p.Product3rdId, p.ProductCode
	OPTION (MAXRECURSION 0)

	INSERT INTO #Result
	(
		rptDate
		,Product3rdId
		,ProductCode
		,HouseTurnover
		,HouseIncome
		,MinFee
		,BAComm
		,PayToSupplier
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
		,FullContribution
		,JackpotPrize
	)
	SELECT
		'MTD' AS rptDate
		,Product3rdId
		,ProductCode
		,SUM(HouseTurnover)
		,SUM(HouseIncome)
		,SUM(MinFee)
		,SUM(BAComm)
		,SUM(PayToSupplier)
		,SUM(PaytoMuayThai)
		,SUM(PaytoMetricGaming)
		,SUM(PayToBetBuilder)
		,SUM(FullContribution)
		,SUM(JackpotPrize)
	FROM #Result
	WHERE rptDate <> 'Monthly'
	GROUP BY
		Product3rdId
		,ProductCode

	;WITH CTE_PayToSB AS (
		SELECT
			CONVERT(VARCHAR(2), rptDate, 106) AS rptDate
			,CASE WHEN GroupId = 1 THEN 'OS' ELSE 'Soccer' END AS ProductCode
			,SUM(CASE WHEN GroupId = 1 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PaytoMuayThai
			,SUM(CASE WHEN GroupId = 2 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PaytoMetricGaming
			,SUM(CASE WHEN GroupId = 3 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PayToBetBuilder
		FROM #__PayToSupplierSB
		GROUP BY
			CONVERT(VARCHAR(2), rptDate, 106)
			,CASE WHEN GroupId = 1 THEN 'OS' ELSE 'Soccer' END
	)
	UPDATE r
	SET r.PaytoMuayThai = p.PaytoMuayThai
		,r.PaytoMetricGaming = p.PaytoMetricGaming
		,r.PayToBetBuilder = CASE WHEN r.rptDate = 'Monthly' AND p.PayToBetBuilder > 0 THEN 0 ELSE p.PayToBetBuilder END
	FROM #Result r
		INNER JOIN (
			SELECT CONVERT(VARCHAR(10), 'Monthly') AS rptDate
				,ProductCode
				,SUM(PaytoMuayThai) AS PaytoMuayThai
				,SUM(PaytoMetricGaming) AS PaytoMetricGaming
				,SUM(PayToBetBuilder) AS PayToBetBuilder
			FROM CTE_PayToSB
			GROUP BY ProductCode
			
			UNION ALL
			SELECT rptDate, ProductCode, PaytoMuayThai, PaytoMetricGaming, PayToBetBuilder FROM CTE_PayToSB
		) p ON r.rptDate = p.rptDate AND r.ProductCode = p.ProductCode
	WHERE r.ProductCode IN ('OS', 'Soccer')

	UPDATE r1
	SET r1.PaytoMuayThai = r2.PaytoMuayThai
		,r1.PaytoMetricGaming = r2.PaytoMetricGaming
		,r1.PayToBetBuilder = r2.PayToBetBuilder
	FROM #Result r1
		INNER JOIN #Result r2 ON r1.ProductCode = r2.ProductCode
	WHERE r1.rptDate = 'MTD' AND r2.rptDate = 'Monthly'

	-- Update result
	UPDATE #Result
	SET HouseIncome			= CASE WHEN Product3rdId = -3 THEN NULL ELSE HouseIncome END
		,HouseTurnover		= CASE WHEN Product3rdId = -3 THEN NULL ELSE HouseTurnover END
		,PayToSupplier		= CASE WHEN Product3rdId IN (0, -3, 6, 13, 15, 25, 37, 38, 42) THEN NULL ELSE PayToSupplier END
		,PaytoMuayThai		= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'OS' THEN NULL ELSE PaytoMuayThai END
		,PaytoMetricGaming	= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'Soccer' THEN NULL ELSE PaytoMetricGaming END
		,PayToBetBuilder	= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'Soccer' THEN NULL ELSE PayToBetBuilder END
		,FullContribution	= CASE WHEN Product3rdId <> -3 THEN NULL ELSE FullContribution END
		,JackpotPrize		= CASE WHEN Product3rdId <> -3 THEN NULL ELSE JackpotPrize END
		,MinFee				= CASE WHEN Product3rdId <> 0 THEN NULL ELSE MinFee END
		,BAComm				= CASE WHEN Product3rdId <> 0 THEN NULL ELSE BAComm END

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

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT ProductCode, Figure, Monthly, MTD, ' + @DateList + '
		FROM (

			SELECT r.ProductCode, f.Value, f.Figure, r.rptDate
			FROM #Result r
			CROSS APPLY (
				SELECT BAComm AS Value, ''BA Commission'' AS Figure WHERE BAComm IS NOT NULL
				UNION ALL SELECT FullContribution, ''Contribution Amount'' WHERE FullContribution IS NOT NULL
				UNION ALL SELECT HouseTurnover, ''House TurnOver'' WHERE HouseTurnover IS NOT NULL
				UNION ALL SELECT JackpotPrize, ''Jackpot Prize'' WHERE JackpotPrize IS NOT NULL
				UNION ALL SELECT HouseIncome, ''Licensee House Income'' WHERE HouseIncome IS NOT NULL
				UNION ALL SELECT MinFee, ''Licensing Minimum Fee'' WHERE MinFee IS NOT NULL
				UNION ALL SELECT PayToBetBuilder, ''Pay to Bet Genius'' WHERE PayToBetBuilder IS NOT NULL
				UNION ALL SELECT PaytoMetricGaming, ''Pay to Metric Gaming'' WHERE PaytoMetricGaming IS NOT NULL
				UNION ALL SELECT PaytoMuayThai, ''Pay to Muay Thai'' WHERE PaytoMuayThai IS NOT NULL
				UNION ALL SELECT PayToSupplier, ''Pay to supplier'' WHERE PayToSupplier IS NOT NULL
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
	
	DROP TABLE #__PayToSupplierSB
	DROP TABLE #__tempData
	DROP TABLE #__tempResult
	DROP TABLE #__tempSite
	DROP TABLE #AllLicensees
	DROP TABLE #Licensees
	DROP TABLE #MetricChargeInfo
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #PartyChargeInfo
	DROP TABLE #Result
	DROP TABLE #tempVendorGlobalSetting
END
GO
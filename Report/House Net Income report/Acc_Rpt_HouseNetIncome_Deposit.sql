/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Deposit]
	@FromDate			DATE
	,@ToDate			DATE
	,@ProductList		VARCHAR(MAX) = 'all'
	,@IsLicPerf			BIT = 0
	,@BaseCurrencyName  VARCHAR(10) = 'MYR'
AS

/*
	Created: 20201201@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Deposit
	
	Revisions:
		- 20201201@Percy: Initiliaze SP [RedmineID: #143208]
		- 20200112@Percy: Integrate Happy 5 Linked Games [RedmineID: #146539]
		- 20210125@Percy: Return SubFigure column [RedmineID: #149267]
		- 20210202@Percy: Integrate Saba.Club Four Guardians games [RedmineID: #149122]
		- 20210325@Sophia: Change Formula of House TO to get rate from LA setting, not use PT Setting [Redmine: #152291] 
		- 20210405@Percy: Missing Contribution Amount & Jackpot Prize on Monthly [RedmineID: #152912]
		- 20210402@Danny: Support Lucky Draw for AE Casino & Integrate Bonus program for credit sites for Arcadia Gaming & Remove the Gold Deluxe (#151870)
		- 20210331@Danny: exclude site saba789 [Redmine: #152450] 
		- 20210419@Danny: Arcadia Gaming - Add 2 new games: Marble Mini and RPS (#153419)
		- 20210405@Danny: Integrate VGaming Casino games (#154157)
		- 20210517@Danny: Special term when billing between OneWorks and 9w licensee (#155045)
		- 20210520@Danny: Incorporate Saba Soccer PinGoal (#155373)
		- 20210616@Danny: Add measure Member TO, Member WL to support Licensee Performance (#156727)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @IsTest BIT = 0
	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)

	IF @FromDate > @ToDate OR DATEDIFF(MONTH, @FromDate, @ToDate) <> 0
		RETURN

	DECLARE
		@FDate DATE, @TDate DATE, @LastDay DATE
		,@FromExDate SMALLDATETIME, @ToExDate SMALLDATETIME, @ExDate SMALLDATETIME
		,@f_date VARCHAR(10), @t_date VARCHAR(10), @SQL VARCHAR(MAX) -- use for dynamic query
		,@FromDateByBatch DATE, @ToDateByBatch DATE

	SELECT
		@FDate = @FromDate
		,@TDate = @ToDate
		,@FromExDate = @FromDate, @ToExDate = @ToDate
		,@f_date = CONVERT(VARCHAR(10), @FromDate, 120)
		,@t_date = CONVERT(VARCHAR(10), @ToDate, 120)
		
	DECLARE @BobbetId INT = 0, @TianboId INT = 0
	DECLARE @Discount_PartyIds VARCHAR(MAX), @Discount_ProductCodes VARCHAR(MAX)
	DECLARE @ProductIds VARCHAR(MAX), @Product3rdIds VARCHAR(MAX), @ProductCodes VARCHAR(MAX), @SubProducts VARCHAR(MAX), @PartyIds VARCHAR(MAX)

	-- Get list of product
	BEGIN
		DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
		INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
		SELECT ProductId, ProductPrefix FROM DBLIC.bodb_Licensee.dbo.Product3rd WITH (NOLOCK)

		DECLARE @Products TABLE (ProductId INT, Product3rdId INT, AliasProductId INT, ProductCode VARCHAR(50), SubProductCode VARCHAR(50), IsPayToSupplier BIT DEFAULT (0))
		INSERT INTO @Products (ProductId, Product3rdId, AliasProductId, ProductCode, SubProductCode)
		SELECT DISTINCT s.ProductId, CASE WHEN s.ProductId = 1 THEN 0 ELSE p3.Product3rdId END, s.AliasProductId, p.ProductPrefix, s.ProductPrefix
		FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Products p WITH (NOLOCK) ON s.ProductId = p.ProductId
			LEFT JOIN @Product3rd p3 ON p.ProductPrefix = p3.ProductPrefix
		WHERE isDeposit = 1
			AND (
				s.EndOfSupportDate IS NULL AND s.isEnable = 1
				OR s.EndOfSupportDate >= @TDate
			)
			AND (
				@ProductList = 'all'
				OR s.ProductId = 1 AND ',' + @ProductList + ',' LIKE '%,SB,%'
				OR ',' + @ProductList + ',' LIKE '%,' + s.ProductPrefix + ',%'
			)
			AND s.IsTest <= @IsTest

		UPDATE @Products SET IsPayToSupplier = 1 WHERE ProductId IN (SELECT ProductId FROM bodb_Account.dbo.HNISettings WITH (NOLOCK) WHERE Figure = 'Pay to Supplier' AND LogicCode = 1 AND isDeposit = 1)

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
		DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		SELECT  @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate

		DECLARE @LA_f_ExchangeDailySel TABLE (ExchangeId INT, BaseCurrencyRate FLOAT)
		DECLARE @SQLExchangeDailySel VARCHAR(MAX)
		SELECT @SQLExchangeDailySel = ' SELECT ExchangeId, BaseCurrencyRate
						FROM OPENQUERY (DBLIC, ''SELECT ExchangeId, BaseCurrencyRate FROM bodb02.dbo.LA_f_ExchangeDailySel(''''' + CONVERT(VARCHAR(10), @ExDate, 120) + ''''', ''''' +  CONVERT(VARCHAR(10), @ExDate, 120) + ''''', ''''' + @BaseCurrencyName + ''''')'')'
	

		INSERT INTO @LA_f_ExchangeDailySel(ExchangeId, BaseCurrencyRate)
		EXEC (@SQLExchangeDailySel)

		-- Update Rate based on @BaseCurrencyName Input
		IF @IsLicPerf = 1 
		BEGIN
			UPDATE t 
			SET  t.Rate = u.BaseCurrencyRate
			FROM @ExchangeOANDA t
			INNER JOIN @LA_f_ExchangeDailySel u ON t.ExchangeId = u.ExchangeId
		END
	END

	-- Get Deposit Licensees
	BEGIN
		-- All Deposit Licensees
		CREATE TABLE #AllLicensees (LicenseeId INT, PartyId INT, ParentId INT, SiteId_DW INT)
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
		SELECT LicenseeId, PartyId, ParentId
		FROM OPENQUERY (DBLIC, 'SELECT OldRefId AS LicenseeId, FromParty AS PartyId, ToParty AS ParentId
								FROM (
									SELECT p.OldRefId, ci.FromParty, ci.ToParty, ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
									FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
										INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
										INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
										INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
									WHERE ci.ChargeType = 1 AND p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98)
								) r
								WHERE RowNum = 1')

		-- Deposit Licensees have setting
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT, ParentId INT)
		SELECT @SQL = ' SELECT LicenseeId, PartyId, ParentId
						FROM OPENQUERY (DBLIC, '' 
							SELECT DISTINCT p.OldRefId AS LicenseeId, ci.FromParty AS PartyId, ci.ToParty AS ParentId
							FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
								INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
								INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
								INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
							WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98)
								AND ci.ProductId IN (' + @Product3rdIds + ')
								AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + ''''''')'
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		EXEC (@SQL)

	END

	-- Get charge rate
	BEGIN
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees

		CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
		SELECT @SQL = '	SELECT ChargeId, PartyId, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.ChargeType
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
							WHERE ci.DI_Rate > 0
								AND (
									ci.ChargeType = 1
									OR ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11 -- GD
									OR ci.ChargeType IN (6, 7) AND ci.ProductId = 15 -- CB
									OR ci.ChargeType = 5 AND ci.ProductId = 25 -- CO
									OR ci.ChargeType = 12 AND ci.ProductId = 39 -- SAG
								)'')'
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)
		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1 AND ci.DI_Rate > 0'')'
		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)

		DECLARE @PartyCharge3rd TABLE (PartyId INT, Product3rdId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		SELECT @SQL = '	SELECT PartyId, ProductId, ChargeType, FromDate, ToDate, Rate
						FROM OPENQUERY (DBLIC, ''SELECT DISTINCT PartyId, ProductId, ChargeType, FromDate, ToDate, CASE WHEN ProductId = 10 THEN 0 ELSE DI_Rate END AS Rate
												 FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''')
												 WHERE DI_Rate > 0
													AND (
														ChargeType = 1
														OR (ChargeType IN (9, 10, 12) AND ProductId = 11) -- GD
													)'')'
		INSERT INTO @PartyCharge3rd (PartyId, Product3rdId, ChargeType, FromDate, ToDate, Rate)
		EXEC (@SQL)

		CREATE TABLE #PartyCharge3rdInfo (ChargeType INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.Product3rdId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #PartyChargeInfo p ON p.PartyId = p3.PartyId AND p.Product3rdId = p3.Product3rdId

		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.Product3rdId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #AllLicensees l ON p3.PartyId = l.ParentId
			INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND p.Product3rdId = p3.Product3rdId
		WHERE NOT EXISTS (SELECT 1 FROM #PartyCharge3rdInfo rd WHERE p.PartyId = rd.PartyId AND p.Product3rdId = rd.Product3rdId)

		SELECT @BobbetId = PartyId FROM DBLIC.bodb_Licensee.dbo.OAS_Party WITH (NOLOCK) WHERE PartyName = 'Bobbet'
		SELECT @TianboId = PartyId FROM DBLIC.bodb_Licensee.dbo.OAS_Party WITH (NOLOCK) WHERE PartyName = 'Tianbo'

		-- Update charge rate for Keno, Lottery, Table Game
		DECLARE @tmp_PartyCharge3rdInfo TABLE (ChargeType INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate MONEY)
		
		IF EXISTS (SELECT 1 FROM #PartyCharge3rdInfo WHERE Product3rdId IN (8, 28, 40) AND ToDate >= '2020-07-01')
		BEGIN
			INSERT INTO @tmp_PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
			SELECT p.ChargeType, p.PartyId, p.Product3rdId
				,CASE WHEN p.FromDate > r.FromDate THEN p.FromDate ELSE r.FromDate END
				,CASE WHEN p.ToDate < r.ToDate THEN p.ToDate ELSE r.ToDate END
				, r.Rate
			FROM #PartyCharge3rdInfo p
				CROSS APPLY (
					SELECT p.FromDate, CONVERT(DATE, '2020-06-30') AS ToDate, p.Rate
					WHERE FromDate <= '2020-06-30'
					UNION ALL
					SELECT CONVERT(DATE, '2020-07-01') AS FromDate, p.ToDate, 0.02 AS Rate
					WHERE p.PartyId IN (@BobbetId, @TianboId)
					UNION ALL
					SELECT CONVERT(DATE, '2020-07-01') AS FromDate, p.ToDate, 0.036 AS Rate
					WHERE p.PartyId NOT IN (@BobbetId, @TianboId)
				) r
			WHERE p.Product3rdId IN (8, 28, 40) AND p.ToDate >= '2020-07-01'

			DELETE #PartyCharge3rdInfo WHERE Product3rdId IN (8, 28, 40) AND ToDate >= '2020-07-01'

			INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
			SELECT ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate FROM @tmp_PartyCharge3rdInfo
		END

		-- Get default setting 3rd
		CREATE TABLE #tempVendorGlobalSetting (Product3rdId INT, Bettype INT, ChargeRate3rd FLOAT)
		INSERT INTO #tempVendorGlobalSetting (Bettype, ChargeRate3rd)
		SELECT Bettype, NumberValue
		FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
		WHERE VName LIKE '3rdCashWLShareRate%'
	END

	-- Get mapping site
	BEGIN
		DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO @tmpSite (LicenseeId, SiteName)
		SELECT LicenseeId, RTRIM(LTRIM(LicenseeName)) FROM DBLIC.bodb_licensee.dbo.Licensees WITH (NOLOCK) WHERE IsDeposit = 1

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM @tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))

		UPDATE l
		SET l.SiteId_DW = s.SiteId_DW
		FROM #AllLicensees l
			INNER JOIN @tmpSite s ON l.LicenseeId = s.LicenseeId
	END

	-- Get data
	BEGIN
		DECLARE @tmpBetType TABLE (Product3rdId INT, AliasProductId INT, BetType INT, BettypeGroup INT, IsOnlyTO BIT)
		INSERT INTO @tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
		SELECT DISTINCT p.Product3rdId, CASE WHEN p.Product3rdId IN (0, 3) THEN 0 ELSE p.AliasProductId END, s.BetType
			,CASE
				WHEN p.Product3rdId = 34 AND bg.BettypeGroupId IS NULL THEN s.BetType -- CC (Card Club)
				WHEN s.BetType = 3007 OR (s.ProductId = 22 AND bg.BettypeGroupId = 11) THEN 1 -- SA Gaming, VB (Macau Games)
				ELSE -1 END AS BettypeGroup
			,CASE WHEN p.Product3rdId IN (0, 3, 10, 11, 15, 31) THEN 1 ELSE 0 END AS IsOnlyTO
		FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
			INNER JOIN @Products p ON s.ProductId = p.ProductId
			LEFT JOIN bodb_Account.dbo.BettypeGroup bg WITH (NOLOCK) ON s.BetType = bg.Bettype
		WHERE s.BetType NOT IN (911, 912, 1906, 4298, 4299, 4300, 1699, 3150, 3899)
			AND (
				s.ProductId <> 3
				OR (p.SubProductCode = 'NG' AND s.sporttype = 161)
				OR (p.SubProductCode = 'H5' AND s.sporttype = 164)
				OR (p.SubProductCode = 'H5LG' AND s.sporttype = 168)
			)
			AND p.SubProductCode NOT IN ('PP-JP', 'SBC-JP', 'VGA-JP')

		IF EXISTS (SELECT 1 FROM @Products WHERE SubProductCode = 'PP-JP')
			INSERT INTO @tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
			SELECT p.Product3rdId, p.AliasProductId, b.BetType, -3, 0
			FROM (SELECT Product3rdId, AliasProductId FROM @Products WHERE SubProductCode = 'PP-JP') p
				CROSS JOIN (SELECT 4297 AS BetType UNION ALL SELECT 4298) b

		IF EXISTS (SELECT 1 FROM @Products WHERE SubProductCode IN ('SBC-JP', 'VGA-JP'))
		BEGIN
			INSERT INTO @tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
			SELECT p.Product3rdId, p.AliasProductId, b.BetType, -3, 0
			FROM (SELECT Product3rdId, AliasProductId FROM @Products WHERE SubProductCode = 'SBC-JP') p
				CROSS JOIN (SELECT 1698 AS BetType UNION ALL SELECT 1699) b

			INSERT INTO @tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
			SELECT p.Product3rdId, p.AliasProductId, b.BetType, -3, 0
			FROM (SELECT Product3rdId, AliasProductId FROM @Products WHERE SubProductCode = 'VGA-JP') p
				CROSS JOIN (SELECT 3898 AS BetType UNION ALL SELECT 3899) b
		END

		CREATE TABLE #__SabaLeague (LeagueId INT, LeagueGroupId INT)

		CREATE TABLE #__tempData
		(
			rptDate				DATE
			,SiteId_DW			INT
			,CurrencyId			INT
			,Product3rdId		INT
			,AliasProductId		INT
			,SporttypeGroup		INT DEFAULT(-1)
			,BetTypeGroup		INT DEFAULT(-1)
			,ValidBetAmount		MONEY DEFAULT(0)
			,OddsSpreadAdj		MONEY DEFAULT(0) -- SB: Odds Spread Adjustment
			,MemberWL			MONEY DEFAULT(0) -- CO: include AWinloss, PP: exclude LicenseeContribution
			,HouseWL			MONEY DEFAULT(0)
			,HouseTO			MONEY DEFAULT(0)
			,Stake				MONEY DEFAULT(0)
			,Comm				MONEY DEFAULT(0) -- SB: BA Comm, Exchange: AComm + PComm
			,HouseContribution	MONEY DEFAULT(0) -- FullContribution - LicenseeContribution
			,FullContribution	MONEY DEFAULT(0) -- FullContribution
			,MemberTurnover		MONEY DEFAULT(0) 
		)

		-- SB
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (0, 3))
		BEGIN
			INSERT INTO #__SabaLeague (LeagueId, LeagueGroupId)
			SELECT LeagueId, LeagueGroupId FROM bodb02.dbo.League WITH (NOLOCK) WHERE sporttype IN (1, 2, 50) AND LeagueGroupId IN (42, 74, 108, 113)

			;WITH CTE_SB AS (
				SELECT rptDate, SiteId, CurrencyId, ProductId, LeagueId
					,CASE
						WHEN BetType IN (9, 29) THEN -2 -- Parlay
						WHEN SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports, Cricket
						ELSE 99 -- Other Sports
						END AS Sporttype
					,SUM(MemberWinloss) AS MemberWinloss
					,SUM(CASE WHEN bettype = 999 THEN AgentWinloss ELSE 0 END) AS AgentWinloss
					,SUM(CASE WHEN ProductId = 10004 THEN AgentComm ELSE 0 END) AS AgentComm
				FROM bodb_Account.dbo.FactLADailyWinloss WITH (NOLOCK)
				WHERE rptDate BETWEEN @FDate AND @TDate
					AND SiteId IN (SELECT SiteId_DW FROM @tmpSite)
					AND ProductId IN (10001, 10004)
					AND Bettype NOT IN (901, 902, 903, 904)
					AND CurrencyId <> 20
					AND TicketStatus NOT IN (-1, 18, 9, 10, 14)
				GROUP BY rptDate, SiteId, CurrencyId, ProductId, LeagueId
					,CASE
						WHEN BetType IN (9, 29) THEN -2 -- Parlay
						WHEN SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports, Cricket
						ELSE 99 -- Other Sports
						END
			)
			INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, MemberWL, OddsSpreadAdj, Comm)
			SELECT t.rptDate, t.SiteId, t.CurrencyId, CASE WHEN t.ProductId = 10001 THEN 0 ELSE 3 END AS ProductId
				,CASE
					WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
					WHEN l.LeagueGroupId = 113 AND t.SportType = 1 THEN -14 --Saba Soc PGoal
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -5 -- Saba Basketball
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -8 -- Saba Cricket
					WHEN t.Sporttype = 1 THEN -2 -- Soccer
					WHEN t.Sporttype = 2 THEN -4 -- Basketball
					WHEN t.Sporttype = 5 THEN -6 -- Tennis
					WHEN t.Sporttype = 43 THEN -7 -- E-Sports
					WHEN t.Sporttype = -2 THEN -10 -- Parlay
					ELSE -9 -- OS
					END AS AliasProductId
				,SUM(t.MemberWinloss) AS MemberWL
				,SUM(t.AgentWinloss) AS OddsSpreadAdj -- Odds Spread Adjustment
				,SUM(t.AgentComm) AS Comm -- BA Commission
			FROM CTE_SB t
				LEFT JOIN #__SabaLeague l ON t.LeagueId = l.LeagueId
			GROUP BY t.rptDate, t.SiteId, t.CurrencyId, CASE WHEN t.ProductId = 10001 THEN 0 ELSE 3 END
				,CASE
					WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
					WHEN l.LeagueGroupId = 113 AND t.SportType = 1 THEN -14 --Saba Soc PGoal
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -5 -- Saba Basketball
					WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -8 -- Saba Cricket
					WHEN t.Sporttype = 1 THEN -2 -- Soccer
					WHEN t.Sporttype = 2 THEN -4 -- Basketball
					WHEN t.Sporttype = 5 THEN -6 -- Tennis
					WHEN t.Sporttype = 43 THEN -7 -- E-Sports
					WHEN t.Sporttype = -2 THEN -10 -- Parlay
					ELSE -9 -- OS
					END
		END

		-- CB, AG, GD, EX
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (10, 11, 15, 31))
		BEGIN
			CREATE TABLE #__BettingByProduct (rptDate DATE, LicenseeId INT, CurrencyId INT, Product3rdId INT, BetTypeGroup INT, ValidBetAmount MONEY, MemberWL MONEY, Comm MONEY)
			INSERT INTO #__BettingByProduct (rptDate, LicenseeId, CurrencyId, Product3rdId, BetTypeGroup, ValidBetAmount, MemberWL, Comm)
			SELECT rptDate, SiteId, CurrencyId, ProductId
				,BetTypeGroup	= CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END
				,ValidBetAmount	= SUM(CASE WHEN ProductId = 11 AND bettype = -1 THEN ValidBetAmount ELSE 0 END)
				,MemberWL		= SUM(CASE WHEN ProductId = 15 THEN Turnover * 0.0405 + BuyBackAmount * 0.15 ELSE MemberWL END)
				,Comm			= SUM(CASE WHEN ProductId = 31 THEN CommissionP + CommissionA ELSE 0 END)

			FROM DBLIC.bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND ProductId IN (10, 11, 15, 31)
				AND CurrencyId <> 20
				AND CustomerCategory NOT IN (27, 28)
				AND StatusId NOT IN (-1, 101, 102, 103)
				AND SiteId < 1000 -- Deposit only
			GROUP BY rptDate, SiteId, CurrencyId, ProductId, CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END

			INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, BetTypeGroup, ValidBetAmount, MemberWL, Comm)
			SELECT b.rptDate, s.SiteId_DW, b.CurrencyId, b.Product3rdId, p.AliasProductId, b.BetTypeGroup, b.ValidBetAmount, b.MemberWL, b.Comm
			FROM #__BettingByProduct b
				INNER JOIN @Products p ON b.Product3rdId = p.Product3rdId AND p.Product3rdId IN (10, 11, 15, 31)
				INNER JOIN @tmpSite s ON b.LicenseeId = s.LicenseeId

			DROP TABLE #__BettingByProduct
		END

		-- Others
		BEGIN
			SELECT @FromDateByBatch = @FDate

			WHILE @FromDateByBatch <= @TDate
			BEGIN
				SELECT @ToDateByBatch = DATEADD(DAY, 7, @FromDateByBatch)

				IF @ToDateByBatch > @TDate
					SET @ToDateByBatch = @TDate

				INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, HouseTO, Stake, HouseContribution, FullContribution, MemberTurnover)
				SELECT b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN b.Sporttype = 1 THEN -2 -- Soccer
						WHEN b.Sporttype = 2 THEN -4 -- Basketball
						WHEN b.Sporttype = 5 THEN -6 -- Tennis
						WHEN b.Sporttype = 43 THEN -7 -- E-Sports
						ELSE -9 -- OS
						END AS AliasProductId
					,CASE WHEN b.SportType IN (150,173) THEN b.SportType ELSE -1 END AS SportTypeGroup
					,bt.BetTypeGroup
					,SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR bt.bettype IN (1698, 4297, 3898) THEN 0
							WHEN bt.BetType IN (913, 914) THEN b.WinlossP + b.WinlossA
							ELSE b.WinlossP END
						) AS MemberWL
					,SUM(CASE WHEN bt.IsOnlyTO = 1 OR bt.bettype IN (1698, 4297, 3898) THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
					,SUM(b.TurnoverIBC * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS HouseTO -- VarianceVR = virtualrate/actualrate - 1
					---- HouseTO change formula, will get MemberTO * ChargeRate
					,SUM(b.Stake * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS Stake -- VarianceVR = virtualrate/actualrate - 1
					,SUM(CASE WHEN bt.bettype IN (1698, 4297, 3898) THEN  b.WinlossIBC ELSE 0 END) AS HouseContribution
					,SUM(CASE WHEN bt.bettype IN (1698, 4297, 3898) THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
					,SUM(b.Stake *  CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS MemberTurnover
				FROM bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
					INNER JOIN @tmpBetType bt ON b.BetType = bt.BetType
					LEFT JOIN #__SabaLeague s ON b.LeagueId = s.LeagueId AND bt.Product3rdId = 0
				WHERE b.rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
					AND b.CurrencyId <> 20
					AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
				GROUP BY b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN b.Sporttype = 1 THEN -2 -- Soccer
						WHEN b.Sporttype = 2 THEN -4 -- Basketball
						WHEN b.Sporttype = 5 THEN -6 -- Tennis
						WHEN b.Sporttype = 43 THEN -7 -- E-Sports
						ELSE -9 -- OS
						END
					,CASE WHEN b.SportType IN (150, 173) THEN b.SportType ELSE -1 END
					,bt.BetTypeGroup
				OPTION (RECOMPILE)

				SELECT @FromDateByBatch = DATEADD(DAY, 1, @ToDateByBatch)
			END
		END

		UPDATE v
		SET v.Product3rdId = s.Product3rdId
		FROM #tempVendorGlobalSetting v
			CROSS APPLY (SELECT TOP 1 b.Product3rdId FROM @tmpBetType b WHERE v.Bettype = b.BetType) s

		DELETE #tempVendorGlobalSetting WHERE Product3rdId IS NULL

		UPDATE v
		SET v.Bettype = -1
		FROM #tempVendorGlobalSetting v
			LEFT JOIN @tmpBetType b ON v.Bettype = b.BetTypeGroup
		WHERE b.BetTypeGroup IS NULL

		-- Process data
		CREATE TABLE #__tempResult
		(
			rptDate				DATETIME
			,CurrencyId			INT
			,PartyId			INT
			,ParentId			INT
			,Product3rdId		INT
			,AliasProductId		INT
			,SporttypeGroup		INT
			-- for Daily
			,OriginalMemberWLDaily	MONEY
			,MemberWLDaily			MONEY
			,CommDaily				MONEY
			,PayToSupplierDaily		MONEY
			,CurrencyPlayDaily		MONEY
			,HouseIncomeDaily		MONEY
			,OriginalMemberTurnoverDaily	MONEY
			,MemberTurnoverDaily			MONEY
			
			-- for Monthly
			,OriginalMemberWLMonth	MONEY
			,MemberWLMonth			MONEY
			,CommMonth				MONEY
			,PayToSupplierMonth		MONEY
			,CurrencyPlayMonth		MONEY
			,HouseIncomeMonth		MONEY
			,OriginalMemberTurnoverMonth	MONEY
			,MemberTurnoverMonth			MONEY
			
			,FullContribution	MONEY
			,JackpotPrize		MONEY
			,HouseTurnover		MONEY
			,IsApplyMinFee		BIT DEFAULT (1) -- for calculate min fee
		)

		INSERT INTO #__tempResult
		(
			rptDate
			,PartyId
			,Product3rdId
			,AliasProductId
			,SporttypeGroup
			,CurrencyId
			,ParentId
			,OriginalMemberWLDaily
			,OriginalMemberWLMonth
			,OriginalMemberTurnoverDaily
			,OriginalMemberTurnoverMonth
			,MemberWLDaily
			,MemberTurnoverDaily
			,MemberWLMonth
			,MemberTurnoverMonth
			,CommDaily
			,CommMonth
			,PayToSupplierDaily
			,PayToSupplierMonth
			,FullContribution
			,JackpotPrize
			,HouseTurnover
			,HouseIncomeDaily
			,HouseIncomeMonth
		)
		SELECT t.rptDate, l.PartyId, t.Product3rdId, t.AliasProductId, t.SportTypeGroup
			,CurrencyId	= CASE WHEN t.Product3rdId = 10 THEN t.CurrencyId END
			,ParentId	= CASE
							WHEN t.Product3rdId IN (5, 11, 34) THEN l.PartyId
							WHEN t.Product3rdId IN (10, 22, 27) THEN l.ParentId
							WHEN t.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
							WHEN t.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
							END
			,OriginalMemberWLDaily	= SUM(t.MemberWL)
			,OriginalMemberWLMonth	= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END)
			-- Licensee performance
			,OriginalMemberTurnoverDaily	= SUM(t.MemberTurnover)
			,OriginalMemberTurnoverMonth	= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberTurnover ELSE 0 END)
			,MemberWLDailyMonth		= SUM(t.MemberWL * e.Rate)
			,MemberTurnoverDaily    = SUM(t.MemberTurnover  * e.Rate)
			,MemberWLMonth			= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END * e.Rate)
			,MemberTurnoverMonth	= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberTurnover ELSE 0 END * e.Rate)
			--- End Turnover
			,CommDaily				= SUM(t.Comm * e.Rate)
			,CommMonth				= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.Comm ELSE 0 END * e.Rate)
			,PayToSupplierDaily	= SUM((t.MemberWL *
										CASE
											WHEN t.Product3rdId IN (8, 28) THEN CASE
																					WHEN t.rptDate >= '2020-07-01' THEN CASE WHEN l.PartyId IN (@BobbetId, @TianboId) THEN 0.02 ELSE 0.036 END
																					WHEN l.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03
																					ELSE 0.05 END -- KN, LT
											WHEN t.Product3rdId = 22 THEN CASE WHEN t.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
											WHEN t.Product3rdId = 27 THEN 0.065 -- VS2
											WHEN t.Product3rdId = 34 AND t.BetTypeGroup <> -1 THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(ISNULL(rd.Rate, v.ChargeRate3rd), 0) END
									+ CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END) * e.Rate)
			,PayToSupplierMonth	= SUM((t.MemberWL *
										CASE
											WHEN p.PartyId IS NULL AND (t.Product3rdId NOT IN (8, 22) OR rd.PartyId IS NULL) THEN 0
											WHEN t.Product3rdId IN (8, 28) THEN CASE
																					WHEN t.rptDate >= '2020-07-01' THEN CASE WHEN l.PartyId IN (@BobbetId, @TianboId) THEN 0.02 ELSE 0.036 END
																					WHEN l.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03
																					ELSE 0.05 END -- KN, LT
											WHEN t.Product3rdId = 22 THEN CASE WHEN t.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
											WHEN t.Product3rdId = 27 THEN 0.065 -- VS2
											WHEN t.Product3rdId = 34 AND t.BetTypeGroup <> -1 THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(rd.Rate, 0) END
									+ CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END) * e.Rate)
			,FullContribution	= SUM(CASE WHEN t.BetTypeGroup = -3 THEN t.FullContribution ELSE 0 END * e.Rate)
			,JackpotPrize		= SUM(CASE WHEN t.BetTypeGroup = -3 THEN -t.MemberWL ELSE 0 END * e.Rate)
			,HouseTurnover		= SUM(CASE 
										WHEN p.PartyId IS NULL THEN HouseTO										
										ELSE (t.Stake * ISNULL(ISNULL(lc.Rate, p.Rate),0)) 
										END * e.Rate)
			,HouseIncomeDaily	= SUM(CASE
										WHEN t.Product3rdId = 15 THEN t.MemberWL
										WHEN t.Product3rdId IN (25, 37) THEN -t.HouseWL
										WHEN p.PartyId IS NULL THEN -t.HouseWL
										WHEN t.SportTypeGroup IN (150, 173) THEN -t.MemberWL + (-(t.FullContribution - t.HouseContribution) - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END-- SBC free bets
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * e.Rate)
			,HouseIncomeMonth	= SUM(CASE
										WHEN t.Product3rdId = 15 THEN t.MemberWL
										WHEN t.Product3rdId = 37 THEN -t.HouseWL
										WHEN p.PartyId IS NULL THEN 0
										WHEN t.Product3rdId IN (25) THEN -t.HouseWL
										WHEN t.SportTypeGroup IN (150, 173) THEN -t.MemberWL + (-(t.FullContribution - t.HouseContribution) - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END-- SBC free bets
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * e.Rate)
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
			INNER JOIN @ExchangeOANDA e ON t.CurrencyId = e.ExchangeId
			LEFT JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND p.Product3rdId = t.Product3rdId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = t.BetTypeGroup)
					AND (t.BetTypeGroup <> -3)
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND p.ChargeType = 12)
						OR (t.Product3rdId = 15 AND p.ChargeType = 6)
						OR (t.Product3rdId <> 15 AND ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND p.ChargeType <> 12))
					)
			LEFT JOIN #PartyCharge3rdInfo rd ON rd.PartyId = l.PartyId AND rd.Product3rdId = t.Product3rdId AND t.rptDate BETWEEN rd.FromDate AND rd.ToDate
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND rd.ChargeType = 12)
						OR ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND rd.ChargeType <> 12)
					)
			LEFT JOIN #tempVendorGlobalSetting v ON v.Product3rdId = t.Product3rdId AND v.Bettype = t.BetTypeGroup
			
			LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		WHERE t.Product3rdId NOT IN (0, 3) OR (t.Product3rdId IN (0, 3) AND p.PartyId IS NOT NULL)
		GROUP BY t.rptDate, l.PartyId, t.Product3rdId, t.AliasProductId, t.SportTypeGroup
			,CASE WHEN t.Product3rdId = 10 THEN t.CurrencyId END
			,CASE
				WHEN t.Product3rdId IN (5, 11, 34) THEN l.PartyId
				WHEN t.Product3rdId IN (10, 22, 27) THEN l.ParentId
				WHEN t.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
				WHEN t.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
				END

		CREATE CLUSTERED INDEX CIX_Product3rdId ON #__tempResult (Product3rdId, PartyId)

		-- For special PayToSupplier
			-- 1. NG, H5
		UPDATE #__tempResult
		SET PayToSupplierDaily = -0.5 * HouseIncomeDaily, PayToSupplierMonth = -0.5 * HouseIncomeMonth
		WHERE Product3rdId = 2 -- NG, H5

			-- 2. AGC
		;WITH CTE_Sum AS
		(
			SELECT ParentId, Product3rdId
				,CASE WHEN LicenseeWLDaily <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END AS RateDaily
				,CASE WHEN LicenseeWLMonth <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END AS RateMonth
			FROM
			(
				SELECT r.ParentId, r.Product3rdId
					,-SUM(r.OriginalMemberWLDaily * CASE WHEN r.ParentId = 1 THEN e.CNY ELSE e.USD END) AS LicenseeWLDaily
					,-SUM(r.OriginalMemberWLMonth * CASE WHEN r.ParentId = 1 THEN e.CNY ELSE e.USD END) AS LicenseeWLMonth
				FROM #__tempResult r
					INNER JOIN @ExchangeOANDA e ON r.CurrencyId = e.ExchangeId
				WHERE r.Product3rdId = 10
				GROUP BY ParentId, Product3rdId
			) t
		)
		UPDATE r
		SET r.PayToSupplierDaily = r.MemberWLDaily * s.RateDaily, r.PayToSupplierMonth = r.MemberWLMonth * s.RateMonth
		FROM #__tempResult r
			INNER JOIN CTE_Sum s ON r.ParentId = s.ParentId
		WHERE r.Product3rdId = 10
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
			,Product3rdId		INT
			,IsPrimary			BIT
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
			,Product3rdId
			,IsPrimary
			,CurrencyId
			,IndividualMinFee
			,FromDate
			,ToDate
		)
		SELECT
			FeeTypeId
			,-PartyId AS GroupMinFeeId
			,PartyId
			,ProductId
			,0 AS IsPrimary
			,CurrencyId
			,FeeAmount
			,CASE WHEN @FDate > FromDate THEN @FDate ELSE FromDate END AS FromDate
			,CASE WHEN @TDate < ToDate THEN @TDate ELSE ToDate END AS ToDate
		FROM DBLIC.bodb_licensee.dbo.LA_MinFee WITH (NOLOCK)
		WHERE FeeTypeId IN (1, 2)
			AND FromDate <= @LastDate AND ToDate >= @FirstDate

		DECLARE @GroupMinFeeSetting TABLE (PartyId INT, GroupMinFeeId SMALLINT, IsPrimary BIT)
		SELECT @SQL = '	SELECT PartyId, GroupMinFeeId, IsPrimary
						FROM OPENQUERY (DBLIC, ''	SELECT TOP (1) WITH TIES a.PartyId, h.GroupMinFeeId, a.IsPrimary
													FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
														INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
													WHERE ''''' + @f_date + ''''' BETWEEN h.FromDate AND h.ToDate
													ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)'')'
		INSERT INTO @GroupMinFeeSetting (PartyId, GroupMinFeeId, IsPrimary)
		EXEC (@SQL)

		UPDATE m
		SET m.GroupMinFeeId = g.GroupMinFeeId, m.IsPrimary = g.IsPrimary, m.IndividualMinFee = 0
		FROM @MinFee m
			INNER JOIN @GroupMinFeeSetting g ON m.PartyId = g.PartyId

		UPDATE m
		SET m.IndividualMinFee = m.IndividualMinFee * e.Rate
		FROM @MinFee m
			INNER JOIN @ExchangeOANDA e ON m.CurrencyId = e.ExchangeId
		WHERE m.GroupMinFeeId < 0

		UPDATE t
		SET t.IsApplyMinFee = 0
		FROM #__tempResult t
			INNER JOIN @MinFee m ON t.PartyId = m.PartyId AND t.Product3rdId = m.Product3rdId AND t.rptDate BETWEEN m.FromDate AND m.ToDate
		WHERE m.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = (
					(
						SELECT TOP 1 m2.IndividualMinFee
						FROM @MinFee m2
						WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId AND m1.Product3rdId = m2.Product3rdId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
			,m1.WaivedFee = ISNULL(
					(
						SELECT SUM(r.HouseIncomeMonth)
						FROM #__tempResult r
						WHERE m1.PartyId = r.PartyId AND m1.Product3rdId = r.Product3rdId AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
					), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = ROUND(
								(m1.IndividualMinFee / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
								- ISNULL((
									SELECT SUM(m2.ProrateMinFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId AND m1.Product3rdId = m2.Product3rdId
									), 0)
								, 2)
			,m1.WaivedFee = ISNULL((
									SELECT SUM(m2.WaivedFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId AND m1.Product3rdId = m2.Product3rdId
									HAVING SUM(m2.WaivedFee) > 0
								), 0)
			,m1.LicenseeFee = ISNULL((
									SELECT SUM(r.HouseIncomeMonth)
									FROM #__tempResult r
									WHERE m1.PartyId = r.PartyId AND m1.Product3rdId = r.Product3rdId AND r.IsApplyMinFee = 1 AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
								), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 1

		DELETE @MinFee WHERE FeeTypeId = 2

		UPDATE @MinFee
		SET ActualFee = CASE
							WHEN LicenseeFee < ProrateMinFee THEN ProrateMinFee
							ELSE LicenseeFee END + WaivedFee

		-- Group min fee
		DECLARE @GroupMinFee TABLE
		(
			GroupMinFeeId	INT
			,Product3rdId	INT
			,CurrencyId		INT
			,GroupMinFee	MONEY DEFAULT(0)
			,HouseWL		MONEY DEFAULT(0)
			,LicenseeFee	MONEY DEFAULT(0)
			,Rebate			MONEY DEFAULT(0)
			,Discount		MONEY DEFAULT(0)
		)
		INSERT INTO @GroupMinFee (GroupMinFeeId, Product3rdId, CurrencyId, GroupMinFee)
		SELECT TOP(1) WITH TIES GroupMinFeeID, ProductId, CurrencyId, MinimumFee
		FROM DBLIC.bodb_Licensee.dbo.LA_GroupMinFeeDetail WITH (NOLOCK)
		WHERE @FDate BETWEEN FromDate AND ToDate
		ORDER BY ROW_NUMBER() OVER(PARTITION BY GroupMinFeeId ORDER BY ToDate DESC)

		UPDATE g
		SET g.GroupMinFee = g.GroupMinFee * e.Rate
		FROM @GroupMinFee g
			INNER JOIN @ExchangeOANDA e ON e.ExchangeId = g.CurrencyId

		-- HouseWL
		UPDATE g
		SET g.HouseWL = ISNULL(m.HouseWL, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(CASE WHEN m.LicenseeFee > 0 THEN m.LicenseeFee ELSE 0 END + m.WaivedFee) AS HouseWL
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.Product3rdId = m.Product3rdId
			) m
		
		-- Include left over min fee into primary licensees
		UPDATE m
		SET m.ActualFee = CASE
								WHEN g.HouseWL >= g.GroupMinFee THEN ActualFee
								WHEN m.LicenseeFee < 0 THEN g.GroupMinFee - g.HouseWL
								ELSE m.LicenseeFee + g.GroupMinFee - g.HouseWL END
		FROM @MinFee m
			INNER JOIN @GroupMinFee g ON g.GroupMinFeeId = m.GroupMinFeeId AND m.Product3rdId = g.Product3rdId
		WHERE m.IsPrimary = 1

		-- Licensee Fee & Licensee Min Fee
		UPDATE g
		SET g.LicenseeFee = ISNULL(m.ActualFee, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(m.ActualFee) AS ActualFee
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.Product3rdId = m.Product3rdId
			) m

		-- Rebate & Discount
		DECLARE @DiscountGroup TABLE (PartyId INT, Product3rdId INT, ProductCode VARCHAR(50))
		SELECT @SQL = 'SELECT PartyId, ProductId
						FROM OPENQUERY (DBLIC, ''	SELECT TOP(1) WITH TIES da.PartyId, dp.ProductId
													FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dh WITH (NOLOCK)
														INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
														INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
													WHERE dh.FromDate <= ''''' + @t_date + ''''' AND dh.ToDate >= ''''' + @f_date + '''''
													ORDER BY ROW_NUMBER() OVER(PARTITION BY da.PartyId, dp.ProductId ORDER BY dh.ToDate DESC)'')'
		INSERT INTO @DiscountGroup (PartyId, Product3rdId)
		EXEC (@SQL)

		UPDATE d
		SET d.ProductCode = p.ProductCode
		FROM @DiscountGroup d
			INNER JOIN @Products p ON d.Product3rdId = p.Product3rdId

		DELETE @DiscountGroup WHERE ProductCode IS NULL

		;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM @DiscountGroup)
		SELECT @Discount_PartyIds = COALESCE(@Discount_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

		;WITH CTE_ProductCode AS (SELECT DISTINCT ProductCode FROM @DiscountGroup)
		SELECT @Discount_ProductCodes = COALESCE(@Discount_ProductCodes + ',', '') + ProductCode FROM CTE_ProductCode

		DECLARE @DiscountData TABLE
		(
			PartyId				INT
			,Product3rdId		INT
			,Winloss			MONEY
			,Fee				MONEY
			,NegativeFee		MONEY
			,Minfee				MONEY
			,IsChargedByMinFee	BIT
			,Discount			MONEY
			,DiscountRate		MONEY
			,DiscountRemark		NVARCHAR(MAX)
			,Rebate				MONEY
			,RebateRate			MONEY
			,RebateRemark		VARCHAR(MAX)

		)

		INSERT INTO @DiscountData
		(
			PartyId
			,Product3rdId
			,Winloss
			,Fee
			,NegativeFee
			,Minfee
			,IsChargedByMinFee
			,Discount
			,DiscountRate
			,DiscountRemark
			,Rebate
			,RebateRate
			,RebateRemark
		)
		EXEC DBLIC.bodb_licensee.dbo.LA_AmountToCompanySel
			@FromDate		= @FDate
			,@ToDate		= @TDate
			,@PartyIds		= @Discount_PartyIds
			,@ProductCodes	= @Discount_ProductCodes
			,@BaseCurrency	= @BaseCurrencyName
			,@CurrencyId	= 0

		DECLARE @tmpResult TABLE
		(
			PartyId			INT
			,Product3rdId	INT
			,AliasProductId	INT
			,GroupMinFeeId	INT
			,IsPrimaryFee	BIT DEFAULT(0)
			,HouseTurnover	MONEY DEFAULT(0)
			,LicenseeWL		MONEY DEFAULT(0)
			,HouseIncome	MONEY DEFAULT(0)
			,AComm			MONEY DEFAULT(0)
			,LicenseeMinFee MONEY DEFAULT(0)
			,LicenseeFee	MONEY DEFAULT(0)
			,Rebate			MONEY DEFAULT(0)
			,Discount		MONEY DEFAULT(0)
			,MemberTurnover MONEY DEFAULT(0)
			,MemberWL		MONEY DEFAULT(0)
		)
		;WITH CTE_tempResult AS (
			SELECT PartyId, Product3rdId, CASE WHEN Product3rdId = 0 AND AliasProductId <> -14  THEN -2 ELSE AliasProductId END AS AliasProductId
				,HouseTurnover	= SUM(HouseTurnover)
				,LicenseeWL		= SUM(CASE WHEN SporttypeGroup IN (150, 173) THEN 0 ELSE -MemberWLMonth END)
				,HouseIncome	= SUM(HouseIncomeMonth)
				,AComm			= SUM(CommMonth)
				,MemberTurnover = SUM(MemberTurnoverDaily)
				,MemberWL		= SUM(MemberWLDaily)
			FROM #__tempResult
			GROUP BY PartyId, Product3rdId, CASE WHEN Product3rdId = 0  AND AliasProductId <> -14 THEN -2 ELSE AliasProductId END
		), CTE_Result AS (
			SELECT
				PartyId = ISNULL(t.PartyId, m.PartyId)
				,Product3rdId = ISNULL(t.Product3rdId, m.Product3rdId)
				,AliasProductId = ISNULL(t.AliasProductId, -2)
				,GroupMinFeeId = ISNULL(m.GroupMinFeeId, -t.PartyId)
				,HouseTurnover = ISNULL(t.HouseTurnover, 0)
				,LicenseeWL = ISNULL(t.LicenseeWL, 0)
				,HouseIncome = ISNULL(t.HouseIncome, 0)
				,AComm = ISNULL(t.AComm, 0)
				,MemberTurnover = ISNULL(t.MemberTurnover, 0)
				,MemberWL = ISNULL(t.MemberWL,0)
			FROM CTE_tempResult t
				FULL OUTER JOIN @MinFee m ON t.PartyId = m.PartyId AND t.Product3rdId = m.Product3rdId			
		)
		INSERT INTO @tmpResult (PartyId, Product3rdId, GroupMinFeeId, AliasProductId, HouseTurnover, LicenseeWL, HouseIncome, AComm, MemberTurnover, MemberWL)
		SELECT r.PartyId, r.Product3rdId, r.GroupMinFeeId, r.AliasProductId, r.HouseTurnover, r.LicenseeWL, r.HouseIncome, r.AComm, r.MemberTurnover, r.MemberWL
		FROM CTE_Result r
			INNER JOIN (SELECT DISTINCT PartyId, Product3rdId FROM #PartyChargeInfo) p ON p.PartyId = r.PartyId AND p.Product3rdId = r.Product3rdId

		DELETE @tmpResult WHERE GroupMinFeeId IS NULL

		UPDATE s
		SET s.IsPrimaryFee		= m.IsPrimary
			,s.HouseIncome		= m.LicenseeFee
			,s.LicenseeMinFee	= CASE
									WHEN m.PartyId IS NULL THEN 0
									WHEN m.LicenseeFee + m.WaivedFee = m.ActualFee THEN 0
									ELSE m.ActualFee END
			,s.LicenseeFee		= CASE
									WHEN m.PartyId IS NULL THEN s.HouseIncome
									WHEN m.LicenseeFee + m.WaivedFee = m.ActualFee THEN m.ActualFee
									ELSE 0 END
			,s.Rebate			= ISNULL(d.Rebate, 0)
			,s.Discount			= ISNULL(d.Discount, 0)
		FROM @tmpResult s
			LEFT JOIN @MinFee m ON m.PartyId = s.PartyId AND m.Product3rdId = s.Product3rdId
			LEFT JOIN @DiscountData d ON d.PartyId = s.PartyId AND d.Product3rdId = s.Product3rdId

		UPDATE g
		SET g.Rebate = ISNULL(d.Rebate, 0), g.Discount = ISNULL(d.Discount, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(s.Rebate) AS Rebate, SUM(s.Discount) AS Discount
				FROM @tmpResult s
				WHERE s.GroupMinFeeId = g.GroupMinFeeId AND s.Product3rdId = g.Product3rdId
			) d

		UPDATE s
		SET s.LicenseeFee = CASE
								WHEN s.Discount = 0 THEN 0
								ELSE s.LicenseeFee + (g.GroupMinFee - (g.LicenseeFee - g.Discount)) END
			,s.LicenseeMinFee = CASE
								WHEN s.Discount <> 0 THEN 0
								ELSE s.LicenseeMinFee + (g.GroupMinFee - (g.LicenseeFee - g.Discount)) END
		FROM @tmpResult s
			INNER JOIN @GroupMinFee g ON s.GroupMinFeeId = g.GroupMinFeeId
		WHERE s.GroupMinFeeId > 0
			AND (g.LicenseeFee - g.Discount) < g.GroupMinFee
			AND s.IsPrimaryFee = 1

		-- Check LicenseeWL > 0
			-- NG include all sports as H5, H5LG
		IF EXISTS (SELECT 1 FROM @tmpResult WHERE Product3rdId = 2)
			UPDATE t
			SET t.LicenseeFee = 0
			FROM @tmpResult t
				INNER JOIN (SELECT PartyId FROM @tmpResult WHERE Product3rdId = 2 GROUP BY PartyId HAVING SUM(LicenseeFee) < 0) r ON t.PartyId = r.PartyId
			WHERE t.Product3rdId = 2

		/*
			GET 9w licensee list
		*/
		--DECLARE @9wLicenseeList TABLE (PartyId INT)
		--INSERT INTO @9wLicenseeList (PartyId)
		--SELECT PartyId FROM OPENQUERY(DBLIC, 'SELECT PartyId FROM bodb_licensee.dbo.LA_f_JVPartyListSel()')
		
		--UPDATE r
		--SET r.HouseIncome = CASE WHEN r.HouseIncome > 0 OR r.Product3rdId = 3 THEN r.HouseIncome ELSE 0 END
		--	,r.LicenseeFee = CASE
		--				WHEN r.Product3rdId = 25 THEN LicenseeFee
		--				WHEN r.Product3rdId IN (42, 66) THEN CASE WHEN r.LicenseeWL > 0 THEN r.LicenseeFee ELSE 0 END
		--				WHEN r.LicenseeFee > 0 THEN r.LicenseeFee ELSE 0 END
		--FROM @tmpResult r
		--WHERE r.Product3rdId <> 2
		--	AND (
		--		r.Product3rdId = 25 -- Cashout
		--		OR r.PartyId NOT IN (SELECT p.PartyId FROM @9wLicenseeList p)
		--	)

		UPDATE r
		SET r.HouseIncome = CASE WHEN r.HouseIncome > 0 OR r.Product3rdId = 3 THEN r.HouseIncome ELSE 0 END
			,r.LicenseeFee = CASE
						WHEN r.Product3rdId = 25 THEN LicenseeFee
						WHEN r.Product3rdId IN (42, 66) THEN CASE WHEN r.LicenseeWL > 0 THEN r.LicenseeFee ELSE 0 END
						WHEN r.LicenseeFee > 0 THEN r.LicenseeFee ELSE 0 END
		FROM @tmpResult r
		WHERE r.Product3rdId <> 2
			AND (
				r.Product3rdId = 25 -- Cashout
				OR r.PartyId NOT IN (
					SELECT p.PartyId FROM DBLIC.bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)
					WHERE p.PartyName IN ('9wickets', '9Wsports', '9w')
				)
			)
	END

	-- Calculate result
	DELETE @Products WHERE Product3rdId = 3 -- BA

	DECLARE @BAComm MONEY, @BAWinloss MONEY
    SELECT  @BAComm = -SUM(AComm), @BAWinloss = SUM(HouseIncome) FROM @tmpResult WHERE Product3rdId = 3
	SELECT  @BAComm = ISNULL(@BAComm, 0), @BAWinloss = ISNULL(@BAWinloss, 0)

	DELETE @tmpResult WHERE Product3rdId = 3
	UPDATE #__tempResult SET Product3rdId = 0 WHERE Product3rdId = 3

	CREATE TABLE #Result
	(
		rptDate				VARCHAR(10)
		,Product3rdId		INT
		,AliasProductId		INT
		,BAComm				MONEY
		,PayToSupplier		MONEY
		,FullContribution	MONEY
		,JackpotPrize		MONEY
		,HouseTurnover		MONEY
		,HouseIncome		MONEY
		,MinFee				MONEY
		,Discount			MONEY
		,Rebate				MONEY
		,MemberTurnover		MONEY
		,MemberWL           MONEY
	)

	-- Daily
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, BAComm, PayToSupplier, FullContribution, JackpotPrize, HouseTurnover, HouseIncome, MemberTurnover, MemberWL)
	SELECT CONVERT(VARCHAR(2), rptDate, 106), Product3rdId, AliasProductId, -SUM(CommDaily), SUM(PayToSupplierDaily), SUM(FullContribution), SUM(JackpotPrize), SUM(HouseTurnover), SUM(HouseIncomeDaily), SUM(MemberTurnoverDaily), SUM(MemberWLDaily)
	FROM #__tempResult
	GROUP BY CONVERT(VARCHAR(2), rptDate, 106), Product3rdId, AliasProductId

	-- MTD (month-to-date)
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, BAComm, PayToSupplier, FullContribution, JackpotPrize, HouseTurnover, HouseIncome, MemberTurnover, MemberWL)
	SELECT 'MTD', Product3rdId, AliasProductId, SUM(BAComm), SUM(PayToSupplier), SUM(FullContribution), SUM(JackpotPrize), SUM(HouseTurnover), SUM(HouseIncome), SUM(MemberTurnover), SUM(MemberWL)
	FROM #Result
	GROUP BY Product3rdId, AliasProductId

	-- Monthly
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, HouseTurnover, HouseIncome, MinFee, Discount, Rebate, MemberTurnover, MemberWL)
	SELECT 'Monthly', Product3rdId, AliasProductId, SUM(HouseTurnover), SUM(LicenseeFee), SUM(LicenseeMinFee), SUM(Discount), SUM(Rebate), SUM(MemberTurnover), SUM(MemberWL)
	FROM @tmpResult
	GROUP BY Product3rdId, AliasProductId

	-- Update full range
	;WITH CTE_HouseTO AS
	(
		SELECT Product3rdId, AliasProductId, HouseTurnover FROM #Result WHERE rptDate = 'MTD'
	)
	MERGE #Result AS s
	USING CTE_HouseTO AS t ON s.Product3rdId = t.Product3rdId AND s.AliasProductId = t.AliasProductId AND s.rptDate = 'Monthly'
	WHEN MATCHED THEN UPDATE
		SET s.HouseTurnover = t.HouseTurnover
	WHEN NOT MATCHED THEN INSERT
		(rptDate, Product3rdId, AliasProductId, HouseTurnover)
		VALUES
		('Monthly', Product3rdId, AliasProductId, HouseTurnover);
	
	UPDATE #Result SET HouseIncome = HouseIncome + @BAWinloss, BAComm = @BAComm WHERE Product3rdId = 0 AND AliasProductId = -2 AND rptDate = 'Monthly'

		-- 1.1 Pay to supplier Base on MemberWL < 0
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(r.PayToSupplier) AS PayToSupplier
			FROM (
				SELECT SUM(t.PayToSupplierMonth) AS PayToSupplier
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId AND t.AliasProductId = r.AliasProductId
				GROUP BY t.ParentId
				HAVING SUM(t.MemberWLMonth) < 0
			) r
		) t
	WHERE r.Product3rdId IN (5, 10, 11, 22, 27)
		AND rptDate = 'Monthly'
		
		-- 1.2 Pay to supplier month
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.PayToSupplierMonth) AS PayToSupplier
			FROM #__tempResult t
			WHERE t.Product3rdId = r.Product3rdId AND t.AliasProductId = r.AliasProductId
		) t
	WHERE r.Product3rdId NOT IN (5, 10, 11, 22, 27)
		AND rptDate = 'Monthly'

		-- 1.3 House Income = sum up Total daily
	UPDATE r
	SET r.HouseIncome = ISNULL(m.HouseIncome, 0)
	FROM #Result r
		INNER JOIN #Result m ON m.Product3rdId = r.Product3rdId AND m.AliasProductId = r.AliasProductId AND r.rptDate = 'Monthly' AND m.rptDate = 'MTD'
	WHERE r.Product3rdId IN (15, 37)

		-- 1.4 FullContribution, JackpotPrize
	UPDATE r
	SET r.FullContribution = ISNULL(m.FullContribution, 0), r.JackpotPrize = ISNULL(m.JackpotPrize, 0)
	FROM #Result r
		INNER JOIN #Result m ON m.Product3rdId = r.Product3rdId AND m.AliasProductId = r.AliasProductId AND r.rptDate = 'Monthly' AND m.rptDate = 'MTD'
	WHERE r.Product3rdId IN (32, 42, 66)

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

	DECLARE @SQL_licperf VARCHAR(MAX) = ''

	IF @IsLicperf = 1
	BEGIN

	 INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, MemberWL, MemberTurnover)
		 SELECT rptDate, Product3rdId, -AliasProductId, JackpotPrize , 0 FROM #Result 
		 WHERE Product3rdId IN (32,42,66)

		SET @SQL_licperf = '
			(
				SELECT  isDePosit, OrderByProduct, OrderByFigure +1 AS OrderByFigure, ProductID, CASE WHEN ProductPrefix IN (''PP-JP'',''SBC-JP'',''VGA-JP'') THEN -AliasProductID ELSE AliasProductID END AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName  
						,u.Figure, u.SubFigure, u.isTest, u.isEnable, u.EndOfSupportDate, u.LogicCode, u.LogicDescription 
				FROM 
				(
					SELECT	isDePosit, 
							OrderByProduct, 
							MAX(OrderByFigure) OrderByFigure, 
							ProductID, 
							AliasProductID, 
							ProductPrefix, 
							ProductCategory, 
							ProductGroup, 
							ProductName, 
							ProductShortName  
					FROM		bodb_Account.dbo.HNISettings s WITH (NOLOCK) WHERE isDeposit = 1 and LogicCode = 2
					GROUP BY	isDePosit, OrderByProduct,  ProductID,  AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName,  ProductShortName  
				)t 
				CROSS APPLY (	SELECT ''Licensee Turnover'' AS Figure, ''Licensee Turnover'' AS SubFigure, 0 AS isTest, 1 AS isEnable, NULL AS EndOfSupportDate, 2 AS LogicCode, '''' AS LogicDescription
								UNION ALL
								SELECT ''Licensee Winloss'' AS Figure, ''Licensee Winloss'' AS SubFigure, 0 AS isTest, 1 AS isEnable, NULL AS EndOfSupportDate, 2 AS LogicCode, '''' AS LogicDescription
							)  AS u
				UNION ALL
				SELECT	s.isDePosit, s.OrderByProduct, s.OrderByFigure, s.ProductID, s.AliasProductID, s.ProductPrefix, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName  
						,s.Figure, s.SubFigure, s.isTest, s.isEnable, s.EndOfSupportDate, s.LogicCode, s.LogicDescription 	  
				FROM	bodb_Account.dbo.HNISettings s WITH (NOLOCK) WHERE isDeposit = 1 and LogicCode = 2
			) s
		'
	END

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT Product3rdId, AliasProductId, Figure, SubFigure, ISNULL(Monthly, 0) AS Monthly, MTD, ' + @DateList + '
		FROM (
			SELECT r.Product3rdId, r.AliasProductId, ISNULL(f.Value, 0) AS Value, f.Figure, f.SubFigure, r.rptDate
			FROM #Result r
			CROSS APPLY (
				SELECT BAComm AS Value, ''BA Commission'' AS Figure, ''BA Commission'' AS SubFigure
				UNION ALL SELECT FullContribution, ''Contribution Amount'', ''Contribution Amount''
				UNION ALL SELECT HouseTurnover, ''House TurnOver'', ''House TurnOver''
				UNION ALL SELECT JackpotPrize, ''Jackpot Prize'', ''Jackpot Prize''
				UNION ALL SELECT HouseIncome, ''Licensee House Income'', ''Licensee House Income''
				UNION ALL SELECT MinFee, ''Licensing Minimum Fee'', ''Licensing Minimum Fee''
				UNION ALL SELECT PayToSupplier, ''Pay to supplier'', ''Pay to supplier''
				UNION ALL SELECT -ISNULL(Rebate, 0), ''Rebate & Discount'', ''Rebate''
				UNION ALL SELECT -ISNULL(Discount, 0), ''Rebate & Discount'', ''Discount''
				'
				+ CASE WHEN @IsLicperf = 1 THEN 
				'
				UNION ALL SELECT MemberTurnover, ''Licensee Turnover'', ''Licensee Turnover''
				UNION ALL SELECT -MemberWL, ''Licensee Winloss'', ''Licensee Winloss''
				'
				ELSE '' END
				+ '
			) f
		) t
		PIVOT (
			MAX(Value)
			FOR rptDate IN (Monthly, MTD, ' + @DateList + ')
		) p
	)
	SELECT DISTINCT s.isDeposit, s.OrderByProduct, s.OrderByFigure, ''Licensee'' AS SiteGroup, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName, s.Figure, s.SubFigure, r.Monthly, r.MTD, ' + @DateList + '
	FROM '+ CASE WHEN @IsLicperf = 1 THEN @SQL_licperf ELSE ' bodb_Account.dbo.HNISettings s WITH (NOLOCK) '  END + '
		LEFT JOIN CTE_Result r ON r.AliasProductId = s.AliasProductId AND r.Figure = s.Figure AND r.SubFigure = ISNULL(s.SubFigure, '''')
	WHERE s.isDeposit = 1 AND s.LogicCode = 2
		AND (
				s.EndOfSupportDate IS NULL AND s.isEnable = 1
				OR s.EndOfSupportDate >= ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''
		)
		AND (
			''' + @ProductList + ''' = ''all''
			OR s.ProductId = 1 AND '',' + @ProductList + ','' LIKE ''%,SB,%''
			OR '',' + @ProductList + ','' LIKE ''%,'' + s.ProductPrefix + '',%''
		)
		AND s.IsTest <= ' + CONVERT(VARCHAR(1), @IsTest) + '
	ORDER BY s.OrderByProduct, s.OrderByFigure'

	EXEC (@SQL)
	
	DROP TABLE #__tempData
	DROP TABLE #__tempResult
	DROP TABLE #AllLicensees
	DROP TABLE #Licensees
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #PartyChargeInfo
	DROP TABLE #tempVendorGlobalSetting
	DROP TABLE #__SabaLeague
	DROP TABLE #Result
END

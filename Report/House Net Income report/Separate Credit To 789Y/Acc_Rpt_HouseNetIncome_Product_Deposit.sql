/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Product_Deposit]
	@FromDate       DATE
   ,@ToDate         DATE
   ,@ProductList    VARCHAR(MAX) = ''
AS

/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
    DB:			DB: DBEXT/bodb02 
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200224@Kean - Add SG product - #123734
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200422@Kean: House Net Income - Integrate Sexy Gaming product (#132792)
		- 20200422@Kean: House Net Income - Integrate Saba.Club product (#132791)
		- 20200521@Ned.Le: Re-Integrate Fishing World product for letstalk (#134533)
		- 20200813@Kean - DHWL Email/Letstalk - Change Product Name and Margin Report Format. (#139537)
		- 20200811@Kean - Email/Letstalk Reports - Integrate PG Soft (#137764)
		- 20200827@Kean - Email/Letstalk Reports - Integrate 10 New BluePrint Games (#140459)
		- 20200916@Roy: Email/Letstalk Reports - Integrate Joker Gaming (#131602)
		- 20200916@Roy: Email/Letstalk Reports - Integrate WM Live Casino (#131593)
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
		- 20201023@Percy: Change 3rd rate of Keno, Lottery, Table Game [RedmineID: #143589]
	
	EXEC [Acc_Rpt_HouseNetIncome_Product_Deposit] '20180601', '20180619'
  
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductCodes VARCHAR(MAX), @ProductCodesGMT VARCHAR(MAX)

	-- Get list of product
	BEGIN
		IF ISNULL(@ProductList, '') = ''
			SELECT @ProductList = 'AGC,CB,CC,CO,EX,LT,PP,SPR,VS2,AB,CS,GD,KN,VB,NG,H5,SB,VS,SG,VRG,SAG,I4D,TG,SXG,SBC,FW,PP-JP,PGS,WM,JK'
			-- remove BT

		SELECT @ProductList = ',' + @ProductList + ','
		SELECT @ProductList = REPLACE(REPLACE(REPLACE(@ProductList, ',SB,', ',SB,BA,'), ',EX,', ',BX,'), ',SP,', ',SPR,')

		DECLARE @Products TABLE (OrderId INT, SubOrder INT, ProductId INT, Product3rdId INT, SporttypeGroup INT DEFAULT (-1), ProductCode VARCHAR(200), SubProductCode VARCHAR(10))
		INSERT INTO @Products (OrderId, ProductCode)
		SELECT [rank] * 100, val FROM dbo.strSplit(@ProductList, ',') WHERE LEN(val) > 0

		UPDATE t
		SET t.ProductId = CASE WHEN t.ProductCode = 'SB' THEN 1 WHEN t.ProductCode = 'BA' THEN 0 WHEN t.ProductCode = 'BT' THEN -1 ELSE p.ProductId END
			,t.Product3rdId = CASE WHEN t.ProductCode = 'SB' THEN 0 ELSE p3.ProductId END
			,t.SubProductCode = CASE WHEN t.ProductCode IN ('NG', 'PP') THEN t.ProductCode END
		FROM @Products t
			LEFT JOIN bodb_Licensee.dbo.Product3rd p3 WITH (NOLOCK) ON t.ProductCode = p3.ProductPrefix
			LEFT JOIN dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = p3.ProductPrefix

		IF ',' + @ProductList + ',' LIKE '%,H5,%'
			UPDATE @Products SET Product3rdId = 2, ProductId = 3, ProductCode = 'NG', SubProductCode = 'H5'
			WHERE ProductCode = 'H5'

		IF ',' + @ProductList + ',' LIKE '%,PP-JP,%'
			UPDATE @Products SET Product3rdId = 32, ProductId = 32, ProductCode = 'PP', SubProductCode = 'PP-JP'
			WHERE ProductCode = 'PP-JP'

		UPDATE @Products SET Product3rdId = -999, ProductId = -999 WHERE ProductId IS NULL

		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode
		FROM (SELECT ProductCode FROM @Products WHERE ProductCode IS NOT NULL) t
	END

	-- Get licensee charge rate
	BEGIN
		-- All licensees
		CREATE TABLE #AllLicensees (LicenseeId INT, PartyId INT, ParentId INT)
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
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
		WHERE RowNum = 1

		-- Licensees by product
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT, ParentId INT)
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		SELECT DISTINCT p.OldRefId, p.PartyId, ci.ToParty
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
		WHERE p.PartyType = 1
			AND pd.IsDeposit = 1
			AND ci.ToParty IN (1, 9, 11, 98)
			AND EXISTS (SELECT 1 FROM @Products pr WHERE ci.ProductId = pr.Product3rdId)
			AND (
				(ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
			)

		-- Get charge rate
		DECLARE @PartyIDs VARCHAR(1000)
		SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees
		
		CREATE TABLE #PartyChargeInfo
		(
			ChargeId		INT
			,PartyId		INT
			,LicenseeId		INT
			,ParentId		INT
			,Product3rdId	INT
			,Rate			MONEY
			,FromDate		DATE
			,ToDate			DATE
			,Bettype		INT
			,ChargeType		INT
		)
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
		SELECT ci.ChargeId, ci.PartyId, ci.LicenseeId, p.ParentId, ci.ProductId, ci.DI_Rate, ci.FromDate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype), ci.ChargeType
		FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductCodes, 'OA', 1) ci
			INNER JOIN #Licensees p ON ci.PartyID = p.PartyID
			LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE
			(
				ci.ChargeType = 1
				OR ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11 -- GD
				OR ci.ChargeType = 12 AND ci.ProductId = 39 -- SAG
			)
			AND ci.DI_Rate > 0

		CREATE TABLE #PartyCharge3rdInfo
		(
			LicenseeId		INT
			,Product3rdId	INT
			,ChargeType		INT
			,Rate			MONEY
			,FromDate		DATE
			,ToDate			DATE
		)

		-- Licensee to 3rd
		INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
		SELECT DISTINCT p.LicenseeId, ci.ProductId, ci.ChargeType, ci.DI_Rate, ci.FromDate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductCodes, 'OA') ci
			INNER JOIN #PartyChargeInfo p ON p.PartyId = ci.PartyId AND ci.ProductId = p.Product3rdId
		WHERE
			(
				ci.ChargeType = 1
				OR (ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11) -- GD
			)
			AND ci.ProductId NOT IN (10) -- AGC

		-- OW to 3rd
		INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
		SELECT DISTINCT p.LicenseeId, ci.ProductId, ci.ChargeType, ci.DI_Rate, ci.FromDate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, @ProductCodes, 'OA') ci
			INNER JOIN #PartyChargeInfo p ON p.ParentId = ci.PartyId AND ci.ProductId = p.Product3rdId
		WHERE
			(
				ci.ChargeType = 1
				OR (ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11) -- GD
			)
			AND ci.ProductId NOT IN (10) -- AGC
			AND NOT EXISTS (SELECT 1 FROM #PartyCharge3rdInfo rd WHERE p.LicenseeId = rd.LicenseeId AND ci.ProductId = rd.Product3rdId)

		-- Get default setting 3rd
		BEGIN
			CREATE TABLE #tempVendorGlobalSetting (ProductId INT, Bettype INT, ChargeRate3rd DECIMAL(19, 8))
			INSERT INTO #tempVendorGlobalSetting (Bettype, ChargeRate3rd)
			SELECT Bettype, NumberValue
			FROM DBCUST.CustDB.dbo.VendorGlobalSetting WITH (NOLOCK)
			WHERE VName LIKE '3rdCashWLShareRate%'
		END

		-- Special products
			-- Metric Gaming
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
		BEGIN
			INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
			SELECT ChargeId, PartyId, LicenseeId, ParentId, -4, Rate, FromDate, ToDate, -1, ChargeType
			FROM #PartyChargeInfo
			WHERE Product3rdId = 0

			INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
			SELECT LicenseeId, -4, ChargeType, Rate, FromDate, ToDate
			FROM #PartyCharge3rdInfo
			WHERE Product3rdId = 0
		END
			-- H5
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'H5')
		BEGIN
			IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'NG')
			BEGIN
				INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
				SELECT ChargeId, PartyId, LicenseeId, ParentId, -2, Rate, FromDate, ToDate, -1, ChargeType
				FROM #PartyChargeInfo
				WHERE Product3rdId = 2

				INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
				SELECT LicenseeId, -2, ChargeType, Rate, FromDate, ToDate
				FROM #PartyCharge3rdInfo
				WHERE Product3rdId = 2
			END
			ELSE
			BEGIN
				UPDATE #PartyChargeInfo SET Product3rdId = -2, Bettype = -1 WHERE Product3rdId = 2
				UPDATE #PartyCharge3rdInfo SET Product3rdId = -2 WHERE Product3rdId = 2
			END
		END

			-- PP-JP
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 32 AND SubProductCode = 'PP-JP')
		BEGIN
			IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 32 AND SubProductCode = 'PP')
			BEGIN
				INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
				SELECT ChargeId, PartyId, LicenseeId, ParentId, -3, Rate, FromDate, ToDate, -1, ChargeType
				FROM #PartyChargeInfo
				WHERE Product3rdId = 32

				INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
				SELECT LicenseeId, -3, ChargeType, Rate, FromDate, ToDate
				FROM #PartyCharge3rdInfo
				WHERE Product3rdId = 32
			END
			ELSE
			BEGIN
				UPDATE #PartyChargeInfo SET Product3rdId = -3, Bettype = -1 WHERE Product3rdId = 32
				UPDATE #PartyCharge3rdInfo SET Product3rdId = -3 WHERE Product3rdId = 32
			END
		END

			-- Update charge rate for Keno, Lottery, Table Game
		DECLARE @tmp_PartyCharge3rdInfo TABLE (LicenseeId INT, Product3rdId INT, ChargeType INT, Rate MONEY, FromDate DATE, ToDate DATE)
		DECLARE @tmp_Licensee TABLE (LicenseeId INT)

		IF EXISTS (SELECT 1 FROM #PartyCharge3rdInfo WHERE Product3rdId IN (8, 28, 40) AND ToDate >= '2020-07-01')
		BEGIN
			INSERT INTO @tmp_Licensee (LicenseeId)
			SELECT LicenseeId FROM bodb_Licensee.dbo.Licensees WITH (NOLOCK)
			WHERE LicenseeName IN ('Bobbet', 'Tianbo')

			INSERT INTO @tmp_PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
			SELECT p.LicenseeId, p.Product3rdId, p.ChargeType, r.Rate
				,CASE WHEN p.FromDate > r.FromDate THEN p.FromDate ELSE r.FromDate END
				,CASE WHEN p.ToDate < r.ToDate THEN p.ToDate ELSE r.ToDate END
			FROM #PartyCharge3rdInfo p
				CROSS APPLY (
					SELECT p.FromDate, CONVERT(DATE, '2020-06-30') AS ToDate, p.Rate
					WHERE FromDate <= '2020-06-30'
					UNION ALL
					SELECT CONVERT(DATE, '2020-07-01') AS FromDate, p.ToDate, 0.02 AS Rate
					WHERE p.LicenseeId IN (SELECT l.LicenseeId FROM @tmp_Licensee l)
					UNION ALL
					SELECT CONVERT(DATE, '2020-07-01') AS FromDate, p.ToDate, 0.036 AS Rate
					WHERE p.LicenseeId NOT IN (SELECT l.LicenseeId FROM @tmp_Licensee l)
				) r
			WHERE p.Product3rdId IN (8, 28, 40) AND p.ToDate >= '2020-07-01'

			DELETE #PartyCharge3rdInfo WHERE Product3rdId IN (8, 28, 40) AND ToDate >= '2020-07-01'

			INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
			SELECT LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate FROM @tmp_PartyCharge3rdInfo
		END

		DROP TABLE #Licensees
	END

	-- Get exchange rate
	BEGIN
		CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeId INT, Rate FLOAT)
		INSERT INTO #Exchange(ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @FDate AND @TDate

		CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')

		-- CNY
		UPDATE oa
		SET oa.CNY = e.BaseCurrencyRate
		FROM #ExchangeOANDA oa
			INNER JOIN dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'CNY') e ON oa.ExchangeDate = e.ExchangeDate AND oa.ExchangeId = e.ExchangeId

		-- USD
		UPDATE oa
		SET oa.USD = e.BaseCurrencyRate
		FROM #ExchangeOANDA oa
			INNER JOIN dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'USD') e ON oa.ExchangeDate = e.ExchangeDate AND oa.ExchangeId = e.ExchangeId
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData
		(
			rptDate				DATE
			,LicenseeId			INT
			,CurrencyId			INT
			,ProductId			INT
			,SportTypeGroup		INT
			,BetTypeGroup		INT
			,ValidBetAmount		MONEY DEFAULT(0) -- GD
			,MemberWL			MONEY DEFAULT(0) -- BT & CO: include AWinloss, PP: exclude LicenseeContribution
			,HouseWL			MONEY DEFAULT(0)
			,Comm				MONEY DEFAULT(0) -- SB: AComm, Exchange: AComm + PComm
			,HouseContribution	MONEY DEFAULT(0) -- FullContribution - LicenseeContribution
			,FullContribution	MONEY DEFAULT(0)
		)

		-- Get data from DW: SB, BA
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (0, 3))
		BEGIN
			-- Mapping site
			CREATE TABLE #__tempSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
			INSERT INTO #__tempSite (SiteId_DW, SiteName)
			SELECT SiteId, RTRIM(LTRIM(Site)) FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE IsDeposit = 1
			
			UPDATE s
			SET s.LicenseeId = l.LicenseeId
			FROM #__tempSite s
				INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(l.LicenseeName))
			
			-- Saba League
			CREATE TABLE #__SabaLeague (LeagueId INT, LeagueGroupId INT)
			INSERT INTO #__SabaLeague (LeagueId, LeagueGroupId)
			SELECT LeagueId, LeagueGroupId FROM dbo.League WITH (NOLOCK) WHERE sporttype IN (1, 2, 50) AND LeagueGroupId IN (42, 74, 108)

			CREATE TABLE #__tempSB (rptDate DATE, SiteId INT, CurrencyId INT, ProductId INT, LeagueId INT, Sporttype INT, MemberWL MONEY, AComm MONEY)
			INSERT INTO #__tempSB (rptDate, SiteId, CurrencyId, ProductId, LeagueId, Sporttype, MemberWL, AComm)
			SELECT f.rptDate, f.SiteId, f.CurrencyId, f.ProductId, f.LeagueId
				,CASE
					WHEN f.BetType IN (9, 29) THEN -2 -- Parlay
					WHEN f.SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
					ELSE 99 -- Other Sports
					END AS Sporttype
				,SUM(f.MemberWinloss) AS MemberWL
				,SUM(f.AgentComm) AS AComm
			FROM DBWH.bodb_Account.dbo.FactLADailyWinloss f WITH (NOLOCK)
			WHERE f.rptDate BETWEEN @FDate AND @TDate
				AND f.SiteId NOT IN(-2, -4)
				AND f.ProductId IN (10001, 10004)
				AND f.Bettype NOT IN (901, 902, 903, 904)
				AND f.CurrencyId <> 20
				AND f.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			GROUP BY f.rptDate, f.SiteId, f.CurrencyId, f.ProductId, f.LeagueId
				,CASE
					WHEN f.BetType IN (9, 29) THEN -2 -- Parlay
					WHEN f.SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
					ELSE 99 -- Other Sports
					END
			OPTION (RECOMPILE)

			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SporttypeGroup, BettypeGroup, MemberWL, Comm)
			SELECT t.rptDate, s.LicenseeId, t.CurrencyId
				,CASE
					WHEN t.ProductId = 10001 THEN 1 -- SB
					ELSE 0 -- BA
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
				,SUM(t.AComm) AS AComm
			FROM #__tempSB t
				INNER JOIN #__tempSite s ON t.SiteId = s.SiteId_DW
				LEFT JOIN #__SabaLeague l ON t.LeagueId = l.LeagueId
			GROUP BY t.rptDate, s.LicenseeId, t.CurrencyId
				,CASE
					WHEN t.ProductId = 10001 THEN 1 -- SB
					ELSE 0 -- BA
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
			DROP TABLE #__tempSite
		END

		-- Get data from DW (input ProductId = 1 return Metric Gaming = -4, Bet Builder = -5)
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId NOT IN (10, 11, 15, 31))
		BEGIN
			DECLARE @ProductIds VARCHAR(MAX)
			;WITH CTE_ProductIds AS (SELECT DISTINCT ProductId FROM @Products WHERE Product3rdId NOT IN (3, 10, 11, 15, 31))
			SELECT  @ProductIds = COALESCE(@ProductIds + ',', '') + CONVERT(VARCHAR(5), ProductId) FROM CTE_ProductIds

			DECLARE @SubProducts VARCHAR(MAX)
			SELECT  @SubProducts = COALESCE(@SubProducts + ',', '') + SubProductCode
			FROM @Products WHERE SubProductCode IS NOT NULL

			SELECT  @SubProducts = ISNULL(@SubProducts, '')

			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, Comm, HouseContribution, FullContribution)
			EXEC DBWH.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MemberWL
				@FromDate		= @FDate
				,@ToDate		= @TDate
				,@ProductIds	= @ProductIds
				,@SubProducts	= @SubProducts
				,@DepositType	= 1
		END

		-- CB: include credit site
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 15)
			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, Comm, HouseContribution)
			SELECT rptDate, CASE WHEN SiteId >= 1000 THEN -1 ELSE SiteId END, CurrencyId, 15, -1, -1
				,SUM(Turnover * CASE WHEN SiteId < 1000 THEN 0.0405 ELSE 0.062 END
					+ BuyBackAmount * CASE WHEN SiteId < 1000 THEN 0.15 ELSE 0.225 END)
				, 0, 0, 0
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND ProductID = 15
				AND CurrencyId <> 20
				AND CustomerCategory NOT IN (27, 28)
				AND StatusId NOT IN(-1, 101, 102, 103)
			GROUP BY rptDate, CASE WHEN SiteId >= 1000 THEN -1 ELSE SiteId END, CurrencyId

		-- 3rd Product: AGC, GD, EX
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (10, 11, 31))
			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SportTypeGroup, BetTypeGroup, ValidBetAmount, MemberWL, HouseWL, Comm, HouseContribution)
			SELECT rptDate, SiteId, CurrencyId
				,CASE
					WHEN ProductId = 10 THEN 11 -- AGC
					WHEN ProductId = 11 THEN 12 -- GD
					WHEN ProductId = 31 THEN 31 -- EX
					END
				,-1
				,CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END
				,SUM(CASE WHEN ProductId = 11 AND bettype = -1 THEN ValidBetAmount ELSE 0 END)
				,SUM(MemberWL)
				,0
				,SUM(CommissionP + CommissionA)
				,0
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
			WHERE rptDate BETWEEN @FDate AND @TDate
				AND ProductId IN (SELECT p.Product3rdId FROM @Products p WHERE p.Product3rdId IN (10, 11, 31))
				AND CurrencyId <> 20
				AND CustomerCategory NOT IN (27, 28)
				AND StatusId NOT IN(-1, 101, 102, 103)
				AND SiteId < 1000 -- Deposit only
			GROUP BY rptDate, SiteId, CurrencyId
				,CASE
					WHEN ProductId = 10 THEN 11 -- AGC
					WHEN ProductId = 11 THEN 12 -- GD
					WHEN ProductId = 31 THEN 31 -- EX
					END
				,CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END

		-- Get ProductId - Bettype
		CREATE TABLE #BetType (ProductId INT, Product3rdId INT, BetTypeGroup INT DEFAULT(-1))
		INSERT INTO #BetType (ProductId, Product3rdId)
		SELECT DISTINCT ProductId, Product3rdId FROM @Products

		INSERT INTO #BetType (ProductId, Product3rdId, BetTypeGroup)
		SELECT ProductId, Product3rdId, 1 AS BetTypeGroup
		FROM @Products p
		WHERE Product3rdId = 22 -- VB (Macau Games)

		INSERT INTO #BetType (ProductId, Product3rdId, BetTypeGroup)
		SELECT ProductId, Product3rdId, BetTypeGroup
		FROM @Products p
			CROSS JOIN (VALUES (1902), (1903), (1904), (1905)) b (BetTypeGroup)
		WHERE Product3rdId = 34 -- Card Club

		INSERT INTO #BetType (ProductId, Product3rdId)
		VALUES (-2, -2), (-3, -3), (-4, -4), (-5, -5)

		UPDATE v
		SET v.ProductId = s.ProductId
		FROM #tempVendorGlobalSetting v
			CROSS APPLY (
				SELECT TOP 1 s.ProductId
				FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
				WHERE v.Bettype = s.BetType
			) s

		DELETE #tempVendorGlobalSetting WHERE ProductId IS NULL OR ProductId NOT IN (SELECT b.ProductId FROM #BetType b)

		UPDATE v
		SET v.Bettype = -1
		FROM #tempVendorGlobalSetting v
			LEFT JOIN #BetType b ON v.Bettype = b.BetTypeGroup
		WHERE b.BetTypeGroup IS NULL

		UPDATE @Products SET ProductId = -2, Product3rdId = -2, ProductCode = 'H5' WHERE SubProductCode = 'H5'
		UPDATE @Products SET ProductId = -3, Product3rdId = -3, ProductCode = 'PP-JP' WHERE SubProductCode = 'PP-JP'

		-- Process data
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
			,PayToSupplier		MONEY
			,CurrencyPlay		MONEY
			,FullContribution	MONEY
			,JackpotPrize		MONEY
			,AmountToCompany	MONEY
			,AComm				MONEY
			,IsApplyMinFee		BIT DEFAULT (1)
		)
		INSERT INTO #__tempResult (rptDate, CurrencyId, PartyId, ParentId, Product3rdId, SporttypeGroup, OriginalMemberWL, MemberWL, PayToSupplier, FullContribution, JackpotPrize, AmountToCompany, AComm)
		SELECT t.rptDate
			,CASE
				WHEN b.Product3rdId = 10 THEN t.CurrencyId
				END
			,l.PartyId
			,CASE
				WHEN b.Product3rdId IN (11, 22, 34) THEN l.PartyId
				WHEN b.Product3rdId = 10 THEN l.ParentId
				WHEN b.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
				WHEN b.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
				END
			,b.Product3rdId
			,t.SportTypeGroup
			,SUM(t.MemberWL)
			,SUM(t.MemberWL * ISNULL(oa.Rate, 0))
			,SUM((
					(
						t.MemberWL + CASE WHEN rd.Product3rdId = 11 AND rd.ChargeType = 12 THEN t.ValidBetAmount * @GDCommissionRate ELSE 0 END
					)
					*
					(
						CASE
							WHEN b.Product3rdId IN (6, 13, 15, 24, 25, 36, 37, 38, 39, 42, 43, 45) THEN 0
							WHEN b.Product3rdId = -4 THEN -1 * ISNULL(lc.Rate, p.Rate) -- Metric Gaming
							WHEN b.Product3rdId = -5 THEN 0.04 -- Bet Builder
							WHEN b.Product3rdId = 27 THEN 0.065 -- VS2
							WHEN b.Product3rdId IN (8, 28) THEN CASE WHEN p.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03 ELSE 0.05 END -- KN, LT
							WHEN b.Product3rdId = 22 THEN CASE WHEN b.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
							WHEN b.Product3rdId = 34 AND b.BetTypeGroup <> -1 THEN ISNULL(v.ChargeRate3rd, 0)
							ELSE ISNULL(rd.Rate, v.ChargeRate3rd)
							END
					
					)
					+
					(
						CASE WHEN b.Product3rdId = 31 THEN t.Comm ELSE 0 END -- EX
					)
						 
				) * ISNULL(oa.Rate, 0)
				)
			,SUM(CASE WHEN b.Product3rdId = -3 THEN t.FullContribution * ISNULL(e.Rate, 0) ELSE 0 END)
			,SUM(CASE WHEN b.Product3rdId = -3 THEN -t.MemberWL * ISNULL(e.Rate, 0) ELSE 0 END)
			,SUM(CASE
					WHEN b.Product3rdId = 15 THEN t.MemberWL * ISNULL(oa.Rate, 0) -- CB
					WHEN b.Product3rdId IN (13, 25) THEN -t.MemberWL * ISNULL(oa.Rate, 0) -- BT & CO
					WHEN b.Product3rdId = 31 THEN (-t.MemberWL * ISNULL(lc.Rate, p.Rate) - t.Comm) * ISNULL(oa.Rate, 0) -- EX
					WHEN b.Product3rdId = 37 OR p.LicenseeId IS NULL THEN -t.HouseWL * ISNULL(e.Rate, 0)
					ELSE ((-t.MemberWL - (t.FullContribution - t.HouseContribution)) * ISNULL(lc.Rate, p.Rate) - t.HouseContribution) * ISNULL(e.Rate, 0)
					END)
			,SUM(t.Comm * ISNULL(e.Rate, 0))
		FROM #__tempData t
			INNER JOIN #BetType b ON t.ProductId = b.ProductId AND b.BetTypeGroup = t.BetTypeGroup
			INNER JOIN #AllLicensees l ON l.LicenseeId = t.LicenseeId
			LEFT JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND p.Product3rdId = b.Product3rdId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = b.BetTypeGroup)
					AND (
						(b.Product3rdId IN (11, 39) AND b.BetTypeGroup <> -1 AND p.ChargeType = 12)
						OR ((b.Product3rdId NOT IN (11, 39) OR b.BetTypeGroup = -1) AND p.ChargeType <> 12)
					)
			LEFT JOIN #PartyCharge3rdInfo rd ON rd.LicenseeId = l.LicenseeId AND rd.Product3rdId = b.Product3rdId AND t.rptDate BETWEEN rd.FromDate AND rd.ToDate
					AND (
						(b.Product3rdId IN (11, 39) AND b.BetTypeGroup <> -1 AND rd.ChargeType = 12)
						OR ((b.Product3rdId NOT IN (11, 39) OR b.BetTypeGroup = -1) AND rd.ChargeType <> 12)
					)
			LEFT JOIN #tempVendorGlobalSetting v ON v.ProductId = b.ProductId AND v.Bettype = b.BetTypeGroup
			LEFT JOIN #Exchange e ON t.rptDate = e.ExchangeDate AND t.CurrencyId = e.ExchangeId
			LEFT JOIN #ExchangeOANDA oa ON t.rptDate = oa.ExchangeDate AND t.CurrencyId = oa.ExchangeId
			LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		WHERE (
			(b.Product3rdId IN (0, 3, -4) AND p.PartyId IS NOT NULL)
			OR (b.Product3rdId NOT IN (0, 3, -4))
		)
		GROUP BY t.rptDate
			,CASE
				WHEN b.Product3rdId = 10 THEN t.CurrencyId
				END
			,l.PartyId
			,CASE
				WHEN b.Product3rdId IN (11, 22, 34) THEN l.PartyId
				WHEN b.Product3rdId = 10 THEN l.ParentId
				WHEN b.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
				WHEN b.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
				END
			,b.Product3rdId
			,t.SportTypeGroup

		DROP TABLE #__tempData
		DROP TABLE #AllLicensees
		DROP TABLE #BetType
		DROP TABLE #PartyCharge3rdInfo
		DROP TABLE #tempVendorGlobalSetting

		CREATE CLUSTERED INDEX CIX_Product3rdId ON #__tempResult (Product3rdId, rptDate)

		-- For special PayToSupplier
			-- 1. NG, H5
		UPDATE #__tempResult
		SET PayToSupplier = -0.5 * AmountToCompany
		WHERE Product3rdId IN (2, -2) -- NG, H5

			-- 2. AGC
		;WITH CTE_Sum AS
		(
			SELECT ParentId, Product3rdId, CASE WHEN LicenseeWL <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END AS Rate
			FROM
			(
				SELECT r.ParentId, r.Product3rdId, -SUM(r.OriginalMemberWL * CASE WHEN r.ParentId = 1 THEN e.CNY ELSE e.USD END) AS LicenseeWL
				FROM #__tempResult r
					INNER JOIN #ExchangeOANDA e ON r.rptDate = e.ExchangeDate AND r.CurrencyId = e.ExchangeId
				WHERE r.Product3rdId IN (10)
				GROUP BY ParentId, Product3rdId
			) t
		)
		UPDATE r
		SET r.PayToSupplier = r.MemberWL * s.Rate
		FROM #__tempResult r
			INNER JOIN CTE_Sum s ON r.ParentId = s.ParentId AND r.Product3rdId = s.Product3rdId

			-- 3. GMT <> -4
		SELECT @ProductCodesGMT = COALESCE(@ProductCodesGMT + ',', '') + ProductCode
		FROM @Products WHERE Product3rdId IN (21,24,32,36,39,45,51) -- 'AB,FW,PP,SG,SAG,SXG,WM'

		CREATE TABLE #__PayToSupplier (Product3rdId INT, ProductCode VARCHAR(50), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
		INSERT INTO #__PayToSupplier (ProductCode, rptDate, PayToSupplier, CurrencyPlay)
		EXEC Acc_Rpt_HouseNetIncome_PayToSupplier @FromDate = @FDate, @ToDate = @TDate, @ProductCodes = @ProductCodesGMT, @DepositType = 1

		UPDATE ps
		SET ps.Product3rdId = p.Product3rdId
		FROM #__PayToSupplier ps
			INNER JOIN @Products p ON ps.ProductCode = p.ProductCode

			-- 4. SB (Metric Gaming, Muay Thai, Bet Builder)
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
					INNER JOIN #ExchangeOANDA oa ON ci.BaseCurrencyId = oa.ExchangeId AND oa.ExchangeDate = @TDate
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
					WHEN r.Product3rdId = -5 THEN r.PaytoSupplier
					WHEN (r.PayToSupplier < 0 AND m.MinAmount = 0) OR r.PayToSupplier >= m.MinAmount
						THEN CASE WHEN r.PayToSupplier > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(r.PayToSupplier - m.MinAmount) END * m.Rate
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
			    INNER JOIN #ExchangeOANDA oa ON oa.ExchangeDate = b.rptDate AND oa.ExchangeId = b.CurrencyId
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyId <> 20
				AND b.StatusId IN (111, 112, 113)
				AND b.customercategory NOT IN (27, 28)
				AND b.SiteId < 1000
				AND b.SportType = 44
				AND p.Product3rdId = 0
			GROUP BY b.rptdate
		END
		
		DROP TABLE #ExchangeOANDA
	END

	-- Calculate House Income full range
	BEGIN
		DECLARE @Month			TINYINT = MONTH(@FDate)
		DECLARE @FirstDate		DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FDate), 0)
		DECLARE @LastDate		DATETIME = DATEADD(dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FDate) + 1, 0))
		DECLARE @DaysInMonth	INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

		DECLARE @PartyGroup TABLE (PartyGroupId INT, PartyId INT)
		INSERT INTO @PartyGroup (PartyGroupId, PartyId)
		SELECT PartyGroupId, PartyId
		FROM bodb_licensee.dbo.LA_PartyGroupAssignment WITH (NOLOCK)
		WHERE PartyGroupId IN
			(
				SELECT p1.PartyGroupId
				FROM bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH (NOLOCK)
				WHERE p1.PartyId IN (SELECT p.PartyId FROM #PartyChargeInfo p)
			)

		DECLARE @MinFeeGroup TABLE
		(
			FeeType				TINYINT
			,PartyId            INT
			,Product3rdId		INT
			,CurrencyId         INT
			,FeeAmount          MONEY
			,FromDate           DATETIME
			,ToDate             DATETIME
			,MinFeeProrate      MONEY
			,WaivedAmount       MONEY
			,TotalAmount        MONEY
			,MinFeeAmount       MONEY
			,AmountToCompany	MONEY
		)
		INSERT INTO @MinFeeGroup
		(
			FeeType
			,PartyId
			,Product3rdId
			,CurrencyId
			,FeeAmount
			,FromDate
			,ToDate
		)
		SELECT
			mf.FeeTypeId
			,mf.PartyId
			,mf.ProductId
			,mf.CurrencyId
			,mf.FeeAmount
			,CASE WHEN @FDate >= mf.FromDate THEN @FDate ELSE mf.FromDate END AS FromDate
			,CASE WHEN @TDate < mf.ToDate THEN @TDate ELSE mf.ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_MinFee mf WITH (NOLOCK)
		WHERE		(
						mf.FeeTypeId = 1
						OR mf.FeeTypeId = 2 
						AND EXISTS (SELECT	PartyId
									FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
									WHERE	m.FeeTypeId = 1
											AND m.PartyId = mf.PartyId
											AND m.ProductId = mf.ProductId
											AND (
													(m.FromDate BETWEEN @FirstDate AND @LastDate)
													OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
													OR (m.FromDate < @FirstDate AND @LastDate < m.ToDate)
												)
									)
					)
					AND mf.ProductId IN (SELECT p.Product3rdId FROM #PartyChargeInfo p)
					AND (	
							(mf.FromDate BETWEEN @FirstDate AND @LastDate) 
							OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
							OR (mf.FromDate < @FirstDate AND @LastDate < mf.ToDate)	
						)

		-- H5
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'H5')
		BEGIN
			IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'NG')
				INSERT INTO @MinFeeGroup (FeeType, PartyId, Product3rdId, CurrencyId, FeeAmount, FromDate, ToDate)
				SELECT FeeType, PartyId, -2, CurrencyId, FeeAmount, FromDate, ToDate FROM @MinFeeGroup
				WHERE Product3rdId = 2
			ELSE
				UPDATE @MinFeeGroup SET Product3rdId = -2 WHERE Product3rdId = 2
		END

		UPDATE m
		SET m.FeeAmount = m.FeeAmount * e.Rate
		FROM @MinFeeGroup m
			INNER JOIN #Exchange e ON e.ExchangeDate = @TDate AND m.CurrencyId = e.ExchangeID

		UPDATE t
		SET t.IsApplyMinFee = 0
		FROM #__tempResult t
			INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
				AND t.PartyId = m.PartyId
				AND t.Product3rdId = m.Product3rdId
		WHERE m.FeeType = 2

		UPDATE amf
		SET amf.MinFeeProrate = (
					(
					   SELECT TOP 1 mfg.FeeAmount
					   FROM @MinFeeGroup AS mfg
					   WHERE mfg.FeeType = 1
							AND mfg.PartyId = amf.PartyId
							AND mfg.Product3rdId = amf.Product3rdId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
		FROM @MinFeeGroup amf
		WHERE FeeType = 2

		UPDATE amf
		SET amf.WaivedAmount = ISNULL(
					(
					   SELECT SUM(td.AmountToCompany)
					   FROM #__tempResult td
					   WHERE amf.PartyId = td.PartyId
							AND amf.Product3rdId = td.Product3rdId
							AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
					), 0)
		FROM @MinFeeGroup amf
		WHERE amf.FeeType = 2

		UPDATE amf
		SET amf.MinFeeProrate = ROUND((amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) - ISNULL(
					(
					   SELECT SUM(f.MinFeeProrate)
					   FROM @MinFeeGroup AS f
					   WHERE f.FeeType = 2
							AND amf.PartyId = f.PartyId
							AND amf.Product3rdId = f.Product3rdId
					), 0), 2)
				  , amf.WaivedAmount = ISNULL(
					(
					   SELECT CASE
								WHEN SUM(f.WaivedAmount) < 0
								THEN 0
								ELSE SUM(f.WaivedAmount)
							END
					   FROM @MinFeeGroup AS f
					   WHERE f.FeeType = 2
							AND amf.PartyId = f.PartyId
							AND amf.Product3rdId = f.Product3rdId
					), 0)
				  , amf.MinFeeAmount = ISNULL(
					(
					   SELECT SUM(td.AmountToCompany)
					   FROM #__tempResult AS td
					   WHERE amf.PartyId = td.PartyId
							AND amf.Product3rdId = td.Product3rdId
							AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
							AND td.IsApplyMinFee = 1
					), 0)
		FROM @MinFeeGroup amf
		WHERE amf.FeeType = 1

		UPDATE amf
		SET amf.TotalAmount = amf.MinFeeAmount + amf.WaivedAmount
		FROM @MinFeeGroup amf
		WHERE amf.FeeType = 1

		DECLARE @TotalMinFees TABLE
		(
			PartyGroupId        INT
			,Product3rdId       INT
			,TotalMinFee        MONEY
			,TotalMinFeeAmount  MONEY
		)
		INSERT INTO @TotalMinFees
		(
			PartyGroupId
			,Product3rdId
			,TotalMinFee
			,TotalMinFeeAmount
		)
		SELECT
			pg.PartyGroupId
			,mf.Product3rdId
			,SUM(mf.MinFeeProrate)
			,SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END)
		FROM @MinFeeGroup mf
			INNER JOIN @PartyGroup pg ON mf.PartyId = pg.PartyId
		WHERE mf.FeeType = 1
		GROUP BY
			pg.PartyGroupId
			,mf.Product3rdId

		UPDATE amf
		SET amf.AmountToCompany = CASE
										WHEN t.TotalMinFeeAmount < t.TotalMinFee
											AND amf.MinFeeAmount < amf.MinFeeProrate
										THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									 END
		FROM @MinFeeGroup amf
			INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
			INNER JOIN @TotalMinFees t ON amf.Product3rdId = t.Product3rdId AND t.PartyGroupId = pg.PartyGroupId
		WHERE amf.FeeType = 1

		UPDATE amf
		SET amf.AmountToCompany = CASE
										WHEN amf.MinFeeAmount < amf.MinFeeProrate
										THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									 END
		FROM @MinFeeGroup amf
		WHERE amf.FeeType = 1 AND amf.AmountToCompany IS NULL

		DECLARE @tmpResult TABLE (PartyId INT, Product3rdId INT, BeforeHouseIncome MONEY, HouseIncome MONEY, AComm MONEY, MinFee MONEY, WLFee MONEY)
		INSERT INTO @tmpResult (PartyId, Product3rdId, BeforeHouseIncome, HouseIncome, AComm, MinFee, WLFee)
		SELECT PartyId, Product3rdId, SUM(AmountToCompany), SUM(AmountToCompany), SUM(AComm), 0, SUM(AmountToCompany) FROM #__tempResult GROUP BY PartyId, Product3rdId

		INSERT INTO @tmpResult (PartyId, Product3rdId, BeforeHouseIncome, HouseIncome, AComm, MinFee, WLFee)
		SELECT mf.PartyId, mf.Product3rdId, 0, 0, 0, 0, 0
		FROM @MinFeeGroup AS mf
			INNER JOIN #PartyChargeInfo p ON p.PartyID = mf.PartyId AND p.Product3rdId = mf.Product3rdId
			LEFT JOIN @tmpResult r ON mf.PartyId = r.PartyId AND mf.Product3rdId = r.Product3rdId
		WHERE r.PartyId IS NULL
			AND mf.FeeType = 1

		UPDATE s
		SET s.HouseIncome	= m.AmountToCompany
			,s.MinFee		= CASE WHEN m.AmountToCompany = m.TotalAmount THEN 0 ELSE m.MinFeeProrate END
			,s.WLFee		= CASE WHEN m.AmountToCompany = m.TotalAmount THEN m.TotalAmount ELSE m.WaivedAmount END
		FROM @tmpResult s
			INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId AND m.Product3rdId = s.Product3rdId
		WHERE m.FeeType = 1

		UPDATE @tmpResult
		SET HouseIncome = CASE WHEN HouseIncome > 0 OR Product3rdId = 3 THEN HouseIncome ELSE 0 END
			,WLFee = CASE WHEN WLFee > 0 THEN WLFee ELSE 0 END

		-- Discount for HAIFA
		CREATE TABLE #DiscountGroup (DiscountGroupId SMALLINT, DiscountGroupType TINYINT, FromAmount MONEY, ToAmount MONEY, Rate MONEY, PartyId INT, Product3rdId INT, BaseCurrency INT)

		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (0, 5, 27))
		BEGIN
			CREATE TABLE #DiscountGroupHeader (DiscountGroupId INT, DiscountGroupType TINYINT, PartyId INT, CurrencyId INT, FromDate DATETIME, ToDate DATETIME)
			INSERT INTO #DiscountGroupHeader (DiscountGroupId, DiscountGroupType, PartyId, CurrencyId, FromDate, ToDate)
			SELECT dg.DiscountGroupId, dg.DiscountGroupType, dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
			FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
					INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
			WHERE @FDate <= ToDate AND FromDate <= @TDate AND dg.DiscountGroupType = 1 -- Get discount winloss only
				AND dga.PartyId IN (SELECT p.PartyId FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyName = 'HAIFA')

			DELETE d
			FROM #DiscountGroupHeader d
			WHERE d.ToDate < (SELECT MAX(g.ToDate) FROM	#DiscountGroupHeader g WHERE d.PartyId = g.PartyId)			
			
			INSERT INTO #DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, Product3rdId , BaseCurrency)	
			SELECT dg.DiscountGroupId, dg.DiscountGroupType, dgd.FromAmount, dgd.ToAmount, dgd.Rate, dg.PartyID, dgp.ProductId, dg.CurrencyId
			FROM #DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId

			UPDATE d
			SET
				d.FromAmount = d.FromAmount * e.Rate,
				d.ToAmount = d.ToAmount * e.Rate
			FROM #DiscountGroup d
				INNER JOIN #Exchange e ON e.ExchangeDate = @TDate AND d.BaseCurrency = e.ExchangeID AND d.DiscountGroupType = 1 -- discount = 1
	
			;WITH CTE_Discount AS (
				SELECT r.PartyId, d.DiscountGroupId, SUM(r.HouseIncome) AS Total
				FROM @tmpResult r
					INNER JOIN (
					  SELECT DISTINCT DiscountGroupId, PartyId, Product3rdId FROM #DiscountGroup WHERE DiscountGroupType = 1
					) AS d ON r.PartyId = d.PartyId AND r.Product3rdId = d.Product3rdId
				GROUP BY r.PartyId, d.DiscountGroupId
			)
			DELETE d
			FROM #DiscountGroup d
			   INNER JOIN CTE_Discount t ON t.PartyId = d.PartyId AND t.DiscountGroupId = d.DiscountGroupId
			WHERE d.DiscountGroupType = 1
				AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount

			DROP TABLE #DiscountGroupHeader
		END
	END

	DROP TABLE #PartyChargeInfo
	DROP TABLE #Exchange

	-- Calculate result
	DELETE @Products WHERE Product3rdId = 3 -- BA
	
	IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
	BEGIN
		UPDATE @Products SET SporttypeGroup = 1, ProductCode = 'Soccer', SubOrder = 1 WHERE Product3rdId = 0

		INSERT INTO @Products (OrderId, SubOrder, ProductId, Product3rdId, SporttypeGroup, ProductCode)
		SELECT p.OrderId, s.SubOrder, p.ProductId, p.Product3rdId, s.SporttypeGroup, s.ProductCode
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
		OrderId INT
		,SubOrder INT
		,rptDate VARCHAR(10)
		,Product3rdId INT
		,ProductCode VARCHAR(50)
		,HouseIncome MONEY
		,MinFee MONEY
		,Discount MONEY
		,BAComm MONEY
		,PayToSupplier MONEY
		,PaytoMuayThai MONEY
		,PaytoMetricGaming MONEY
		,PayToBetBuilder MONEY
		,CurrencyPlay MONEY
		,FullContribution MONEY
		,JackpotPrize MONEY
	)
	INSERT INTO #Result
	(
		rptDate
		,Product3rdId
		,ProductCode
		,HouseIncome
		,MinFee
		,Discount
		,BAComm
		,PayToSupplier
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
		,CurrencyPlay
		,FullContribution
		,JackpotPrize
	)
	SELECT 'FullRange', p.Product3rdId, p.ProductCode
			,HouseIncome = SUM(CASE WHEN p.Product3rdId = 0 AND p.SporttypeGroup <> 1 THEN 0 ELSE ISNULL(r.WLFee, 0) END)
			,MinFee = SUM(CASE WHEN p.Product3rdId = 0 AND p.SporttypeGroup = 1 THEN ISNULL(r.MinFee, 0) ELSE 0 END)
			,Discount = 0
			,BAComm = 0
			,PayToSupplier = SUM(CASE WHEN p.Product3rdId IN (2, -2) THEN -0.5 * ISNULL(HouseIncome, 0) ELSE 0 END)
			,PaytoMuayThai = 0
			,PaytoMetricGaming = 0
			,PayToBetBuilder = 0
			,CurrencyPlay = 0
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
				SELECT SUM(t.PayToSupplier) AS PayToSupplier
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId
				GROUP BY t.ParentId
				HAVING SUM(t.MemberWL) < 0
			) r
		) t
	WHERE r.Product3rdId IN (5, 10, 22, 27, 34)

		-- 1.2. Base on PayToSupplier < 0
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(r.PayToSupplier) AS PayToSupplier
			FROM (
				SELECT SUM(t.PayToSupplier) AS PayToSupplier
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId
				GROUP BY t.ParentId
				HAVING SUM(t.PayToSupplier) < 0
			) r
		) t
	WHERE r.Product3rdId IN (11)

		-- 1.3. 1/2 House Income
	UPDATE #Result
	SET PayToSupplier = -0.5 * HouseIncome
	WHERE Product3rdId IN (-2, 2)

		-- 1.4. Total daily
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.PayToSupplier) AS PayToSupplier FROM #__tempResult t WHERE t.Product3rdId = r.Product3rdId
		) t
	WHERE r.Product3rdId NOT IN (-2, 2, 5, 10, 11, 22, 27, 34)

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
				SELECT SUM(t.AmountToCompany) AS HouseIncome
				FROM #__tempResult t
				WHERE t.Product3rdId = r.Product3rdId
				GROUP BY t.ParentId
				HAVING SUM(t.AmountToCompany) > 0
			) r
		) t
	WHERE r.Product3rdId IN (22)

		-- 2.3. Total daily
	UPDATE r
	SET r.HouseIncome = ISNULL(t.HouseIncome, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.AmountToCompany) AS HouseIncome FROM #__tempResult t WHERE t.Product3rdId = r.Product3rdId
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
		,HouseIncome
		,MinFee
		,Discount
		,BAComm
		,PayToSupplier
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
		,CurrencyPlay
		,FullContribution
		,JackpotPrize
	)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106), p.Product3rdId, p.ProductCode
		,SUM(ISNULL(t.AmountToCompany, 0))
		,0 AS MinFee
		,SUM(ISNULL(t.AmountToCompany * d.Rate, 0))
		,SUM(ISNULL(-t.AComm, 0))
		,SUM(ISNULL(t.PayToSupplier, 0))
		,0
		,0
		,0
		,SUM(ISNULL(t.CurrencyPlay, 0))
		,SUM(ISNULL(t.FullContribution, 0))
		,SUM(ISNULL(t.JackpotPrize, 0))
	FROM CTE_rptDate r
		CROSS JOIN @Products p
		LEFT JOIN #__tempResult t ON r.rptDate = t.rptDate AND t.Product3rdId = p.Product3rdId AND t.SporttypeGroup = p.SporttypeGroup
		LEFT JOIN #DiscountGroup d ON t.PartyId = d.PartyId AND t.Product3rdId = d.Product3rdId
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106), p.Product3rdId, p.ProductCode
	OPTION (MAXRECURSION 0)

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
		,r.PayToBetBuilder = CASE WHEN r.rptDate = 'FullRange' AND p.PayToBetBuilder > 0 THEN 0 ELSE p.PayToBetBuilder END
	FROM #Result r
		INNER JOIN (
			SELECT CONVERT(VARCHAR(10), 'FullRange') AS rptDate
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

	UPDATE r
	SET r.PayToSupplier = p.PayToSupplier, r.CurrencyPlay = p.CurrencyPlay
	FROM #Result r
		INNER JOIN #__PayToSupplier p ON r.Product3rdId = p.Product3rdId AND r.rptDate = p.rptDate

	DROP TABLE #__PayToSupplier
	DROP TABLE #__PayToSupplierSB
	DROP TABLE #__tempResult
	DROP TABLE #DiscountGroup

	-- Update result
	UPDATE #Result
	SET HouseIncome			= CASE WHEN Product3rdId = -3 THEN NULL ELSE HouseIncome END
		,PayToSupplier		= CASE WHEN Product3rdId IN (0, -3, 6, 13, 15, 25, 37, 38, 42) THEN NULL ELSE PayToSupplier END
		,PaytoMuayThai		= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'OS' THEN NULL ELSE PaytoMuayThai END
		,PaytoMetricGaming	= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'Soccer' THEN NULL ELSE PaytoMetricGaming END
		,PayToBetBuilder	= CASE WHEN Product3rdId <> 0 OR ProductCode <> 'Soccer' THEN NULL ELSE PayToBetBuilder END
		,CurrencyPlay		= CASE WHEN Product3rdId <> 21 THEN NULL ELSE CurrencyPlay END
		,FullContribution	= CASE WHEN Product3rdId <> -3 THEN NULL ELSE FullContribution END
		,JackpotPrize		= CASE WHEN Product3rdId <> -3 THEN NULL ELSE JackpotPrize END
		,MinFee				= CASE WHEN Product3rdId <> 0 THEN NULL ELSE MinFee END
		,Discount			= CASE WHEN Product3rdId NOT IN (0, 5, 27) THEN NULL ELSE Discount END
		,BAComm				= CASE WHEN Product3rdId <> 0 THEN NULL ELSE BAComm END

	UPDATE r
	SET r.OrderId = p.OrderId, r.SubOrder = p.SubOrder
	FROM #Result r
		INNER JOIN @Products p ON r.Product3rdId = p.Product3rdId AND r.ProductCode = p.ProductCode

	UPDATE #Result
	SET ProductCode = CASE Product3rdId
						WHEN 31 THEN 'EX'
						WHEN 37 THEN 'NPH'
						WHEN 38 THEN 'VG'
						ELSE ProductCode
						END
	WHERE Product3rdId IN (31, 37, 38)

	DECLARE @DateList VARCHAR(2000), @tmpProduct3rdId INT, @ReturnColumns VARCHAR(2000)
	SELECT TOP 1 @tmpProduct3rdId = Product3rdId FROM #Result
	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #Result
	WHERE Product3rdId = @tmpProduct3rdId
		AND (
			Product3rdId <> 0
			OR (Product3rdId = 0 AND ProductCode = 'Soccer')
		)

	SELECT @ReturnColumns = 'ProductCode,[Order],Figure,' + @DateList

    /* End region*/
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT  @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT OrderId, Product3rdId, ProductCode, [Order], SubOrder, [RptDate], Figure, ISNULL(value, 0) value
								FROM #Result
									CROSS APPLY (
												  SELECT  1, ''House Income''			, HouseIncome		WHERE HouseIncome IS NOT NULL
										UNION ALL SELECT  2, ''Licensing Minimum Fee''	, MinFee			WHERE MinFee IS NOT NULL
										UNION ALL SELECT  3, ''Rebate & Discount''		, Discount			WHERE Discount IS NOT NULL
										UNION ALL SELECT  4, ''BA Commission''			, BAComm			WHERE BAComm IS NOT NULL
										UNION ALL SELECT  5, ''Pay to supplier''		, PayToSupplier		WHERE PayToSupplier IS NOT NULL
										UNION ALL SELECT  6, ''Currency Play''			, CurrencyPlay		WHERE CurrencyPlay IS NOT NULL
										UNION ALL SELECT  7, ''Contribution Amount''	, FullContribution	WHERE FullContribution IS NOT NULL
										UNION ALL SELECT  8, ''Jackpot Prize''			, JackpotPrize		WHERE JackpotPrize IS NOT NULL
										UNION ALL SELECT  9, ''Pay to Muay Thai''		, PaytoMuayThai		WHERE PaytoMuayThai IS NOT NULL
										UNION ALL SELECT 10, ''Pay to Metric Gaming''	, PaytoMetricGaming WHERE PaytoMetricGaming IS NOT NULL
										UNION ALL SELECT 11, ''Pay to Bet Genius''		, PayToBetBuilder	WHERE PayToBetBuilder IS NOT NULL
									) c ([Order], Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p
							ORDER BY OrderId, [Order], SubOrder'
	EXEC(@SQL)

	DROP TABLE #Result
END
GO
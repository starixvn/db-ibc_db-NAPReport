/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductList	VARCHAR(MAX) = 'all'
	,@DepositType	TINYINT = 2
	,@IsOldView		BIT = 0
	,@IsLicPerf		BIT = 0
	,@BaseCurrencyName  VARCHAR(10) = 'MYR'
	,@isGetDataFromBettrans BIT = 0
AS

/*
	Created: 20201201@Percy
	DB: DBWH-bodb_dwrs
	Task: House Net Income - Pay to supplier for some products
	
	Revisions:
		- 20201201@Percy: Initiliaze SP [RedmineID: #143208]
		- 20200112@Percy: Return ProductCategory column [RedmineID: #146539]
		- 20210125@Percy: Return SubFigure column [RedmineID: #149267]
		- 20210323@Percy: Integrate PP Live Casino [RedmineID: #133734]
		- 20210402@Danny: Support Lucky Draw for AE Casino & Integrate Bonus program for credit sites for Arcadia Gaming & Remove the Gold Deluxe (#151870)
		- 20210331@Danny: handle site saba789 follow credit term [Redmine: #152450] 
		- 20210517@Danny: Remove the following term for Allbet (#155119)
		- 20210616@Danny: Support @BaseCurrencyName with Licensee Performance view mode (#156727)
		- 20210727@Danny: HNI Email/Letstalk - Change the formula to calculate House Income, Pay To Supplier for Arcadia Gaming/PP Promotion tickets (#158971)
		- 20210803@Danny: Change Data Source to retrieve yesterday data from Bettrans table (#151993)
		- 20210917@Danny: Split Basketball betbuilder (#160737)
		- 20211102@Danny: SG integrate JP, Contribution (#166684)
		- 20220401@Danny: Get Royalty credit site fee by site (#170842)
		- 20220325@Danny: Incorporate FGG (#170522)
		- 20220805@Danny: Modify SPs to retrieve yesterday data in Data warehouse in case in-house replicator got problem (#176077)
		- 20221003@Danny: Integrate MGRNG product and restructure code (#177505)
		- 20231027@Danny: Change LicenseeID detection formulary of deposit licensee [#183209]
		- 20230111@Danny: Email/Letstalk Reports - Split 789Y site into smaller sites (#182388)
		- 20230522@Danny: Incorporate YeeBet (#186481)
		- 20231024@Danny: Remove redundant hardcode (#195608)
		- 20240305@Danny: Incorporate UU Slots (#192594)
		- 20240328@Danny: Incorporate Yolo And remove unsupported products (#201590)
*/
BEGIN
    SET NOCOUNT ON
	---- Param And temporary table
	DECLARE @IsTest BIT = 0
			,@FDate DATE
			,@TDate DATE
			,@FDate_GMT DATETIME
			,@TDate_GMT DATETIME
			,@LastDay DATE
			,@ExDate SMALLDATETIME
			,@f_date VARCHAR(10)
			,@t_date VARCHAR(10)
			,@SQL VARCHAR(MAX) -- use for dynamic query
			,@ProductCodes VARCHAR(MAX)
			,@Product3rdIds VARCHAR(MAX)
			,@PartyIds VARCHAR(MAX)
			,@FromDateByBatch DATE
			,@ToDateByBatch DATE
			,@Site789y_dwh INT
			,@InHouseReplicationWorkingStatus INT
			,@SQLExchangeDailySel VARCHAR(MAX)
			,@FDateGetData	DATE 
			,@TDateGetData	DATE
			,@yesterday		DATE = DATEADD(DAY,-1,CONVERT(date, GETDATE()))
			,@FDate_GMT_getdata DATETIME
			,@TDate_GMT_getdata DATETIME
			,@Today DATETIME = CONVERT(DATE, GETDATE())
			,@DateList VARCHAR(2000)
			,@AmountRM MONEY
			,@Exec_rpt_ThirdPartyWL_ExtraGMT VARCHAR(MAX)
			,@Exec_rpt_BettingBySport VARCHAR(MAX)

	DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
	DECLARE @Products TABLE (ProductId INT, VendorId INT, Product3rdId INT, AliasProductId INT, ProductCode VARCHAR(50), SubProductCode VARCHAR(50))
	DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
	DECLARE @LA_f_ExchangeDailySel TABLE (ExchangeId INT, BaseCurrencyRate FLOAT)
	DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
	DECLARE @AB_CurrencyPlay_Month TABLE (CurrencyPlay_Month MONEY, SiteGroup VARCHAR(20))
	DECLARE @ProductSupportBonus TABLE (ProductID INT)
	DECLARE	@Site789y_lic TABLE (SiteID INT)

	CREATE TABLE #AllParties (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
	CREATE TABLE #Party (PartyId INT, ParentId INT, LicenseeId INT, IsDeposit BIT)
	CREATE TABLE #__PartyChargeInfo (LicenseeId INT, IsDeposit BIT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
	CREATE TABLE #__Party3rdInfo (PartyId INT, Product3rdId INT, ChargeId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate MONEY)
	CREATE TABLE #__PartyCharge3rdInfo (ParentId INT, PartyId INT, LicenseeId INT, IsDeposit BIT, Product3rdId INT, ChargeId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate MONEY)
	CREATE TABLE #__PartyCharge3rdInfoByAmount (IsDeposit BIT, Product3rdId INT, CurrencyId INT, Rate MONEY, MinAmount MONEY, MaxAmount MONEY)
	CREATE TABLE #__tmpVendorGlobalSetting (IsDeposit BIT, VendorId SMALLINT, Product3rdId INT, ChargeRate3rd DECIMAL(19, 8))
	CREATE TABLE #MetricChargeInfo (FromDate DATE, ToDate DATE, BaseCurrencyId INT, MinAmount MONEY, MaxAmount MONEY, Rate FLOAT)
	CREATE TABLE #__tempResult (rptDate DATE, ParentId INT, IsDeposit BIT, Product3rdId INT, Bettype INT, CurrencyId INT, PlayCurrency INT, 
		PayDaily MONEY, PayDailyRate MONEY, PayMonth MONEY, PayMonthRate MONEY, MemberWLDailyRate MONEY, MemberWLMonthRate MONEY, BonusRate MONEY, SiteGroup VARCHAR(20))
	CREATE TABLE #__Bettype (Product3rdId INT, ProductCode VARCHAR(50), BetType INT, SubProduct VARCHAR(500) DEFAULT '')
	CREATE TABLE #__DailyPayToSupplier (IsDeposit BIT, Product3rdId INT, Bettype INT DEFAULT(0), rptDate DATE, PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0), Bonus MONEY DEFAULT(0), SiteGroup VARCHAR(20))
	CREATE TABLE #__FullRangePayToSupplier (IsDeposit BIT, Product3rdId INT, Bettype INT DEFAULT(0), PayToSupplier MONEY, CurrencyPlay MONEY DEFAULT(0), Bonus MONEY DEFAULT(0), SiteGroup VARCHAR(20))
	CREATE TABLE #__FinalResult (IsDeposit BIT, Product3rdId INT, ProductCode VARCHAR(50), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY, SiteGroup VARCHAR(20))
	-- Use Valid Bet Amount
	CREATE TABLE #__ValidBetRate (IsDeposit BIT, Product3rdId INT, FromDate DATE, ToDate DATE, CommRate FLOAT)
	-- For Allbet
	CREATE TABLE #__PlayCurrencySettings (SiteId INT, MemberCurrency INT, PlayCurrency INT, FromDate DATETIME, ToDate DATETIME)
	CREATE TABLE #__tempData (rptDate DATE, SiteId INT, BetTypeId INT, CurrencyId INT, Winloss MONEY, ValidBetAmount MONEY, ProgressiveContribution MONEY)
	---- Param And temporary table

	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)
			,@FDate = @FromDate
			,@TDate = @ToDate
			,@FDate_GMT = DATEADD(DAY, -1, @FromDate)
			,@TDate_GMT = DATEADD(DAY, 1, @ToDate)
			,@LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
			,@f_date = CONVERT(VARCHAR(10), @FromDate, 120)
			,@t_date = CONVERT(VARCHAR(10), @ToDate, 120)

	INSERT INTO @Site789y_lic(siteid)
	SELECT siteid FROM DBLIC.bodb_licensee.dbo.view_site_list  WITH(NOLOCK) where SiteName IN (SELECT x.Site FROM bodb02.dbo.Site x WITH(NOLOCK) WHERE x.SiteLabel = '789y')

    SELECT  @InHouseReplicationWorkingStatus = CAST(VValue AS INT)
    FROM	bodb_account.dbo.SystemSettings (NOLOCK)
    WHERE	VID = 16

	IF @InHouseReplicationWorkingStatus = 0
		SELECT @isGetDataFromBettrans = 0

	-- Get list of product
	BEGIN
		INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
		SELECT ProductId, ProductPrefix FROM DBLIC.bodb_Licensee.dbo.Product3rd WITH (NOLOCK)

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
			AND s.IsTest <= @IsTest

		;WITH CTE_Product AS (SELECT DISTINCT ProductCode FROM @Products)
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

		;WITH CTE_Product AS (SELECT DISTINCT Product3rdId FROM @Products)
		SELECT @Product3rdIds = COALESCE(@Product3rdIds + ',', '') + CONVERT(VARCHAR(3), Product3rdId) FROM CTE_Product
	END

	-- Get Exchange
	BEGIN
		SELECT  @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate

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

	-- Get Licensees
	BEGIN
		-- All licensees
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
															AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98, 962))
													) AS r
													WHERE r.RowNum = 1'')'
		INSERT INTO #AllParties (PartyId, ParentId, LicenseeId, IsDeposit)
		EXEC (@SQL)

		-------------------------------------

		-- Licensees have setting
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
														AND (pd.IsDeposit = 0 OR ci.ToParty IN (1, 9, 11, 98, 962))'')'
		INSERT INTO #Party (PartyId, ParentId, LicenseeId, IsDeposit)
		EXEC (@SQL)

		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Party

	END

	-- Get charge rate
	BEGIN
		SELECT @SQL = '	SELECT LicenseeId, IsDeposit, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.LicenseeId, ci.IsDeposit, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.ChargeType
								,CASE WHEN ci.ProductId = 0 THEN -1 ELSE ISNULL(sbr.Bettype, ci.Bettype) END AS Bettype
								,CASE WHEN ci.IsDeposit = 0 AND ci.ProductId IN (32, 65, 70, 76) THEN 0 ELSE ci.DI_Rate END AS Rate
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
						WHERE ci.DI_Rate > 0
								AND (
									ci.ChargeType = 1
									OR ci.ChargeType IN (9, 10, 11, 12) AND ci.ProductId IN (21, 39) -- Allbet, SAG
								)'')'
		INSERT INTO #__PartyChargeInfo (LicenseeId, IsDeposit, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		SELECT @SQL = '	SELECT PartyId, ProductId, ChargeId, ChargeType, FromDate, ToDate, Rate
						FROM OPENQUERY (DBLIC, ''SELECT DISTINCT PartyId, ProductId, ChargeId, ChargeType, FromDate, ToDate, DI_Rate AS Rate FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''')
												 WHERE (
														(ProductID IN (21, 39, 70, 76) AND ChargeType IN (9, 10, 11)) -- AB, SAG, FGGL, YB
														OR (ProductID NOT IN (21, 39) AND ChargeType = 1)
													)'')'
		INSERT INTO #__Party3rdInfo (PartyId, Product3rdId, ChargeId, ChargeType, FromDate, ToDate, Rate)
		EXEC (@SQL)

		INSERT INTO #__PartyCharge3rdInfo (ParentId, PartyId, LicenseeId, IsDeposit, Product3rdId, ChargeId, ChargeType, FromDate, ToDate, Rate)
		SELECT p.ParentId, p.PartyId, p.LicenseeId, p.IsDeposit, p3.Product3rdId, p3.ChargeId, p3.ChargeType, p3.FromDate, p3.ToDate, p3.Rate
		FROM #__Party3rdInfo p3
			INNER JOIN #Party p ON p3.PartyId = p.ParentId

		INSERT INTO #__PartyCharge3rdInfoByAmount (IsDeposit, Product3rdId, CurrencyId, Rate, MinAmount, MaxAmount)
		SELECT DISTINCT p.IsDeposit, p.Product3rdId, c.BaseCurrencyId, p.Rate, c.MinAmount, c.MaxAmount
		FROM #__PartyCharge3rdInfo p
			INNER JOIN DBLIC.bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON p.ChargeId = c.ChargeId
		WHERE p.ChargeType = 1 AND p.IsDeposit = 0 AND p.Product3rdId IN (32, 65) -- PP, PP Live Casino
			AND @ToDate BETWEEN c.FromDate AND c.ToDate
		
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
		INSERT INTO @tmpSite (LicenseeId, SiteName)
		SELECT SiteId, RTRIM(LTRIM(SiteName)) FROM DBLIC.bodb_licensee.dbo.view_site_list WITH (NOLOCK)

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM @tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))
	END

	-- Get data
	BEGIN
		IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
		BEGIN
			SELECT @FDateGetData = @FromDate
			SELECT @TDateGetData = DATEADD(DAY,-1,@ToDate)
		END
		ELSE 
		BEGIN
			SELECT @FDateGetData = @FromDate
			SELECT @TDateGetData = @ToDate
		END
		-----
		INSERT INTO #__Bettype (Product3rdId, ProductCode, BetType, SubProduct)
		SELECT DISTINCT p.Product3rdId, p.ProductCode, s.BetType, s.SubProduct FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
			INNER JOIN @Products p ON s.ProductId = p.ProductId AND p.Product3rdId <> 0
		WHERE s.BetType NOT IN (4298, 4600) -- Remove for implement bonus amount  4299, 4300, 3150

		INSERT INTO  @ProductSupportBonus (ProductID) 
		SELECT DISTINCT Product3rdId FROM #__Bettype WHERE SubProduct IN ('Prize','Lucky Draw','Bonus','Promotion')

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

		IF (@DepositType IN (0, 2) AND (',' + @ProductCodes + ',' LIKE '%,AB,%' OR ',' + @ProductCodes + ',' LIKE '%,SAG,%')) OR (',' + @ProductCodes + ',' LIKE '%,FGGL,%') OR (',' + @ProductCodes + ',' LIKE '%,YB,%')
		BEGIN
			INSERT INTO #__ValidBetRate (IsDeposit, Product3rdId, FromDate, ToDate, CommRate)
			SELECT DISTINCT IsDeposit, Product3rdId, FromDate, ToDate, Rate
			FROM #__PartyCharge3rdInfo
			WHERE ChargeType = 11 AND ( 
										(IsDeposit = 0 AND Product3rdId IN (21, 39) )
										OR Product3rdId NOT IN (21,39)
									  )
		END

		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 0)
		BEGIN
			DELETE #__tempData

			-- Metric Gaming, Bet Builder
			SELECT @FromDateByBatch = @FDateGetData

			WHILE @FromDateByBatch <= @TDateGetData
			BEGIN
				SELECT @ToDateByBatch = DATEADD(DAY, 7, @FromDateByBatch)

				IF @ToDateByBatch > @TDateGetData
					SET @ToDateByBatch = @TDateGetData
				
				INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
				SELECT f.rptDate, s.LicenseeId, CASE WHEN f.BetType = 38 THEN CASE WHEN f.SportType = 2 THEN -4 ELSE -3 END ELSE -1 END, f.CurrencyId, SUM(CASE WHEN f.BetType = 38 THEN winlossP + commissionS ELSE winlossP + winlossA + winlossM + winlossS + commissionS END)
				FROM bodb_Account.dbo.FactSiteWinloss f WITH (NOLOCK)
					INNER JOIN @tmpSite s ON f.SiteId = s.SiteId_DW
				WHERE f.rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
					AND f.TicketStatus NOT IN (-1, 18, 9, 10, 14)
					AND f.CurrencyId <> 20
					AND (f.BetType = 38 OR f.BetType BETWEEN 801 AND 899)
				GROUP BY f.rptDate, s.LicenseeId, CASE WHEN f.BetType = 38 THEN CASE WHEN f.SportType = 2 THEN -4 ELSE -3 END ELSE -1 END, f.CurrencyId
				OPTION (RECOMPILE)

				SELECT @FromDateByBatch = DATEADD(DAY, 1, @ToDateByBatch)
			END

			-- Get Metric Gaming, Bet Builder yesterday
			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN
				INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
				EXEC DBACC.bodb02.dbo.Acc_rpt_FactSiteWinloss_Bettrans @Winlostdate = @yesterday, @isUseForPayToSupplier = 1
			END

			-- Muay Thai
			SELECT @Exec_rpt_BettingBySport ='
				SELECT rptDate, SiteId, BetTypeId, CurrencyId, Winloss
				FROM OPENQUERY (DBLIC,''	
									SELECT rptDate, SiteId, -2 BetTypeId, CurrencyId, SUM(ISNULL(AdjustedCustomerWL * 0.03, 0) - ISNULL(AdjustedCommShare, 0)) Winloss
									FROM bodb_LicenseeReport.dbo.rpt_BettingBySport t WITH (NOLOCK)
									WHERE t.RptDate BETWEEN ''''' + CONVERT(VARCHAR(10),@FDateGetData,120) +''''' AND ''''' + CONVERT(VARCHAR(10),@TDateGetData,120) +'''''
										AND t.CurrencyId <> 20
										AND StatusId IN (111, 112, 113)
										AND customercategory NOT IN (27, 28)
										AND SportType = 44
										AND (
											' + CAST( @DepositType AS VARCHAR(10) ) +' = 2
											OR (' + CAST( @DepositType AS VARCHAR(10) ) +' = 0 AND ((SiteId > 1000 OR SiteID < 50000) OR SiteID = 509))
											OR (' + CAST( @DepositType AS VARCHAR(10) ) +' = 1 AND ((SiteId <= 1000 OR SiteId >= 50000) AND SiteID <> 509))
										)
									GROUP BY rptDate, SiteId, CurrencyId
								 '')'


			INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
			EXEC (@Exec_rpt_BettingBySport)

			-- Muay Thai yesterday
			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN
				INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss)
				EXEC DBACC.bodb02.dbo.Acc_rpt_rptBettingBySport_Bettrans @Date = @yesterday ,@DepositType = @DepositType
			END

			INSERT INTO #__tempResult (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDailyRate, SiteGroup)
			SELECT d.rptDate, 0, a.IsDeposit, 0, d.BetTypeId, d.CurrencyId, d.CurrencyId
				,SUM(CASE 
						WHEN d.BetTypeId = -2 THEN Winloss * e.Rate
						WHEN d.BetTypeId IN (-3, -4) THEN Winloss * e.Rate * 0.04
						WHEN (-d.Winloss * p.Rate * e.Rate < 0 AND m.MinAmount = 0) OR -d.Winloss * p.Rate * e.Rate >= m.MinAmount
								THEN CASE WHEN -d.Winloss * p.Rate * e.Rate > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(-d.Winloss * p.Rate * e.Rate - m.MinAmount) END * m.Rate 
						ELSE 0 END)
				,CASE	WHEN  (d.SiteId <= 1000 OR d.SiteID >= 50000) THEN 'Licensee'
						WHEN  (d.SiteId > 1000 OR d.SiteId < 50000) THEN CASE WHEN x.SiteID IS NOT NULL THEN '789Y'  ELSE 'MBC' END 
						END SiteGroup
			FROM #__tempData d
				INNER JOIN #AllParties a ON d.SiteId = a.LicenseeId
				INNER JOIN @ExchangeOANDA e ON d.CurrencyId = e.ExchangeId
				LEFT JOIN #__PartyChargeInfo p ON p.LicenseeId = d.SiteId AND p.Product3rdId = 0 AND d.rptDate BETWEEN p.FromDate AND p.ToDate AND d.BetTypeId = -1
				LEFT JOIN #MetricChargeInfo m ON d.rptDate BETWEEN m.FromDate AND m.ToDate AND d.BetTypeId = -1
				LEFT JOIN @Site789y_lic x ON x.SiteID = d.SiteID
			GROUP BY d.rptDate, a.IsDeposit, d.BetTypeId, d.CurrencyId, 
					CASE	WHEN  (d.SiteId <= 1000 OR d.SiteID >= 50000) THEN 'Licensee'
							WHEN (d.SiteId > 1000 OR d.SiteId < 50000) THEN CASE WHEN x.SiteID IS NOT NULL THEN '789Y'  ELSE 'MBC' END 
						END

			UPDATE r
			SET r.PayMonthRate = r.PayDailyRate
				,r.PayDaily = CASE WHEN e.Rate = 0 THEN 0 ELSE r.PayDailyRate / e.Rate END
				,r.PayMonth = CASE WHEN e.Rate = 0 THEN 0 ELSE r.PayDailyRate / e.Rate END
			FROM #__tempResult r
				INNER JOIN @ExchangeOANDA e ON r.CurrencyId = e.ExchangeId
		END

		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId <> 0)
		BEGIN
			-- handle GTM param
			IF @isGetDataFromBettrans = 1 AND @TDate = @yesterday
			BEGIN
				SELECT @FDate_GMT_getdata = @FDate_GMT
				SELECT @TDate_GMT_getdata = @Today
			END
			ELSE 
			BEGIN
				SELECT @FDate_GMT_getdata = @FDate_GMT
				SELECT @TDate_GMT_getdata = @TDate_GMT
			END
			---------

			DELETE #__tempData

			SELECT @Exec_rpt_ThirdPartyWL_ExtraGMT ='
				SELECT rptDate, SiteId, BetTypeId, CurrencyId, Winloss, ValidBetAmount, ProgressiveContribution
				FROM OPENQUERY (DBLIC,''	
									SELECT RptDate3rd rptDate, SiteId, BetTypeId, CurrencyId, SUM(Winloss) Winloss , SUM(ValidBetAmount) ValidBetAmount, SUM(ProgressiveContribution) ProgressiveContribution
									FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT t WITH (NOLOCK)
									WHERE t.RptDate BETWEEN ''''' + CONVERT(VARCHAR(10),@FDate_GMT_getdata,120) +''''' AND ''''' + CONVERT(VARCHAR(10),@TDate_GMT_getdata,120) +'''''
										AND t.RptDate3rd BETWEEN ''''' + CONVERT(VARCHAR(10),@FDateGetData,120) +''''' AND ''''' + CONVERT(VARCHAR(10),@TDateGetData,120) +'''''
										AND t.CurrencyId <> 20
										AND StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
										AND (
											' + CAST( @DepositType AS VARCHAR(10) ) +' = 2
											OR (' + CAST( @DepositType AS VARCHAR(10) ) +' = 0 AND ((SiteId > 1000 OR SiteID < 50000) OR SiteID = 509))
											OR (' + CAST( @DepositType AS VARCHAR(10) ) +' = 1 AND ((SiteId <= 1000 OR SiteId >= 50000) AND SiteID <> 509))
										)
									GROUP BY RptDate3rd, SiteId, BetTypeId, CurrencyId
								 '')'
			
			INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss, ValidBetAmount, ProgressiveContribution)
			EXEC (@Exec_rpt_ThirdPartyWL_ExtraGMT)

			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN				
				INSERT INTO #__tempData (rptDate, SiteId, BetTypeId, CurrencyId, Winloss, ValidBetAmount, ProgressiveContribution)
				EXEC DBACC.bodb02.dbo.Acc_rpt_ThirdPartyWL_ExtraGMT_Bettrans @Winlostdate = @yesterday,  @DepositType = @DepositType
			END

			INSERT INTO #__tempResult (rptDate, ParentId, IsDeposit, Product3rdId, Bettype, CurrencyId, PlayCurrency, PayDaily, PayDailyRate, PayMonth, PayMonthRate, MemberWLDailyRate, MemberWLMonthRate, BonusRate, SiteGroup)
			SELECT d.rptDate, tp.ParentId, tp.IsDeposit, bt.Product3rdId, CASE WHEN d.BetTypeId = 3007 THEN 3007 ELSE 0 END, d.CurrencyId, ISNULL(pc.PlayCurrency, d.CurrencyId) AS PlayCurrency
				,SUM(CASE  WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN (CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * ISNULL(ISNULL(p3.Rate, vs.ChargeRate3rd), 0) 
						  ELSE 0 END) AS PayDaily
				,SUM(CASE  WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN (CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * e.Rate * ISNULL(ISNULL(p3.Rate, vs.ChargeRate3rd), 0) 
						  ELSE 0 END) AS PayDailyRate
				,SUM(CASE WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN (CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * CASE WHEN p.LicenseeId IS NULL OR p3.LicenseeId IS NULL THEN 0 ELSE p3.Rate END 
						  ELSE 0 END) AS PayMonth
				,SUM(CASE  WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN (CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END + ISNULL(d.ValidBetAmount * v.CommRate, 0)) * e.Rate * CASE WHEN p.LicenseeId IS NULL OR p3.LicenseeId IS NULL THEN 0 ELSE p3.Rate END  
						  ELSE 0 END) AS PayMonthRate
				,SUM(CASE WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END * e.Rate ELSE 0 END) AS MemberWLDailyRate
				,SUM(CASE WHEN bt.SubProduct NOT IN ('Prize','Lucky Draw','Bonus','Promotion') THEN CASE WHEN d.BetTypeId IN (4297, 4599) THEN d.ProgressiveContribution ELSE d.Winloss END * e.Rate * CASE WHEN p.LicenseeId IS NULL THEN 0.0 ELSE 1.0 END ELSE 0 END) AS MemberWLMonthRate
				,SUM(CASE WHEN  bt.SubProduct IN ('Prize','Lucky Draw','Bonus','Promotion') THEN d.Winloss * e.Rate ELSE 0 END) AS BonusRate
				,CASE	WHEN  (d.SiteId <= 1000 OR d.SiteId >= 50000) THEN 'Licensee'
						WHEN  (d.SiteId > 1000 OR d.SiteId < 50000) THEN CASE WHEN x.SiteID IS NOT NULL THEN '789Y'  ELSE 'MBC' END 
						END 
			FROM #__tempData d
				INNER JOIN #__Bettype bt ON d.BetTypeId = bt.BetType
				INNER JOIN #AllParties tp ON tp.LicenseeId = d.SiteId
				INNER JOIN @ExchangeOANDA e ON d.CurrencyId = e.ExchangeId
				LEFT JOIN #__PartyChargeInfo p ON tp.LicenseeId = p.LicenseeId AND bt.Product3rdId = p.Product3rdId AND d.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ChargeType <> 11 AND ((d.BetTypeId <> 3007 AND p.ChargeType <> 12) OR (d.BetTypeId = 3007 AND p.ChargeType = 12))
				LEFT JOIN #__PartyCharge3rdInfo p3 ON tp.LicenseeId = p3.LicenseeId AND bt.Product3rdId = p3.Product3rdId AND d.rptDate BETWEEN p3.FromDate AND p3.ToDate AND p3.ChargeType <> 11 AND ((d.BetTypeId <> 3007 AND p3.ChargeType <> 12) OR (d.BetTypeId = 3007 AND p3.ChargeType = 12))
				LEFT JOIN #__tmpVendorGlobalSetting vs ON vs.IsDeposit = tp.IsDeposit AND vs.Product3rdId = bt.Product3rdId
				LEFT JOIN #__PlayCurrencySettings pc ON d.SiteId = pc.SiteId AND d.CurrencyId = pc.MemberCurrency AND d.rptDate BETWEEN pc.FromDate AND pc.ToDate
				LEFT JOIN #__ValidBetRate v ON tp.IsDeposit = v.IsDeposit AND bt.Product3rdId = v.Product3rdId AND d.rptDate BETWEEN v.FromDate AND v.ToDate
				LEFT JOIN @Site789y_lic x ON x.SiteID = d.SiteId
			GROUP BY d.rptDate, tp.ParentId, tp.IsDeposit, bt.Product3rdId, CASE WHEN d.BetTypeId = 3007 THEN 3007 ELSE 0 END, d.CurrencyId, ISNULL(pc.PlayCurrency, d.CurrencyId), 
				CASE	WHEN  (d.SiteId <= 1000 OR d.SiteId >= 50000) THEN 'Licensee'
						WHEN  (d.SiteId > 1000 OR d.SiteId < 50000) THEN CASE WHEN x.SiteID IS NOT NULL THEN '789Y'  ELSE 'MBC' END 
						END 
		END
	END

	-- PP & PP Live Casino for Credit
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId IN (32, 65) AND IsDeposit = 0)
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier, Bonus, SiteGroup)
		SELECT wl.IsDeposit, wl.Product3rdId, wl.rptDate
			,(CASE
				WHEN
					(wl.MemberWLRate < 0 AND (ci.MinAmount * ex.Rate) = 0)
					OR (wl.MemberWLRate >= (ci.MinAmount * ex.Rate))
				THEN 
					CASE
						WHEN wl.MemberWLRate > (ci.MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
						ELSE wl.MemberWLRate - (ci.MinAmount * ex.Rate) END
				ELSE 0 END
			) * ci.Rate AS PayToSupplier, wl.BonusRate, wl.SiteGroup
		FROM
		(
			SELECT rptDate, Product3rdId, IsDeposit, SUM(MemberWLDailyRate) AS MemberWLRate, SUM(BonusRate) AS BonusRate, SiteGroup
			FROM #__tempResult
			WHERE Product3rdId IN (32, 65) AND IsDeposit = 0
			GROUP BY rptDate, Product3rdId, IsDeposit, SiteGroup
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.Product3rdId = ci.Product3rdId AND wl.IsDeposit = ci.IsDeposit
			INNER JOIN @ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier, Bonus, SiteGroup)
		SELECT wl.IsDeposit, wl.Product3rdId
			,SUM((CASE
				WHEN wl.Product3rdId = 32 AND -wl.MemberWLRate < 0 THEN 0
				WHEN
					(wl.MemberWLRate < 0 AND (ci.MinAmount * ex.Rate) = 0)
					OR (wl.MemberWLRate >= (ci.MinAmount * ex.Rate))
				THEN 
					CASE
						WHEN wl.MemberWLRate > (ci.MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
						ELSE wl.MemberWLRate - (ci.MinAmount * ex.Rate) END
				ELSE 0 END
			) * ci.Rate) AS PayToSupplier, SUM(wl.BonusRate) AS BonusRate , wl.SiteGroup
		FROM
		(
			SELECT Product3rdId, IsDeposit, SUM(MemberWLMonthRate) AS MemberWLRate, SUM(BonusRate) AS BonusRate, SiteGroup
			FROM #__tempResult
			WHERE Product3rdId IN (32, 65) AND IsDeposit = 0
			GROUP BY Product3rdId, IsDeposit, SiteGroup
		) wl
			INNER JOIN #__PartyCharge3rdInfoByAmount ci ON wl.Product3rdId = ci.Product3rdId AND wl.IsDeposit = ci.IsDeposit
			INNER JOIN @ExchangeOANDA ex ON ci.CurrencyId = ex.ExchangeId
		GROUP BY wl.IsDeposit, wl.Product3rdId, wl.SiteGroup
	END

	-- SA Gaming for Deposit
	IF @DepositType IN (1, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId = 39 AND IsDeposit = 1)
	BEGIN
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
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, rptDate, PayToSupplier, SiteGroup)
		SELECT 1, 39, d.rptDate, SUM(d.MemberWLDailyRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END),'Licensee' SiteGroup
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
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, PayToSupplier, SiteGroup)
		SELECT 1, 39, SUM(d.MemberWLMonthRate * CASE WHEN d.BetType = 3007 THEN 0.5 ELSE t.Rate END),'Licensee' SiteGroup
		FROM #__tempResult d
			INNER JOIN CTE_SA t ON t.ParentId = d.ParentId
		WHERE d.Product3rdId = 39 AND IsDeposit = 1
	END

	-- Check by MemberWL
	BEGIN
		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, Bettype, PayToSupplier, SiteGroup)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, SUM(PayToSupplier), SiteGroup
		FROM (
			SELECT IsDeposit, Product3rdId, ParentId, Bettype, SUM(PayMonthRate) AS PayToSupplier, SiteGroup
			FROM #__tempResult
			WHERE Product3rdId IN (10, 24) OR (Product3rdId = 0 AND Bettype IN (-1, -3, -4))
			GROUP BY IsDeposit, Product3rdId, ParentId, Bettype, SiteGroup
			HAVING SUM(PayMonthRate) < 0
		) t
		GROUP BY IsDeposit, Product3rdId,  CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, SiteGroup
	END

	-- Others
	BEGIN
		INSERT INTO #__DailyPayToSupplier (IsDeposit, Product3rdId, Bettype, rptDate, PayToSupplier, Bonus, SiteGroup)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, rptDate, SUM(PayDailyRate), SUM(BonusRate), SiteGroup
		FROM #__tempResult
		WHERE
			(IsDeposit = 0 AND Product3rdId NOT IN (32, 65))
			OR (IsDeposit = 1 AND Product3rdId <> 39)
		GROUP BY IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, rptDate, SiteGroup

		INSERT INTO #__FullRangePayToSupplier (IsDeposit, Product3rdId, Bettype, PayToSupplier, Bonus, SiteGroup)
		SELECT IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, SUM(PayMonthRate), SUM(BonusRate), SiteGroup
		FROM #__tempResult
		WHERE Product3rdId NOT IN (10, 24)
			AND (Product3rdId <> 0 OR Bettype NOT IN (-1, -3, -4))
			AND (IsDeposit = 1 OR Product3rdId NOT IN (32, 65))
			AND (IsDeposit = 0 OR Product3rdId <> 39)
		GROUP BY IsDeposit, Product3rdId, CASE WHEN Product3rdId = 0 THEN Bettype ELSE 0 END, SiteGroup
	END

	-- Play Currency
	IF @DepositType IN (0, 2)
		AND EXISTS (SELECT 1 FROM #__tempResult WHERE Product3rdId = 21 AND IsDeposit = 0)
	BEGIN
		;WITH CTE_AB AS
		(
			SELECT b.rptDate, SUM(b.PayDaily * (pe.Rate - oe.Rate)) AS CurrencyPlay, b.SiteGroup
			FROM #__tempResult b
				INNER JOIN @ExchangeOANDA oe ON oe.ExchangeID = b.CurrencyId
				INNER JOIN @ExchangeOANDA pe ON pe.ExchangeID = b.PlayCurrency
			WHERE Product3rdId = 21 AND IsDeposit = 0
			GROUP BY b.rptDate, b.SiteGroup
		)
		UPDATE d
		SET d.CurrencyPlay = c.CurrencyPlay
		FROM #__DailyPayToSupplier d
			INNER JOIN CTE_AB c ON d.rptDate = c.rptDate AND d.SiteGroup = c.SiteGroup
		WHERE d.Product3rdId = 21 AND d.IsDeposit = 0

		INSERT INTO @AB_CurrencyPlay_Month (CurrencyPlay_Month, SiteGroup)
		SELECT  SUM(b.PayMonth * (pe.Rate - oe.Rate)), SiteGroup
		FROM #__tempResult b
			INNER JOIN @ExchangeOANDA oe ON oe.ExchangeID = b.CurrencyId
			INNER JOIN @ExchangeOANDA pe ON pe.ExchangeID = b.PlayCurrency
		WHERE Product3rdId = 21 AND IsDeposit = 0
		GROUP BY SiteGroup

		UPDATE f
		SET f.CurrencyPlay = ISNULL(ab.CurrencyPlay_Month, 0)
		FROM #__FullRangePayToSupplier f
		INNER JOIN @AB_CurrencyPlay_Month ab ON f.SiteGroup = ab.SiteGroup
		WHERE Product3rdId = 21 AND IsDeposit = 0
	END

	;WITH CTE_Product AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay, SiteGroup)
	SELECT f.IsDeposit, p.Product3rdId, p.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, 'Monthly', 
			SUM(CASE WHEN ps.ProductID IS NOT NULL THEN ISNULL(f.Bonus,0) ELSE 0 END + ISNULL(f.PayToSupplier, 0)), 
			SUM(ISNULL(f.CurrencyPlay, 0)), f.SiteGroup
	FROM CTE_Product p
		INNER JOIN #__FullRangePayToSupplier f ON p.Product3rdId = f.Product3rdId
		LEFT JOIN @ProductSupportBonus ps ON p.Product3rdId = ps.ProductID
	GROUP BY f.IsDeposit, p.Product3rdId, p.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, f.SiteGroup

	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay, SiteGroup)
	SELECT t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, 'MTD', 
			SUM(CASE WHEN ps.ProductID IS NOT NULL THEN ISNULL(t.Bonus,0) ELSE 0 END + ISNULL(t.PayToSupplier, 0)), 
			SUM(ISNULL(t.CurrencyPlay, 0)), t.SiteGroup
	FROM CTE_RptDate d
		INNER JOIN #__DailyPayToSupplier t ON d.Product3rdId = t.Product3rdId
		LEFT JOIN @ProductSupportBonus ps ON d.Product3rdId = ps.ProductID
	GROUP BY t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, t.SiteGroup
	OPTION (MAXRECURSION 0)
	
	;WITH CTE_rptDate AS
	(
		SELECT DISTINCT Product3rdId, ProductCode FROM @Products
	)
	INSERT INTO #__FinalResult (IsDeposit, Product3rdId, ProductCode, rptDate, PayToSupplier, CurrencyPlay, t.SiteGroup)
	SELECT t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, CONVERT(VARCHAR(2), t.rptDate, 106),
			SUM(CASE WHEN ps.ProductID IS NOT NULL THEN ISNULL(t.Bonus,0) ELSE 0 END + ISNULL(t.PayToSupplier, 0)), 
			SUM(ISNULL(t.CurrencyPlay, 0)), t.SiteGroup
	FROM CTE_RptDate d
		INNER JOIN #__DailyPayToSupplier t ON d.Product3rdId = t.Product3rdId
		LEFT JOIN @ProductSupportBonus ps ON d.Product3rdId = ps.ProductID
	GROUP BY t.IsDeposit, d.Product3rdId, d.ProductCode + CASE WHEN Bettype <> 0 THEN CONVERT(VARCHAR(5), Bettype) ELSE '' END, CONVERT(VARCHAR(2), t.rptDate, 106), t.SiteGroup

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
		SELECT IsDeposit, SiteGroup, ProductCode, Figure, Monthly, MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31]
		FROM (
			SELECT r.IsDeposit, r.SiteGroup ,f.ProductCode, Value, Figure, rptDate
			FROM #__FinalResult r
			CROSS APPLY (
				SELECT ProductCode, PayToSupplier AS Value, ''Pay to supplier'' AS Figure WHERE ProductCode NOT LIKE ''SB%''
				UNION ALL SELECT ProductCode, CurrencyPlay, ''Currency Play'' WHERE ProductCode NOT LIKE ''SB%''
				UNION ALL SELECT ''Soccer'', PayToSupplier, ''Pay to Metric Gaming'' WHERE ProductCode = ''SB-1''
				UNION ALL SELECT ''OS'', PayToSupplier, ''Pay to Muay Thai'' WHERE ProductCode = ''SB-2''
				UNION ALL SELECT ''Soccer'', PayToSupplier, ''Pay to Bet Genius'' WHERE ProductCode = ''SB-3''
				UNION ALL SELECT ''Basketball'', PayToSupplier, ''Pay to Bet Genius'' WHERE ProductCode = ''SB-4''
			) f
		) t
		PIVOT (
			MAX(Value)
			FOR rptDate IN (Monthly, MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31])
		) p
	)
	SELECT
		s.IsDeposit, s.OrderByProduct, s.OrderByFigure, x.SiteGroup, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName
		,s.Figure, s.SubFigure, r.Monthly, r.MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31]
	FROM bodb_Account.dbo.HNISettings s WITH (NOLOCK)
	CROSS APPLY (
					SELECT SiteGroup,  IsDeposit FROM
					(
						SELECT ''MBC'' AS SiteGroup , 0 AS IsDeposit
						UNION ALL
						SELECT ''789Y'' AS SiteGroup, 0 AS IsDeposit
						UNION ALL
						SELECT ''Licensee'' AS SiteGroup , 1 AS IsDeposit
					) x WHERE x.IsDeposit = s.IsDeposit
				) x
		LEFT JOIN CTE_Result r ON r.ProductCode = s.ProductPrefix AND x.IsDeposit = s.IsDeposit AND r.Figure = s.Figure AND r.SiteGroup = x.SiteGroup
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
		AND s.IsTest <= ' + CONVERT(VARCHAR(1), @IsTest) + '
	ORDER BY s.IsDeposit, x.SiteGroup, s.OrderByProduct, s.OrderByFigure'

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

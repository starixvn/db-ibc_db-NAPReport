/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Deposit]
	@FromDate			DATE
	,@ToDate			DATE
	,@ProductList		VARCHAR(MAX) = 'all'
	,@IsLicPerf			BIT = 0
	,@BaseCurrencyName  VARCHAR(10) = 'MYR'
	,@isGetDataFromBettrans BIT = 0
AS

/*
	Created: 20201201@Percy
	DB: DBWH-bodb_dwrs
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
		- 20210708@Danny: Missing BA WL in Licensee House Income for monthly report (#158191)
		- 20210706@Danny: Split Licensee House Income by Sport for SB (#157953)
		- 20210727@Danny: HNI Email/Letstalk - Change the formula to calculate House Income, Pay To Supplier for Arcadia Gaming/PP Promotion tickets (#158971)
		- 20210803@Danny: Change Data Source to retrieve yesterday data from Bettrans table (#151993)
		- 20210830@Danny: Integrate Bitcoin Product (#159045)
		- 20210917@Danny: Prorated minfee for the group min fee (#160737)
		- 20211102@Danny: Treat Sports Lottery as Sportsbook data in licensee billing (#163175)
		- 20211102@Danny: SG integrate JP, Contribution (#166684)
		- 20220211@Danny: Email/Letstalk Reports - Incorporate Saba Basketball Soccer PinGoal (#168373)
		- 20220330@Danny: support Licensee Sponsorship column (#170729)
		- 20220805@Danny: Modify SPs to retrieve yesterday data in Data warehouse in case in-house replicator got problem (#176077)
		- 20221003@Danny: Integrate MGRNG product and restructure code (#177505)
		- 20221121@Danny: Integrate Player Tips Product (#180653)
		- 20221206@Danny: Incorporate Saba E-Sports PinGoal (#181261)
		- 20230414@Danny: New Commercial Terms for 12B (#186505)
		- 20230425@Danny: SP LA_AmountToCompanyByProduct return Discount Rate ExtraInfo (#169160)
		- 20230614@Danny: Incorporate PG promotion (#189313)
		- 20230614@Danny: Incorporate Saba Tennis (#190458)
		- 20230821@Danny: Integrate Parlay Boost Bonus (#192894)
		- 20231024@Danny: Change AGC 3rd billing term (#195608)
		- 20231101@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 (#194561)
		- 20240115@Danny: Merge the settings of VS1 VS2 VS3 into Virtual Sports (#199544)
		- 20240229@Danny: AGC product integrate JP, Contribution, Promotion  (#200523)
		- 20240305@Danny: Incorporate UU Slots (#192594)
		- 20240328@Danny: Incorporate Yolo And remove unsupported products (#201590)
        
*/
BEGIN
	SET NOCOUNT ON
	-- Param And temporary table
	DECLARE @IsTest BIT = 0,
			@FDate		DATE, 
			@TDate		DATE, 
			@LastDay	DATE,
			@FromExDate SMALLDATETIME, 
			@ToExDate	SMALLDATETIME, 
			@ExDate		SMALLDATETIME,
			@f_date		VARCHAR(10), 
			@t_date		VARCHAR(10), 
			@SQL		VARCHAR(MAX),
			@FromDateByBatch	DATE, 
			@ToDateByBatch		DATE,
			@BobbetId		INT = 0, 
			@TianboId		INT = 0,
			@Discount_PartyIds		VARCHAR(MAX), 
			@Discount_ProductCodes	VARCHAR(MAX),
			@ProductIds		VARCHAR(MAX), 
			@Product3rdIds	VARCHAR(MAX), 
			@ProductCodes	VARCHAR(MAX), 
			@SubProducts	VARCHAR(MAX), 
			@PartyIds		VARCHAR(MAX),
			@InHouseReplicationWorkingStatus INT,
			@SQLExchangeDailySel		VARCHAR(MAX),
			@Exec_rpt_BettingByProduct	VARCHAR(MAX),
			@FDateGetData	DATE, 
			@TDateGetData	DATE,
			@yesterday		DATE =  DATEADD(DAY,-1,CONVERT(date, GETDATE())),
			@SupportedProductList VARCHAR(200) = 'SB,VS,NG,VS2',
			@BAComm			MONEY, 
			@BAWinloss		MONEY,
			@SBHouseIncomeRealSoc	MONEY,
			@SBHouseIncomeOthers	MONEY,
			@CC_PayToSupplier	MONEY, 
			@CC_Bonus			MONEY,
			@SQL_licperf			VARCHAR(MAX) = '',
			@SB_HouseIncome_total	MONEY,
			@ExchaneFomularCutoff DATE	= '2023-05-01',
			@SB_SLT_BTC_MergePerfCutoff DATE= '2021-11-30',
			@AGCPaytoSuplierCutoff DATE  = '2023-10-01',
			@VSMergeSettingCutoff DATE  = '2024-03-01'
			

	DECLARE @Product3rd TABLE (Product3rdId INT, ProductPrefix VARCHAR(10))
	DECLARE @Products TABLE (ProductId INT, Product3rdId INT, AliasProductId INT, ProductCode VARCHAR(50), SubProductCode VARCHAR(50), IsPayToSupplier BIT DEFAULT (0), isOnlyTO BIT DEFAULT (0))
	DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
	DECLARE @LA_f_ExchangeDailySel TABLE (ExchangeId INT, BaseCurrencyRate FLOAT)
	DECLARE @PartyCharge3rd TABLE (PartyId INT, Product3rdId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate FLOAT)
	DECLARE @tmp_PartyCharge3rdInfo TABLE (ChargeType INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate MONEY)
	DECLARE @9wLicenseeList TABLE (PartyId INT)
	DECLARE @BTC_data TABLE (PartyId INT,Product3rdId INT, AliasProductId INT, HouseTurnover MONEY, LicenseeFee MONEY)
	DECLARE @SLT_data TABLE (PartyId INT,Product3rdId INT, AliasProductId INT, HouseTurnover MONEY, LicenseeFee MONEY)
	DECLARE @LicenseeFeeAndRebateDiscount TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId TINYINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
	)
	DECLARE @tmpResult_licperf TABLE(PartyId INT ,Product3rdId	INT ,AliasProductId	INT)
	DECLARE @SBGrossHouseIncome TABLE (Product3rdId	INT, AliasProductId INT, HouseIncome MONEY DEFAULT(0))
	DECLARE @ProductSupportBonus TABLE (ProductID INT)
	DECLARE @ProductSupportJPContrib TABLE (ProductID INT, Product3rdId INT)
	DECLARE @ContributionBettypeList TABLE (bettype INT)
	DECLARE @VSProductList TABLE (ProductID INT)

	CREATE TABLE #AllLicensees(LicenseeId INT, PartyId INT, ParentId INT, SiteId_DW INT)
	CREATE TABLE #Licensees(LicenseeId INT, PartyId INT, ParentId INT)
	CREATE TABLE #PartyChargeByCurrencyInfo(ChargeId INT, CurrencyId INT, Rate FLOAT)
	CREATE TABLE #tempVendorGlobalSetting(Product3rdId INT, Bettype INT, ChargeRate3rd FLOAT)
	CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
	CREATE TABLE #PartyCharge3rdInfo (ChargeType INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
	CREATE TABLE #tmpSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
	CREATE TABLE #tmpBetType (Product3rdId INT, AliasProductId INT, BetType INT, BettypeGroup INT, IsOnlyTO BIT)
	CREATE CLUSTERED INDEX CIX_#tmpBetType ON #tmpBetType(BetType, BettypeGroup)
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
		,LicenseeTO			MONEY DEFAULT(0) 
		,LicenseeWL			MONEY DEFAULT(0) -- General formula -(winlost - actual_stake)
		,ExchangePlayerComm MONEY DEFAULT(0)
		,FullParlayBoostBonus	MONEY DEFAULT(0)
		,AgentParlayBoostBonusSharing MONEY DEFAULT(0)
	)
	CREATE TABLE #__BettingByProduct (
		rptDate DATE, 
		LicenseeId INT, 
		CurrencyId INT, 
		Product3rdId INT, 
		BetTypeGroup INT, -- Store bettype
		ValidBetAmount MONEY, 
		MemberWL MONEY, 
		Comm MONEY, 
		LicenseeWL MONEY, 
		LicenseeTO MONEY, 
		ExchangePlayerComm MONEY,
		HouseContribution  MONEY,
		FullContribution	MONEY
	)	CREATE TABLE #__tempResult
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
		-- for Monthly
		,OriginalMemberWLMonth	MONEY
		,MemberWLMonth			MONEY
		,CommMonth				MONEY
		,PayToSupplierMonth		MONEY
		,CurrencyPlayMonth		MONEY
		,HouseIncomeMonth		MONEY
		,FullContribution	MONEY
		,JackpotPrize		MONEY
		,HouseTurnover		MONEY
		,IsApplyMinFee		BIT DEFAULT (1) -- for calculate min fee
		-- for Licensee Performance Only
		,LicenseeTODaily	MONEY
		,LicenseeWLDaily	MONEY
		,Bonus				MONEY
		-- For billing SBC, VGA, PP
		,FreeBet			MONEY
		,GrossWL			MONEY
		,HouseContribution  MONEY
	)
	CREATE TABLE #FactSiteWinloss(
		[RptDate] [date],
		[SiteID] [int],
		[CurrencyID] [int] ,
		[BetType] [int],
		[LeagueID] [int] ,
		[SportType] [int] ,
		[TicketStatus] [tinyint],
		[VarianceVR] [decimal](9, 6),
		[Stake] [decimal](19, 4),
		[WinlossIBC] [decimal](19, 4),
		[WinlossS] [decimal](19, 4),
		[WinlossM] [decimal](19, 4),
		[WinlossA] [decimal](19, 4),
		[WinlossP] [decimal](19, 4),
		[TurnoverIBC] [decimal](19, 4),
		[CommissionS] [decimal](19, 4)	
	)
	CREATE TABLE #tmpResult 
	(
		PartyId			INT
		,Product3rdId	INT
		,AliasProductId	INT
		,HouseTurnover	MONEY DEFAULT(0)
		,LicenseeWL		MONEY DEFAULT(0)
		,HouseIncome	MONEY DEFAULT(0)
		,AComm			MONEY DEFAULT(0)
		,LicenseeMinFee MONEY DEFAULT(0)
		,LicenseeFee	MONEY DEFAULT(0)
		,Rebate			MONEY DEFAULT(0)
		,Discount		MONEY DEFAULT(0)
	)
	CREATE CLUSTERED INDEX CIX_#tmpResult ON #tmpResult(Product3rdId, PartyId, AliasProductId)

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
		-- Licensee performance 
		,LicenseeTO_licperf	MONEY
		,LicenseeWL_licperf MONEY
		,Bonus				MONEY
	)
	--End Param And temporary table

	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)
			,@FDate = @FromDate
			,@TDate = @ToDate
			,@FromExDate = @FromDate
			,@ToExDate = @ToDate
			,@f_date = CONVERT(VARCHAR(10), @FromDate, 120)
			,@t_date = CONVERT(VARCHAR(10), @ToDate, 120)
	IF @FromDate > @ToDate OR DATEDIFF(MONTH, @FromDate, @ToDate) <> 0
		RETURN

    SELECT  @InHouseReplicationWorkingStatus = CAST(VValue AS INT)
    FROM	bodb_account.dbo.SystemSettings (NOLOCK)
    WHERE	VID = 16

	IF @InHouseReplicationWorkingStatus = 0
		SELECT @isGetDataFromBettrans = 0

	-- Get list of product
	BEGIN	
		INSERT INTO @Product3rd (Product3rdId, ProductPrefix)
		SELECT ProductId, ProductPrefix 
		FROM OPENQUERY (DBLIC,'SELECT ProductId, ProductPrefix FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK)')

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

		UPDATE @Products SET IsOnlyTO = 1 WHERE Product3rdId IN (0, 3, 10, 31)

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

	-- Get Deposit Licensees
	BEGIN
		-- All Deposit Licensees
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
		SELECT LicenseeId, PartyId, ParentId
		FROM OPENQUERY (DBLIC, 'SELECT OldRefId AS LicenseeId, FromParty AS PartyId, ToParty AS ParentId
								FROM (
									SELECT p.OldRefId, ci.FromParty, ci.ToParty, ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
									FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
										INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
										INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
										INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
									WHERE ci.ChargeType = 1 AND p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98, 962)
								) r
								WHERE RowNum = 1')

		-- Deposit Licensees have setting
		SELECT @SQL = ' SELECT LicenseeId, PartyId, ParentId
						FROM OPENQUERY (DBLIC, '' 
							SELECT DISTINCT p.OldRefId AS LicenseeId, ci.FromParty AS PartyId, ci.ToParty AS ParentId
							FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
								INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
								INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
								INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
							WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98, 962)
								AND ci.ProductId IN (' + @Product3rdIds + ')
								AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + ''''''')'
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		EXEC (@SQL)
	END

	-- Get charge rate
	BEGIN
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees

		SELECT @SQL = '	SELECT ChargeId, PartyId, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.ChargeType
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
							WHERE ci.DI_Rate > 0
								AND (
									ci.ChargeType = 1
									OR ci.ChargeType = 12 AND ci.ProductId = 39 -- SAG
								)'')'
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, Product3rdId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1 AND ci.DI_Rate > 0'')'
		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)

		SELECT @SQL = '	SELECT PartyId, ProductId, ChargeType, FromDate, ToDate, Rate
						FROM OPENQUERY (DBLIC, ''SELECT DISTINCT PartyId, ProductId, ChargeType, FromDate, ToDate, CASE WHEN ProductId = 10 THEN 0 ELSE DI_Rate END AS Rate
												 FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''' + @ProductCodes + ''''', ''''OA'''')
												 WHERE DI_Rate > 0
													AND ChargeType = 1 '')'
		INSERT INTO @PartyCharge3rd (PartyId, Product3rdId, ChargeType, FromDate, ToDate, Rate)
		EXEC (@SQL)

		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.Product3rdId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #PartyChargeInfo p ON p.PartyId = p3.PartyId AND p.Product3rdId = p3.Product3rdId

		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, Product3rdId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.Product3rdId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #AllLicensees l ON p3.PartyId = l.ParentId
			INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId  AND CASE WHEN p.Product3rdId IN (0, 69) THEN 69 ELSE p.Product3rdId END = p3.Product3rdId
		WHERE NOT EXISTS (SELECT 1 FROM #PartyCharge3rdInfo rd WHERE p.PartyId = rd.PartyId AND p.Product3rdId = rd.Product3rdId)

		SELECT	@BobbetId = BobbetId , 
				@TianboId = TianboId
		FROM OPENQUERY (DBLIC,' SELECT MAX(CASE WHEN PartyName = ''Bobbet'' THEN PartyId ELSE NULL END) BobbetId,
									   MAX(CASE WHEN PartyName = ''Tianbo'' THEN PartyId ELSE NULL END) TianboId
								FROM bodb_Licensee.dbo.OAS_Party WITH (NOLOCK) WHERE PartyName IN (''Bobbet'', ''Tianbo'')'
					    )   

		-- Update charge rate for Keno, Lottery, Table Game
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
		INSERT INTO #tempVendorGlobalSetting (Bettype, ChargeRate3rd)
		SELECT Bettype, NumberValue
		FROM   OPENQUERY(DBCUST,'SELECT Bettype, NumberValue FROM CustDB.dbo.VendorGlobalSetting WITH(NOLOCK) WHERE VName LIKE ''3rdCashWLShareRate%''')
	END

	-- Get mapping site
	BEGIN
		INSERT INTO #tmpSite (LicenseeId, SiteName)
		SELECT LicenseeId, SiteName FROM OPENQUERY(DBLIC,'	SELECT LicenseeId, RTRIM(LTRIM(LicenseeName)) SiteName 
															FROM bodb_licensee.dbo.Licensees WITH(NOLOCK) 
															WHERE IsDeposit = 1')
		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM #tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))

		UPDATE l
		SET l.SiteId_DW = s.SiteId_DW
		FROM #AllLicensees l
			INNER JOIN #tmpSite s ON l.LicenseeId = s.LicenseeId
	END

	-- Get data
	BEGIN
		INSERT INTO #tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
		SELECT DISTINCT p.Product3rdId, CASE WHEN p.Product3rdId IN (0, 3) THEN 0 ELSE p.AliasProductId END, s.BetType
			,CASE
				WHEN p.Product3rdId = 34  AND s.SubProduct = 'Mini Game' THEN s.BetType -- CC (Card Club)
				WHEN s.SubProduct = 'Tips' OR (s.ProductId = 22 AND s.SubProduct = 'Blueprint') THEN 1 -- SA Gaming, VB (Macau Games)
				WHEN s.SubProduct IN ('Prize','Lucky Draw','Bonus','Promotion') THEN -4 -- BOnus, Prize
				WHEN s.SubProduct = 'Jackpot Contribution' THEN -1
				WHEN s.SubProduct = 'Jackpot Prize' THEN -999 -- Remove later
				ELSE -1 END AS BettypeGroup
			,p.IsOnlyTO
		FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
			INNER JOIN @Products p ON s.ProductId = p.ProductId
		WHERE (s.BetType NOT IN (911, 912))
			AND (
				s.ProductId <> 3
				OR (p.SubProductCode = 'NG' AND s.sporttype = 161)
				OR (p.SubProductCode = 'H5' AND s.sporttype = 164)
				OR (p.SubProductCode = 'H5LG' AND s.sporttype = 168)
			)
			AND p.SubProductCode NOT IN ('PP-JP', 'SBC-JP', 'VGA-JP','SG-JP','AGC-JP')

		INSERT INTO @ProductSupportBonus(ProductID)
		SELECT DISTINCT Product3rdId FROM #tmpBetType WHERE BettypeGroup = -4

		INSERT INTO @ProductSupportJPContrib(ProductID, Product3rdId)
		SELECT DISTINCT AliasProductId, Product3rdId  FROM #tmpBetType WHERE BettypeGroup = -999 

		INSERT INTO @ContributionBettypeList(bettype)
		SELECT DISTINCT bettype
		FROM bodb02.dbo.SportBettypeMatrix WITH(NOLOCK)
		WHERE ProductID IN (SELECT x.ProductID FROM @ProductSupportJPContrib x) AND SubProduct = 'Jackpot Contribution'

		INSERT INTO @VSProductList(ProductID)
		SELECT Product3rdId
		FROM @Product3rd WHERE ProductPrefix IN ('VS','VS2','VS3','VS4','LG')

		DELETE #tmpBetType WHERE BettypeGroup = -999

		INSERT INTO #tmpBetType (Product3rdId, AliasProductId, BetType, BettypeGroup, IsOnlyTO)
		SELECT DISTINCT p.Product3rdId, p.AliasProductId, gb.Bettype, -3 BettypeGroup, p.IsOnlyTO
		FROM @Products p
		INNER JOIN bodb02.dbo.SportBettypeMatrix gb WITH(NOLOCK) oN p.ProductId = gb.ProductID AND gb.SubProduct IN ('Jackpot Contribution','Jackpot Prize')
		WHERE p.SubProductCode IN ('PP-JP', 'VGA-JP', 'SBC-JP', 'SG-JP', 'AGC-JP')

		--- 
		IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
		BEGIN
			SELECT @FDateGetData = @FromDate,
				   @TDateGetData = DATEADD(DAY,-1,@ToDate)
		END
		ELSE 
		BEGIN
			SELECT @FDateGetData = @FromDate,
					@TDateGetData = @ToDate
		END
		-----

		-- SB
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (0, 3))
		BEGIN
			INSERT INTO #__SabaLeague (LeagueId, LeagueGroupId)
			SELECT LeagueId, LeagueGroupId FROM bodb02.dbo.League WITH (NOLOCK) WHERE sporttype IN (1, 2, 5, 50, 43) AND LeagueGroupId IN (42, 74, 108, 113, 122, 151)

			-- retrieve data yesterday if flag is turned on
			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN
				INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, MemberWL, OddsSpreadAdj, Comm, LicenseeWL, LicenseeTO, FullParlayBoostBonus, AgentParlayBoostBonusSharing)
				EXEC DBACC.bodb02.dbo.Acc_rpt_FactLADailyWinloss_Bettrans @Winlostdate = @yesterday

				DELETE t
				FROM  #__tempData t 
				WHERE t.SiteId_DW  NOT IN (SELECT SiteId_DW FROM #tmpSite)
			END

			SELECT @FromDateByBatch = @FDateGetData

			WHILE @FromDateByBatch <= @TDateGetData
			BEGIN
				SELECT @ToDateByBatch = DATEADD(DAY, 7, @FromDateByBatch)

				IF @ToDateByBatch > @TDateGetData
					SET @ToDateByBatch = @TDateGetData

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
						,-SUM(CASE WHEN ProductID = 10004 THEN 0 ELSE MemberWinloss END)  AS LicenseeWL
						,SUM(MemberTurnover  *  CASE WHEN TicketStatus = 3 OR ProductID = 10004 THEN 0 WHEN TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS LicenseeTO
						,SUM(ISNULL(MemberBonus,0)) AS FullParlayBoostBonus
						,SUM(ISNULL(AgentBonusShare,0)) AS AgentParlayBoostBonusSharing
					FROM bodb_Account.dbo.FactLADailyWinloss WITH (NOLOCK)
					WHERE rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
						AND SiteId IN (SELECT SiteId_DW FROM #tmpSite)
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
				INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, MemberWL, OddsSpreadAdj, Comm, LicenseeWL, LicenseeTO, FullParlayBoostBonus, AgentParlayBoostBonusSharing)
				SELECT t.rptDate, t.SiteId, t.CurrencyId, CASE WHEN t.ProductId = 10001 THEN 0 ELSE 3 END AS ProductId
					,CASE
						WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
						WHEN l.LeagueGroupId = 113 AND t.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN l.LeagueGroupId = 122 AND t.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -5 -- Saba Basketball
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -8 -- Saba Cricket
						WHEN l.LeagueGroupId IN (151) AND t.SportType = 43 THEN -16 -- Saba E-S PGoal
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 5 THEN -17 -- Saba Tennis
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
					,SUM(t.LicenseeWL)
					,SUM(t.LicenseeTO)
					,SUM(FullParlayBoostBonus)
					,SUM(AgentParlayBoostBonusSharing)
				FROM CTE_SB t
					LEFT JOIN #__SabaLeague l ON t.LeagueId = l.LeagueId
				GROUP BY t.rptDate, t.SiteId, t.CurrencyId, CASE WHEN t.ProductId = 10001 THEN 0 ELSE 3 END
					,CASE
						WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
						WHEN l.LeagueGroupId = 113 AND t.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN l.LeagueGroupId = 122 AND t.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -5 -- Saba Basketball
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -8 -- Saba Cricket
						WHEN l.LeagueGroupId IN (151) AND t.SportType = 43 THEN -16 -- Saba E-S PGoal
						WHEN l.LeagueGroupId IN (42) AND t.SportType = 5 THEN -17 -- Saba Tennis
						WHEN t.Sporttype = 1 THEN -2 -- Soccer
						WHEN t.Sporttype = 2 THEN -4 -- Basketball
						WHEN t.Sporttype = 5 THEN -6 -- Tennis
						WHEN t.Sporttype = 43 THEN -7 -- E-Sports
						WHEN t.Sporttype = -2 THEN -10 -- Parlay
						ELSE -9 -- OS
						END

				SELECT @FromDateByBatch = DATEADD(DAY, 1, @ToDateByBatch)
			END
		END

		-- AGC, EX
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId IN (10, 31))
		BEGIN
			SELECT @Exec_rpt_BettingByProduct = '
			SELECT rptDate, SiteId, CurrencyId, ProductId, BetTypeGroup, ValidBetAmount, MemberWL, Comm, LicenseeWL, LicensesTO, ExchangePlayerComm, HouseContribution, FullContribution
			FROM OPENQUERY (DBLIC,''	
								SELECT  t.rptDate, t.SiteId, t.CurrencyId, t.ProductId
										,BetTypeGroup	= t.bettype
										,ValidBetAmount	= SUM(t.ValidBetAmount)
										,MemberWL		= SUM(t.MemberWL)
										,Comm			= SUM(CASE WHEN t.ProductId = 31 THEN t.CommissionP + t.CommissionA ELSE 0 END)
										,LicenseeWL		= -SUM(t.MemberWL)
										,LicensesTO		= SUM(t.Turnover)
										,ExchangePlayerComm = SUM(CASE WHEN t.ProductId = 31 THEN t.CommissionP ELSE 0 END)
										,HouseContribution = 0
										,FullContribution = SUM(t.ExtraAmount)
									FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct t WITH (NOLOCK)
									--LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() u ON t.bettype = u.bettype
									WHERE t.rptDate BETWEEN ''''' + CONVERT(VARCHAR(10),@FDateGetData,120) +''''' AND ''''' + CONVERT(VARCHAR(10),@TDateGetData,120) +'''''
										AND t.ProductId IN (10, 31)
										AND t.CurrencyId <> 20
										AND t.CustomerCategory NOT IN (27, 28)
										AND t.StatusId NOT IN (-1, 101, 102, 103)
									GROUP BY t.rptDate, t.SiteId, t.CurrencyId, t.ProductId, t.bettype
								'')
			'
			INSERT INTO #__BettingByProduct (rptDate, LicenseeId, CurrencyId, Product3rdId, BetTypeGroup, ValidBetAmount, MemberWL, Comm, LicenseeWL, LicenseeTO, ExchangePlayerComm, HouseContribution, FullContribution)
			EXEC (@Exec_rpt_BettingByProduct)

			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN
				INSERT INTO #__BettingByProduct (rptDate, LicenseeId, CurrencyId, Product3rdId, BetTypeGroup, ValidBetAmount, MemberWL, Comm, LicenseeWL, LicenseeTO, ExchangePlayerComm, HouseContribution, FullContribution)
				EXEC DBEXT.bodb02.dbo.Acc_rpt_rptBettingByProduct_Bettrans @winlostdate = @yesterday
			END

			INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, BetTypeGroup, ValidBetAmount, MemberWL, Comm, LicenseeWL, LicenseeTO, ExchangePlayerComm, HouseContribution, FullContribution)
			SELECT	b.rptDate, 
					s.SiteId_DW, 
					b.CurrencyId, 
					b.Product3rdId, 
					CASE WHEN b.Product3rdId = 10 THEN 11 ELSE  ISNULL(tb.AliasProductId, b.Product3rdId) END AliasProductId, 
					ISNULL(tb.BetTypeGroup,b.BetTypeGroup) BetTypeGroup, 
					b.ValidBetAmount, 
					CASE WHEN cb.bettype IS NOT NULL THEN 0 ELSE b.MemberWL END, 
					b.Comm, 
					CASE WHEN cb.bettype IS NOT NULL THEN 0 ELSE b.LicenseeWL END, 
					CASE WHEN cb.bettype IS NOT NULL THEN 0 ELSE b.LicenseeTO END, 
					b.ExchangePlayerComm, 
					b.HouseContribution, 
					CASE WHEN cb.bettype IS NOT NULL THEN b.FullContribution ELSE 0 END
			FROM #__BettingByProduct b
				LEFT JOIN #tmpBetType tb ON b.BetTypeGroup = tb.BetType
				LEFT JOIN @ContributionBettypeList cb ON cb.BetType = tb.BetType
				INNER JOIN #tmpSite s ON b.LicenseeId = s.LicenseeId

			DROP TABLE #__BettingByProduct
		END

		-- Others
		BEGIN
			SELECT @FromDateByBatch = @FDateGetData

			WHILE @FromDateByBatch <= @TDateGetData
			BEGIN
				SELECT @ToDateByBatch = DATEADD(DAY, 7, @FromDateByBatch)

				IF @ToDateByBatch > @TDateGetData
					SET @ToDateByBatch = @TDateGetData

				INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, HouseTO, Stake, HouseContribution, FullContribution, LicenseeWL, LicenseeTO)
				SELECT b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId = 122 AND b.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN s.LeagueGroupId IN (151) AND b.SportType = 43 THEN -16 --Saba E-S PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 5 THEN -17 --Saba Tennis
						WHEN b.Sporttype = 1 THEN -2 -- Soccer
						WHEN b.Sporttype = 2 THEN -4 -- Basketball
						WHEN b.Sporttype = 5 THEN -6 -- Tennis
						WHEN b.Sporttype = 43 THEN -7 -- E-Sports
						ELSE -9 -- OS
						END AS AliasProductId
					,CASE WHEN b.SportType IN (150,173) THEN b.SportType ELSE -1 END AS SportTypeGroup
					,bt.BetTypeGroup
					,SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							WHEN bt.BetType IN (913, 914) THEN b.WinlossP + b.WinlossA
							ELSE b.WinlossP END
						) AS MemberWL
					,SUM(CASE WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
					,SUM(b.TurnoverIBC * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS HouseTO -- VarianceVR = virtualrate/actualrate - 1
					---- HouseTO change formula, will get MemberTO * ChargeRate
					,SUM(b.Stake * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS Stake -- VarianceVR = virtualrate/actualrate - 1
					,SUM(CASE WHEN bt.IsOnlyTO <> 1 AND cb.bettype IS NOT NULL THEN  b.WinlossIBC ELSE 0 END) AS HouseContribution
					,SUM(CASE WHEN bt.IsOnlyTO <> 1 AND cb.bettype IS NOT NULL THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution

					-- Licensee performance
					,-SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							ELSE b.WinlossP END
						) AS LicenseeWL
					,SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							ELSE b.Stake END *  CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS LicenseeTO
					
				FROM bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
					INNER JOIN #tmpBetType bt ON b.BetType = bt.BetType
					LEFT JOIN #__SabaLeague s ON b.LeagueId = s.LeagueId AND bt.Product3rdId = 0
					LEFT JOIN @ContributionBettypeList cb ON cb.BetType =b.BetType
				WHERE b.rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
					AND b.CurrencyId <> 20
					AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
				GROUP BY b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId = 122 AND b.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN s.LeagueGroupId IN (151) AND b.SportType = 43 THEN -16 --Saba E-S PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 5 THEN -17 --Saba Tennis
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

			IF @isGetDataFromBettrans = 1 AND @ToDate = @yesterday
			BEGIN 
				-- FactSiteWinloss
				INSERT INTO #FactSiteWinloss(RptDate,SiteID,CurrencyID,Sporttype,Bettype,LeagueID,TicketStatus,VarianceVR,TurnoverIBC,WinlossIBC,WinlossP,WinlossS,WinlossM,WinlossA,CommissionS,Stake)
				EXEC DBACC.bodb02.dbo.Acc_rpt_FactSiteWinloss_Bettrans @Winlostdate = @yesterday
			
				INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, Product3rdId, AliasProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, HouseTO, Stake, HouseContribution, FullContribution, LicenseeWL, LicenseeTO)
				SELECT b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId = 122 AND b.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN s.LeagueGroupId IN (151) AND b.SportType = 43 THEN -16 --Saba E-S PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 5 THEN -17 --Saba Tennis
						WHEN b.Sporttype = 1 THEN -2 -- Soccer
						WHEN b.Sporttype = 2 THEN -4 -- Basketball
						WHEN b.Sporttype = 5 THEN -6 -- Tennis
						WHEN b.Sporttype = 43 THEN -7 -- E-Sports
						ELSE -9 -- OS
						END AS AliasProductId
					,CASE WHEN b.SportType IN (150, 173) THEN b.SportType ELSE -1 END AS SportTypeGroup
					,bt.BetTypeGroup
					,SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							WHEN bt.BetType IN (913, 914) THEN b.WinlossP + b.WinlossA
							ELSE b.WinlossP END
						) AS MemberWL
					,SUM(CASE WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
					,SUM(b.TurnoverIBC * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS HouseTO -- VarianceVR = virtualrate/actualrate - 1
					---- HouseTO change formula, will get MemberTO * ChargeRate
					,SUM(b.Stake * CASE WHEN b.VarianceVR > 0 THEN b.VarianceVR + 1.0 ELSE 1.0 END * CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS Stake -- VarianceVR = virtualrate/actualrate - 1
					,SUM(CASE WHEN bt.IsOnlyTO <> 1 AND cb.bettype IS NOT NULL THEN b.WinlossIBC ELSE 0 END) AS HouseContribution
					,SUM(CASE WHEN bt.IsOnlyTO <> 1 AND cb.bettype IS NOT NULL THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
					-- Licensee performance
					,-SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							ELSE b.WinlossP END
						) AS LicenseeWL
					,SUM(CASE
							WHEN bt.IsOnlyTO = 1 OR cb.bettype IS NOT NULL THEN 0
							ELSE b.Stake END *  CASE WHEN b.TicketStatus = 3 THEN 0 WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1.0 END) AS LicenseeTO
				FROM #FactSiteWinloss b 
					INNER JOIN #tmpBetType bt ON b.BetType = bt.BetType
					LEFT JOIN #__SabaLeague s ON b.LeagueId = s.LeagueId AND bt.Product3rdId = 0
					LEFT JOIN @ContributionBettypeList cb ON b.BetType = cb.bettype
				WHERE b.CurrencyId <> 20
					AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
				GROUP BY b.rptDate, b.SiteId, b.CurrencyId, bt.Product3rdId
					,CASE
						WHEN bt.Product3rdId <> 0 THEN bt.AliasProductId
						WHEN bt.BetType IN (9, 29) THEN -10 -- Parlay
						WHEN s.LeagueGroupId IN (42, 74, 108) AND b.SportType = 1 THEN -3 -- Saba Soccer
						WHEN s.LeagueGroupId = 113 AND b.SportType = 1 THEN -14 --Saba Soc PGoal
						WHEN s.LeagueGroupId = 122 AND b.SportType = 2 THEN -15 --Saba Bas PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 2 THEN -5 -- Saba Basketball
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 50 THEN -8 -- Saba Cricket
						WHEN s.LeagueGroupId IN (151) AND b.SportType = 43 THEN -16 --Saba E-S PGoal
						WHEN s.LeagueGroupId IN (42) AND b.SportType = 5 THEN -17 --Saba Tennis
						WHEN b.Sporttype = 1 THEN -2 -- Soccer
						WHEN b.Sporttype = 2 THEN -4 -- Basketball
						WHEN b.Sporttype = 5 THEN -6 -- Tennis
						WHEN b.Sporttype = 43 THEN -7 -- E-Sports
						ELSE -9 -- OS
						END
					,CASE WHEN b.SportType IN (150, 173) THEN b.SportType ELSE -1 END
					,bt.BetTypeGroup

				DROP TABLE #FactSiteWinloss

			END
		END

		UPDATE v
		SET v.Product3rdId = s.Product3rdId
		FROM #tempVendorGlobalSetting v
			CROSS APPLY (SELECT TOP 1 b.Product3rdId FROM #tmpBetType b WHERE v.Bettype = b.BetType) s

		DELETE #tempVendorGlobalSetting WHERE Product3rdId IS NULL

		UPDATE v
		SET v.Bettype = -1
		FROM #tempVendorGlobalSetting v
			LEFT JOIN #tmpBetType b ON v.Bettype = b.BetTypeGroup
		WHERE b.BetTypeGroup IS NULL

		-- Process data
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
			,MemberWLDaily
			,MemberWLMonth
			,CommDaily
			,CommMonth
			,PayToSupplierDaily
			,PayToSupplierMonth
			,FullContribution
			,JackpotPrize
			,HouseTurnover
			,HouseIncomeDaily
			,HouseIncomeMonth
			,LicenseeTODaily
			,LicenseeWLDaily
			,Bonus
			,FreeBet			
			,GrossWL		
			,HouseContribution
		)
		SELECT t.rptDate, l.PartyId, t.Product3rdId, t.AliasProductId, t.SportTypeGroup
			,CurrencyId	= CASE WHEN t.Product3rdId = 10 THEN t.CurrencyId END
			,ParentId	= CASE
							WHEN t.Product3rdId IN (5, 11, 34) THEN l.PartyId
							WHEN t.Product3rdId IN (10, 22, 27) THEN l.ParentId
							WHEN t.Product3rdId IN (8, 28) THEN CASE WHEN l.PartyId = 14 THEN 1 ELSE 2 END
							WHEN t.Product3rdId = 40 THEN CASE WHEN l.PartyId = 14 THEN -1 ELSE l.ParentId END
							END
			,OriginalMemberWLDaily	= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END)
			,OriginalMemberWLMonth	= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END)
			,MemberWLDailyMonth		= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END * e.Rate)
			,MemberWLMonth			= SUM(CASE WHEN t.Product3rdId = 37 OR p.PartyId IS NOT NULL THEN t.MemberWL ELSE 0 END * e.Rate)
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
											WHEN t.Product3rdId IN (10, 34) AND t.BetTypeGroup NOT IN (-1,-4) THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(ISNULL(rd.Rate, v.ChargeRate3rd), 0) END
									+ CASE WHEN t.Product3rdId = 31 THEN CASE WHEN @FDate >= @ExchaneFomularCutoff THEN  t.ExchangePlayerComm *  ISNULL(ISNULL(rd.Rate, v.ChargeRate3rd), 0) ELSE  t.Comm END ELSE 0 END) * e.Rate)
			,PayToSupplierMonth	= SUM((t.MemberWL *
										CASE
											WHEN p.PartyId IS NULL AND (t.Product3rdId NOT IN (8, 22) OR rd.PartyId IS NULL) THEN 0
											WHEN t.Product3rdId IN (8, 28) THEN CASE
																					WHEN t.rptDate >= '2020-07-01' THEN CASE WHEN l.PartyId IN (@BobbetId, @TianboId) THEN 0.02 ELSE 0.036 END
																					WHEN l.PartyId = 14 OR @FDate >= '2018-08-01' THEN 0.03
																					ELSE 0.05 END -- KN, LT
											WHEN t.Product3rdId = 22 THEN CASE WHEN t.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END -- VB (Macau Games)
											WHEN t.Product3rdId = 27 THEN 0.065 -- VS2
											WHEN t.Product3rdId IN (10, 34) AND t.BetTypeGroup NOT IN (-1,-4) THEN ISNULL(v.ChargeRate3rd, 0)
											ELSE ISNULL(rd.Rate, 0) END
									+ CASE WHEN t.Product3rdId = 31 THEN CASE WHEN @FDate >= @ExchaneFomularCutoff THEN  t.ExchangePlayerComm *  ISNULL(ISNULL(rd.Rate, v.ChargeRate3rd), 0) ELSE  t.Comm END ELSE 0 END) * e.Rate)
			,FullContribution	= SUM(CASE WHEN t.BetTypeGroup = -3 THEN t.FullContribution ELSE 0 END * e.Rate)
			,JackpotPrize		= SUM(CASE WHEN t.BetTypeGroup = -3 THEN -t.MemberWL ELSE 0 END * e.Rate)
			,HouseTurnover		= SUM(CASE 
										WHEN p.PartyId IS NULL THEN HouseTO										
										ELSE (t.Stake * ISNULL(ISNULL(lc.Rate, p.Rate),0)) 
										END * e.Rate)
			,HouseIncomeDaily	= SUM(CASE
										WHEN t.Product3rdId IN (37, 74) THEN -t.HouseWL
										WHEN p.PartyId IS NULL THEN -t.HouseWL
										WHEN t.SportTypeGroup IN (150, 173) THEN -t.MemberWL
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) + t.FullParlayBoostBonus) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - (t.FullParlayBoostBonus - t.AgentParlayBoostBonusSharing) - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * e.Rate)
			,HouseIncomeMonth	= SUM(CASE
										WHEN t.Product3rdId IN (37, 74) THEN -t.HouseWL
										WHEN p.PartyId IS NULL THEN 0
										WHEN t.SportTypeGroup IN (150, 173) THEN -t.MemberWL
										ELSE
											(- t.MemberWL - (t.FullContribution - t.HouseContribution) + t.FullParlayBoostBonus) * ISNULL(lc.Rate, p.Rate)
											- t.HouseContribution - t.OddsSpreadAdj - (t.FullParlayBoostBonus - t.AgentParlayBoostBonusSharing) - CASE WHEN t.Product3rdId = 31 THEN t.Comm ELSE 0 END
										END * e.Rate)
			 ---- Licensee performance
			 ,LicenseeTODaily = SUM(t.LicenseeTO * e.Rate)
			 ,LicenseeWLDaily = SUM(t.LicenseeWL * e.Rate)

			 ---- Bonus
			 ,Bonus			  = SUM(CASE WHEN t.BetTypeGroup = -4 THEN -t.MemberWL ELSE 0 END * e.Rate) 

			 -- For billing SBC, PP, VGA
			 ,FreeBet = SUM(CASE WHEN t.SportTypeGroup IN (150,173) AND pj.ProductID IS NOT NULL THEN -t.MemberWL * e.Rate ELSE 0 END)
			 ,GrossWL = SUM(CASE WHEN t.SportTypeGroup = -1 AND pj.ProductID IS NOT NULL THEN (- t.MemberWL - (t.FullContribution - t.HouseContribution)) * ISNULL(lc.Rate, p.Rate) ELSE 0 END * e.Rate)
			 ,HouseContribution	= SUM(CASE WHEN t.BetTypeGroup = -3 THEN t.HouseContribution ELSE 0 END * e.Rate)

		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
			INNER JOIN @ExchangeOANDA e ON t.CurrencyId = e.ExchangeId
			LEFT JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId 
					AND p.Product3rdId =  CASE	 WHEN @FromDate > @SB_SLT_BTC_MergePerfCutoff THEN  CASE WHEN t.Product3rdId IN (0,69,63) THEN 0 ELSE t.Product3rdId END
												 WHEN @FromDate > @VSMergeSettingCutoff THEN CASE WHEN t.Product3rdId IN (5,27,49,77,83) THEN 5 ELSE t.Product3rdId END
										  ELSE   CASE WHEN t.Product3rdId IN (0,69) THEN 0 ELSE t.Product3rdId END  END
					AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = t.BetTypeGroup)
					AND (t.BetTypeGroup NOT IN (-3, -4))
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND p.ChargeType = 12)
						OR (t.Product3rdId = 15 AND p.ChargeType = 6)
						OR (t.Product3rdId <> 15 AND ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND p.ChargeType <> 12))
					)
			LEFT JOIN #PartyCharge3rdInfo rd ON rd.PartyId = l.PartyId AND rd.Product3rdId = t.Product3rdId AND t.rptDate BETWEEN rd.FromDate AND rd.ToDate
					AND (
						(t.Product3rdId IN (11, 39) AND t.BetTypeGroup <> -1 AND rd.ChargeType = 12)
						OR ((t.Product3rdId NOT IN (11, 39) OR t.BetTypeGroup = -1) AND rd.ChargeType <> 12)
					) AND t.BetTypeGroup NOT IN (-4)
			LEFT JOIN #tempVendorGlobalSetting v ON v.Product3rdId = t.Product3rdId AND v.Bettype = t.BetTypeGroup
			LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
			LEFT JOIN @ProductSupportJPContrib pj ON t.Product3rdId = pj.Product3rdId
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
		-- 1. NG, YOLO, 
		UPDATE #__tempResult
		SET PayToSupplierDaily = CASE WHEN Product3rdId = 2 THEN -0.5 * HouseIncomeDaily
									WHEN Product3rdId = 84 THEN -0.4 * HouseIncomeDaily END, 
			PayToSupplierMonth = CASE WHEN Product3rdId = 2 THEN -0.5 * HouseIncomeMonth
									WHEN Product3rdId = 84 THEN -0.4 * HouseIncomeMonth END
		WHERE Product3rdId IN ( 2, 84) -- NG, YOLO

		-- 2. AGC
		;WITH CTE_Sum AS
		(
			SELECT ParentId, Product3rdId
				,CASE WHEN @FromDate >= @AGCPaytoSuplierCutoff THEN 0.07 ELSE CASE WHEN LicenseeWLDaily <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END END AS RateDaily
				,CASE WHEN @FromDate >= @AGCPaytoSuplierCutoff THEN 0.07 ELSE CASE WHEN LicenseeWLMonth <= CASE WHEN ParentId = 1 THEN 15000000 ELSE 2500000 END THEN 0.08 ELSE 0.07 END END AS RateMonth
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
		SET r.PayToSupplierDaily = r.MemberWLDaily * s.RateDaily - r.Bonus, r.PayToSupplierMonth = r.MemberWLMonth * s.RateMonth - r.Bonus
		FROM #__tempResult r
			INNER JOIN CTE_Sum s ON r.ParentId = s.ParentId
		WHERE r.Product3rdId = 10

	END

	-- Licensee Min Fee
	BEGIN
		DECLARE @PartyIds_AlekGroup VARCHAR(200), @isRecalRebate BIT = 0, @RecalRebateEffectiveFrom DATETIME , @RecalRebateEffectiveTo DATETIME

		SELECT @PartyIds_AlekGroup = STRING_AGG(CONVERT(VARCHAR(50), op.PartyID), ',')
		FROM DBLIC.bodb_licensee.dbo.OAS_Party op WITH(NOLOCK)
		INNER JOIN (
			SELECT CAST(value AS INT ) AS PartyID FROM STRING_SPLIT(@PartyIds, ',')
		) x ON op.PartyID = x.PartyID
		WHERE op.PartyName IN ('BigGaming','HuangMa','BGCV','VNS888')

		IF @PartyIds_AlekGroup IS NOT NULL
			SELECT @isRecalRebate = 1

		IF @isRecalRebate = 1
			SELECT @RecalRebateEffectiveFrom = '2023-08-01', @RecalRebateEffectiveTo = '2024-08-01'
		
		INSERT INTO @LicenseeFeeAndRebateDiscount
		(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC DBLIC.bodb_licensee.dbo.LA_AmountToCompanyByProduct
			@PartyIds				= @PartyIds
			,@ProductCodes			= @SupportedProductList
			,@Currencies			= ''
			,@FromDate				= @FDate
			,@ToDate				= @TDate
			,@IsConvertExRate		= 1
			,@LicensingFeeTypeIds	= '0,12' -- 12: Parlay Boost Bonus
			,@BaseCurrencyName		= @BaseCurrencyName

		IF @isRecalRebate =1 AND @FromDate BETWEEN @RecalRebateEffectiveFrom AND @RecalRebateEffectiveTo AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@SupportedProductList,',') WHERE value = 'SB')
		BEGIN
			DECLARE @Result_OldSetting TABLE
			(
				PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
				,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
				,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
			)
			INSERT INTO @Result_OldSetting
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC DBLIC.bodb_Licensee.dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds_AlekGroup
				,@ProductCodes = 'SB'
				,@FromDate = @FDate
				,@ToDate = @TDate
				,@BaseCurrencyName = @BaseCurrencyName
				,@IsUsePreviousSetting = 1

			IF EXISTS (SELECT TOP 1 1 FROM @Result_OldSetting) 
			BEGIN
				UPDATE r
				SET r.Rebate = ri.Rebate
				FROM @LicenseeFeeAndRebateDiscount r
				INNER JOIN @Result_OldSetting ri ON r.PartyId = ri.PartyId AND r.ProductId = ri.ProductId AND ri.LicensingFeeTypeId = 0
				WHERE r.LicensingFeeTypeId = 0 AND r.PartyId IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds_AlekGroup,','))
				 
				DELETE FROM @Result_OldSetting
			END
		END

		;WITH ReCalHouseIncome42_32_66_36 AS
		(
			SELECT  t.PartyId,
					t.Product3rdId,
					t.AliasProductId,
					FreeBet = SUM(FreeBet),
					GrossWL = SUM(GrossWL),
					FullContribution = SUM(FullContribution),
					HouseContribution = SUM(HouseContribution)
			FROM #__tempResult t
			WHERE t.Product3rdId IN (SELECT x.Product3rdId FROM @ProductSupportJPContrib x)
			GROUP BY t.PartyId, t.Product3rdId, t.AliasProductId
		),
		FinalHouseIncome42_32_66_36 AS
		(
			SELECT  t.PartyId, t.Product3rdId, t.AliasProductId, 
					 CASE WHEN t.GrossWL < 0 THEN 0 ELSE  t.GrossWL END - HouseContribution + FreeBet AS HouseIncome
			FROM	 ReCalHouseIncome42_32_66_36 t
		), CTE_tempResult AS (
			SELECT PartyId, Product3rdId, CASE WHEN Product3rdId IN (0,69) THEN -2 ELSE AliasProductId END AS AliasProductId
				,HouseTurnover	= SUM(HouseTurnover)
				,LicenseeWL		= SUM(CASE WHEN SporttypeGroup IN (150, 173) THEN 0 ELSE -MemberWLMonth END)
				,HouseIncome	= SUM(HouseIncomeMonth)
				,AComm			= SUM(CommMonth)
		
			FROM #__tempResult
			GROUP BY PartyId, Product3rdId, CASE WHEN Product3rdId IN (0,69) THEN -2 ELSE AliasProductId END
		), CTE_Result AS (
			SELECT
				PartyId = ISNULL(t.PartyId, m.PartyId)
				,Product3rdId = ISNULL(t.Product3rdId, m.ProductId)
				,AliasProductId = ISNULL(t.AliasProductId, CASE WHEN ISNULL(t.Product3rdId, m.ProductId) = 0 THEN -2  WHEN ISNULL(t.Product3rdId, m.ProductId) = 2 THEN -11  ELSE m.ProductId END)
				,HouseTurnover = ISNULL(t.HouseTurnover, 0)
				,LicenseeWL = ISNULL(t.LicenseeWL, 0)
				,HouseIncome = CASE WHEN t.Product3rdId IN (SELECT x.ProductID FROM @ProductSupportJPContrib x) THEN ISNULL(f.HouseIncome,0) ELSE ISNULL(t.HouseIncome, 0) END
				,AComm = ISNULL(t.AComm, 0)

			FROM CTE_tempResult t
				FULL OUTER JOIN @LicenseeFeeAndRebateDiscount m ON t.PartyId = m.PartyId AND t.Product3rdId = m.ProductId	AND m.LicensingFeeTypeId = 0	
				LEFT JOIN	FinalHouseIncome42_32_66_36 f ON t.PartyId = f.PartyId AND t.Product3rdId = f.Product3rdId AND t.AliasProductId = f.AliasProductId
		)
		INSERT INTO #tmpResult (PartyId, Product3rdId, AliasProductId, HouseTurnover, LicenseeWL, HouseIncome, AComm)
		SELECT r.PartyId, r.Product3rdId, r.AliasProductId, r.HouseTurnover, r.LicenseeWL, r.HouseIncome, r.AComm
		FROM CTE_Result r
			INNER JOIN (SELECT DISTINCT PartyId, Product3rdId FROM #PartyChargeInfo) p ON p.PartyId = r.PartyId AND p.Product3rdId = r.Product3rdId
		UNION 
		SELECT r.PartyId, r.Product3rdId, r.AliasProductId, r.HouseTurnover, r.LicenseeWL, r.HouseIncome, r.AComm
		FROM CTE_Result r
		WHERE  (r.Product3rdId = 0 AND r.PartyId  NOT IN (SELECT p.PartyId FROM #PartyChargeInfo p WHERE p.Product3rdId = 0)  )
				OR r.Product3rdId = 37
		 
		UPDATE s
		SET s.LicenseeMinFee	= CASE WHEN m.PartyId IS NULL OR m.ProductId <> 0 THEN 0 
									   ELSE CASE WHEN m.IsChargedByGroupMinFee = 1 OR m.IsChargedByMinFee = 1 THEN m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0)) ELSE 0 END 
								  END
			,s.LicenseeFee		= CASE
									WHEN m.PartyId IS NULL OR m.ProductId NOT IN (0,37) THEN s.HouseIncome
									ELSE CASE WHEN m.IsChargedByGroupMinFee = 0 AND m.IsChargedByMinFee = 0 THEN CASE WHEN m.ProductId = 37 THEN - (m.LicensingFee+ m.ExtraAmount)  ELSE m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0)) END ELSE 0 END
								  END
			,s.Rebate			= ISNULL(m.Rebate, 0)
			,s.Discount			= ISNULL(m.Discount, 0)
		FROM #tmpResult s
			LEFT JOIN @LicenseeFeeAndRebateDiscount m ON m.PartyId = s.PartyId AND m.ProductId = s.Product3rdId AND m.LicensingFeeTypeId = 0
			LEFT JOIN @LicenseeFeeAndRebateDiscount m12 ON m12.PartyId = s.PartyId AND m12.ProductId = s.Product3rdId AND m12.LicensingFeeTypeId = 12

		/*
			GET 9w licensee list
		*/
		INSERT INTO @9wLicenseeList (PartyId)
		SELECT PartyId FROM OPENQUERY(DBLIC, 'SELECT PartyId FROM bodb_licensee.dbo.LA_f_JVPartyListSel()')

		-- Check LicenseeWL > 0
		-- NG include all sports as H5, H5LG
		IF EXISTS (SELECT 1 FROM #tmpResult WHERE Product3rdId = 2)
			UPDATE t
			SET t.LicenseeFee = 0
			FROM #tmpResult t
				INNER JOIN (SELECT PartyId FROM #tmpResult WHERE Product3rdId = 2 GROUP BY PartyId HAVING SUM(LicenseeFee) < 0) r ON t.PartyId = r.PartyId
			WHERE t.Product3rdId = 2 AND  t.PartyId NOT IN (SELECT p.PartyId FROM @9wLicenseeList p)

		UPDATE r
		SET r.HouseIncome = CASE  WHEN ( r.Product3rdId IN (SELECT z.ProductID FROM @VSProductList z) AND @FromDate >= @VSMergeSettingCutoff) THEN r.HouseIncome
								WHEN r.HouseIncome > 0 THEN r.HouseIncome ELSE 0 END
			,r.LicenseeFee = CASE
						WHEN r.Product3rdId IN (3,31,37,74) 
							OR r.Product3rdId IN (SELECT x.ProductID FROM @ProductSupportJPContrib x) 
							OR ( r.Product3rdId IN (SELECT z.ProductID FROM @VSProductList z) AND @FromDate >= @VSMergeSettingCutoff)
							THEN LicenseeFee
						WHEN r.LicenseeFee > 0 THEN r.LicenseeFee ELSE 0 END
		FROM #tmpResult r
		WHERE r.Product3rdId <> 2
			AND (
				r.Product3rdId IN (3,31,37,74) -- BA, Cashout 
				OR r.Product3rdId IN (SELECT x.ProductID FROM @ProductSupportJPContrib x)
				OR r.PartyId NOT IN (SELECT p.PartyId FROM @9wLicenseeList p)
				OR ( r.Product3rdId IN (SELECT z.ProductID FROM @VSProductList z) AND @FromDate >= @VSMergeSettingCutoff)
			)

		-- Handle VS product performance after cutoff date
		IF @FromDate >= @VSMergeSettingCutoff
		BEGIN
			;WITH t AS
			(
				SELECT PartyId, SUM(LicenseeFee) TotalLicenseeFee FROM #tmpResult tmp
				INNER JOIN @VSProductList vs ON vs.ProductID = tmp.Product3rdId
				GROUP BY PartyId
			)UPDATE r
			SET r.HouseIncome = 0, r.LicenseeFee = 0
			FROM #tmpResult r
			INNER JOIN t ON r.PartyId = t.PartyId
			WHERE t.TotalLicenseeFee < 0  AND r.Product3rdId IN (SELECT z.ProductID FROM @VSProductList z)

		END

		-- Handle Bitcoin, SLT (Cutoff 2021-11-30)
		;WITH btc_partyList AS
		(
			SELECT PartyId, LicenseeFee
			FROM #tmpResult WHERE Product3rdId = 0 AND AliasProductId = -2 AND LicenseeFee <> 0
		)
		INSERT INTO @BTC_data(PartyId, Product3rdId, AliasProductId, HouseTurnover, LicenseeFee)
		SELECT PartyId, Product3rdId, AliasProductId
			,HouseTurnover	= SUM(HouseTurnover)
			,LicenseeFee	= SUM(HouseIncomeMonth)
		
		FROM #__tempResult t
		WHERE Product3rdId  = 69 AND PartyId IN (SELECT x.PartyId FROM btc_partyList x)
		GROUP BY PartyId, Product3rdId, AliasProductId 

		-- Add PartyID have SB LicenseeFee <> 0 AND Have data BTC
		;MERGE #tmpResult AS s
		USING @BTC_data AS t ON s.Product3rdId = t.Product3rdId AND s.AliasProductId = t.AliasProductId AND s.PartyId = t.PartyId
		WHEN MATCHED THEN UPDATE
			SET s.HouseTurnover = t.HouseTurnover,
				s.LicenseeFee = t.LicenseeFee
		WHEN NOT MATCHED THEN INSERT
			(PartyId, Product3rdId, AliasProductId, HouseTurnover, LicenseeFee)
			VALUES
			(t.PartyId, t.Product3rdId, t.AliasProductId, t.HouseTurnover, t.LicenseeFee);

		UPDATE  t
		SET  t.LicenseeFee = t.LicenseeFee - u.LicenseeFee,
			 t.HouseTurnover = t.HouseTurnover - u.HouseTurnover
		FROM #tmpResult t
		INNER JOIN @BTC_data u ON t.PartyId = u.PartyId
		WHERE t.Product3rdId = 0 AND t.AliasProductId = -2
		
		-- SLT
		IF @FromDate > @SB_SLT_BTC_MergePerfCutoff
		BEGIN
			DELETE #tmpResult WHERE Product3rdId = 63

			;WITH slt_partyList AS
			(
				SELECT PartyId, LicenseeFee
				FROM #tmpResult WHERE Product3rdId = 0 AND AliasProductId = -2 AND LicenseeFee <> 0
			)
			INSERT INTO @SLT_data(PartyId, Product3rdId, AliasProductId, HouseTurnover, LicenseeFee)
			SELECT PartyId, Product3rdId, AliasProductId
				,HouseTurnover	= SUM(HouseTurnover)
				,LicenseeFee	= SUM(HouseIncomeMonth)
		
			FROM #__tempResult t
			WHERE Product3rdId  = 63 AND PartyId IN (SELECT x.PartyId FROM  slt_partyList x)
			GROUP BY PartyId, Product3rdId, AliasProductId 

			-- Add PartyID have SB LicenseeFee <> 0 AND Have data BTC
			;MERGE #tmpResult AS s
			USING @SLT_data AS t ON s.Product3rdId = t.Product3rdId AND s.AliasProductId = t.AliasProductId AND s.PartyId = t.PartyId
			WHEN MATCHED THEN UPDATE
				SET s.HouseTurnover = t.HouseTurnover,
					s.LicenseeFee = t.LicenseeFee
			WHEN NOT MATCHED THEN INSERT
				(PartyId, Product3rdId, AliasProductId, HouseTurnover, LicenseeFee)
				VALUES
				(t.PartyId, t.Product3rdId, t.AliasProductId, t.HouseTurnover, t.LicenseeFee);

			UPDATE  t
			SET  t.LicenseeFee = t.LicenseeFee - u.LicenseeFee,
					t.HouseTurnover = t.HouseTurnover - u.HouseTurnover
			FROM #tmpResult t
			INNER JOIN @SLT_data u ON t.PartyId = u.PartyId
			WHERE t.Product3rdId = 0 AND t.AliasProductId = -2
		END
	END
	-- Calculate result
	DELETE @Products WHERE Product3rdId = 3 -- BA

    SELECT  @BAComm = -SUM(AComm), @BAWinloss = SUM(LicenseeFee) FROM #tmpResult WHERE Product3rdId = 3
	SELECT  @BAComm = ISNULL(@BAComm, 0), @BAWinloss = ISNULL(@BAWinloss, 0)

	DELETE #tmpResult WHERE Product3rdId = 3
	UPDATE #__tempResult SET Product3rdId = 0 WHERE Product3rdId = 3

	-- Daily
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, BAComm, PayToSupplier, FullContribution, JackpotPrize, HouseTurnover, HouseIncome, LicenseeTO_licperf, LicenseeWL_licperf, Bonus)
	SELECT CONVERT(VARCHAR(2), rptDate, 106), Product3rdId, AliasProductId, -SUM(CommDaily), SUM(PayToSupplierDaily), SUM(FullContribution), SUM(JackpotPrize), SUM(HouseTurnover), SUM(HouseIncomeDaily), SUM(LicenseeTODaily), SUM(LicenseeWLDaily), SUM(Bonus)
	FROM #__tempResult
	GROUP BY CONVERT(VARCHAR(2), rptDate, 106), Product3rdId, AliasProductId

	UPDATE #Result
	SET PayToSupplier = PayToSupplier - Bonus
	WHERE  Product3rdId = 34

	-- MTD (month-to-date)
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, BAComm, PayToSupplier, FullContribution, JackpotPrize, HouseTurnover, HouseIncome, LicenseeTO_licperf, LicenseeWL_licperf, Bonus)
	SELECT 'MTD', Product3rdId, AliasProductId, SUM(BAComm), SUM(PayToSupplier), SUM(FullContribution), SUM(JackpotPrize), SUM(HouseTurnover), SUM(HouseIncome), SUM(LicenseeTO_licperf), SUM(LicenseeWL_licperf), SUM(Bonus)
	FROM #Result
	GROUP BY Product3rdId, AliasProductId

	-- Monthly
	INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, HouseTurnover, HouseIncome, MinFee, Discount, Rebate)
	SELECT 'Monthly', Product3rdId, AliasProductId, SUM(HouseTurnover), SUM(LicenseeFee), SUM(LicenseeMinFee), SUM(Discount), SUM(Rebate)
	FROM #tmpResult
	GROUP BY Product3rdId, AliasProductId

	--- Get PayToSupplier For CC
	SELECT @CC_PayToSupplier = SUM (-t.Bonus + t.PayToSupplierMonth), @CC_Bonus = SUM(t.Bonus)
	FROM #tmpResult x 
	CROSS APPLY (SELECT SUM(t.Bonus) AS Bonus, SUM(PayToSupplierMonth) PayToSupplierMonth
						FROM #__tempResult t WHERE t.PartyId = x.PartyId AND t.Product3rdId = x.Product3rdId) t
	WHERE x.Product3rdId = 34

	UPDATE #Result
	SET PayToSupplier = @CC_PayToSupplier, Bonus = @CC_Bonus
	WHERE rptDate = 'Monthly'  AND  Product3rdId = 34

	--- END PayToSupplier For CC

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
	
	IF @IsLicPerf = 0 
	BEGIN
		UPDATE #Result SET HouseIncome = HouseIncome + @BAWinloss, BAComm = @BAComm WHERE Product3rdId = 0 AND AliasProductId = -2 AND rptDate = 'Monthly'
	END

	-- Update bonus for monthly fomular
	UPDATE r
	SET r.Bonus = ISNULL(m.Bonus, 0)
	FROM #Result r
		INNER JOIN #Result m ON m.Product3rdId = r.Product3rdId AND m.AliasProductId = r.AliasProductId AND r.rptDate = 'Monthly' AND m.rptDate = 'MTD'
	WHERE r.Product3rdId IN (SELECT x.productID FROM @ProductSupportBonus x WHERE x.ProductID <> 34)

	-- Update Monthly AGC Contribution, Jackpot
	UPDATE r
	SET r.FullContribution = ISNULL(m.FullContribution, 0),
	    r.JackpotPrize = ISNULL(m.JackpotPrize, 0)
	FROM #Result r
		INNER JOIN #Result m ON m.Product3rdId = r.Product3rdId AND m.AliasProductId = r.AliasProductId AND r.rptDate = 'Monthly' AND m.rptDate = 'MTD'
	WHERE r.Product3rdId = 10

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
	WHERE ( r.Product3rdId IN (10, 22)  OR  r.Product3rdId IN (SELECT z.ProductID FROM @VSProductList z))
		AND rptDate = 'Monthly'
		
	-- 1.2 Pay to supplier month
	UPDATE r
	SET r.PayToSupplier = ISNULL(t.PayToSupplier, 0)
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(t.PayToSupplierMonth) AS PayToSupplier, SUM(t.Bonus) AS Bonus
			FROM #__tempResult t
			WHERE t.Product3rdId = r.Product3rdId AND t.AliasProductId = r.AliasProductId
		) t
	WHERE r.Product3rdId NOT IN (10, 22, 34) 
	    AND r.Product3rdId NOT IN (SELECT z.ProductID FROM @VSProductList z)
		AND rptDate = 'Monthly'

	-- 1.4 FullContribution, JackpotPrize
	UPDATE r
	SET r.FullContribution = ISNULL(m.FullContribution, 0), r.JackpotPrize = ISNULL(m.JackpotPrize, 0)
	FROM #Result r
		INNER JOIN #Result m ON m.Product3rdId = r.Product3rdId AND m.AliasProductId = r.AliasProductId AND r.rptDate = 'Monthly' AND m.rptDate = 'MTD'
	WHERE r.Product3rdId IN (SELECT x.ProductID FROM @ProductSupportJPContrib x)

	-- 1.5 Bonus
	UPDATE r
	SET r.HouseIncome = r.HouseIncome + ISNULL(r.Bonus,0) ,
		r.PayToSupplier = r.PayToSupplier - CASE WHEN r.Product3rdId IN (10, 34) THEN 0 ELSE  ISNULL(r.Bonus,0)  END
	FROM #Result r
	WHERE r.Product3rdId IN (SELECT x.ProductID FROM @ProductSupportBonus x)

	IF @IsLicperf = 1
	BEGIN

		INSERT INTO #Result (rptDate, Product3rdId, AliasProductId, LicenseeWL_licperf, LicenseeTO_licperf, HouseIncome)
		SELECT rptDate, Product3rdId, -AliasProductId, JackpotPrize , 0, FullContribution + JackpotPrize FROM #Result 
		WHERE Product3rdId IN (SELECT x.ProductID FROM @ProductSupportJPContrib x) AND  rptDate = 'Monthly'

		-- HouseIncome Include LicenseeMinFee,Rebate,Discount except SB
		UPDATE	t
		SET		t.HouseIncome = ISNULL(t.HouseIncome,0) 
								+ CASE WHEN rb.AliasProductID IS NOT NULL THEN ISNULL(-t.Rebate,0) ELSE 0 END
								+ CASE WHEN dc.AliasProductID IS NOT NULL THEN ISNULL(-t.Discount,0) ELSE 0 END

		FROM	#Result t
		LEFT JOIN bodb_Account.dbo.HNISettings rb WITH (NOLOCK) ON  rb.AliasProductID = t.AliasProductId AND  rb.isDeposit = 1 and rb.LogicCode = 2 AND rb.SubFigure = 'Rebate'
		LEFT JOIN bodb_Account.dbo.HNISettings dc WITH (NOLOCK) ON  dc.AliasProductID = t.AliasProductId AND  dc.isDeposit = 1 and dc.LogicCode = 2 AND dc.SubFigure = 'Discount'
		WHERE (t.Product3rdId <> 0 AND t.Product3rdId NOT IN (SELECT x.ProductID FROM @ProductSupportJPContrib x)) AND t.rptDate = 'Monthly'
		-- END

		-- HouseIncome Include LicenseeMinFee,Rebate,Discount calculated in Real Soccer 
		-- Remaining Sports include LicenseeWL * ChargeRate Only (Force 0 If PartyId have LicenseeMinFee > 0)
		SELECT @SB_HouseIncome_total = ISNULL(HouseIncome,0) + ISNULL(MinFee,0) - ISNULL(Discount,0) - ISNULL(Rebate,0)
		FROM #Result WHERE Product3rdId =0 AND AliasProductId = -2 AND rptDate = 'Monthly'

		INSERT INTO @tmpResult_licperf(PartyId,Product3rdId,AliasProductId)
		SELECT PartyId,Product3rdId,AliasProductId
		FROM #tmpResult WHERE Product3rdId  = 0 AND AliasProductId = -2 AND ISNULL(LicenseeMinFee,0) = 0 AND ISNULL(LicenseeFee,0) <> 0
		
		;WITH t AS
		(
			SELECT PartyId, Product3rdId, AliasProductId, HouseIncomeMonth FROM #__tempResult WHERE Product3rdId = 0
		)INSERT INTO @SBGrossHouseIncome (Product3rdId, AliasProductId, HouseIncome)
		SELECT  t.Product3rdId, t.AliasProductId, SUM(t.HouseIncomeMonth)
		FROM	t 
		INNER JOIN @tmpResult_licperf tr ON t.PartyId = tr.PartyId AND t.Product3rdId = tr.Product3rdId
		WHERE t.AliasProductId <> - 2 AND t.Product3rdId = 0
		GROUP BY t.Product3rdId, t.AliasProductId

		;MERGE #Result AS t
		USING @SBGrossHouseIncome AS s ON t.Product3rdId = s.Product3rdId AND t.AliasProductId = s.AliasProductId AND t.rptDate = 'Monthly'
		WHEN MATCHED THEN UPDATE
			SET HouseIncome = s.HouseIncome
		WHEN NOT MATCHED THEN
		INSERT
		(
			rptDate, Product3rdId, AliasProductId, HouseIncome
		)
		VALUES
		(
			'Monthly', s.Product3rdId, s.AliasProductId, s.HouseIncome
		);


		--- Force remaining fee to real soc
		SELECT @SBHouseIncomeOthers = SUM(ISNULL(HouseIncome,0))
		FROM #Result 
		WHERE rptDate = 'Monthly' AND AliasProductId <> -2 AND Product3rdId = 0

		SELECT @SBHouseIncomeRealSoc = @SB_HouseIncome_total - @SBHouseIncomeOthers

		UPDATE #Result 
		SET HouseIncome = @SBHouseIncomeRealSoc
		WHERE rptDate = 'Monthly' AND AliasProductId = -2 AND Product3rdId = 0

		SET @SQL_licperf = '
			(
				SELECT  isDePosit, OrderByProduct, OrderByFigure +1 AS OrderByFigure, ProductID, CASE WHEN ProductPrefix IN (''PP-JP'',''SBC-JP'',''VGA-JP'',''SG-JP'',''AGC-JP'') THEN -AliasProductID ELSE AliasProductID END AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName  
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
					FROM	bodb_Account.dbo.HNISettings s WITH (NOLOCK)
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

				UNION ALL
				SELECT	s.isDePosit, s.OrderByProduct, s.OrderByFigure, s.ProductID, -s.AliasProductID, s.ProductPrefix, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName  
						,''Licensee House Income'' Figure, ''Licensee House Income'' SubFigure, s.isTest, s.isEnable, s.EndOfSupportDate, s.LogicCode, s.LogicDescription 	  
				FROM	bodb_Account.dbo.HNISettings s WITH (NOLOCK) WHERE isDeposit = 1 and LogicCode = 2	and ProductPrefix IN (''PP-JP'',''SBC-JP'',''VGA-JP'',''SG-JP'',''AGC-JP'') AND s.Figure = ''Jackpot Prize''
			) s
		'
	END

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT Product3rdId, AliasProductId, Figure, SubFigure, ISNULL(Monthly, 0) AS Monthly, MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31]
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
				UNION ALL SELECT LicenseeTO_licperf, ''Licensee Turnover'', ''Licensee Turnover''
				UNION ALL SELECT LicenseeWL_licperf, ''Licensee Winloss'', ''Licensee Winloss''
				'
				ELSE '' END
				+ '
			) f
		) t
		PIVOT (
			MAX(Value)
			FOR rptDate IN (Monthly, MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31])
		) p
	)
	SELECT DISTINCT s.isDeposit, s.OrderByProduct, s.OrderByFigure, ''Licensee'' AS SiteGroup, s.ProductCategory, s.ProductGroup, s.ProductName, s.ProductShortName, s.Figure, s.SubFigure, r.Monthly, r.MTD, [01],[02],[03],[04],[05],[06],[07],[08],[09],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31]
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

	DROP TABLE #tmpSite
	DROP TABLE #tmpBetType
	DROP TABLE #__tempData
	DROP TABLE #__tempResult
	DROP TABLE #tmpResult
	DROP TABLE #AllLicensees
	DROP TABLE #Licensees
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #PartyChargeInfo
	DROP TABLE #tempVendorGlobalSetting
	DROP TABLE #__SabaLeague
	DROP TABLE #Result
END


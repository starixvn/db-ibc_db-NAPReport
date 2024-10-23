/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Reconciliation]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*
	Created: 20210129@Percy
	DB: DBWH-bodb_dwrs
	Task: Auto mail - Licensee Sportsbook Data
	
	Revisions:
		- 20210129@Percy: Initiliaze SP [RedmineID: #148805]
		- 20210708@Danny: Handle JV parties (#158191)
		- 20210706@Danny: Change HouseIncome calculation formula (#157953)
		- 20210830@Danny: Integrate Bitcoin Product (#159045)
		- 20211125@Danny: Add BA information (#165135)
		- 20210917@Danny: Prorated minfee for the group min fee (#160737)
		- 20230425@Danny: SP LA_AmountToCompanyByProduct return Discount Rate ExtraInfo (#169160)
		- 20230821@Danny: Integrate Parlay Boost Bonus (#192894)
		- 20241003@Danny: Move Acc_Licensee_HousePT to DBCUST (#208100)
*/
BEGIN
	SET NOCOUNT ON

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
		
	DECLARE @PartyIds VARCHAR(MAX), @Discount_PartyIds VARCHAR(MAX)

	-- Get Exchange
	BEGIN
		-- Daily System Rate
		CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
		INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @FromExDate AND @ToExDate

		-- Oanda Rate
		DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		SELECT  @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate
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
								AND ci.ProductId = 0
								AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + ''''''')'
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		EXEC (@SQL)
	END

	-- Get charge rate
	BEGIN
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees

		CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
		SELECT @SQL = '	SELECT ChargeId, PartyId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.ChargeType
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
							WHERE ci.DI_Rate > 0
								AND ci.ChargeType = 1
								AND ci.ProductId = 0'')'
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)
		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1 AND ci.DI_Rate > 0'')'
		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)


	END

	-- Get mapping site
	BEGIN
		CREATE TABLE #__tmpSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO #__tmpSite (LicenseeId, SiteName)
		SELECT LicenseeId, RTRIM(LTRIM(LicenseeName)) FROM DBLIC.bodb_licensee.dbo.Licensees WITH (NOLOCK) WHERE IsDeposit = 1

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM #__tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))

		UPDATE l
		SET l.SiteId_DW = s.SiteId_DW
		FROM #AllLicensees l
			INNER JOIN #__tmpSite s ON l.LicenseeId = s.LicenseeId
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData (rptDate DATE, ProductID INT ,SiteId_DW INT, CurrencyId INT, MemberWL MONEY, AgentWL MONEY, AgentComm MONEY, OddsSpreadAdj MONEY)
		CREATE CLUSTERED INDEX CIX_tempData ON #__tempData (SiteId_DW, rptDate, ProductID)

		SELECT @FromDateByBatch = @FDate

		WHILE @FromDateByBatch <= @TDate
		BEGIN
			SELECT @ToDateByBatch = DATEADD(DAY, 15, @FromDateByBatch)

			IF @ToDateByBatch > @TDate
				SET @ToDateByBatch = @TDate
		
			INSERT INTO #__tempData (rptDate, ProductID, SiteId_DW, CurrencyId, MemberWL, AgentWL, AgentComm, OddsSpreadAdj)
			SELECT rptDate
				,ProductId
				,SiteId
				,CurrencyId
				,SUM(MemberWinloss) AS MemberWL
				,SUM(AgentWinloss)	AS AgentWL
				,SUM(AgentComm)		AS AgentComm
				,SUM(CASE WHEN bettype = 999 THEN AgentWinloss ELSE 0 END) AS OddsSpreadAdj
			FROM bodb_Account.dbo.FactLADailyWinloss WITH (NOLOCK)
			WHERE rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
				AND SiteId IN (SELECT SiteId_DW FROM #__tmpSite)
				AND ProductId IN (10001, 10070, 10004) -- SB only And Bitcoin And BA
				AND Bettype NOT IN (901, 902, 903, 904)
				AND CurrencyId <> 20
				AND TicketStatus NOT IN (-1, 18, 9, 10, 14)
			GROUP BY rptDate, SiteId, CurrencyId, ProductId
			OPTION (RECOMPILE)

			SELECT @FromDateByBatch = DATEADD(DAY, 1, @ToDateByBatch)
		END

		-- Process data
		CREATE TABLE #__tempResult (
			rptDate DATETIME
			,PartyId INT
			-- SystemRate
			,MemberWL_e MONEY
			,AgentWL_e MONEY
			,AgentComm_e MONEY
			,HouseWL_e MONEY
			,HouseIncome_e MONEY
			-- Oanda Rate
			,MemberWL_oa MONEY
			,AgentWL_oa MONEY
			,AgentComm_oa MONEY
			,HouseWL_oa MONEY
			,HouseIncome_oa MONEY
		)
		CREATE CLUSTERED INDEX CIX_tempResult ON #__tempResult (PartyId, rptDate)

		CREATE TABLE #__tempResult_BA (
			rptDate DATETIME
			,PartyId INT
			-- SystemRate
			,BAWinLoss_e MONEY
			,BAComm_e	MONEY
			-- Oanda Rate
			,BAWinLoss_oa MONEY
			,BAComm_oa	MONEY
		)
		CREATE CLUSTERED INDEX CIX_tempResult_BA ON #__tempResult_BA (PartyId, rptDate)

		CREATE TABLE #__tempResult_BTC (
			
			PartyId INT,
			HouseIncome_e MONEY,
			HouseIncome_oa MONEY
		)
		CREATE CLUSTERED INDEX CIX_tempResult_BTC ON #__tempResult_BTC (PartyId)

		INSERT INTO #__tempResult_BTC(PartyId, HouseIncome_e, HouseIncome_oa)
		SELECT 	l.PartyId
				,HouseIncome_e	= SUM(((- t.MemberWL) * ISNULL(lc.Rate, p.Rate)) * e.Rate)
				,HouseIncome_oa = SUM(((- t.MemberWL) * ISNULL(lc.Rate, p.Rate)) * oa.Rate)
		FROM	#__tempData t
		INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
		INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
		INNER JOIN @ExchangeOANDA oa ON t.CurrencyId = oa.ExchangeId
		WHERE t.ProductID = 10070
		GROUP BY l.PartyId

		INSERT INTO #__tempResult (	rptDate 
									,PartyId 
									,MemberWL_e 
									,AgentWL_e 
									,AgentComm_e 
									,HouseWL_e 
									,HouseIncome_e 
									,MemberWL_oa 
									,AgentWL_oa
									,AgentComm_oa 
									,HouseWL_oa 
									,HouseIncome_oa
									)
		SELECT t.rptDate, l.PartyId
			,MemberWL_e		= SUM(t.MemberWL * e.Rate)
			,AgentWL_e		= SUM(t.AgentWL * e.Rate)
			,AgentComm_e	= SUM(t.AgentComm * e.Rate)
			,HouseWL_e		= SUM(-(t.MemberWL + t.AgentWL + t.AgentComm) * e.Rate)
			,HouseIncome_e	= SUM(((- t.MemberWL) * ISNULL(lc.Rate, p.Rate) - t.OddsSpreadAdj) * e.Rate)
			,MemberWL_oa	= SUM(t.MemberWL * oa.Rate)
			,AgentWL_oa		= SUM(t.AgentWL * oa.Rate)
			,AgentComm_oa	= SUM(t.AgentComm * oa.Rate)
			,HouseWL_oa		= SUM(-(t.MemberWL + t.AgentWL + t.AgentComm) * oa.Rate)
			,HouseIncome_oa = SUM(((- t.MemberWL) * ISNULL(lc.Rate, p.Rate) - t.OddsSpreadAdj) * oa.Rate)
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
			INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
			INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
			INNER JOIN @ExchangeOANDA oa ON t.CurrencyId = oa.ExchangeId
		WHERE t.ProductID = 10001
		GROUP BY t.rptDate, l.PartyId

		INSERT INTO #__tempResult_BA (	rptDate 
										,PartyId 
										,BAWinLoss_e
										,BAComm_e
										,BAWinLoss_oa
										,BAComm_oa
									)
		SELECT t.rptDate, l.PartyId
			,BAWinLoss_e		= SUM(-(t.MemberWL) * e.Rate)
			,BAComm_e			= SUM(t.AgentComm * e.Rate)
			,BAWinLoss_oa		= SUM(-(t.MemberWL) * oa.Rate)
			,BAComm_oa			= SUM(t.AgentComm * oa.Rate)
			
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
			INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
			INNER JOIN @ExchangeOANDA oa ON t.CurrencyId = oa.ExchangeId
		WHERE t.ProductID = 10004
		GROUP BY t.rptDate, l.PartyId


	END

	-- Licensee Min Fee (get data from LA core function - supported OANDA rate Only)
	BEGIN
		DECLARE @LicenseeFeeAndRebateDiscount TABLE
		(
			PartyId INT, ProductId INT, LicensingFeeTypeId TINYINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
		)
		INSERT INTO @LicenseeFeeAndRebateDiscount
		(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC DBLIC.bodb_licensee.dbo.LA_AmountToCompanyByProduct
			@PartyIds				= @PartyIds
			,@ProductCodes			= 'SB'
			,@Currencies			= ''
			,@FromDate				= @FDate
			,@ToDate				= @TDate
			,@IsConvertExRate		= 1
			,@LicensingFeeTypeIds	= '0,12' -- 12: Parlay Boost Bonus
			,@BaseCurrencyName		= 'MYR'

		DELETE @LicenseeFeeAndRebateDiscount
		WHERE ProductId <> 0

		DECLARE @tmpResult_BA TABLE
		(
			PartyId			INT
			-- System Rate
			,LicenseeWL_e		MONEY DEFAULT(0)
			,BAcomm_e			MONEY DEFAULT(0)
			,LicenseeFee_e		MONEY DEFAULT(0)
			-- Oanda Rate
			,LicenseeWL_oa		MONEY DEFAULT(0)
			,BAcomm_oa			MONEY DEFAULT(0)
			,LicenseeFee_oa		MONEY DEFAULT(0)

		)
		
		DECLARE @tmpResult TABLE
		(
			PartyId			INT
			,Rebate				MONEY DEFAULT(0)
			,RebateRate			MONEY DEFAULT(0)
			,Discount			MONEY DEFAULT(0)
			,DiscountRate		MONEY DEFAULT(0)
			-- System Rate
			,LicenseeWL_e		MONEY DEFAULT(0)
			,HouseWL_e			MONEY DEFAULT(0)
			,HouseIncome_e		MONEY DEFAULT(0)
			,LicenseeMinFee_e	MONEY DEFAULT(0)
			,LicenseeFee_e		MONEY DEFAULT(0)
			,ActualWLFee_e		MONEY DEFAULT(0)
			-- Oanda Rate
			,LicenseeWL_oa		MONEY DEFAULT(0)
			,HouseWL_oa			MONEY DEFAULT(0)
			,HouseIncome_oa		MONEY DEFAULT(0)
			,LicenseeMinFee_oa	MONEY DEFAULT(0)
			,LicenseeFee_oa		MONEY DEFAULT(0)
			,ActualWLFee_oa		MONEY DEFAULT(0)
		)
		;WITH CTE_tempResult AS (
			SELECT PartyId
				,LicenseeWL_e	= SUM(-MemberWL_e)
				,HouseWL_e		= SUM(HouseWL_e)
				,HouseIncome_e	= SUM(HouseIncome_e)
				,LicenseeWL_oa	= SUM(-MemberWL_oa)
				,HouseWL_oa		= SUM(HouseWL_oa)
				,HouseIncome_oa	= SUM(HouseIncome_oa)
			FROM #__tempResult
			GROUP BY PartyId
		)
		,CTE_Result AS (
			SELECT
				PartyId				= m.PartyId
				,LicenseeWL_e		= ISNULL(t.LicenseeWL_e, 0)
				,HouseWL_e			= ISNULL(t.HouseWL_e, 0)
				,HouseIncome_e		= ISNULL(t.HouseIncome_e, 0)
				,LicenseeWL_oa		= ISNULL(t.LicenseeWL_oa, 0)
				,HouseWL_oa			= ISNULL(t.HouseWL_oa, 0)
				,HouseIncome_oa		= ISNULL(t.HouseIncome_oa, 0)
				,Rebate				= m.Rebate
				,RebateRate			= m.RebateRate
				,Discount			= m.Discount
				,DiscountRate		= m.DiscountRate
				,LicenseeMinFee_e	= CASE WHEN m.IsChargedByGroupMinFee = 1 OR m.IsChargedByMinFee = 1 THEN m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0)) ELSE 0 END 					
				,LicenseeFee_e		= CASE WHEN m.IsChargedByGroupMinFee = 0 AND m.IsChargedByMinFee = 0 THEN m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0))ELSE 0 END
								
				,LicenseeMinFee_oa	= CASE WHEN m.IsChargedByGroupMinFee = 1 OR m.IsChargedByMinFee = 1 THEN m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0))ELSE 0 END
				,LicenseeFee_oa		= CASE WHEN m.IsChargedByGroupMinFee = 0 AND m.IsChargedByMinFee = 0 THEN m.LicensingFee + m.ExtraAmount - (ISNULL(m12.LicensingFee,0) - ISNULL(m12.ExtraAmount,0))ELSE 0 END
			FROM @LicenseeFeeAndRebateDiscount m 
				LEFT JOIN CTE_tempResult t ON t.PartyId = m.PartyId
				LEFT JOIN @LicenseeFeeAndRebateDiscount m12 ON m.PartyId = m12.PartyId AND m12.LicensingFeeTypeId = 12
			WHERE m.LicensingFeeTypeId = 0
		)
		INSERT INTO @tmpResult (PartyId, LicenseeWL_e, HouseWL_e, HouseIncome_e, LicenseeWL_oa, HouseWL_oa, HouseIncome_oa, Rebate, RebateRate, Discount, DiscountRate, LicenseeMinFee_e, LicenseeFee_e, LicenseeMinFee_oa, LicenseeFee_oa)
		SELECT r.PartyId, r.LicenseeWL_e, r.HouseWL_e, r.HouseIncome_e, r.LicenseeWL_oa, r.HouseWL_oa, r.HouseIncome_oa, r.Rebate, r.RebateRate, r.Discount, r.DiscountRate, r.LicenseeMinFee_e, r.LicenseeFee_e, r.LicenseeMinFee_oa, r.LicenseeFee_oa
		FROM CTE_Result r

		UPDATE t
		SET t.LicenseeFee_e =  ISNULL(LicenseeFee_e, 0) - ISNULL(u.HouseIncome_e,0), 
			t.LicenseeFee_oa = ISNULL(LicenseeFee_oa, 0) - ISNULL(u.HouseIncome_oa,0)
		FROM @tmpResult t
		LEFT JOIN #__tempResult_BTC u ON t.PartyId = u.PartyId
		WHERE  ISNULL(LicenseeFee_e, 0) <> 0  OR  ISNULL(LicenseeFee_oa, 0) <> 0

		UPDATE @tmpResult
		SET ActualWLFee_e = ISNULL(LicenseeMinFee_e, 0) + ISNULL(LicenseeFee_e, 0)
			,ActualWLFee_oa = ISNULL(LicenseeMinFee_oa, 0) + ISNULL(LicenseeFee_oa, 0)
	END

	DELETE r
	FROM @tmpResult r
		LEFT JOIN #PartyChargeInfo p ON r.PartyId = p.PartyId
	WHERE p.PartyId IS NULL

	-- Get Licensee House PT
	DECLARE @Sites VARCHAR(MAX), @SiteCurrencies VARCHAR(MAX)
	SET @Sites = CONVERT(VARCHAR(MAX), (
		SELECT
			s.SiteId	AS '@SiteId'
			,l.PartyId	AS '@PartyId'
			,s.SiteName	AS '@SiteName'
		FROM #AllLicensees l
			INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
			INNER JOIN #PartyChargeInfo p ON l.PartyId = p.PartyId
		FOR XML PATH('r'), TYPE, ROOT('root')
	))

	SET @SiteCurrencies = CONVERT(VARCHAR(MAX), (
		SELECT
			s.SiteId		AS '@SiteId'
			,l.PartyId		AS '@PartyId'
			,s.SiteName		AS '@SiteName'
			,lc.CurrencyId	AS '@CurrencyId'
		FROM #AllLicensees l
			INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
			INNER JOIN #PartyChargeInfo p ON l.PartyId = p.PartyId
			INNER JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId
		FOR XML PATH('r'), TYPE, ROOT('root')
	))

	CREATE TABLE #__HousePT (PartyId INT, CurrencyId INT, HousePT FLOAT)
	INSERT INTO #__HousePT (PartyId, CurrencyId, HousePT)
	EXEC DBCUST.CustDB.dbo.Acc_Licensee_HousePT @Sites = @Sites, @SiteCurrencies = @SiteCurrencies


	-- BA sheet data
	BEGIN	
		INSERT INTO @tmpResult_BA(PartyId, LicenseeWL_e, BAcomm_e, LicenseeFee_e, LicenseeWL_oa, BAcomm_oa, LicenseeFee_oa)
		SELECT PartyId
				,LicenseeWL_e	= SUM(-BAWinLoss_e)
				,BAcomm_e		= SUM(BAComm_e)
				,LicenseeFee_e	= SUM(BAWinLoss_e - BAComm_e)
				,LicenseeWL_oa	= SUM(-BAWinLoss_oa)
				,BAcomm_oa		= SUM(BAComm_oa)
				,LicenseeFee_oa	= SUM(BAWinLoss_oa - BAComm_oa)
		FROM	#__tempResult_BA
		GROUP BY PartyId
	END
	--

	-- Return Data
	CREATE TABLE #__Result (OrderId TINYINT, PartyId INT, Product VARCHAR(10), SiteName VARCHAR(50)
		,MemberWL_SysRate MONEY, MemberWL_OaRate MONEY, LicenseeWL_SysRate MONEY, LicenseeWL_OaRate MONEY
		,HousePT VARCHAR(200), HouseWL_SysRate MONEY, HouseWL_OaRate MONEY,ChargeRate VARCHAR(200)
		, GrossLicenseeFee_SysRate MONEY, GrossLicenseeFee_OaRate MONEY, LicenseeMinFee_OaRate MONEY
		, LicenseeFee_OaRate MONEY, LicenseeFeeAfterMinFee_OaRate MONEY, RebateRate FLOAT, Rebate MONEY
		, DiscountRate FLOAT, Discount MONEY, RebateDiscount MONEY, ActualLicenseeFee_OaRate MONEY)

	CREATE TABLE #__Result_BA (OrderId TINYINT, PartyId INT, Product VARCHAR(10), SiteName VARCHAR(50)
		,MemberWL_SysRate MONEY, MemberWL_OaRate MONEY, LicenseeWL_SysRate MONEY, LicenseeWL_OaRate MONEY
		,BAComm_SysRate MONEY, BAComm_OaRate MONEY, ActualLicensingFee_SysRate MONEY, ActualLicensingFee_OaRate MONEY)


	INSERT INTO  #__Result_BA (OrderId, PartyId, Product, SiteName 
		,MemberWL_SysRate , MemberWL_OaRate, LicenseeWL_SysRate , LicenseeWL_OaRate 
		,BAComm_SysRate , BAComm_OaRate, ActualLicensingFee_SysRate , ActualLicensingFee_OaRate)

	SELECT
		1 AS OrderId
		,0 AS PartyId
		,'BA Total'	AS Product
		,''			AS SiteName
		,-SUM(ISNULL(tr.LicenseeWL_e, 0))	AS MemberWL_SysRate
		,-SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS MemberWL_OaRate
		,SUM(ISNULL(tr.LicenseeWL_e, 0))	AS LicenseeWL_SysRate
		,SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS LicenseeWL_OaRate
		,SUM(ISNULL(tr.BAcomm_e, 0))		AS BAComm_SysRate
		,SUM(ISNULL(tr.BAcomm_oa, 0))		AS BAComm_OaRate
		,SUM(ISNULL(tr.LicenseeFee_e, 0))		AS ActualLicensingFee_SysRate
		,SUM(ISNULL(tr.LicenseeFee_oa, 0))		AS ActualLicensingFee_OaRate
	FROM @tmpResult_BA tr

	UNION ALL
	SELECT
		2 AS OrderId
		,tr.PartyId
		,'BA' AS Product
		,s.SiteName
		,-ISNULL(tr.LicenseeWL_e, 0)	AS MemberWL_SysRate
		,-ISNULL(tr.LicenseeWL_oa, 0)	AS MemberWL_OaRate
		,ISNULL(tr.LicenseeWL_e, 0)	AS LicenseeWL_SysRate
		,ISNULL(tr.LicenseeWL_oa, 0)	AS LicenseeWL_OaRate
		,ISNULL(tr.BAcomm_e, 0)		AS BAComm_SysRate
		,ISNULL(tr.BAcomm_oa, 0)		AS BAComm_OaRate
		,ISNULL(tr.LicenseeFee_e, 0)		AS ActualLicensingFee_SysRate
		,ISNULL(tr.LicenseeFee_oa, 0)		AS ActualLicensingFee_OaRate
	FROM @tmpResult_BA tr
		INNER JOIN #AllLicensees l ON tr.PartyId = l.PartyId
		INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
	WHERE ISNULL(tr.LicenseeWL_e, 0) <> 0 OR ISNULL(tr.BAcomm_e, 0) <> 0


	INSERT INTO #__Result (OrderId, PartyId, Product, SiteName
		,MemberWL_SysRate, MemberWL_OaRate, LicenseeWL_SysRate, LicenseeWL_OaRate
		,HousePT, HouseWL_SysRate, HouseWL_OaRate
		,ChargeRate, GrossLicenseeFee_SysRate, GrossLicenseeFee_OaRate
		,LicenseeMinFee_OaRate, LicenseeFee_OaRate
		,LicenseeFeeAfterMinFee_OaRate
		,RebateRate, Rebate, DiscountRate, Discount, RebateDiscount
		, ActualLicenseeFee_OaRate)
	SELECT
		1 AS OrderId
		,0 AS PartyId
		,'SB Total'	AS Product
		,''			AS SiteName
		,-SUM(ISNULL(tr.LicenseeWL_e, 0))	AS MemberWL_SysRate
		,-SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS MemberWL_OaRate
		,SUM(ISNULL(tr.LicenseeWL_e, 0))	AS LicenseeWL_SysRate
		,SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS LicenseeWL_OaRate
		,NULL	AS HousePT
		,SUM(ISNULL(tr.HouseWL_e, 0))		AS HouseWL_SysRate
		,SUM(ISNULL(tr.HouseWL_oa, 0))		AS HouseWL_OaRate
		,NULL	AS ChargeRate
		,SUM(ISNULL(tr.HouseIncome_e, 0))		AS GrossLicenseeFee_SysRate
		,SUM(ISNULL(tr.HouseIncome_oa, 0))		AS GrossLicenseeFee_OaRate
		,SUM(ISNULL(tr.LicenseeMinFee_oa, 0))	AS LicenseeMinFee_OaRate
		,SUM(ISNULL(tr.LicenseeFee_oa, 0))		AS LicenseeFee_OaRate
		,SUM(ISNULL(tr.ActualWLFee_oa, 0))		AS LicenseeFeeAfterMinFee_OaRate
		,NULL							AS RebateRate
		,SUM(ISNULL(tr.Rebate, 0))		AS Rebate
		,NULL							AS DiscountRate
		,SUM(ISNULL(tr.Discount, 0))	AS Discount
		,SUM(ISNULL(tr.Rebate, 0) + ISNULL(tr.Discount, 0)) AS RebateDiscount
		,SUM(ISNULL(tr.ActualWLFee_oa, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0))	AS ActualLicenseeFee_OaRate
	FROM @tmpResult tr

	UNION ALL
	SELECT
		2 AS OrderId
		,tr.PartyId
		,'SB' AS Product
		,s.SiteName
		,-ISNULL(tr.LicenseeWL_e, 0)	AS MemberWL_SysRate
		,-ISNULL(tr.LicenseeWL_oa, 0)	AS MemberWL_OaRate
		,ISNULL(tr.LicenseeWL_e, 0)		AS LicenseeWL_SysRate
		,ISNULL(tr.LicenseeWL_oa, 0)	AS LicenseeWL_OaRate
		,''	AS HousePT
		,ISNULL(tr.HouseWL_e, 0)		AS HouseWL_SysRate
		,ISNULL(tr.HouseWL_oa, 0)		AS HouseWL_OaRate
		,''	AS ChargeRate
		,ISNULL(tr.HouseIncome_e, 0)	AS GrossLicenseeFee_SysRate
		,ISNULL(tr.HouseIncome_oa, 0)	AS GrossLicenseeFee_OaRate
		,ISNULL(tr.LicenseeMinFee_oa, 0)	AS LicenseeMinFee_OaRate
		,ISNULL(tr.LicenseeFee_oa, 0)		AS LicenseeFee_OaRate
		,ISNULL(tr.ActualWLFee_oa, 0)		AS LicenseeFeeAfterMinFee_OaRate
		,ISNULL(tr.RebateRate, 0)	AS RebateRate
		,ISNULL(tr.Rebate, 0)		AS Rebate
		,ISNULL(tr.DiscountRate, 0) AS DiscountRate
		,ISNULL(tr.Discount, 0)		AS Discount
		,ISNULL(tr.Rebate, 0) + ISNULL(tr.Discount, 0) AS RebateDiscount
		,ISNULL(tr.ActualWLFee_oa, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0) AS ActualLicenseeFee_OaRate
	FROM @tmpResult tr
		INNER JOIN #AllLicensees l ON tr.PartyId = l.PartyId
		INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
	WHERE ISNULL(tr.LicenseeWL_e, 0) <> 0 OR ISNULL(tr.ActualWLFee_e, 0) <> 0

	;WITH CTE_ChargeRate AS (
		SELECT PartyId, Rate = ISNULL(CurrencyCode + ': ', '') + CONVERT(VARCHAR(5), ROUND(Rate, 3))
		FROM (
		SELECT DISTINCT PartyId, Rate, CONVERT(VARCHAR(3), NULL) AS CurrencyCode FROM #PartyChargeInfo
		UNION ALL
		SELECT DISTINCT p.PartyId, lc.Rate, CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END
		FROM #PartyChargeInfo p
			INNER JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId
			INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON lc.CurrencyId = e.ExchangeId
		) t
	), CTE_ChargeRateByCurrency AS (
		SELECT p1.PartyId, ChargeRate = STUFF((
            SELECT ' | ' + p2.Rate
            FROM CTE_ChargeRate p2 WHERE p1.PartyId = p2.PartyId ORDER BY p2.Rate
            FOR XML PATH('')
            ), 1, 3, '')
		FROM CTE_ChargeRate p1
		GROUP BY p1.PartyId
	)
	UPDATE r
	SET r.ChargeRate = c.ChargeRate
	FROM #__Result r
		INNER JOIN CTE_ChargeRateByCurrency c ON r.PartyId = c.PartyId
	WHERE r.Product = 'SB'

	;WITH CTE_HousePT AS (
		SELECT h.PartyId, Rate = ISNULL(CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END + ': ', '') + CONVERT(VARCHAR(5), ROUND(h.HousePT, 3))
		FROM #__HousePT h
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
	), CTE_HousePTByCurrency AS (
		SELECT p1.PartyId, HousePT = STUFF((
            SELECT ' | ' + p2.Rate
            FROM CTE_HousePT p2 WHERE p1.PartyId = p2.PartyId ORDER BY p2.Rate
            FOR XML PATH('')
            ), 1, 3, '')
		FROM CTE_HousePT p1
		GROUP BY p1.PartyId
	)
	UPDATE r
	SET r.HousePT = c.HousePT
	FROM #__Result r
		INNER JOIN CTE_HousePTByCurrency c ON r.PartyId = c.PartyId
	WHERE r.Product = 'SB'

	SELECT Product
		,SiteName
		,MemberWL_SysRate
		,MemberWL_OaRate
		,LicenseeWL_SysRate
		,LicenseeWL_OaRate
		,HousePT
		,HouseWL_SysRate
		,HouseWL_OaRate
		,ChargeRate
		,GrossLicenseeFee_SysRate
		,GrossLicenseeFee_OaRate
		,LicenseeMinFee_OaRate
		,LicenseeFee_OaRate
		,LicenseeFeeAfterMinFee_OaRate
		,RebateRate
		,Rebate
		,DiscountRate
		,Discount
		,RebateDiscount
		,ActualLicenseeFee_OaRate
	FROM #__Result
	ORDER BY OrderId, SiteName

		SELECT Product
		,SiteName
		,MemberWL_SysRate
		,MemberWL_OaRate
		,LicenseeWL_SysRate
		,LicenseeWL_OaRate
		,BAComm_SysRate
		,BAComm_OaRate
		,ActualLicensingFee_SysRate
		,ActualLicensingFee_OaRate
	FROM #__Result_BA
	ORDER BY OrderId, SiteName

	DROP TABLE #__HousePT
	DROP TABLE #__Result
	DROP TABLE #__Result_BA
	DROP TABLE #__tempData
	DROP TABLE #__tempResult_BA
	DROP TABLE #__tempResult_BTC
	DROP TABLE #__tempResult
	DROP TABLE #__tmpSite
	DROP TABLE #AllLicensees
	DROP TABLE #Exchange
	DROP TABLE #Licensees
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #PartyChargeInfo
END
GO
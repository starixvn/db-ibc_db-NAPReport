/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit]
	@FromDate       DATE
   ,@ToDate         DATE
   ,@ProductList    VARCHAR(MAX) = ''
AS

/*
	Created:	20180126@Harper 
	Task:		HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:			DBEXT-bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20180806@Harper - DHWL Margin Chart - Create new message notification to NSD group based on Product List [#RedmineID: 98611]
		- 20180813@Harper - DHWL Non-sports Margin Chart - Integrate OneRNG Jackpot & Pragmatic [#RedmineID: 97562]
		- 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20191107@Robert -  NPH - House Net Income, Licensee Performance Email/Letstalk Report Integration [122516]
		- 20191127@Robert: Rename Product from 'NPH Promotion' to 'Saba Promotion'
		- 20200224@Kean: #123734 - Integrate SG (Spadegaming) product
		- 20200313@Kean - Change the "Pay to supplier" formula of SG - #126465
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200403@Percy: Integrate Xoc Dia (CC), Bluesprint's games (Macau Games), Table Games [RedmineID: #131507,#131755,#129447]
		- 20200422@Percy: Integrate 3D Lottery (CC), Saba.Club, Sexy Gaming [RedmineID: #132790,#132791,#132792]
		- 20200521@Percy: Re-integrate FW [RedmineID: #134533]
		- 20200529@Percy: Special members for AB [RedmineID: #134867]
		- 20200818@Percy: Integrate PG Soft [RedmineID: #137764]
		- 20200922@Percy: Integrate WM Live Casino & Joker Gaming [RedmineID: #131593,#131602]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]

	Param's Explanation:   
		- @ProductList: List of Product Code

	Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit '2018-07-01', '2018-07-30'
  
*/ 

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductCodes VARCHAR(MAX)

	-- Get list of product
	BEGIN
		IF ISNULL(@ProductList, '') = ''
			SELECT @ProductList = 'EX,GD,FW,AB,VB,CB,CO,AGC,KN,LT,CS,NG,H5,PP,CC,SP,SG,VRG,SAG,I4D,TG,SBC,SXG,PGS,WM,JK,VS,VS2'

		SELECT @ProductList = ',' + @ProductList + ','
		SELECT @ProductList = REPLACE(REPLACE(REPLACE(@ProductList, ',SB,', ',SB,BA,'), ',EX,', ',BX,'), ',SP,', ',SPR,')

		DECLARE @Products TABLE (OrderId INT, SubOrder INT, ProductId INT, Product3rdId INT, ProductCode VARCHAR(200), SubProductCode VARCHAR(10))
		INSERT INTO @Products (OrderId, ProductCode)
		SELECT [rank] * 100, val FROM dbo.strSplit(@ProductList, ',') WHERE LEN(val) > 0

		UPDATE t
		SET t.ProductId = CASE WHEN t.ProductCode = 'SB' THEN 1 WHEN t.ProductCode = 'BA' THEN 0 ELSE p.ProductId END
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
				(ci.FromDate BETWEEN @FromDate AND @ToDate)
				OR (ci.ToDate BETWEEN @FromDate AND @ToDate)
				OR (ci.FromDate < @FromDate AND @ToDate < ci.ToDate)
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
		FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
			INNER JOIN #Licensees p ON ci.PartyID = p.PartyID
			LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE
			(
				ci.ChargeType = 1
				OR ci.ChargeType IN (9, 10, 12) AND ci.ProductId = 11 -- GD
				OR ci.ChargeType = 12 AND ci.ProductId = 39 -- SAG
			)
			AND ci.DI_Rate > 0

		-- Special products
			-- H5
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'H5')
		BEGIN
			IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId = 2 AND SubProductCode = 'NG')
			BEGIN
				INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
				SELECT ChargeId, PartyId, LicenseeId, ParentId, -2, Rate, FromDate, ToDate, -1, ChargeType
				FROM #PartyChargeInfo
				WHERE Product3rdId = 2
			END
			ELSE
			BEGIN
				UPDATE #PartyChargeInfo SET Product3rdId = -2, Bettype = -1 WHERE Product3rdId = 2
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
			END
			ELSE
			BEGIN
				UPDATE #PartyChargeInfo SET Product3rdId = -3, Bettype = -1 WHERE Product3rdId = 32
			END
		END

		DROP TABLE #Licensees
	END

	-- Get exchange rate
	BEGIN
		CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeId INT, Rate FLOAT)
		INSERT INTO #Exchange(ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

		CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
		INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'MYR')
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

		-- Get data from DW
		IF EXISTS (SELECT 1 FROM @Products WHERE Product3rdId NOT IN (10, 11, 15, 31))
		BEGIN
			DECLARE @ProductIds VARCHAR(MAX)
			;WITH CTE_ProductIds AS (SELECT DISTINCT ProductId FROM @Products WHERE Product3rdId NOT IN (10, 11, 15, 31))
			SELECT  @ProductIds = COALESCE(@ProductIds + ',', '') + CONVERT(VARCHAR(5), ProductId) FROM CTE_ProductIds

			DECLARE @SubProducts VARCHAR(MAX)
			SELECT  @SubProducts = COALESCE(@SubProducts + ',', '') + SubProductCode
			FROM @Products WHERE SubProductCode IS NOT NULL

			SELECT  @SubProducts = ISNULL(@SubProducts, '')

			INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, Comm, HouseContribution, FullContribution)
			EXEC DBWH.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MemberWL
				@FromDate		= @FromDate
				,@ToDate		= @ToDate
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
			WHERE rptDate BETWEEN @FromDate AND @ToDate
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
			WHERE rptDate BETWEEN @FromDate AND @ToDate
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

		UPDATE @Products SET ProductId = -2, Product3rdId = -2, ProductCode = 'H5' WHERE SubProductCode = 'H5'
		UPDATE @Products SET ProductId = -3, Product3rdId = -3, ProductCode = 'PP-JP' WHERE SubProductCode = 'PP-JP'

		-- Process data
		DECLARE @GDCommissionRate FLOAT = 0
		SELECT  @GDCommissionRate = DI_Rate FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'GD', 'OA') WHERE ChargeType = 11
		
		CREATE TABLE #__tempResult
		(
			rptDate				DATETIME
			,AmountToCompany	MONEY
		)
		INSERT INTO #__tempResult (rptDate, AmountToCompany)
		SELECT t.rptDate
			,SUM(CASE
					WHEN b.Product3rdId = 15 THEN t.MemberWL * ISNULL(oa.Rate, 0) -- CB
					WHEN b.Product3rdId = 25 THEN -t.MemberWL * ISNULL(oa.Rate, 0) -- BT & CO
					WHEN b.Product3rdId = 31 THEN (-t.MemberWL * ISNULL(lc.Rate, p.Rate) - t.Comm) * ISNULL(oa.Rate, 0) -- EX
					WHEN b.Product3rdId = 37 OR p.LicenseeId IS NULL THEN -t.HouseWL * ISNULL(e.Rate, 0)
					ELSE ((-t.MemberWL - (t.FullContribution - t.HouseContribution)) * ISNULL(lc.Rate, p.Rate) - t.HouseContribution) * ISNULL(e.Rate, 0)
					END)
		FROM #__tempData t
			INNER JOIN #BetType b ON t.ProductId = b.ProductId AND b.BetTypeGroup = t.BetTypeGroup
			INNER JOIN #AllLicensees l ON l.LicenseeId = t.LicenseeId
			LEFT JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND p.Product3rdId = b.Product3rdId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = b.BetTypeGroup)
					AND (
						(b.Product3rdId IN (11, 39) AND b.BetTypeGroup <> -1 AND p.ChargeType = 12)
						OR ((b.Product3rdId NOT IN (11, 39) OR b.BetTypeGroup = -1) AND p.ChargeType <> 12)
					)
			LEFT JOIN #Exchange e ON t.rptDate = e.ExchangeDate AND t.CurrencyId = e.ExchangeId
			LEFT JOIN #ExchangeOANDA oa ON t.rptDate = oa.ExchangeDate AND t.CurrencyId = oa.ExchangeId
			LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		GROUP BY t.rptDate
	END

	DROP TABLE #__tempData
	DROP TABLE #AllLicensees
	DROP TABLE #BetType
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #PartyChargeInfo

	-- Calculate result
	CREATE TABLE #Result (rptDate VARCHAR(10), HouseIncome MONEY)
	;WITH CTE_rptDate AS
	(
		SELECT CONVERT(DATETIME, @FromDate) AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @ToDate
	)
	INSERT INTO #Result (rptDate, HouseIncome)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106) AS rptDate, SUM(ISNULL(t.AmountToCompany, 0))
	FROM CTE_rptDate r
		LEFT JOIN #__tempResult t ON r.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106)
	ORDER BY rptDate
	OPTION (MAXRECURSION 0)

	DROP TABLE #__tempResult

	-- Update result
	DECLARE @DateList VARCHAR(2000), @ReturnColumns VARCHAR(2000)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #Result
	SELECT  @ReturnColumns = '''NonSport'' AS ProductCode,1 AS [Order],Figure,' + @DateList

    /* End region*/
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(2000)
	SELECT  @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT [RptDate], Figure, ISNULL(value, 0) value
								FROM #Result
									CROSS APPLY (
										SELECT ''House Income'', HouseIncome
									) c (Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p'
	EXEC(@SQL)

	DROP TABLE #Result
END
GO
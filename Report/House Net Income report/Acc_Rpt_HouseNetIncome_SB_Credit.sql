/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit]
	@FromDate   DATE
   ,@ToDate     DATE
AS

/*  Created: Victor  
	Date: 2016-05-27  
    Task: House month-to-date Net Income report
    DB: DBWH/bodb_dwrs
   
    Revisions:	
		- 20160922@Harper - #64429 - Edit status ID
		- 20190529@Dan: tuning to prevent wrong excution plan (scan all table)
		- 20200210@Robert: #126634 - DHWL Letstalk Reports - Break SB into Soccer, OS and Parlay
		- 20200202@Robert: #126634 DHWL - break OS into Basketball, E-sports, Tennis and Other Sports
		- 20200720@Kean - DHWL Email/Letstalk - Separate Saba Sports from real Sports (#137822)
		- 20200529@Ned.Le: Letstalk Reports - Saba - Treat Saba Futsal as Saba Soccer (#142264)
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    SET NOCOUNT ON

    DECLARE @FDate DATE, @TDate DATE
    SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @SQL VARCHAR(MAX)
	DECLARE @f_date VARCHAR(10), @t_date VARCHAR(10)
	SELECT  @f_date = CONVERT(VARCHAR(10), @FDate, 120), @t_date = CONVERT(VARCHAR(10), @TDate, 120)

	-- Exchange
    CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
    INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
	
	SELECT @SQL = '	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
					FROM OPENQUERY(DBEXT, ''SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
											FROM bodb02.dbo.LA_f_ExchangeDailySel(''''' + @f_date + ''''', ''''' + @t_date+ ''''', ''''MYR'''')''
									)'
	
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeId, Rate)
	EXEC (@SQL)

	-- Credit licensees by product
	CREATE TABLE #Licensees (PartyId INT)

	SELECT @SQL = '	SELECT PartyId
					FROM OPENQUERY(DBLIC, ''SELECT DISTINCT p.PartyId
											FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
												INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
												INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
												INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
											WHERE p.PartyType = 1
												AND pd.IsDeposit = 0
												AND ci.ProductId = 0
												AND (
													(ci.FromDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.ToDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.FromDate < ''''' + @f_date + ''''' AND ''''' + @t_date + ''''' < ci.ToDate)
												)''
									)'
	INSERT INTO #Licensees (PartyId)
	EXEC (@SQL)

	-- Get charge rate
	DECLARE @PartyIDs VARCHAR(MAX)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees
		
	CREATE TABLE #PartyChargeInfo (ChargeId INT, LicenseeId INT, LicenseeName VARCHAR(200), SiteId_DW INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		
	SELECT @SQL = '	SELECT ChargeId, LicenseeId, LicenseeName, FromDate, ToDate, Rate
					FROM OPENQUERY(DBLIC, ''SELECT DISTINCT ci.ChargeId, ci.LicenseeId, LTRIM(RTRIM(s.SiteName)) AS LicenseeName, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate
											FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
												INNER JOIN bodb_licensee.dbo.view_site_list s with (nolock) on ci.LicenseeId = s.SiteId''
									)'

	INSERT INTO #PartyChargeInfo (ChargeId, LicenseeId, LicenseeName, FromDate, ToDate, Rate)
	EXEC (@SQL)

	UPDATE p
	SET p.SiteId_DW = s.SiteId
	FROM #PartyChargeInfo p
		INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON p.LicenseeName = LTRIM(RTRIM(s.site))

	CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)

	SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
					FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
											FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
												INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
											WHERE ci.ChargeType = 1
												AND ci.DI_Rate > 0''
									)'

	INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
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
												AND (
													(ci.FromDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.ToDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.FromDate < ''''' + @f_date + ''''' AND ''''' + @t_date + ''''' < ci.ToDate)
												)''
									)'

	INSERT INTO #MetricChargeInfo (FromDate, ToDate, BaseCurrencyId, MinAmount, MaxAmount, Rate)
	EXEC (@SQL)

	UPDATE m
	SET m.MinAmount = m.MinAmount * ISNULL(oa.Rate, 0), m.MaxAmount = m.MaxAmount * ISNULL(oa.Rate, 0)
	FROM #MetricChargeInfo m
		LEFT JOIN #ExchangeOANDA oa ON m.BaseCurrencyId = oa.ExchangeId AND oa.ExchangeDate = @TDate

	-- Saba League
	CREATE TABLE #SabaLeague (LeagueId INT, LeagueGroupId INT)
	INSERT INTO #SabaLeague (LeagueId, LeagueGroupId)
	SELECT LeagueId, LeagueGroupId FROM bodb02.dbo.League WITH (NOLOCK) 
	WHERE sporttype IN (1, 2, 50) ANd LeagueGroupID IN (42, 74, 108)

    -- Bettype
    CREATE TABLE #SportBettypeMatrix (Bettype INT)
    INSERT INTO #SportBettypeMatrix (Bettype)
	SELECT DISTINCT Bettype FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE ProductId = 1 AND BetType NOT IN (901, 902, 903, 904)

	-- Data
    CREATE TABLE #tempData (rptDate DATE, GroupId INT, SporttypeGroup INT, HouseIncome MONEY, ExtraPT MONEY, PayToSupplier MONEY)
    ;WITH CTE_tempData AS (
		SELECT b.rptDate, b.SiteId, b.CurrencyId
			,CASE
				WHEN b.bettype BETWEEN 801 AND 899 THEN 2
				WHEN b.bettype = 38 THEN 3
				END AS GroupId
			,CASE
				WHEN b.BetType IN (9, 29) THEN -2
				WHEN b.SportType = 1 AND l.LeagueGroupId IN (42, 74, 108) THEN -3  -- Saba Soccer
				WHEN b.SportType = 2 AND l.LeagueGroupId IN (42) THEN -4  -- Saba Basketball
				WHEN b.SportType = 50 AND l.LeagueGroupId IN (42) THEN -5  -- Saba Cricket 
				WHEN b.SportType IN (1, 2, 5, 43) THEN b.SportType
				ELSE 99 END AS SporttypeGroup
			,-SUM(winlossP + winlossS + winlossM + winlossA + commissionS) AS HouseIncome
			,SUM(b.ExtraWL + b.ExtraComm) AS ExtraPT
			,SUM(b.winlossP) AS MemberWL
			,SUM(b.CommissionS) AS HouseComm
		FROM bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix bt ON b.Bettype = bt.Bettype
			LEFT JOIN #SabaLeague l ON l.leagueid = b.leagueId
		WHERE b.rptDate BETWEEN @FDate AND @TDate
			AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			AND b.CurrencyId <> 20
			AND b.SiteId IN (SELECT s.SiteId FROM bodb_Account.dbo.tbl_Site s WITH (NOLOCK) WHERE s.isDeposit = 0)
		GROUP BY
			b.rptDate, b.SiteId, b.CurrencyId
			,CASE
				WHEN b.bettype BETWEEN 801 AND 899 THEN 2
				WHEN b.bettype = 38 THEN 3
				END
			,CASE
				WHEN b.BetType IN (9, 29) THEN -2
				WHEN b.SportType = 1 AND l.LeagueGroupId IN (42, 74, 108) THEN -3  -- Saba Soccer
				WHEN b.SportType = 2 AND l.LeagueGroupId IN (42) THEN -4  -- Saba Basketball
				WHEN b.SportType = 50 AND l.LeagueGroupId IN (42) THEN -5  -- Saba Cricket 
				WHEN b.SportType IN (1, 2, 5, 43) THEN b.SportType
				ELSE 99 END
	)
	INSERT INTO #tempData (rptDate, GroupId, SporttypeGroup, HouseIncome, ExtraPT, PayToSupplier)
	SELECT b.rptDate, b.GroupId, b.SporttypeGroup
		,SUM(b.HouseIncome * ISNULL(e.Rate, 0)) AS HouseIncome
		,SUM(b.ExtraPT * ISNULL(e.Rate, 0)) AS ExtraPT
		,SUM(CASE
				WHEN b.GroupId = 3 THEN (b.MemberWL + b.HouseComm) * 0.04
				ELSE b.HouseIncome * ISNULL(ISNULL(pc.Rate, p.Rate), 0)
				END
				* ISNULL(oa.Rate, 0)
			) AS PayToSupplier
	FROM CTE_tempData b
		LEFT JOIN #PartyChargeInfo p ON b.SiteId = p.SiteId_DW AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #PartyChargeByCurrencyInfo pc WITH (NOLOCK) ON p.ChargeId = pc.ChargeId AND b.CurrencyId = pc.CurrencyId
		LEFT JOIN #Exchange e ON b.rptdate = e.ExchangeDate AND b.CurrencyId = e.ExchangeId
		LEFT JOIN #ExchangeOANDA oa ON b.rptdate = oa.ExchangeDate AND b.CurrencyId = oa.ExchangeId
	GROUP BY
		b.rptDate, b.GroupId, b.SporttypeGroup
	OPTION(RECOMPILE)

	DROP TABLE #Exchange
	DROP TABLE #SabaLeague
	DROP TABLE #SportBettypeMatrix


	-- PayToSupplier of Metric Gaming, Muay Thai, Bet Builder
	BEGIN
		CREATE TABLE #__PayToSupplierSB (GroupId TINYINT, rptDate DATE, PaytoSupplier MONEY) -- GroupId: 1 = Metric Gaming, 2 = Muay Thai, 3 = Bet Builder
		INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
		SELECT r.GroupId, r.rptDate
			,CASE
				WHEN r.GroupId = 3 THEN r.PaytoSupplier
				WHEN (r.PayToSupplier < 0 AND m.MinAmount = 0) OR r.PayToSupplier >= m.MinAmount
					THEN CASE WHEN r.PayToSupplier > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(r.PayToSupplier - m.MinAmount) END * m.Rate
				ELSE 0
				END
		FROM #tempData r
			LEFT JOIN #MetricChargeInfo m ON r.rptDate BETWEEN m.FromDate AND m.ToDate AND r.GroupId = 2
		WHERE r.GroupId IS NOT NULL

		-- Muay Thai
		;WITH CTE_MuayThai AS (
			SELECT b.rptDate, b.SiteId, b.CurrencyId, SUM(ISNULL(b.AdjustedCustomerWL * 0.03, 0) - ISNULL(b.AdjustedCommShare, 0)) AS PaytoSupplier
			FROM DBLIC.bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyId <> 20
				AND b.StatusId IN (111, 112, 113)
				AND b.customercategory NOT IN (27, 28)
				AND b.SiteId > 1000
				AND b.SportType = 44
			GROUP BY b.rptdate, b.SiteId, b.CurrencyId
		)
		INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
		SELECT 1, b.rptDate, SUM(b.PaytoSupplier * ISNULL(oa.Rate, 0))
		FROM CTE_MuayThai b
			INNER JOIN #PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #ExchangeOANDA oa ON oa.ExchangeDate = b.rptDate AND oa.ExchangeId = b.CurrencyId
		GROUP BY b.rptdate

		DROP TABLE #ExchangeOANDA
		DROP TABLE #Licensees
		DROP TABLE #MetricChargeInfo
		DROP TABLE #PartyChargeByCurrencyInfo
		DROP TABLE #PartyChargeInfo
	END

	-- Result
	DECLARE @DateList VARCHAR(2000) = '[FullRange]', @ReturnColumns VARCHAR(2000)

	DECLARE @SporttypeGroup TABLE (OrderId INT, SportTypeGroup INT, ProductCode VARCHAR(100))
	INSERT INTO @SporttypeGroup (OrderId, SportTypeGroup, ProductCode)
				SELECT 1 AS OrderId,  1 AS SportTypeGroup, 'Soccer'			AS ProductCode
	UNION ALL	SELECT 2 AS OrderId, -3 AS SportTypeGroup, 'SabaSoccer'		AS ProductCode
	UNION ALL	SELECT 3 AS OrderId,  2 AS SportTypeGroup, 'Basketball'		AS ProductCode
	UNION ALL	SELECT 4 AS OrderId, -4 AS SportTypeGroup, 'SabaBasketball' AS ProductCode
	UNION ALL	SELECT 5 AS OrderId,  5 AS SportTypeGroup, 'Tennis'			AS ProductCode
	UNION ALL	SELECT 6 AS OrderId, 43 AS SportTypeGroup, 'E-Sports'		AS ProductCode
	UNION ALL	SELECT 7 AS OrderId, 99 AS SportTypeGroup, 'OS'				AS ProductCode
	UNION ALL	SELECT 8 AS OrderId, -5 AS SportTypeGroup, 'SabaCricket'	AS ProductCode
	UNION ALL	SELECT 9 AS OrderId, -2 AS SportTypeGroup, 'Parlay'			AS ProductCode

	CREATE TABLE #Result (OrderId INT, rptDate VARCHAR(10), ProductCode VARCHAR(50), HouseIncome MONEY, ExtraPT MONEY, PaytoMuayThai MONEY DEFAULT(0), PaytoMetricGaming MONEY DEFAULT(0), PayToBetBuilder MONEY DEFAULT(0))
	
	;WITH CTE_rptDate AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #Result (OrderId, rptDate, ProductCode, HouseIncome, ExtraPT)
	SELECT s.OrderId, CONVERT(VARCHAR(2), r.rptDate, 106) AS rptDate, s.ProductCode, SUM(ISNULL(t.HouseIncome, 0)), SUM(ISNULL(t.ExtraPT, 0))
	FROM CTE_rptDate r
		CROSS JOIN @SporttypeGroup s
		LEFT JOIN #tempData t ON r.rptDate = t.rptDate AND s.SportTypeGroup = t.SporttypeGroup
	GROUP BY s.OrderId, CONVERT(VARCHAR(2), r.rptDate, 106), s.ProductCode
	OPTION (MAXRECURSION 0)

	DROP TABLE #tempData

	INSERT INTO #Result (OrderId, rptDate, ProductCode, HouseIncome, ExtraPT)
	SELECT OrderId, 'FullRange', ProductCode, SUM(HouseIncome), SUM(ExtraPT)
	FROM #Result
	GROUP BY OrderId, ProductCode

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

	DROP TABLE #__PayToSupplierSB

	UPDATE #Result
	SET PaytoMuayThai		= CASE WHEN ProductCode <> 'OS' THEN NULL ELSE PaytoMuayThai END
		,PaytoMetricGaming	= CASE WHEN ProductCode <> 'Soccer' THEN NULL ELSE PaytoMetricGaming END
		,PayToBetBuilder	= CASE WHEN ProductCode <> 'Soccer' THEN NULL ELSE PayToBetBuilder END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #Result WHERE rptDate <> 'FullRange' AND ProductCode = 'Soccer' ORDER BY rptDate
	SELECT @ReturnColumns = 'ProductCode,[Order],Figure,' + @DateList

	-- Output
	SELECT @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT OrderId, ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value
								FROM #Result
									CROSS APPLY (
												  SELECT 1, ''House Income''			, HouseIncome		WHERE HouseIncome IS NOT NULL
										UNION ALL SELECT 3, ''Extra PT''				, ExtraPT			WHERE ExtraPT IS NOT NULL
										UNION ALL SELECT 6, ''Pay to Muay Thai''		, PaytoMuayThai		WHERE PaytoMuayThai IS NOT NULL
										UNION ALL SELECT 7, ''Pay to Metric Gaming''	, PaytoMetricGaming WHERE PaytoMetricGaming IS NOT NULL
										UNION ALL SELECT 8, ''Pay to Bet Genius''		, PayToBetBuilder	WHERE PayToBetBuilder IS NOT NULL
									) c ([Order], Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p
							ORDER BY [Order], OrderId'
	EXEC(@SQL)

	DROP TABLE #Result
END
GO
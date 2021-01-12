/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_SB_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*
	Created: 20180126@Harper
	DB: DBWH-bodb02
	Task: House Net Income - Sportsbook Margin [RedmineID: #89632]
	
	Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin [RedmineID: #89632]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @SQL VARCHAR(MAX)

	-- Get licensee charge rate
	BEGIN
		DECLARE @f_date VARCHAR(10), @t_date VARCHAR(10)
		SELECT  @f_date = CONVERT(VARCHAR(10), @FDate, 120), @t_date = CONVERT(VARCHAR(10), @TDate, 120)
		-- Licensees by product
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT)

		SELECT @SQL = '	SELECT OldRefId, PartyId
						FROM OPENQUERY(DBLIC, ''SELECT DISTINCT p.OldRefId, p.PartyId
												FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
													INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
													INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
													INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
												WHERE p.PartyType = 1
													AND pd.IsDeposit = 1
													AND ci.ToParty IN (1, 9, 11, 98)
													AND ci.ProductId IN (0, 3)
													AND (
														(ci.FromDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
														OR (ci.ToDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
														OR (ci.FromDate < ''''' + @f_date + ''''' AND ''''' + @t_date + ''''' < ci.ToDate)
													)''
										)'
		INSERT INTO #Licensees (LicenseeId, PartyId)
		EXEC (@SQL)

		-- Get charge rate
		DECLARE @PartyIDs VARCHAR(MAX)
		SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees
		
		CREATE TABLE #PartyChargeInfo (ChargeId INT, LicenseeId INT, PartyId INT, ProductDWId INT, Product3rdId INT, Bettype INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		
		SELECT @SQL = '	SELECT ChargeId, PartyId, ProductId, Bettype, FromDate, ToDate, Rate
						FROM OPENQUERY(DBLIC, ''SELECT ci.ChargeId, ci.PartyId, ci.ProductId, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB,BA'''', ''''OA'''', 1) ci
													LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
												WHERE ci.ChargeType = 1
													AND ci.DI_Rate > 0''
										)'
		
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, Product3rdId, Bettype, FromDate, ToDate, Rate)
		EXEC (@SQL)

		UPDATE p
		SET p.LicenseeId = l.LicenseeId, p.ProductDWId = CASE WHEN p.Product3rdId = 0 THEN 10001 ELSE 10004 END
		FROM #PartyChargeInfo p
			INNER JOIN #Licensees l ON p.PartyId = l.PartyId

		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)

		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIDs + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB,BA'''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1
													AND ci.DI_Rate > 0''
										)'

		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)

		DROP TABLE #Licensees
	END

	-- Get exchange rate
	BEGIN
		DECLARE @ExFromDate SMALLDATETIME, @ExToDate SMALLDATETIME, @tmpDate DATE
		SELECT @ExFromDate = @FromDate, @ExToDate = @ToDate

		CREATE TABLE #ExchangeDaily (ExchangeDate DATE, Currency INT, Rate FLOAT, PRIMARY KEY (ExchangeDate, Currency))
		INSERT INTO #ExchangeDaily (ExchangeDate, Currency, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @ExFromDate AND @ExToDate

		CREATE TABLE #Exchange (Currency INT, FromDate DATE, ToDate DATE, Rate FLOAT)

		SELECT @tmpDate = @FDate

		INSERT INTO #Exchange (Currency, FromDate, ToDate, Rate)
		SELECT Currency, @tmpDate, @tmpDate, Rate FROM #ExchangeDaily WHERE ExchangeDate = @tmpDate

		WHILE 1 = 1
		BEGIN
			SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)

			IF NOT EXISTS (SELECT 1 FROM #ExchangeDaily WHERE ExchangeDate = @tmpDate)
				BREAK

			UPDATE e
			SET e.ToDate = @tmpDate
			FROM #Exchange e
				INNER JOIN #ExchangeDaily ed ON e.Currency = ed.Currency AND DATEADD(DAY, 1, e.ToDate) = ed.ExchangeDate
			WHERE ed.ExchangeDate = @tmpDate AND e.Rate = ed.Rate

			INSERT INTO #Exchange (Currency, FromDate, ToDate, Rate)
			SELECT Currency, @tmpDate, @tmpDate, Rate FROM #ExchangeDaily ed
			WHERE ExchangeDate = @tmpDate
				AND NOT EXISTS (SELECT 1 FROM #Exchange e WHERE e.Currency = ed.Currency AND e.ToDate = @tmpDate)
		END

		DROP TABLE #ExchangeDaily
	END

	-- Get site
	BEGIN
		DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO @tmpSite (LicenseeId, SiteName)
		SELECT LicenseeId, RTRIM(LTRIM(LicenseeName))
		FROM DBLIC.bodb_licensee.dbo.Licensees WITH (NOLOCK)
		WHERE IsDeposit = 1

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM @tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData (rptDate DATE, LicenseeId INT, ProductDWId INT, CurrencyId INT, MemberWL MONEY, MemberTO MONEY)
		INSERT INTO #__tempData (rptDate, LicenseeId, ProductDWId, CurrencyId, MemberWL, MemberTO)
		SELECT f.rptDate, s.LicenseeId, f.ProductId, f.CurrencyId, SUM(f.MemberWinloss) AS MemberWL, SUM(f.MemberTurnover) AS MemberTO
		FROM bodb_Account.dbo.FactLADailyWinloss f WITH (NOLOCK)
			INNER JOIN @tmpSite s ON f.SiteId = s.SiteId_DW
		WHERE f.rptDate BETWEEN @FDate AND @TDate
			AND f.SiteId NOT IN (-2, -4)
			AND f.ProductId IN (10001, 10004)
			AND f.Bettype NOT IN (901, 902, 903, 904)
			AND f.CurrencyId <> 20
			AND f.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		GROUP BY f.rptDate, s.LicenseeId, f.ProductId, f.CurrencyId
		OPTION (RECOMPILE)

		CREATE TABLE #__tempResult (rptDate DATETIME, PartyId INT, Product3rdId INT, AmountToCompany MONEY, Turnover MONEY, IsApplyMinFee BIT DEFAULT(1))
		INSERT INTO #__tempResult (rptDate, PartyId, Product3rdId, AmountToCompany, Turnover)
		SELECT t.rptDate, p.PartyId, p.Product3rdId, SUM(-t.MemberWL * ISNULL(pc.Rate, p.Rate) * e.Rate), SUM(ISNULL(t.MemberTO, 0) * ISNULL(pc.Rate, p.Rate) * e.Rate)
		FROM #__tempData t
			INNER JOIN #Exchange e ON t.CurrencyId = e.Currency AND t.rptDate BETWEEN e.FromDate AND e.ToDate
			INNER JOIN #PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductDWId = p.ProductDWId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN #PartyChargeByCurrencyInfo pc ON p.ChargeId = pc.ChargeId AND t.CurrencyId = pc.CurrencyId
		GROUP BY t.rptDate, p.PartyId, p.Product3rdId
	END

	DROP TABLE #__tempData
	DROP TABLE #Exchange
	DROP TABLE #PartyChargeInfo
	DROP TABLE #PartyChargeByCurrencyInfo

	-- Calculate result
	CREATE TABLE #Result (rptDate VARCHAR(10), HouseIncome MONEY, Turnover MONEY)
	;WITH CTE_rptDate AS
	(
		SELECT CONVERT(DATETIME, @FDate) AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #Result (rptDate, HouseIncome, Turnover)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106) AS rptDate, SUM(ISNULL(t.AmountToCompany, 0)), SUM(ISNULL(t.Turnover, 0))
	FROM CTE_rptDate r
		LEFT JOIN #__tempResult t ON r.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106)
	ORDER BY rptDate
	OPTION (MAXRECURSION 0)

	DROP TABLE #__tempResult

	DECLARE @DateList VARCHAR(2000), @ReturnColumns VARCHAR(2000)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #Result

	SELECT @ReturnColumns = '''SB'' AS ProductCode,1 AS [Order],Figure,' + @DateList
	SELECT @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT [Order], [RptDate], Figure, ISNULL(value, 0) value
								FROM #Result
									CROSS APPLY (
												  SELECT 1, ''House Income'', HouseIncome	WHERE HouseIncome IS NOT NULL
										UNION ALL SELECT 2, ''Turn Over''	, Turnover		WHERE Turnover IS NOT NULL
									) c ([Order], Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p
							ORDER BY [Order]'
	EXEC(@SQL)

	DROP TABLE #Result
END
GO
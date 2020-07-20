/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PP_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20180612@Harper  
    Task :		House month-to-date Net Income report for Pramatic product
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20180618@Harper - HDWL Letstalk - Implement report for Pramatic product [#RedmineID: 94403]
		- 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
		- 20191121@Robert: #123733 - Email/Letstalk Reports - Integrate PP Tournament (Exclude bettype 4299)
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200715@Percy: Integrate PP Jackpot [RedmineID: #137280]

	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_PP_Deposit '20180601', '20180630'   
*/

BEGIN
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 32, @ProductPrefix VARCHAR(5) = 'PP'

	-- Region: Active licensees
	DECLARE @tmpAllParty TABLE (PartyID INT, ParentID INT, LicenseeID INT)
	INSERT INTO @tmpAllParty (PartyID, ParentID, LicenseeID)
	SELECT PartyID, ParentID, OldRefID
	FROM (
		SELECT ci.FromParty AS PartyID, ci.ToParty AS ParentID, p.OldRefID
			,ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE ci.ChargeType = 1
			AND p.PartyType = 1
			AND pd.IsDeposit = 1
			AND ci.ToParty IN (1, 9, 11, 98)
	) AS r
	WHERE r.RowNum = 1

	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT)
	INSERT INTO @tmpParty (PartyID, ParentID)
	SELECT DISTINCT ci.FromParty, ci.ToParty
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
	WHERE p.PartyType = 1
		AND pd.IsDeposit = 1
		AND ci.ProductId = @ProductID
		AND (
			(ci.FromDate BETWEEN @FDate AND @TDate)
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty
	-- End Region

	-- Region: Get charge rate
	CREATE TABLE #PartyChargeInfo
	(
		ChargeID	INT
		,PartyID    INT
		,LicenseeID INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
		,Bettype    INT
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, Rate, Fromdate, Todate, Bettype)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE ci.DI_Rate > 0

	-- Region: Get Exchange
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataDW
	(
		rptDate					DATE
		,LicenseeID				INT
		,CurrencyID				INT
		,LicenseeWL				MONEY
		,HouseWL				MONEY
		,LicenseeContribution	MONEY
		,FullContribution		MONEY
		,MegaPrize				MONEY
	)

	CREATE TABLE #Site (SiteID_DW INT, LicenseeID INT, SiteName VARCHAR(20))
	INSERT INTO #Site (SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName
	FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE isDeposit = 1

	UPDATE s
	SET s.LicenseeID = l.LicenseeID
	FROM #Site s
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName  = RTRIM(LTRIM(l.LicenseeName))

	CREATE TABLE #Bettype (BetType INT)
	INSERT INTO #Bettype (BetType)
	SELECT BetType FROM dbo.f_SportBettypeMatrixByProduct_Sel (@ProductID, 0)
	WHERE Bettype NOT IN (4298, 4299, 4300)

	INSERT INTO #tempDataDW (rptDate, LicenseeID, CurrencyID, LicenseeWL, HouseWL, LicenseeContribution, FullContribution, MegaPrize)
	SELECT b.rptDate, s.LicenseeID, b.CurrencyID
		,SUM(CASE WHEN b.bettype IN (4297, 4298) THEN 0 ELSE -b.WinlossP END) AS LicenseeWL
		,SUM(CASE WHEN b.bettype IN (4297, 4298) THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
		,SUM(CASE WHEN b.bettype = 4297 THEN -b.WinlossA ELSE 0 END) AS LicenseeContribution
		,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
		,SUM(CASE WHEN b.bettype = 4298 THEN b.WinlossP ELSE 0 END) AS MegaPrize
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN #Site s ON b.SiteID = s.SiteID_DW
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		AND EXISTS (SELECT 1 FROM #Bettype bt WITH (NOLOCK) WHERE b.BetType = bt.BetType)
	GROUP BY b.rptDate, s.LicenseeID, b.CurrencyID

	CREATE TABLE #tempData
	(
		rptDate				DATETIME
		,AmountToCompany	MONEY
		,FullContribution	MONEY
		,MegaPrize			MONEY
	)
	INSERT INTO #tempData (rptDate, AmountToCompany, FullContribution, MegaPrize)
	SELECT
		b.rptDate
		,SUM(CASE WHEN p.LicenseeID IS NULL THEN -b.HouseWL ELSE (b.LicenseeWL - b.LicenseeContribution) * ISNULL(lc.Rate, p.Rate) END * ISNULL(e.Rate, 0))
		,SUM(b.FullContribution)
		,SUM(b.MegaPrize)
	FROM #tempDataDW b
		INNER JOIN @tmpAllParty tp ON tp.LicenseeID = b.LicenseeID
		LEFT JOIN #PartyChargeInfo p
			ON		p.PartyID = tp.PartyID
				AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	GROUP BY b.rptDate
	-- End Region

	CREATE TABLE #FeeData (PartyID INT, ProductID INT, AComm MONEY, MinFeeApplied MONEY, WLFeeApplied MONEY, AmountToCompany MONEY)
    INSERT INTO #FeeData (PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = @ProductPrefix

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY, FullContribution MONEY, MegaPrize MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, FullContribution, MegaPrize)
	SELECT 'FullRange', ISNULL(SUM(AmountToCompany), 0), ISNULL(SUM(FullContribution), 0), ISNULL(SUM(MegaPrize), 0)
	FROM #FeeData

	;WITH CTE_rptDate AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (RptDate, LicenseeWL, FullContribution, MegaPrize)
	SELECT CONVERT(VARCHAR(2), d.rptDate, 106), SUM(ISNULL(t.AmountToCompany, 0)), SUM(ISNULL(t.FullContribution, 0)), SUM(ISNULL(t.MegaPrize, 0))
	FROM CTE_RptDate d
		LEFT JOIN #tempData t ON d.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), d.rptDate, 106)
	OPTION (MAXRECURSION 0)

	CREATE TABLE #PayToSupplier (ProductCode VARCHAR(50), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay	MONEY)
	INSERT INTO #PayToSupplier (ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier @FromDate = @FDate, @ToDate = @TDate, @ProductCodes = @ProductPrefix, @DepositType = 1

	UPDATE f
	SET f.PayToSupplier = p.PayToSupplier
	FROM #FinalResult f
		INNER JOIN #PayToSupplier p ON f.rptDate = p.rptDate

    DECLARE @DateList VARCHAR(200)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT  @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 2, ''Pay to supplier'', PayToSupplier' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + '-JP'', 3, ''Contribution Amount'', FullContribution' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + '-JP'', 4, ''Mega Prize'', MegaPrize) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC (@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Bettype
	DROP TABLE #Exchange
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #PartyChargeInfo
	DROP TABLE #Site
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	DROP TABLE #PayToSupplier
	-- End Region
END
GO
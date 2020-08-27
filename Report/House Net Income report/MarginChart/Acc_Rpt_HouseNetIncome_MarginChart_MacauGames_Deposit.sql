/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_MacauGames_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS

/*
	Created:	20180126@Harper 
	Task:		HDWL Letstalk - Implement Chart of NonSport product margin
    DB:			DBEXT-bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200403@Percy: Integrate Blueprint's games - Macau Games [RedmineID: #131755]
		- 20200827@Percy: Use table to apply Blueprint's games - Macau Games [RedmineID: #140459]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_MacauGames_Deposit '2018-04-01', '2018-04-30'
*/ 

BEGIN  
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 22, @ProductPrefix VARCHAR(5) = 'VB'

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

	DECLARE @tmpParty TABLE (PartyID INT, ParentID INT, LicenseeID INT)
	INSERT INTO @tmpParty (PartyID, ParentID, LicenseeID)
	SELECT DISTINCT p.PartyID, ci.ToParty, p.OldRefID
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
    -- End region

	-- Region: Get charge rate
	CREATE TABLE #PartyChargeInfo
	(
		ChargeID	INT
		,PartyID    INT
		,LicenseeID INT
		,ParentID	INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
		,Bettype	INT
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ParentID, Rate, FromDate, ToDate, Bettype)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.FromDate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE ci.ChargeType = 1
		AND ci.DI_Rate > 0
	-- End Region

	-- Region: Get Exchange
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #tempDataDW
	(
		rptDate		DATE
		,LicenseeID	INT
		,CurrencyID	INT
		,BetType	INT
		,MemberWL	MONEY
		,HouseWL	MONEY
	)

	CREATE TABLE #Site (SiteID_DW INT, LicenseeID INT, SiteName VARCHAR(20))
	INSERT INTO #Site (SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName
	FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE isDeposit = 1

	UPDATE s
	SET s.LicenseeID = l.LicenseeID
	FROM #Site s
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName  = RTRIM(LTRIM(l.LicenseeName))

	CREATE TABLE #Bettype (BetType INT, BetTypeGroup TINYINT) -- BetTypeGroup: 1 - Blueprint's Games, 2 - Normal Macau Games
	INSERT INTO #Bettype (BetType, BetTypeGroup)
	SELECT BetType, 2 FROM dbo.f_SportBettypeMatrixByProduct_Sel (@ProductID, 0)

	UPDATE #Bettype
	SET BetTypeGroup = 1
	WHERE BetType IN (SELECT BetType FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK) WHERE BettypeGroupID = 11)

	INSERT INTO #tempDataDW (rptDate, LicenseeID, CurrencyID, BetType, MemberWL, HouseWL)
	SELECT b.rptDate, s.LicenseeID, b.CurrencyID, b.BetType, SUM(ISNULL(b.WinlossP, 0)) AS MemberWL, SUM((b.WinlossIBC + b.CommissionS)) AS HouseWL
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN #Site s ON b.SiteID = s.SiteID_DW
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		AND EXISTS (SELECT 1 FROM #Bettype bt WITH (NOLOCK) WHERE b.BetType = bt.BetType)
	GROUP BY b.rptDate, s.LicenseeID, b.CurrencyID, b.BetType

	CREATE TABLE #tempData
	(
		PartyID				INT
		,ParentID			INT
		,rptDate			DATETIME
		,MemberWL			MONEY
		,PayToSupplier		MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #tempData (PartyID, ParentID, rptDate, MemberWL, PayToSupplier, AmountToCompany)
	SELECT
		tp.PartyID
		,tp.ParentID
		,b.rptDate
		,SUM(ISNULL(b.MemberWL, 0) * ISNULL(oa.Rate, 0))
		,SUM(ISNULL(b.MemberWL, 0) * ISNULL(oa.Rate, 0) * CASE WHEN bt.BetTypeGroup = 1 THEN 0.045 ELSE 0.035 END)
		,SUM(CASE WHEN p.LicenseeID IS NULL THEN -ISNULL(b.HouseWL, 0) ELSE -ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) END * ISNULL(e.Rate, 0))
	FROM #tempDataDW b
		INNER JOIN #Bettype bt ON b.BetType = bt.BetType
		INNER JOIN @tmpAllParty tp ON tp.LicenseeID = b.LicenseeID
		LEFT JOIN #PartyChargeInfo p ON p.PartyID = tp.PartyID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		LEFT JOIN #ExchangeOANDA oa ON b.rptDate = oa.ExchangeDate AND b.CurrencyId = oa.ExchangeID
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	GROUP BY
		tp.PartyID
		,tp.ParentID
		,b.rptDate
    -- End region

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY, PayToSupplier MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, 0

	;WITH CTE_rptDate AS
	(
		SELECT CONVERT(DATETIME, @FDate) AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106), SUM(ISNULL(t.AmountToCompany, 0)), SUM(ISNULL(t.PayToSupplier, 0))
	FROM CTE_rptDate r
		LEFT JOIN #tempData t ON r.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106)
	OPTION (MAXRECURSION 0)
	
	DECLARE @DateList VARCHAR(1000)
	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT	@SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', LicenseeWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #PartyChargeInfo
	DROP TABLE #Site
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	-- End Region
END
GO
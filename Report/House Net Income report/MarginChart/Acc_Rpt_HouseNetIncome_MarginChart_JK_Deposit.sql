/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_JK_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: 20200922@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Integrate Joker Gaming - Deposit
	
	Revisions:  
		- 20200922@Percy: Initialize SP [RedmineID: #131602]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductID INT = 56, @ProductPrefix VARCHAR(5) = 'JK'

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
		AND ci.ToParty IN (1, 9, 11, 98)
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
		,ParentID	INT
		,Rate       MONEY
		,FromDate   SMALLDATETIME
		,ToDate     SMALLDATETIME
		,Bettype    INT
		,ChargeType	INT
	)
	INSERT INTO #PartyChargeInfo (ChargeID, PartyID, LicenseeID, ParentID, Rate, Fromdate, Todate, Bettype, ChargeType)
	SELECT ci.ChargeID, ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype), ci.ChargeType
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) ci
		INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE ci.DI_Rate > 0
	-- End Region
	
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

	CREATE TABLE #Bettype (BetType INT)
	INSERT INTO #Bettype (BetType)
	SELECT BetType FROM dbo.f_SportBettypeMatrixByProduct_Sel (@ProductID, 0)

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
		rptDate				DATETIME
		,PayToSupplier		MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #tempData (rptDate, AmountToCompany)
	SELECT b.rptDate, SUM(CASE WHEN p.LicenseeID IS NULL THEN -ISNULL(b.HouseWL, 0) ELSE -ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) END * ISNULL(e.Rate, 0))
	FROM #tempDataDW b
		INNER JOIN @tmpAllParty tp ON tp.LicenseeID = b.LicenseeID
		LEFT JOIN #PartyChargeInfo p
			ON		p.PartyID = tp.PartyID
				AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		LEFT JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyID = e.ExchangeID
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeID = lc.ChargeID AND b.CurrencyID = lc.CurrencyID
	GROUP BY b.rptDate
	-- End Region

	CREATE TABLE #FinalResult (rptDate VARCHAR(10), LicenseeWL MONEY)
	INSERT INTO #FinalResult (rptDate, LicenseeWL)
	SELECT 'FullRange', 0

	DECLARE @tmpDate DATETIME, @DateList VARCHAR(200)
	SELECT  @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL)
		SELECT
			CONVERT(VARCHAR(2), @tmpDate, 106)
			,ISNULL(SUM(AmountToCompany), 0)
		FROM #tempData
		WHERE rptDate = @tmpDate

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT	@SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', LicenseeWL) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #FinalResult
	DROP TABLE #PartyChargeInfo
	DROP TABLE #Site
	DROP TABLE #tempData
	DROP TABLE #tempDataDW
	-- End Region
END
GO
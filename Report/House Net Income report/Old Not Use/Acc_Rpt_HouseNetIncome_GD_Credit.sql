/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_GD_Credit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created:	20170213@Harper  
    Task :		House month-to-date Net Income report for Gold Deluxe
    DB:			DBWH/bodb_dwrs  
   
    Revisions:
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_GD_Credit '20161101', '20161130' 
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @tmpFDate DATETIME, @tmpTDate DATETIME
	SELECT  @tmpFDate = @FromDate, @tmpTDate = @ToDate

	DECLARE @SQL VARCHAR(MAX)
	DECLARE @f_date VARCHAR(10), @t_date VARCHAR(10)
	SELECT  @f_date = CONVERT(VARCHAR(10), @FDate, 120), @t_date = CONVERT(VARCHAR(10), @TDate, 120)

	DECLARE @CommissionRate FLOAT
	
	CREATE TABLE #Licensees (GroupPartyId INT, ParentId INT, LicenseeId INT)
	CREATE TABLE #ParentCharge3rdInfo (ChargeType INT, ParentId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
	CREATE TABLE #PartyCharge3rdInfo (ChargeType INT, GroupPartyId INT, LicenseeId INT, FromDate DATE, ToDate DATE, Rate FLOAT)

	-- Credit licensees by product
	SELECT @SQL = '	SELECT PartyId, 999, LabelId
					FROM OPENQUERY(DBLIC, ''SELECT DISTINCT p.PartyId, lb.LabelId
											FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
												INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
												INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
												INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
												INNER JOIN bodb_Licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefId = lb.LicenseeId
											WHERE p.PartyType = 1
												AND pd.IsDeposit = 0
												AND ci.ProductId = 11
												AND (
													(ci.FromDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.ToDate BETWEEN ''''' + @f_date + ''''' AND ''''' + @t_date + ''''')
													OR (ci.FromDate < ''''' + @f_date + ''''' AND ''''' + @t_date + ''''' < ci.ToDate)
												)''
									)'
	INSERT INTO #Licensees (GroupPartyId, ParentId, LicenseeId)
	EXEC (@SQL)

	-- Charge rate
	SELECT @SQL = '	SELECT ChargeType, PartyId, FromDate, ToDate, DI_Rate
					FROM OPENQUERY(DBLIC, ''SELECT DISTINCT ChargeType, PartyId, FromDate, ToDate, DI_Rate
											FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''GD'''', ''''OA'''')
											WHERE ChargeType IN (1, 9, 10, 11) AND IsDeposit = 0''
									)'


	
	
	INSERT INTO #ParentCharge3rdInfo (ChargeType, ParentId, FromDate, ToDate, Rate)
	EXEC (@SQL)

	INSERT INTO #PartyCharge3rdInfo (ChargeType, GroupPartyId, LicenseeId, FromDate, ToDate, Rate)
	SELECT DISTINCT p.ChargeType, l.GroupPartyId, l.LicenseeId, p.FromDate, p.ToDate, p.Rate
	FROM #ParentCharge3rdInfo p
		INNER JOIN #Licensees l ON p.ParentId = l.ParentId

    SELECT @CommissionRate = Rate FROM #PartyCharge3rdInfo WHERE ChargeType = 11
	SELECT @CommissionRate = ISNULL(@CommissionRate, 0)

	DROP TABLE #Licensees
	DROP TABLE #ParentCharge3rdInfo

	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)	
	INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
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

	CREATE TABLE #Bettype (bettype INT)
	INSERT INTO #Bettype (bettype)
	SELECT DISTINCT bettype FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK) WHERE ProductId = 12

	CREATE TABLE #tmpData (rptDate DATE, GroupPartyId INT, HouseIncome MONEY, ExtraPT MONEY, PaytoSupplier MONEY)

	-- House Income, Extra PT
	BEGIN
		INSERT INTO #tmpData (rptDate, HouseIncome, ExtraPT)
		SELECT f.rptDate
			,-SUM((f.winlossP + f.winlossS + f.winlossM + f.winlossA + f.commissionS) * ISNULL(e.Rate, 0))
			,SUM((f.ExtraWL + f.ExtraComm) * ISNULL(e.Rate, 0))
		FROM bodb_Account.dbo.FactSiteWinloss f WITH (NOLOCK)
			INNER JOIN #Bettype b ON f.BetType = b.bettype
			LEFT JOIN #Exchange e ON f.rptDate = e.ExchangeDate AND f.CurrencyId = e.ExchangeId
		WHERE f.rptDate BETWEEN @FDate AND @TDate
			AND f.CurrencyId <> 20
			AND f.TicketStatus NOT IN (-1, 18, 9, 10, 14)
			AND EXISTS (SELECT 1 FROM bodb_Account.dbo.tbl_Site s WITH (NOLOCK) WHERE f.SiteId = s.SiteId AND s.IsDeposit = 0)
		GROUP BY f.rptDate
		OPTION (RECOMPILE)
	END

	DROP TABLE #Bettype
	DROP TABLE #Exchange
	
	-- PaytoSupplier
	BEGIN
		WITH CTE_tmpData AS (
			SELECT rptDate, SiteId, CurrencyId, SUM(MemberWL) AS MemberWL, SUM(ValidBetAmount) AS ValidBetAmount
			FROM DBLIC.bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
			WHERE rptDate BETWEEN @tmpFDate AND @tmpTDate
				AND CurrencyId <> 20
				AND CustomerCategory NOT IN(27, 28)
				AND StatusId NOT IN (-1, 101, 102, 103)
				AND SiteId > 1000
				AND ProductId = 11
			GROUP BY rptDate, SiteId, CurrencyId
		)
		INSERT INTO #tmpData (rptDate, GroupPartyId, PaytoSupplier)
		SELECT t.rptDate, p.GroupPartyId
			,SUM(ISNULL(oa.Rate, 0) * ISNULL(p.Rate, 0)
				* (t.MemberWL
					+ CASE
						WHEN p.ChargeType = 10 THEN t.ValidBetAmount * @CommissionRate
						ELSE 0 END
					)
				) AS PaytoSupplier
		FROM CTE_tmpData t
			INNER JOIN #PartyCharge3rdInfo p ON t.SiteId = p.LicenseeId AND p.ChargeType <> 11
			LEFT JOIN #ExchangeOANDA oa ON t.rptDate = oa.ExchangeDate AND t.CurrencyId = oa.ExchangeId
		GROUP BY t.rptDate, p.GroupPartyId
		OPTION (RECOMPILE)
	END

	DROP TABLE #ExchangeOANDA
	DROP TABLE #PartyCharge3rdInfo

	-- Result
	CREATE TABLE #FinalResult (rptDate VARCHAR(10), HouseIncome MONEY, ExtraPT MONEY, PaytoSupplier MONEY)
	
	;WITH CTE_rptDate AS (
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (rptDate, HouseIncome, ExtraPT, PaytoSupplier)
	SELECT CONVERT(VARCHAR(2), r.rptDate, 106)
		,SUM(ISNULL(t.HouseIncome, 0))
		,SUM(ISNULL(t.ExtraPT, 0))
		,SUM(ISNULL(t.PaytoSupplier, 0))
	FROM CTE_rptDate r
		LEFT JOIN #tmpData t ON r.rptDate = t.rptDate
	GROUP BY CONVERT(VARCHAR(2), r.rptDate, 106)

	INSERT INTO #FinalResult (rptDate, HouseIncome, ExtraPT, PaytoSupplier)
	SELECT 'FullRange', SUM(HouseIncome), SUM(ExtraPT), SUM(CASE WHEN PaytoSupplier < 0 THEN PaytoSupplier ELSE 0 END)
	FROM (
		SELECT SUM(HouseIncome) AS HouseIncome, SUM(ExtraPT) AS ExtraPT, SUM(PaytoSupplier) AS PaytoSupplier
		FROM #tmpData
		GROUP BY GroupPartyId
	) t

	DROP TABLE #tmpData

	DECLARE @DateList VARCHAR(2000) = '[FullRange]', @ReturnColumns VARCHAR(2000)
	SELECT @DateList = @DateList + ',' + '[' + rptDate + ']' FROM #FinalResult WHERE rptDate <> 'FullRange' ORDER BY rptDate

	SELECT @ReturnColumns = '''GD'' AS ProductCode,[Order],Figure,' + @DateList
	SELECT  @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT [Order], [RptDate], Figure, ISNULL(value, 0) value
								FROM #FinalResult
									CROSS APPLY (
												  SELECT  1, ''House Income''	, HouseIncome
										UNION ALL SELECT  2, ''Extra PT''		, ExtraPT
										UNION ALL SELECT  5, ''Pay to supplier'', PayToSupplier
									) c ([Order], Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p
							ORDER BY [Order]'
	EXEC(@SQL)
	
	DROP TABLE #FinalResult
END
GO
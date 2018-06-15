/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_KN_LT_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin
    Source :		Acc_Rpt_HouseNetIncome_KN_Deposit
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin (Keno + Lottery) [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_KN_Deposit '2018-04-01', '2018-04-30'
  
*/ 
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, PartyGroup VARCHAR(20), Rate3rd FLOAT)
	INSERT INTO @tmpParty (PartyID, IsDeposit, PartyGroup, Rate3rd)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit , '', 0.05
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
	WHERE	p.PartyType = 1
			AND ci.ProductId IN (8, 28) -- KN + LT
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty

	UPDATE @tmpParty 
	SET PartyGroup = CASE 						
						WHEN IsDeposit = 1 AND PartyID = 14 THEN '12bet'
						ELSE 'Licensees'
					 END,
		Rate3rd = CASE 					
					WHEN IsDeposit = 1 AND PartyID = 14 THEN 0.03
					ELSE 0.05
				 END
	-- End region

	DECLARE @PartyChargeInfo AS TABLE (
			PartyId			INT,
			LicenseeId		INT,
			IsDeposit		BIT,
			ProductID		INT,
			Rate			MONEY,
			FromDate		SMALLDATETIME,
			ToDate			SMALLDATETIME,
			Bettype			INT)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT	ci.PartyID, ci.LicenseeID, ci.isDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'KN,LT', 'OA', 1) ci
			LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)

	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End region

	CREATE	TABLE #TempDataKNLT (
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			WinLoss			MONEY,
			AComm			MONEY,
			ProductId		TINYINT,
			AmountToCompany MONEY)

	INSERT INTO #TempDataKNLT (PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,AmountToCompany)
	(
		SELECT	p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)),
				SUM(ISNULL(b.CommissionA, 0)) * e.Rate,
				p.ProductId,
				SUM(-ISNULL(b.MemberWL, 0) * p.Rate) * e.Rate
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataKNLT (PartyId, ProductId)
		
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)
	
	DECLARE @DailyPayAmt TABLE (rptDate DATE, PartyGroup VARCHAR(20), Amount MONEY, LicenseeWL MONEY, KNRate FLOAT)
	
	INSERT INTO @DailyPayAmt (rptDate, PartyGroup, Amount, LicenseeWL, KNRate)
	SELECT d.rptDate, p.PartyGroup, SUM(d.WinLoss * oanda.Rate * p.Rate3rd), SUM(-d.WinLoss * oanda.Rate), p.Rate3rd
	FROM #TempDataKNLT d
		INNER JOIN @tmpParty p ON p.PartyID = d.PartyId
		INNER JOIN #ExchangeOANDA oanda ON d.rptDate = oanda.ExchangeDate AND d.CurrencyId = oanda.ExchangeID
	GROUP BY d.rptDate, p.PartyGroup, p.Rate3rd
	
	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, 0

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #TempDataKNLT WHERE rptDate = @tmpDate), -- LicenseeWL
			(SELECT ISNULL(SUM(Amount), 0) FROM @DailyPayAmt WHERE rptDate = @tmpDate)			
		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''KNLT'', 1, ''House Income'', LicenseeWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''KNLT'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #TempDataKNLT
	--DROP TABLE #FeeData
	DROP TABLE #FinalResult
END
GO

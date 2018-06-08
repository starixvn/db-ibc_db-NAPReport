/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin
    Source :		Acc_Rpt_HouseNetIncome_FW_Deposit
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit '2018-04-01', '2018-04-30'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Region: Active licensees	

	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, LicenseeID INT, ParentID INT, Rate FLOAT, ChargeType INT)
	INSERT INTO @tmpParty( PartyID , IsDeposit , LicenseeID, ParentID)	
	SELECT DISTINCT p.PartyID, pd.IsDeposit,
		CASE 
			WHEN ISNULL(pd.IsDeposit, 0) = 1 
			THEN p.OldRefID 
			ELSE lb.LabelID 
		END AS LicenseeID,
		ci.ToParty
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID AND map.SystemID = 2 -- LA
		LEFT JOIN bodb_licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE p.PartyType = 1 -- Licensee
		AND ci.ProductID = 24 -- FW		
		AND ((ci.FromDate BETWEEN @FDate AND @TDate) 
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))		

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty WHERE IsDeposit = 1
	-- End region

	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			IsDeposit	BIT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT	ci.PartyID, ci.LicenseeID, ci.isDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype)
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'FW', 'OA', 1) ci
			LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	ci.isDeposit = 1 AND DI_Rate > 0 AND ProductId <> 1 --exclude RB 
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

	CREATE	TABLE #TempDataFW (
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			MemberWL		MONEY,
			AComm			MONEY,
			ProductId		TINYINT,
			AmountToCompany MONEY)

	INSERT INTO #TempDataFW (PartyId,rptDate,CurrencyId,MemberWL,AComm,ProductId,AmountToCompany)
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
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)
	
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataFW (PartyId, ProductId)	

	-- Region: Result	

	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)

	-- Pay to Supplier for Credit + Deposit (GMT +8)
	DECLARE @DailyPayAmt TABLE (RptDate DATE, IsDeposit INT, AmountDaily MONEY)
	
	;WITH rate3rd AS (
		SELECT DISTINCT	ci.IsDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ChargeType, p.LicenseeID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'FW', 'OA') ci	
				INNER JOIN @tmpParty p ON p.ParentID = ci.PartyID	
	)
	INSERT INTO @DailyPayAmt (RptDate, IsDeposit, AmountDaily)
	SELECT b.RptDate3rd, p.IsDeposit,		
		SUM(b.Winloss * oanda.Rate * p.DI_Rate)		
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN rate3rd p ON p.LicenseeID = b.SiteID 								
								AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
		INNER JOIN #ExchangeOANDA oanda ON b.RptDate3rd = oanda.ExchangeDate AND b.CurrencyId = oanda.ExchangeID
	WHERE	b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.Bettypeid BETWEEN 1011 AND 1020 -- FW
			AND b.CurrencyID <> 20				
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund				
	GROUP BY b.RptDate3rd, p.IsDeposit	

	--CREATE TABLE #FeeData (
	--	PartyId			INT,
	--	ProductID		INT,
	--	AComm			MONEY,
	--	MinFeeApplied	MONEY,
	--	WLFeeApplied	MONEY,
	--	AmountToCompany	MONEY
	--)

	--INSERT INTO #FeeData(PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
	--EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = 'FW'
	
	--DECLARE @PayToSupplier MONEY
	--SET @PayToSupplier = (SELECT SUM (CASE WHEN AmountDaily > 0 THEN 0 ELSE AmountDaily END)
	--						FROM (	SELECT SUM(AmountDaily) AS AmountDaily
	--								FROM @DailyPayAmt
	--								GROUP BY IsDeposit
	--							  ) s
	--					)
	--INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	--SELECT 'FullRange', 
	--		(SELECT CASE WHEN SUM(AmountToCompany) < 0 THEN 0 ELSE SUM(WLFeeApplied) END FROM #FeeData),
	--		@PayToSupplier

	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', 0, 0 
			
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
				(SELECT SUM(AmountToCompany) FROM #TempDataFW WHERE rptDate = @tmpDate),
				(SELECT SUM(AmountDaily) FROM @DailyPayAmt WHERE RptDate = @tmpDate)		

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''FW'', 1, ''House Income'', LicenseeWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''FW'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataFW
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit] TO vnteam
GO
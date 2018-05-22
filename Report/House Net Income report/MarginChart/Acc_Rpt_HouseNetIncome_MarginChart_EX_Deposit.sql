/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin
    Source :		Acc_Rpt_HouseNetIncome_EX_Deposit
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit '2018-04-01', '2018-04-30'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate	
	
	-- Region: Active licensees

	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, ParentID INT)
	INSERT INTO @tmpParty (PartyID, IsDeposit, ParentID)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit, ci.ToParty
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
	WHERE	p.PartyType = 1 AND pd.IsDeposit = 1
			AND ci.ProductId = 5 -- VS
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty
	-- End region
	
	-- Region: Get Licensees has charge rate
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ParentID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			ProductID	INT
			)

	DECLARE @PartyCharge3rdInfo AS TABLE (		
			LicenseeId	INT,
			Rate		MONEY,			
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			ProductID	INT
			)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ParentID, Rate, Fromdate, Todate, ProductID)
	(
		SELECT	ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'BX', 'OA', 1) ci	
			INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID	
		WHERE	DI_Rate > 0 AND ci.ChargeType = 1 -- get PT
	)
	
	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'BX', 'OA') ci	
			INNER JOIN @PartyChargeInfo p ON ci.IsParent = 0 AND p.PartyID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
	)

	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'BX', 'OA') ci	
			INNER JOIN @PartyChargeInfo p ON ci.IsParent = 1 AND p.ParentID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
			AND NOT EXISTS (SELECT 1 FROM @PartyCharge3rdInfo ci WHERE ci.LicenseeId = p.LicenseeId)
	)	
	-- End Region
	
	-- Region: Get Exchange
	CREATE	TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	
	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE	TABLE #TempDataEX (
			PartyId			INT,
			rptDate			DATETIME,
			ProductID		INT,
			CurrencyId		INT,
			MemberWL		MONEY,
			AComm			MONEY,
			PComm			MONEY,			
			AmountToCompany MONEY,
			PayToSupplier	MONEY,
			TurnOver		MONEY)

	INSERT INTO #TempDataEX (PartyId, rptDate, CurrencyId, MemberWL, AComm, PComm, ProductId, AmountToCompany, PayToSupplier, TurnOver)
	(
		SELECT	p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)),
				SUM(ISNULL(b.CommissionA, 0) * e.Rate),
				SUM(ISNULL(b.CommissionP, 0) * e.Rate) ,
				b.ProductId,
				SUM(-ISNULL(b.MemberWL, 0) * p.Rate * e.Rate),
				SUM(ISNULL(b.MemberWL, 0) * rd.Rate * e.Rate),
				SUM(ISNULL(b.Turnover, 0) * p.Rate * e.Rate)
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ExchangeOANDA e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID				
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)													
				INNER JOIN @PartyCharge3rdInfo rd ON b.ProductID = rd.ProductID
													AND b.SiteID = rd.LicenseeID
													AND (b.rptDate BETWEEN rd.FromDate AND rd.ToDate)	
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, b.ProductId
	)	
	
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY,
		TurnOver			MONEY
	)

	--INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	--SELECT 'FullRange', SUM(AmountToCompany) - SUM(AComm + PComm), SUM(PayToSupplier) + SUM(AComm + PComm)
	--FROM #TempDataEX

	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier, TurnOver)
	SELECT 'FullRange', 0, 0, 0

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			SUM(AmountToCompany) - SUM(AComm + PComm),
			SUM(PayToSupplier) + SUM(AComm + PComm),
			SUM(TurnOver)
		FROM #TempDataEX 
		WHERE rptDate = @tmpDate
			
		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''EX'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''EX'', 8, ''Turn Over'', TurnOver' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''EX'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #ExchangeOANDA
	DROP TABLE #TempDataEX
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit] TO vnteam
GO
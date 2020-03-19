/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SG_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20200224@Kean  
    Task :		Integrate SG (Spadegaming) product [RedmineID: #123734] 
    DB:			DBEXT/bodb02  
   
    Revisions:  
	   - 20200224@Kean: #123734 - House Net Income - Integrate SG (Spadegaming) product

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_SG_Deposit '20160901', '20160930'
*/  
BEGIN  
SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate	
	
	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 

	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,[VName]
		  ,[NumberValue]
		  ,[sporttype]
		  ,[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN bodb02.dbo.Products p WITH(NOLOCK) ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCashWLShareRate')
	AND p.ProductPrefix IN ('SG')

	-- Region: Active licensees
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, ParentID INT)
	INSERT INTO @tmpParty (PartyID, IsDeposit, ParentID)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit, ci.ToParty
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
	WHERE	p.PartyType = 1 AND pd.IsDeposit = 1
			AND ci.ProductId = 36
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty
	-- End region
	
	-- Region: Get Licensees has charge rate
	CREATE TABLE #PartyChargeInfo (
		ChargeId	INT
	  , PartyId       INT
	  , LicenseeId    INT
	  , ParentID	  INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

	-- BEGIN - Rate for PayToSupplier
	CREATE TABLE #PartyCharge3rdInfo_Direct (		
			IsDeposit	INT,
			ProductID		INT,			
			DI_Rate	MONEY,
			Fromdate		SMALLDATETIME,
			ToDate	SMALLDATETIME,
			PartyID		INT
			)

	CREATE TABLE #PartyCharge3rdInfo_ALL (		
			IsDeposit	INT,
			ProductID		INT,			
			DI_Rate	MONEY,
			Fromdate		SMALLDATETIME,
			ToDate	SMALLDATETIME,
			PartyID		INT
			)

	 INSERT INTO #PartyChargeInfo(ChargeId, PartyId, LicenseeId, ParentID, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
			SELECT ci.ChargeId 
				, ci.PartyID
				, ci.LicenseeID, p.ParentID, ci.isDeposit, ci.ProductID
				, ci.DI_Rate, ci.Fromdate, ci.ToDate
				, ISNULL(sbr.Bettype, ci.Bettype)
			FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'SG', 'OA', 1) AS ci
				INNER JOIN @tmpParty p ON ci.PartyID = p.PartyID
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 --exclude RB

	INSERT INTO #PartyCharge3rdInfo_Direct( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID)	
	SELECT DISTINCT ci.IsDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.PartyID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'SG', 'OA') ci	
		INNER JOIN @tmpParty p ON p.PartyId = ci.PartyId

	INSERT INTO #PartyCharge3rdInfo_ALL( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID)	
	SELECT DISTINCT ci.IsDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, p.PartyID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'SG', 'OA') AS ci 
			INNER JOIN @tmpParty AS p ON p.ParentID = ci.PartyID
	WHERE p.PartyID NOT IN (SELECT PartyID FROM #PartyCharge3rdInfo_Direct)
				
	INSERT INTO #PartyCharge3rdInfo_ALL( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID)	
	SELECT IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID FROM #PartyCharge3rdInfo_Direct
	-- End Region
	
	-- Region: Get Exchange
	CREATE	TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	CREATE TABLE #Exchange(ExchangeDate DATE, ExchangeID INT, Rate FLOAT);

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate;

	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End Region

	-- Region: Get Sum data
	CREATE TABLE #TempDataSG(
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			ProductId		TINYINT,
			MemberWL		MONEY,
			AmountToCompany MONEY);
	CREATE TABLE #DailyPayToSupplier(ParentID INT, rptDate DATE, MemberWLOANDA MONEY, PayToSupplier MONEY)
	CREATE TABLE #FullRangePayToSupplier(ParentID INT, PayToSupplier MONEY)

    INSERT INTO #TempDataSG(PartyId, RptDate, CurrencyId, ProductId, MemberWL, AmountToCompany)
			SELECT p.PartyId
				, b.rptdate
				, b.CurrencyId
				, b.ProductId
				, SUM(ISNULL(b.MemberWL, 0))
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH (NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
										AND b.CurrencyId = e.ExchangeID
			    INNER JOIN #PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
											AND
											    (p.Bettype = -1
												OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 103) -- Exclude Reject , Void, Refund
			GROUP BY p.PartyId, b.rptdate, b.CurrencyId, b.ProductId

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataSG(PartyId);

	INSERT INTO #DailyPayToSupplier(ParentID, rptDate, MemberWLOANDA, PayToSupplier)
	SELECT t.ParentID, d.rptDate, SUM(d.MemberWL * oanda.Rate), SUM(d.MemberWL * oanda.Rate * ISNULL(p.DI_Rate,ISNULL(v.ChargeRate3rd, 0)))
	FROM #TempDataSG d
		INNER JOIN @tmpParty AS t ON t.PartyID = d.PartyId
		INNER JOIN #ExchangeOANDA oanda ON d.rptDate = oanda.ExchangeDate AND d.CurrencyId = oanda.ExchangeID
		LEFT JOIN #PartyCharge3rdInfo_ALL p ON p.PartyID = d.PartyId AND d.rptDate BETWEEN p.Fromdate AND p.Todate
		LEFT JOIN #tmpVendorGlobalSetting v ON v.ProductID = d.ProductId
	GROUP BY t.ParentID, d.rptDate

	INSERT INTO #FullRangePayToSupplier(ParentID, PayToSupplier)
	SELECT ParentID
		 , CASE WHEN ParentId = 1 THEN
					CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(PayToSupplier) END
				ELSE
					CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(PayToSupplier) END
				END 
	FROM #DailyPayToSupplier
	GROUP BY ParentID
	-- END - Rate for PayToSupplier

	CREATE TABLE #FeeData(
	    PartyId            INT
	  , ProductID          INT
	  , AComm              MONEY
	  , MinFeeApplied      MONEY
	  , WLFeeApplied       MONEY
	  , AmountToCompany    MONEY);

    INSERT INTO #FeeData(PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate, @ToDate = @TDate, @Products = 'SG';

	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)

	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange'
		, (SELECT SUM(WLFeeApplied) FROM #FeeData)
		, (SELECT SUM(PayToSupplier) FROM #FullRangePayToSupplier)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(AmountToCompany), 0) FROM #TempDataSG WHERE ProductId = 36 AND rptDate = @tmpDate), -- LicenseeWL
			(SELECT ISNULL(SUM(PayToSupplier), 0) FROM #DailyPayToSupplier WHERE rptDate = @tmpDate)		

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SG'', 1, ''House Income'', LicenseeWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''SG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #ExchangeOANDA
	DROP TABLE #Exchange
	DROP TABLE #PartyCharge3rdInfo_Direct
	DROP TABLE #PartyCharge3rdInfo_ALL
	DROP TABLE #PartyChargeInfo
	DROP TABLE #TempDataSG
	DROP TABLE #DailyPayToSupplier
	DROP TABLE #FullRangePayToSupplier
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
END
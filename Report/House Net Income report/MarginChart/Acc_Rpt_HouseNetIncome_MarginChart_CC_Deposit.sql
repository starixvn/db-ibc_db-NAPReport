/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_CC_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  	
	 Created:	20190819@Robert
    Task :		House month-to-date Net Income report for Card Club
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_CC_Deposit '20180601', '20180630'   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Active licensees

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT
	  , ParentID     INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , ParentID)
		 SELECT DISTINCT 
			   ci.FromParty
			 , pd.IsDeposit
			 , ci.ToParty
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																  AND map.SystemID = 2
		 WHERE p.PartyType = 1
			  AND pd.IsDeposit = 1
			  AND ci.ProductId = 34 -- CC
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
					AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    -- End region
    -- Region: Get Licensees has charge rate

    DECLARE @PartyChargeInfo AS TABLE(
	    ChargeId      INT
	  , PartyId       INT
	  , LicenseeId    INT
	  , ParentID      INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , ProductID     INT);

    DECLARE @PartyCharge3rdInfo AS TABLE(
	    LicenseeId    INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , ProductID     INT);

    INSERT INTO @PartyChargeInfo(ChargeId
						 , PartyId
						 , LicenseeId
						 , ParentID
						 , Rate
						 , Fromdate
						 , Todate
						 , ProductID)
		 (
			SELECT ci.ChargeId
				, ci.PartyID
				, ci.LicenseeID
				, p.ParentID
				, ci.DI_Rate
				, ci.Fromdate
				, ci.ToDate
				, ci.ProductID
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIDs, @FDate, @TDate, 'CC', 'OA', 1) AS ci
			    INNER JOIN @tmpParty AS p ON ci.PartyID = p.PartyID
			WHERE DI_Rate > 0
				 AND ci.ChargeType = 1 -- get PT
		 );
		 
    INSERT INTO @PartyCharge3rdInfo(LicenseeId
						    , Rate
						    , FromDate
						    , ToDate
						    , ProductID)
		 (
			SELECT DISTINCT 
				  p.LicenseeID
				, ci.DI_Rate
				, ci.Fromdate
				, ci.ToDate
				, ci.ProductID
			FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd
				(@FDate, @TDate, 'CC', 'OA') AS ci
			    INNER JOIN @PartyChargeInfo AS p ON p.ParentID = ci.PartyId
			WHERE ci.ChargeType = 1
				 AND ci.IsDeposit = 1
		 );		
		 
    -- End Region
    -- Region: Get exchange rate info

    CREATE TABLE #Exchange(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    INSERT INTO #Exchange(ExchangeDate
				    , ExchangeID
				    , Rate)
		 SELECT ExchangeDate
			 , Currency
			 , Rate
		 FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 SELECT ExchangeDate
			 , ExchangeID
			 , BaseCurrencyRate
		 FROM bodb02.dbo.LA_f_ExchangeDailySel
			 (@FDate, @TDate, 'MYR');
    -- End region

    CREATE TABLE #TempDataCC(
	    PartyId            INT
	  , rptDate            DATETIME
	  , MemberWL           MONEY
	  , PayToSupplier      MONEY
	  , ProductId          TINYINT
	  , LicenseWL          MONEY
	  , AmountToCompany    MONEY);

    INSERT INTO #TempDataCC(PartyId
					 , rptDate
					 , MemberWL
					 , PayToSupplier
					 , ProductId
					 , LicenseWL
					 , AmountToCompany)
		 (
			SELECT p.PartyId
				, b.rptDate
				, SUM(ISNULL(b.MemberWL, 0) * oa.Rate) MemberWL
				, SUM(ISNULL(b.MemberWL, 0) * rd.Rate * oa.Rate) PayToSupplier
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * e.Rate) LicenseWL
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate) AmountToCompany
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    INNER JOIN #ExchangeOANDA AS oa ON b.rptDate = oa.ExchangeDate
										    AND b.CurrencyId = oa.ExchangeID
			    INNER JOIN @PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
			    INNER JOIN @PartyCharge3rdInfo AS rd ON b.ProductID = rd.ProductID
											    AND b.SiteID = rd.LicenseeID
											    AND b.rptDate BETWEEN rd.FromDate AND rd.ToDate
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , p.ProductId
		 );
		 
    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataCC(PartyId, ProductId);
    -- Region: Result	

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , PayToSupplier    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , 0
			 , 0;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , SUM(AmountToCompany) -- LicenseeWL
				    , SUM(PayToSupplier) -- PayToSupplier
			    FROM #TempDataCC
			    WHERE rptDate = @tmpDate;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
    -- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''CC'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''CC'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataCC
	DROP TABLE #FinalResult
END
GO

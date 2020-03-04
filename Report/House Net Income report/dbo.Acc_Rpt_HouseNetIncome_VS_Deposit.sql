/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_VS_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created: Victor  
	Date: 2016-08-15  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20160915@Harper - #64211 - Rebate and Discount should be included when calculating the Pay to Suplplier
		- 20160919@Harper - #64338 - PayToSupplier of FullMonth is incorrect
		- 20160923@Harper - #64582 - PayToSupplier should use ExchangeOANDA
		- 20161024@Harper - #65699: HAIFA - Apply new charge rate discount for HNI report
		- 20180327@Harper - #91291 - Virtual Sports - Change of commercial terms between company and provider
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]

	Param's Explanation:   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Active licensees

    DECLARE @TmpPartyList AS TABLE(
	    PartyID      INT
	  , PartyName    VARCHAR(200)
	  , BrandName    VARCHAR(200)
	  , ParentID     INT);

    INSERT INTO @TmpPartyList
    EXECUTE bodb_licensee.dbo.LA_PartyListSel;

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT
	  , VSRate       FLOAT
	  , ParentID     INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , VSRate)
		 SELECT DISTINCT
			   ci.FromParty
			 , pd.IsDeposit
			 , 0
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																  AND map.SystemID = 2
		 WHERE p.PartyType = 1
			  AND ci.ProductId = 5 -- VS
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
					AND @TDate < ci.ToDate);

    UPDATE p
		 SET
			p.ParentID = pa.ParentID
    FROM @tmpParty p
	   INNER JOIN @TmpPartyList pa ON pa.PartyID = p.PartyID;

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    -- End region

    DECLARE @PartyChargeInfo AS TABLE(
	    ChargeId      INT
	  , PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

    INSERT INTO @PartyChargeInfo(ChargeId
						 , PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate
						 , Bettype)
		 (
			SELECT ci.ChargeId
				, ci.PartyID
				, ci.LicenseeID
				, ci.isDeposit
				, ci.ProductID
				, ci.DI_Rate
				, ci.Fromdate
				, ci.ToDate
				, ISNULL(sbr.Bettype, ci.Bettype)
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIDs, @FDate, @TDate, 'VS', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 --exclude RB
		 );
    -- End region

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
		 FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 SELECT ExchangeDate
			 , ExchangeID
			 , BaseCurrencyRate
		 FROM bodb02.dbo.LA_f_ExchangeDailySel
			 (@FDate, @TDate, 'MYR'); -- Currency ID = 2
    -- End region

    -- Region: HAIFA - Adding more discount rate

    CREATE TABLE #DiscountGroup(
	    DiscountGroupId      SMALLINT
	  , DiscountGroupType    TINYINT
	  , FromAmount           MONEY
	  , ToAmount             MONEY
	  , Rate                 MONEY
	  , PartyId              INT
	  , ProductId            TINYINT
	  , BaseCurrency         INT);

    INSERT INTO #DiscountGroup(DiscountGroupId
					    , DiscountGroupType
					    , FromAmount
					    , ToAmount
					    , Rate
					    , PartyId
					    , ProductId
					    , BaseCurrency)
    EXEC Acc_Rpt_HouseNetIncome_DiscountInWinLoss
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @ProductCodes = 'VS';
    -- End Region: HAIFA

    CREATE TABLE #TempDataVS(
	    PartyId            INT
	  , rptDate            DATETIME
	  , CurrencyId         INT
	  , WinLoss            MONEY
	  , AComm              MONEY
	  , ProductId          TINYINT
	  , AmountToCompany    MONEY
	  , DiscountAmount     MONEY);

    INSERT INTO #TempDataVS(PartyId
					 , rptDate
					 , CurrencyId
					 , WinLoss
					 , AComm
					 , ProductId
					 , AmountToCompany
					 , DiscountAmount)
		 (
			SELECT p.PartyId
				, b.rptDate
				, b.CurrencyID
				, SUM(ISNULL(b.MemberWL, 0))
				, SUM(ISNULL(b.CommissionA, 0)) * e.Rate
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate)) * e.Rate
				, SUM(-ISNULL(b.MemberWL, 0)) * ISNULL(d.Rate, 0) * e.Rate
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH (NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    INNER JOIN @PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
											AND
											    (p.Bettype = -1
												OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
			    LEFT JOIN #DiscountGroup AS d ON d.PartyId = p.PartyId
										  AND d.ProductId = p.ProductID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , b.CurrencyID
				  , p.ProductId
				  , e.Rate
				  , d.Rate
		 );

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataVS(PartyId, ProductId);
    -- Region: Result

    CREATE TABLE #FeeData(
	    PartyId            INT
	  , ProductID          INT
	  , AComm              MONEY
	  , MinFeeApplied      MONEY
	  , WLFeeApplied       MONEY
	  , AmountToCompany    MONEY);

    INSERT INTO #FeeData(PartyId
				   , ProductID
				   , AComm
				   , MinFeeApplied
				   , WLFeeApplied
				   , AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @Products = 'VS';

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , DiscountWL       MONEY
	  , PayToSupplier    MONEY);

    DECLARE @DailyPayAmt TABLE(
	    rptDate       DATE
	  , IsDeposit     BIT
	  , Amount        MONEY
	  , LicenseeWL    MONEY
	  , VSRate        FLOAT);
    -- Rate for PayToSupplier

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
	INSERT INTO #PartyCharge3rdInfo_Direct( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID )	
	SELECT DISTINCT ci.IsDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.PartyID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'VS', 'OA') ci	
		INNER JOIN @tmpParty p ON p.PartyId = ci.PartyId

	INSERT INTO #PartyCharge3rdInfo_ALL( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID )	
	SELECT DISTINCT ci.IsDeposit, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate, p.PartyID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'VS', 'OA') AS ci 
			INNER JOIN @tmpParty AS p ON p.ParentID = ci.PartyID
	WHERE p.PartyID NOT IN (SELECT PartyID FROM #PartyCharge3rdInfo_Direct)
				
	INSERT INTO #PartyCharge3rdInfo_ALL( IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID )	
	SELECT IsDeposit, ProductID, DI_Rate, Fromdate, ToDate, PartyID FROM #PartyCharge3rdInfo_Direct

	    INSERT INTO @DailyPayAmt(rptDate
						  , IsDeposit
						  , Amount
						  , LicenseeWL)
			 SELECT d.rptDate
				 , p.IsDeposit
				 , SUM(d.WinLoss * oanda.Rate * p.DI_Rate)
				 , SUM(-d.WinLoss * oanda.Rate)
			 FROM #TempDataVS AS d
				INNER JOIN #PartyCharge3rdInfo_ALL AS p ON p.PartyID = d.PartyId
									  AND d.rptDate BETWEEN p.Fromdate AND p.Todate
				INNER JOIN #ExchangeOANDA AS oanda ON d.rptDate = oanda.ExchangeDate
											   AND d.CurrencyId = oanda.ExchangeID
			 GROUP BY d.rptDate
				   , p.IsDeposit;

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL
					  , DiscountWL
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , ISNULL(SUM(WLFeeApplied), 0)
			 , 0
			 ,
			   (
				  SELECT CASE
						   WHEN SUM(LicenseeWL) < 0
						   THEN 0
						   ELSE SUM(Amount)
					    END
				  FROM @DailyPayAmt
			   )
		 FROM #FeeData
		 WHERE ProductID = 5;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL
							, DiscountWL
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT ISNULL(SUM(AmountToCompany), 0)
						FROM #TempDataVS
						WHERE ProductId = 5
							 AND rptDate = @tmpDate
					 ) -- LicenseeWL
				    ,
					 (
						SELECT-ISNULL(SUM(DiscountAmount), 0)
						FROM #TempDataVS
						WHERE ProductId = 5
							 AND rptDate = @tmpDate
					 ) -- DiscountWL
				    ,
					 (
						SELECT ISNULL(SUM(Amount), 0)
						FROM @DailyPayAmt
						WHERE rptDate = @tmpDate
					 );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    -- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''VS'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VS'', 3, ''Rebate & Discount'', DiscountWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VS'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataVS
	DROP TABLE #FeeData
	DROP TABLE #PartyCharge3rdInfo_ALL
	DROP TABLE #PartyCharge3rdInfo_Direct
	DROP TABLE #DiscountGroup
	DROP TABLE #FinalResult
END
GO
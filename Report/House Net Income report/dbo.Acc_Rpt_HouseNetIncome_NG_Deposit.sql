/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_NG_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created: Victor  
	Date: 2016-08-15  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions:  
		- 20160909@Harper - #63853 - Return wrong data Pay to Supplier
		- 20160922@Harper - #63926 - Remove IsApplyMinFee
		- 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200225@Kean: #128007 - Changes on the rate of Pay to suppliers

	Param's Explanation:   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    /* Region: Active licensees*/

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit)
		 SELECT DISTINCT
			   ci.FromParty
			 , pd.IsDeposit
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																  AND map.SystemID = 2
		 WHERE p.PartyType = 1
			  AND ci.ProductId = 2 /* NG*/
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    /* End region*/


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
				(@PartyIDs, @FDate, @TDate, 'NG', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 /*exclude RB*/
		 );
    /* End region

					 Region: Get exchange rate info*/

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
			 (@FDate, @TDate, 'MYR');
    /* End region*/


    CREATE TABLE #TempDataNG(
	    rptDate            DATETIME
	  , ProductId          TINYINT
	  , AmountToCompany    MONEY);

    INSERT INTO #TempDataNG(rptDate
					 , ProductId
					 , AmountToCompany)
		 (
			SELECT b.rptDate
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate)) * e.Rate
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
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 103) /* Exclude Reject , Void, Refund*/
				 AND b.Bettype = -1
			GROUP BY b.rptdate
				  , p.ProductId
				  , e.Rate
		 );
    /* Region: Result*/

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
	  , @Products = 'NG';

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , PayToSupplier    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , ISNULL(SUM(AmountToCompany), 0)
			 , -0.5 * ISNULL(SUM(AmountToCompany), 0)
		 FROM #FeeData
		 WHERE ProductID = 2;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT ISNULL(SUM(AmountToCompany), 0)
						FROM #TempDataNG
						WHERE ProductId = 2
							 AND rptDate = @tmpDate
					 ) /* LicenseeWL*/
				    ,
					 (
						SELECT-0.5 * SUM(AmountToCompany)
						FROM #TempDataNG
						WHERE rptDate = @tmpDate
					 );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    /* End region*/
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''NG'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataNG
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
END
GO
/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming
	@FromDate       DATE
   , @ToDate         DATE
   , @DepositType    SMALLINT = 0
AS
/*
    Created: Robert  
    Date: 2019-05-24  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  

    Revisions:
	   - 20190524@Robert: #113946 - DHWL Margin Chart - Separate Payto Metric Gaming & Bet Genius for credit/licensee

    Param's Explanation:  
    - DepositType  
	   = 2 All
	   = 1 Deposit Only 
	   = 0 Credit Only 
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate       DATE
		, @TDate       DATE
		, @tmpDate     DATE
		, @PartyIDs    VARCHAR(1000);

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate
	    , @tmpDate = @FDate;

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT);

    DECLARE @PartyChargeInfo AS TABLE(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

    DECLARE @ProductChargeInfo TABLE(
	    Rate         FLOAT
	  , FromDate     SMALLDATETIME
	  , ToDate       SMALLDATETIME
	  , MinAmount    MONEY
	  , MaxAmount    MONEY);

    CREATE TABLE #MetricGamingData(
	    LicenseeID     INT
	  , PartyID        INT
	  , RptDate        DATE
	  , CurrencyID     INT
	  , LicenseeWL     MONEY
	  , AmtLicensee    MONEY);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    CREATE TABLE #FinalResult(
	    RptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , PayToMetricGaming)
		 (
			SELECT 'FullRange' AS rptDate
				, 0 AS PayToMetricGaming
		 );


    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 (
			SELECT ExchangeDate
				, ExchangeID
				, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel
				(@FDate, @TDate, 'MYR')
		 );

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit)
		 (
			SELECT DISTINCT
				  ci.FromParty
				, pd.IsDeposit
			FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			    INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			    INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			    INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																	 AND map.SystemID = 2
			WHERE p.PartyType = 1
				 AND ci.ProductId = 0 -- SB				 
				 AND pd.IsDeposit = CASE
								    WHEN @DepositType = 2
								    THEN pd.IsDeposit
								    ELSE @DepositType
								END
				 AND
					(ci.FromDate BETWEEN @FDate AND @TDate
					 OR ci.ToDate BETWEEN @FDate AND @TDate
					 OR ci.FromDate < @FDate
					 AND @TDate < ci.ToDate)
		 );


    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty;

    INSERT INTO @PartyChargeInfo(PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate)
		 (
			SELECT PartyID
				, LicenseeID
				, isDeposit
				, ProductID
				, DI_Rate
				, Fromdate
				, Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0) AS ci
			WHERE DI_Rate > 0
		 );



    INSERT INTO #MetricGamingData(LicenseeID
						  , PartyId
						  , RptDate
						  , CurrencyId
						  , LicenseeWL
						  , AmtLicensee)
		 (
			SELECT b.SiteID
				, p.PartyId
				, b.rptDate
				, b.CurrencyID
				, SUM(CASE
						WHEN p.IsDeposit = 0
						THEN(-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS)
						ELSE-b.WinLoss
					 END) AS LicenseeWL
				, SUM(CASE
						WHEN p.IsDeposit = 0
						THEN(-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS) * p.Rate
						ELSE-b.WinLoss * p.Rate
					 END) AS AmtLicensee
			FROM bodb_licenseereport.dbo.rpt_Betting AS b WITH (NOLOCK)
			    INNER JOIN @PartyChargeInfo AS p ON b.SiteID = p.LicenseeId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.Status BETWEEN 111 AND 113
				 AND b.customercategory NOT IN(27, 28)
				 AND b.Bettype BETWEEN 800 AND 899 -- Metric Gaming Bettype In Sportsbook
			GROUP BY b.rptdate
				  , b.SiteId
				  , b.CurrencyID
				  , p.PartyId
		 );

    UPDATE b
		 SET
			LicenseeWL = LicenseeWL * e.Rate
		   , AmtLicensee = AmtLicensee * e.Rate
    FROM #MetricGamingData b
	   INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate
							    AND e.ExchangeID = b.CurrencyID;

    INSERT INTO @ProductChargeInfo(Rate
						   , FromDate
						   , ToDate
						   , MinAmount
						   , MaxAmount)
		 (
			SELECT ci.Rate
				, CASE
					 WHEN @FDate >= ci.FromDate
					 THEN @FDate
					 ELSE ci.FromDate
				  END AS FromDate
				, CASE
					 WHEN @TDate < ci.ToDate
					 THEN @TDate
					 ELSE ci.ToDate
				  END AS ToDate
				, ci.MinAmount * ex.Rate
				, ci.MaxAmount * ex.Rate
			FROM bodb_licensee.dbo.OAS_ChargeInfo AS ci
			    INNER JOIN #ExchangeOANDA AS ex ON ci.BaseCurrencyId = ex.ExchangeID
										    AND ex.ExchangeDate = @TDate
			WHERE ci.ProductID = 0
				 AND ci.FromParty = 1
				 AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming
				 AND
					(ci.FromDate BETWEEN @FDate AND @TDate
					 OR ci.ToDate BETWEEN @FDate AND @TDate
					 OR ci.FromDate < @FDate
					 AND @TDate < ci.ToDate)
		 );

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMetricGaming)
			    (
				   SELECT CONVERT(VARCHAR(2), @tmpDate, 106) AS RptDate
					   , 0 AS PayToMetricGaming
			    );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    WITH WLAmount
	    AS (
	    SELECT CONVERT(VARCHAR(2), RptDate, 106) AS rptDate
		    , rptDate AS FullDate
		    , SUM(AmtLicensee) AS AmtLicensee
	    FROM #MetricGamingData
	    GROUP BY CONVERT(VARCHAR(2), RptDate, 106)
			 , rptDate),
	    MetricGamingFee
	    AS (
	    SELECT wl.*
		    , ci.MinAmount
		    , ci.MaxAmount
		    , ci.Rate
		    , CASE
				WHEN AmtLicensee < 0
					AND ci.MinAmount = 0
					OR AmtLicensee >= ci.MinAmount
				THEN CASE
					    WHEN AmtLicensee > MaxAmount
					    THEN ci.MaxAmount - ci.MinAmount
					    ELSE AmtLicensee - ci.MinAmount
					END
				ELSE 0
			 END * ci.Rate AS AmtByRange
	    FROM WLAmount AS wl
		   INNER JOIN @ProductChargeInfo AS ci ON wl.FullDate BETWEEN ci.FromDate AND ci.ToDate),
	    AmtByDate
	    AS (
	    SELECT m.rptDate
		    , SUM(AmtByRange) AS AmtByDate
	    FROM MetricGamingFee AS m
	    GROUP BY m.rptDate)
	    UPDATE r
			 SET
				PayToMetricGaming = -AmtByDate
	    FROM AmtByDate m
		   INNER JOIN #FinalResult r ON r.RptDate = m.rptDate;
-- Calculate Pay to Metric gaming amount
    WITH WLAmount
	    AS (
	    SELECT ci.*
		    , SUM(d.AmtLicensee) AS AmtLicensee
	    FROM @ProductChargeInfo AS ci
		   INNER JOIN #MetricGamingData AS d ON d.RptDate BETWEEN ci.FromDate AND ci.ToDate
	    GROUP BY ci.Rate
			 , ci.FromDate
			 , ci.ToDate
			 , ci.MinAmount
			 , ci.MaxAmount),
	    AmtByRange
	    AS (
	    SELECT wl.*
		    , CASE
				WHEN AmtLicensee > MinAmount
				THEN CASE
					    WHEN AmtLicensee > MaxAmount
					    THEN MaxAmount - MinAmount
					    ELSE AmtLicensee - MinAmount
					END
				ELSE 0
			 END * Rate AS AmtDue
	    FROM WLAmount AS wl)
	    UPDATE #FinalResult
			 SET
				PayToMetricGaming = -
				(
				    SELECT SUM(AmtDue)
				    FROM AmtByRange
				)
	    WHERE RptDate LIKE 'FullRange';


    SELECT RptDate
	    , PayToMetricGaming
    FROM #FinalResult;

    DROP TABLE #MetricGamingData;
    DROP TABLE #ExchangeOANDA;
    DROP TABLE #FinalResult;
END;
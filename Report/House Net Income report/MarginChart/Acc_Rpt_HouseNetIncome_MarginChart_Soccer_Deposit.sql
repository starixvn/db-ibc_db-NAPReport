/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit]
	@FromDate DATE,
	@ToDate	DATE 
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Soccer [#RedmineID: 89632]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		- 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit '2018-04-01', '2018-04-30'
  
*/    
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Handle data of Soccer

    CREATE TABLE #FinalResult(
	    RptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY
	  , HouseWL              MONEY DEFAULT 0
	  , ExtraPT              MONEY DEFAULT 0
	  , TurnOver             MONEY DEFAULT 0
	  , PayToGenius          MONEY DEFAULT 0);

    CREATE TABLE #BetBuilderData(
	    rptDate    DATETIME
	  , WinLoss    MONEY);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);	

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 SELECT ExchangeDate
			 , ExchangeID
			 , BaseCurrencyRate
		 FROM bodb02.dbo.LA_f_ExchangeDailySel
			 (@FDate, @TDate, 'MYR');

    INSERT INTO #BetBuilderData(rptDate
						, WinLoss)
		 (
			SELECT b.rptDate
				, SUM(ISNULL(b.WinLoss, 0) * e.Rate)
			FROM bodb_LicenseeReport.dbo.rpt_Betting AS b WITH (NOLOCK)
			    INNER JOIN #ExchangeOANDA AS e ON b.rptDate = e.ExchangeDate
										   AND b.CurrencyId = e.ExchangeID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.Bettype = 38
				 AND b.Status NOT IN(101, 102, 103) -- Exclude Reject , Void, Refund;				 
			GROUP BY b.rptDate
		 );	

    INSERT INTO #FinalResult(rptDate
					  , PayToMetricGaming
					  , PayToGenius)
		 SELECT 'FullRange'
			 , 0
			 , 0;
    -- Date list to draw chart

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMetricGaming
							, PayToGenius)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0
				    ,
					 (
						SELECT ISNULL(SUM(WinLoss * 0.04), 0)
						FROM #BetBuilderData
						WHERE rptDate = @tmpDate
					 ) AS PayToGenius;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    -- End region	

    ---------------------------------------------------- Pay to Metric Gaming ----------------------------------------------------

    -- Region: Get Party list, including credit licensees	

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
			  AND ci.ProductId = 0 -- SB
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty;

    DECLARE @PartyChargeInfo AS TABLE(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

    INSERT INTO @PartyChargeInfo(PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate)
		 SELECT PartyID
			 , LicenseeID
			 , isDeposit
			 , ProductID
			 , DI_Rate
			 , Fromdate
			 , Todate
		 FROM bodb_licensee.dbo.LA_f_ChargeInfo
			 (@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)
		 WHERE DI_Rate > 0;
    -- End Region: Get Party list, including credit licensees	

    CREATE TABLE #MetricGamingData(
	    LicenseeID     INT
	  , PartyID        INT
	  , RptDate        DATE
	  , CurrencyID     INT
	  , LicenseeWL     MONEY
	  , AmtLicensee    MONEY);

	      

    INSERT INTO #MetricGamingData(LicenseeID
						  , PartyId
						  , RptDate
						  , CurrencyId
						  , LicenseeWL
						  , AmtLicensee)
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
			   , p.PartyId;
    -- Apply currency rate

    UPDATE b
		 SET
			LicenseeWL = LicenseeWL * e.Rate
		   , AmtLicensee = AmtLicensee * e.Rate
    FROM #MetricGamingData b
	   INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate
							    AND e.ExchangeID = b.CurrencyID;
    -- Get Metric Gaming charge info

    DECLARE @ProductChargeInfo TABLE(
	    Rate         FLOAT
	  , FromDate     SMALLDATETIME
	  , ToDate       SMALLDATETIME
	  , MinAmount    MONEY
	  , MaxAmount    MONEY);

    INSERT INTO @ProductChargeInfo(Rate
						   , FromDate
						   , ToDate
						   , MinAmount
						   , MaxAmount)
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
				  AND @TDate < ci.ToDate);

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
    -- Get Turnover, House Income from DW [Credit]

    CREATE TABLE #TmpHouseWL(
	    rptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , HouseWL
					 , ExtraPT
					 , TurnOver)
    EXEC dbwh.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub
	    @FDate
	  , @TDate
	  , @isDeposit = 1;

    UPDATE f
		 SET
			f.HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0)
		   , f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0)
		   , f.ExtraPT = ISNULL(f.ExtraPT, 0) + ISNULL(wl.ExtraPT, 0)
    FROM #FinalResult f
	   INNER JOIN #TmpHouseWL wl ON wl.rptDate = f.RptDate;

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''Soccer'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 8, ''Turn Over'', TurnOver' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 7, ''Pay to Metric Gaming'', PayToMetricGaming' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 8, ''Pay to Bet Genius'', PayToGenius) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop temp table
	DROP TABLE #ExchangeOANDA
	DROP TABLE #MetricGamingData
	DROP TABLE #FinalResult	
	DROP TABLE #TmpHouseWL
	DROP TABLE #BetBuilderData
END

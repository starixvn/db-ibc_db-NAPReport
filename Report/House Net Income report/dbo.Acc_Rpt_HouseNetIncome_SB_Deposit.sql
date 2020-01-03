/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SB_Deposit]
	@FromDate DATE 
	, @ToDate	DATE 
AS  
/*  
	Created: Victor  
	Date: 2016-05-23  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20161024@Harper - #65699: HAIFA - Apply new charge rate discount for HNI report
		- 20171206@Harper - Update Pay To MuayThai amount due to include Parlay data [RedmineID: #83193]		
		- 20180131@Harper - Fix Daily HAIFA data [#RedmineID: 90263]
		- 20180518@Harper - Hot Fix Daily HAIFA data [#RedmineID: 95399]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20190308@Robert: 109770 - House Net Income - Change formula for MTD values and add old month data into a new sheet
		- 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		- 20200203@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report

	Param's Explanation:  
		  - DepositType  
				    = 2 All
				    = 1 Deposit Only 
				    = 0 Credit Only 

	EXEC Acc_Rpt_HouseNetIncome_SB_Deposit '2017-12-01', '2017-12-31'
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit)
		 SELECT DISTINCT 
			   ci.FromParty
			 , pd.IsDeposit
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
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

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    -- End region

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
						 , Todate
						 , Bettype)
		 (
			SELECT ci.PartyID
				, ci.LicenseeID
				, ci.isDeposit
				, ci.ProductID
				, ci.DI_Rate
				, ci.Fromdate
				, ci.ToDate
				, ISNULL(sbr.Bettype, ci.Bettype)
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIDs, @FDate, @TDate, 'SB,BA', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 --exclude RB
		 );

    CREATE TABLE #Exchange(
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
	  , @Products = 'SB,BA';
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
    EXEC Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA 
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @ProductCodes = 'SB';
    -- Apply discount & rebate

    WITH t
	    AS (SELECT SUM(s.AmountToCompany) AS Total
			   , s.PartyId
			   , d.DiscountGroupId
		   FROM #FeeData AS s
			  INNER JOIN
			   (
				  SELECT DISTINCT 
					    DiscountGroupId
					  , PartyId
					  , ProductId
				  FROM #DiscountGroup
				  WHERE DiscountGroupType = 1
			   ) AS d ON s.PartyId = d.PartyId
					   AND s.ProductId = d.ProductId
		   GROUP BY s.PartyId
				, d.DiscountGroupId)
	    DELETE d
	    FROM #DiscountGroup d
		   INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId
					    AND t.PartyId = d.PartyId
	    WHERE d.DiscountGroupType = 1
			AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount;
    -- End Region: HAIFA

    CREATE TABLE #TempDataSB(
	    PartyId            INT
	  , rptDate            DATETIME
	  , CurrencyId         INT
	  , WinLoss            MONEY
	  , AComm              MONEY
	  , ProductId          TINYINT
	  , AmountToCompany    MONEY
	  , IsApplyMinFee      BIT
	  , DiscountAmount     MONEY);

    DECLARE @PayToBetBuilder TABLE(
	    rptDate        VARCHAR(10)
	  , PayToGenius    MONEY);

    DECLARE @PayToMetricGaming TABLE(
	    rptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY);

    DECLARE @PayToMuayThai TABLE(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY);

    INSERT INTO #TempDataSB(PartyId
					 , rptDate
					 , CurrencyId
					 , WinLoss
					 , AComm
					 , ProductId
					 , AmountToCompany
					 , IsApplyMinFee
					 , DiscountAmount)
		 (
			SELECT p.PartyId
				, b.rptDate
				, b.CurrencyID
				, SUM(ISNULL(b.MemberWL, 0) * e.Rate)
				, SUM(ISNULL(b.CommissionA, 0) * e.Rate)
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * p.Rate * e.Rate)
				, 1 AS IsApplyMinFee
				, SUM(-ISNULL(b.MemberWL, 0) * p.Rate * ISNULL(d.Rate, 0) * e.Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    INNER JOIN @PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
											AND
											    (p.Bettype = -1
												OR p.Bettype = b.Bettype)
			    LEFT JOIN #DiscountGroup AS d ON d.PartyId = p.PartyId
										  AND d.ProductId = p.ProductID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.Bettype NOT IN(901, 902, 903, 904)
				 AND b.StatusId NOT IN(-1, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , b.CurrencyID
				  , p.ProductId--, e.Rate, d.Rate
		 );

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataSB(PartyId, ProductId);

    CREATE TABLE #FinalResult(
	    RptDate       VARCHAR(10)
	  , LicenseeWL    MONEY
	  , DiscountWL    MONEY
	  , MinFee        MONEY
	  , BAComm        MONEY);

    DECLARE @BAComm       MONEY = 0
		, @BAWinloss    MONEY = 0;

    SELECT @BAComm = ISNULL(-SUM(AComm), 0)
	    , @BAWinloss = ISNULL(SUM(AmountToCompany), 0)
    FROM #FeeData
    WHERE ProductId = 3;

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL
					  , DiscountWL
					  , MinFee
					  , BAComm)
		 SELECT 'FullRange'
			 , ISNULL(SUM(WLFeeApplied) + @BAWinloss, 0) AS LicenseeWL
			 , 0 AS DiscountWL
			 , ISNULL(SUM(MinFeeApplied), 0) AS MinFee
			 , ISNULL(@BAComm, 0) AS BAComm
		 FROM #FeeData
		 WHERE ProductID = 0;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL
							, DiscountWL
							, MinFee
							, BAComm)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106) AS RptDate
				    ,
					 (
						SELECT ISNULL(SUM(AmountToCompany), 0)
						FROM #TempDataSB
						WHERE ProductId IN(0, 3)
							 AND rptDate = @tmpDate
					 ) AS LicenseeWL -- LicenseeWL + BA Winloss
				    ,
					 (
						SELECT-ISNULL(SUM(DiscountAmount), 0)
						FROM #TempDataSB
						WHERE ProductId = 0
							 AND rptDate = @tmpDate
					 ) AS DiscountWL
				    , 0 AS MinFee
				    ,
					 (
						SELECT ISNULL(-SUM(AComm), 0)
						FROM #TempDataSB
						WHERE ProductId = 3
							 AND rptDate = @tmpDate
					 ) AS BAComm; -- BA Commission				    

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
							'(SELECT ''SB'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 2, ''Licensing Minimum Fee'', MinFee' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 4, ''Rebate & Discount'', DiscountWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +							
							'SELECT ''SB'', 5, ''BA Commission'', BAComm) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +							
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #Exchange		
	DROP TABLE #TempDataSB
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #DiscountGroup	
END
GO

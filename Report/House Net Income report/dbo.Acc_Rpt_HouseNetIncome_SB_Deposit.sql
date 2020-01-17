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
		- 20200113@Ned.Le: DHWL Letstalk Reports - Break SB into Soccer, OS and Parlay (#126634)

	Param's Explanation:  
		  - DepositType  
				    = 2 All
				    = 1 Deposit Only 
				    = 0 Credit Only 

	EXEC Acc_Rpt_HouseNetIncome_SB_Deposit '2017-12-01', '2017-12-31'
*/  
BEGIN  
    SET NOCOUNT ON;

	-----------------------------
	-- Declare datetime variables

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
	
	-------------------------
	-- Get data about PartyID

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
		  AND (ci.FromDate BETWEEN @FDate AND @TDate
			   OR ci.ToDate BETWEEN @FDate AND @TDate
			   OR ci.FromDate < @FDate AND @TDate < ci.ToDate)
	OPTION(RECOMPILE);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    
	---------------------------------
	-- Get data about PartyChargeInfo

    CREATE TABLE #TempPartyChargeInfo(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT)

    INSERT INTO #TempPartyChargeInfo(PartyId
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
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'SB,BA', 'OA', 1) AS ci
			 LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE DI_Rate > 0
			  AND ProductId <> 1 --exclude RB
	)
	
	CREATE CLUSTERED INDEX [PK_TempPartyChargeInfo] ON #TempPartyChargeInfo(PartyId ASC,
																		    Fromdate ASC,
																		    Todate ASC,
																			ProductID ASC,
																			LicenseeId ASC,
																			Bettype ASC)

	--------------------------
	-- Get data about Exchange

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
	
	---------------------------------------------
	-- Get FullRange data and contain in #FeeData

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
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee @FromDate = @FDate
	                                          , @ToDate = @TDate
	                                          , @Products = 'SB,BA';
	
	-----------------------------------------------------------------
	-- Get data about Rebate & Discount and contain in #DiscountGroup

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
    EXEC Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA @FromDate = @FDate
	                                             , @ToDate = @TDate
	                                             , @ProductCodes = 'SB';

    WITH t AS
	(
		SELECT SUM(s.AmountToCompany) AS Total
			   , s.PartyId
			   , d.DiscountGroupId
		FROM #FeeData AS s
			 INNER JOIN(SELECT DISTINCT 
							   DiscountGroupId
							   , PartyId
							   , ProductId
						FROM #DiscountGroup
						WHERE DiscountGroupType = 1) AS d ON s.PartyId = d.PartyId
														     AND s.ProductId = d.ProductId
		GROUP BY s.PartyId, d.DiscountGroupId
	)
	DELETE d
	FROM #DiscountGroup d
		 INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId
					     AND t.PartyId = d.PartyId
	WHERE d.DiscountGroupType = 1
		  AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount;
	
	--------------------------------------------------
	-- Get DetailDaily data and contain in #TempDataSB

	-- #TempFactLADailyWinloss
	CREATE TABLE #TempFactLADailyWinloss(
		[RptDate] [date] NOT NULL,
		[SiteID] [int] NOT NULL,
		[SportType] [int] NOT NULL,
		[BetType] [int] NOT NULL,
		[ProductID] [int] NOT NULL,
		[CurrencyID] [int] NOT NULL,
		[MemberWinloss] [decimal](19, 4) NOT NULL,
		[AgentComm] [decimal](19, 4) NOT NULL
	)
	
	INSERT INTO #TempFactLADailyWinloss (RptDate, SiteID, SportType, BetType, ProductID, CurrencyID, MemberWinloss, AgentComm)
	SELECT rptDate, SiteID, SportType, BetType, ProductID, CurrencyID,
		   SUM(MemberWinloss) MemberWinloss,
		   SUM(AgentComm) AgentComm
	FROM DBWH.bodb_Account.dbo.FactLAOverallPerformance f WITH(NOLOCK)
	WHERE RptDate BETWEEN @FDate AND @TDate
		  AND SiteID NOT IN (-2,-4)
		  AND ProductID IN (10001, 10004)
		  AND Bettype NOT IN (901, 902, 903, 904)
		  AND CurrencyID <> 20
		  AND TicketStatus NOT IN (-1, 18, 9, 10, 14)
	GROUP BY rptDate, SiteID, SportType, BetType, ProductID, CurrencyID
	OPTION(RECOMPILE)

	CREATE CLUSTERED INDEX [PK_TempFactLADailyWinloss] ON #TempFactLADailyWinloss([RptDate] ASC,
																				  [SiteID] ASC,
																				  [ProductID] ASC,
																				  [SportType] ASC,
																				  [BetType] ASC,
																				  [CurrencyID] ASC)

	-- #TempProductMapping
	CREATE TABLE #TempProductMapping(ProductID_DW INT, ProductID_Li INT)

	INSERT INTO #TempProductMapping(ProductID_DW,ProductID_Li)
	SELECT ProductID,SourceID 
	FROM DBWH.bodb_account.dbo.DimProduct WITH(NOLOCK)
	WHERE SourceInfo = 'Licensee'
		  AND ProductID not in (10010,10011,10012,10013,10032) -- seperate wallet data: Playtech Casino,,AG Casino,Gold Deluxe,Macau,Exchange 
	      AND ProductID not in (19001) --special product only for FactLicPerformanceAnalysis BI
	
	CREATE CLUSTERED INDEX [PK_TempProductMapping] ON #TempProductMapping(ProductID_DW ASC, ProductID_Li ASC)

	-- #TempSiteMapping
	CREATE TABLE #TempSiteMapping(SiteID_DW INT, SiteID_Li INT, SiteName VARCHAR(100))
	
	INSERT INTO #TempSiteMapping(SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM DBWH.bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = 1
	
	UPDATE tmpS
	SET tmpS.SiteID_Li = [site].SiteID
	FROM #TempSiteMapping tmpS
		 INNER JOIN bodb_Licensee.dbo.view_site_list [site] ON tmpS.SiteName  = [site].SiteName
	
	CREATE CLUSTERED INDEX [PK_TempSiteMapping] ON #TempSiteMapping(SiteID_DW ASC, SiteID_Li ASC)

	-- #TempDataSB
    CREATE TABLE #TempDataSB(
	    PartyId            INT
	  , rptDate            DATETIME
	  , CurrencyId         INT
	  , WinLoss            MONEY
	  , AComm              MONEY
	  , ProductId          TINYINT
	  , Sporttype		   VARCHAR(20)
	  , AmountToCompany    MONEY
	  , IsApplyMinFee      BIT
	  , DiscountAmount     MONEY);

    INSERT INTO #TempDataSB(PartyId
						  , rptDate
					      , CurrencyId
					      , WinLoss
					      , AComm
					      , ProductId
					      , Sporttype
					      , AmountToCompany
					      , IsApplyMinFee
					      , DiscountAmount)
	(
		SELECT p.PartyId
			 , b.rptDate
			 , b.CurrencyID
			 , SUM(ISNULL(b.MemberWinloss, 0) * e.Rate)
			 , SUM(ISNULL(b.AgentComm, 0) * e.Rate)
			 , p.ProductId
			 , CASE WHEN b.BetType IN (9, 29) THEN 'Parlay'
			   	    ELSE CASE WHEN b.SportType = 1 THEN 'Soccer' ELSE 'OS' END END Sporttype
			 , SUM(-ISNULL(b.MemberWinloss, 0) * p.Rate * e.Rate)
			 , 1 AS IsApplyMinFee
			 , SUM(-ISNULL(b.MemberWinloss, 0) * p.Rate * ISNULL(d.Rate, 0) * e.Rate)
		FROM #TempFactLADailyWinloss AS b
			 LEFT JOIN #TempProductMapping pm ON b.ProductID = pm.ProductID_DW
			 LEFT JOIN #TempSiteMapping sm ON b.SiteID = sm.SiteID_DW
			 INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			 INNER JOIN #TempPartyChargeInfo AS p ON b.rptDate BETWEEN p.FromDate AND p.ToDate
												  AND pm.ProductID_Li = p.ProductID
											      AND sm.SiteID_Li = p.LicenseeId
											      AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
			 LEFT JOIN #DiscountGroup AS d ON d.PartyId = p.PartyId
										      AND d.ProductId = pm.ProductID_Li
			WHERE b.rptDate BETWEEN @FDate AND @TDate
			GROUP BY p.PartyId
				   , b.rptdate
				   , b.CurrencyID
				   , p.ProductId
				   , b.SiteID
				   , CASE WHEN b.BetType IN (9, 29) THEN 'Parlay'
					      ELSE CASE WHEN b.SportType = 1 THEN 'Soccer' ELSE 'OS' END END
	);

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataSB(PartyId, ProductId);

	------------------------------------------------
	-- Collect all data and insert into #FinalResult

	-- Create temp table
    CREATE TABLE #FinalResult(
	    RptDate				VARCHAR(10)
	  , LicenseeWL_Soccer	MONEY
	  , LicenseeWL_OS		MONEY
	  , LicenseeWL_Parlay	MONEY
	  , DiscountWL_Soccer   MONEY
	  , DiscountWL_OS		MONEY
	  , DiscountWL_Parlay   MONEY
	  , MinFee_Soccer       MONEY
	  , MinFee_OS			MONEY
	  , MinFee_Parlay       MONEY
	  , BAComm_Soccer       MONEY
	  , BAComm_OS			MONEY
	  , BAComm_Parlay       MONEY);
	
	-- Get data about BAComm for FullRange
    DECLARE @BAComm			MONEY = 0
		    , @BAWinloss    MONEY = 0;

    SELECT @BAComm = ISNULL(-SUM(AComm), 0)
	       , @BAWinloss = ISNULL(SUM(AmountToCompany), 0)
    FROM #FeeData
    WHERE ProductId = 3;

	-- Get FullRange data
    INSERT INTO #FinalResult(rptDate
						   , LicenseeWL_Soccer
						   , LicenseeWL_OS
						   , LicenseeWL_Parlay
						   , DiscountWL_Soccer
						   , DiscountWL_OS
						   , DiscountWL_Parlay
						   , MinFee_Soccer
						   , MinFee_OS
						   , MinFee_Parlay
						   , BAComm_Soccer
						   , BAComm_OS
						   , BAComm_Parlay)
	SELECT 'FullRange'
		, ISNULL(SUM(WLFeeApplied) + @BAWinloss, 0)		AS LicenseeWL_Soccer
		, 0												AS LicenseeWL_OS
		, 0												AS LicenseeWL_Parlay
		, 0												AS DiscountWL_Soccer
		, 0												AS DiscountWL_OS
		, 0												AS DiscountWL_Parlay
		, ISNULL(SUM(MinFeeApplied), 0)					AS MinFee_Soccer
		, 0												AS MinFee_OS
		, 0												AS MinFee_Parlay
		, ISNULL(@BAComm, 0)							AS BAComm_Soccer
		, 0												AS BAComm_OS
		, 0												AS BAComm_Parlay
	FROM #FeeData
	WHERE ProductID = 0;
	
	-- Get DetailDaily data
    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult(RptDate
						       , LicenseeWL_Soccer
						       , LicenseeWL_OS
						       , LicenseeWL_Parlay
						       , DiscountWL_Soccer
						       , DiscountWL_OS
						       , DiscountWL_Parlay
						       , MinFee_Soccer
						       , MinFee_OS
						       , MinFee_Parlay
						       , BAComm_Soccer
						       , BAComm_OS
						       , BAComm_Parlay)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106)				AS RptDate
			   ,(SELECT ISNULL(SUM(AmountToCompany), 0)
				 FROM #TempDataSB
				 WHERE ProductId IN(0, 3)
				       AND rptDate = @tmpDate
					   AND Sporttype = 'Soccer')				AS LicenseeWL_Soccer
			   ,(SELECT ISNULL(SUM(AmountToCompany), 0)
				 FROM #TempDataSB
				 WHERE ProductId IN(0, 3)
				       AND rptDate = @tmpDate
					   AND Sporttype = 'OS')					AS LicenseeWL_OS
			   ,(SELECT ISNULL(SUM(AmountToCompany), 0)
				 FROM #TempDataSB
				 WHERE ProductId IN(0, 3)
				       AND rptDate = @tmpDate
					   AND Sporttype = 'Parlay')				AS LicenseeWL_Parlay
			   ,(SELECT -ISNULL(SUM(DiscountAmount), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 0
					   AND rptDate = @tmpDate
					   AND Sporttype = 'Soccer')				AS DiscountWL_Soccer
			   ,(SELECT -ISNULL(SUM(DiscountAmount), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 0
					   AND rptDate = @tmpDate
					   AND Sporttype = 'OS')					AS DiscountWL_OS
			   ,(SELECT -ISNULL(SUM(DiscountAmount), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 0
					   AND rptDate = @tmpDate
					   AND Sporttype = 'Parlay')				AS DiscountWL_Parlay
			   ,0												AS MinFee_Soccer
			   ,0												AS MinFee_OS
			   ,0												AS MinFee_Parlay
			   ,(SELECT ISNULL(-SUM(AComm), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 3
					   AND rptDate = @tmpDate
					   AND Sporttype = 'Soccer')				AS BAComm_Soccer
			   ,(SELECT ISNULL(-SUM(AComm), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 3
					   AND rptDate = @tmpDate
					   AND Sporttype = 'OS')					AS BAComm_OS
			   ,(SELECT ISNULL(-SUM(AComm), 0)
				 FROM #TempDataSB
				 WHERE ProductId = 3
					   AND rptDate = @tmpDate
					   AND Sporttype = 'Parlay')				AS BAComm_Parlay

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END;

	--------------------
	-- Select the output

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
    
	DECLARE @SQL VARCHAR(3000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''Soccer'', 1.1, ''House Income'', LicenseeWL_Soccer' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OS'', 1.2, ''House Income'', LicenseeWL_OS' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Parlay'', 1.3, ''House Income'', LicenseeWL_Parlay' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 2.1, ''Licensing Minimum Fee'', MinFee_Soccer' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OS'', 2.2, ''Licensing Minimum Fee'', MinFee_OS' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Parlay'', 2.3, ''Licensing Minimum Fee'', MinFee_Parlay' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 4.1, ''Rebate & Discount'', DiscountWL_Soccer' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OS'', 4.2, ''Rebate & Discount'', DiscountWL_OS' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Parlay'', 4.3, ''Rebate & Discount'', DiscountWL_Parlay' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 5.1, ''BA Commission'', BAComm_Soccer' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OS'', 5.2, ''BA Commission'', BAComm_OS' + CHAR(13) +
							'UNION ALL' + CHAR(13) +							
							'SELECT ''Parlay'', 5.3, ''BA Commission'', BAComm_Parlay) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +							
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-------------------
	-- Drop temp tables

	DROP TABLE #TempPartyChargeInfo
	DROP TABLE #Exchange
	DROP TABLE #TempDataSB
	DROP TABLE #FeeData
	DROP TABLE #FinalResult
	DROP TABLE #DiscountGroup
	DROP TABLE #TempFactLADailyWinloss
	DROP TABLE #TempProductMapping
	DROP TABLE #TempSiteMapping
END
GO

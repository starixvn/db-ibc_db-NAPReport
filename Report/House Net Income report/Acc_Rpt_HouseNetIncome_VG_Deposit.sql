/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_VG_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  
    Created:	20200317@Kean
    Task :		Integrate Virtual Games product [#126465]
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_VG_Deposit '20180601', '20180630'   
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
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																  AND map.SystemID = 2
		 WHERE p.PartyType = 1
			  AND pd.IsDeposit = 1
			  AND ci.ProductId = 38 -- VG
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
    -- End region

    -- Region: Get Licensees has charge rate

    CREATE TABLE #PartyChargeInfo (
	    ChargeId	  INT
	  , PartyId       INT
	  , LicenseeId    INT
	  , ParentID      INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , ProductID     INT);

    INSERT INTO #PartyChargeInfo(ChargeId
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
				(@PartyIDs, @FDate, @TDate, 'VRG', 'OA', 1) AS ci
			    INNER JOIN @tmpParty AS p ON ci.PartyID = p.PartyID
			WHERE DI_Rate > 0
				 AND ci.ChargeType = 1 -- get PT
		 );     
			
    -- End Region
	CREATE TABLE #SportBettypeMatrix(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype
						    , EventType
						    , SubProduct)
		 SELECT ProductID
			 , BetType
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (38, 0, 0, 2, '', 'VRG', 0);
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
			 (@FDate, @TDate, 'MYR');
    -- End region

	CREATE TABLE #tmpSite(SiteID_DW INT,SiteID_Li INT,SiteName VARCHAR(100))

	INSERT INTO #tmpSite(SiteID_DW,SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM DBWH.bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = 1;

	UPDATE tmpS
	SET tmpS.SiteID_Li = l.SiteID
	FROM #tmpSite tmpS
	INNER JOIN DBLIC.bodb_licensee.dbo.view_site_list l WITH(NOLOCK)
		ON tmpS.SiteName  = RTRIM(LTRIM(l.SiteName));

    CREATE TABLE #TempDataVG(
		rptDate            DATETIME
	  , ProductId          TINYINT
	  , SportType INT
	  , BetType INT
	  , SiteID	INT
	  , CurrencyID          INT
	  , MemberWL           MONEY
	  , HouseWL           MONEY);

	CREATE TABLE #DailyPayAmmount(
	    PartyId            INT
	  , rptDate            DATETIME
	  , ProductId          TINYINT
	  , LicenseWL          MONEY
	  , AmountToCompany    MONEY);

	INSERT INTO #TempDataVG(rptDate, ProductId, SportType, BetType          
				, SiteID
				, CurrencyID	
				, MemberWL, HouseWL)
			SELECT b.rptDate
				, 38 ProductID
				, b.SportType
				, b.BetType
				, s.SiteID_Li
				, b.CurrencyID 
				, SUM(ISNULL(b.WinlossP, 0))
				, SUM((b.WinlossIBC + b.CommissionS)) AS HouseWL
			FROM DBWH.bodb_account.dbo.FactSiteWinloss b WITH (NOLOCK)
				--INNER JOIN #SportBettypeMatrix AS sb ON sb.Bettype = b.bettype
				INNER JOIN #tmpSite s ON b.SiteId = s.SiteID_DW
			WHERE b.rptDate >= @FDate AND b.rptDate <= @TDate
				 AND b.CurrencyID <> 20
				 AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
				 AND b.BetType IN (SELECT sb.Bettype FROM #SportBettypeMatrix AS sb)
			GROUP BY b.rptDate
				--, sb.ProductID
				, b.SportType
				, b.BetType
				, s.SiteID_Li
				, b.CurrencyID

    INSERT INTO #DailyPayAmmount(PartyId, rptDate, ProductId, LicenseWL, AmountToCompany)
			SELECT p.PartyId
				, b.rptDate
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(e.Rate,0))
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * ISNULL(e.Rate,0))
			FROM #TempDataVG b
			    LEFT JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    INNER JOIN #PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , p.ProductId
		 
		 -- LA not return charge rate of Licensee TO ONEWork And Then use HouseWL 
			INSERT INTO #DailyPayAmmount(rptDate, ProductId, LicenseWL, AmountToCompany)
			SELECT b.rptDate
				, b.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(e.Rate,0))
				, SUM(-ISNULL(b.HouseWL, 0) * ISNULL(e.Rate,0))
			FROM #TempDataVG b
			    LEFT JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
				WHERE b.SiteID NOT IN (SELECT p.LicenseeId FROM #PartyChargeInfo p)
			GROUP BY b.rptdate
				  , b.ProductId	

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #DailyPayAmmount(PartyId, ProductId);

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
	  , @Products = 'VRG';
    -- Region: Result	

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , PayToSupplier    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , SUM(WLFeeApplied)
			 , 0 -- Product of House not aplly PayToSupplier
		 FROM #FeeData;		 


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
				    , 0 -- Product of House not aplly PayToSupplier
			    FROM #DailyPayAmmount
			    WHERE rptDate = @tmpDate;

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
							'(SELECT ''VG'', 1, ''House Income'', LicenseeWL) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataVG
	DROP TABLE #FinalResult
	DROP TABLE #FeeData
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #PartyChargeInfo
	DROP TABLE #tmpSite
	DROP TABLE #DailyPayAmmount
END
GO

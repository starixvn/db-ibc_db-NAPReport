/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CC_Deposit]
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
		- 20200313@Kean - Change the "Pay to supplier" formula of CC(New Bettype 1902) - #126465
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_CC_Deposit '20180601', '20180630'   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 

	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,[VName]
		  ,[NumberValue]
		  ,[sporttype]
		  ,[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN bodb02.dbo.Products p WITH(NOLOCK) ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCashWLShareRateTX')
	AND p.ProductPrefix IN ('CC')
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
			  AND ci.ProductId = 34 -- CC
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

    DECLARE @PartyChargeInfo AS TABLE(
	    ChargeId	  INT
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
			 (34, 0, 0, 2, '', 'CC', 0);
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

    CREATE TABLE #TempDataCC(
		rptDate            DATETIME
	  , ProductId          TINYINT
	  , SportType INT
	  , BetType INT
	  , SiteID	INT
	  , CurrencyID          INT
	  , MemberWL           MONEY);

	CREATE TABLE #DailyPayAmmount(
	    PartyId            INT
	  , rptDate            DATETIME
	  , MemberWL           MONEY
	  , PayToSupplier      MONEY
	  , ProductId          TINYINT
	  , LicenseWL          MONEY
	  , AmountToCompany    MONEY);

	INSERT INTO #TempDataCC(rptDate, ProductId, SportType, BetType          
				, SiteID
				, CurrencyID	
				, MemberWL)
			SELECT b.rptDate
				, 34 ProductID
				, b.SportType
				, b.BetType
				, s.SiteID_Li
				, b.CurrencyID 
				, SUM(ISNULL(b.WinlossP, 0))
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

    INSERT INTO #DailyPayAmmount(PartyId
				    , rptDate
				    , MemberWL
				    , PayToSupplier
				    , ProductId
				    , LicenseWL
				    , AmountToCompany)
		 (
			SELECT p.PartyId
				, b.rptDate
				, SUM(ISNULL(b.MemberWL, 0) * ISNULL(oa.Rate,0))
				, SUM(ISNULL(b.MemberWL, 0) * (CASE WHEN b.Bettype = 1902 THEN ISNULL(v.ChargeRate3rd,0) ELSE ISNULL(rd.Rate,0) END) * oa.Rate)
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(e.Rate,0))
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * ISNULL(e.Rate,0))
			FROM #TempDataCC b
				INNER JOIN #SportBettypeMatrix AS sb ON sb.Bettype = b.bettype
			    LEFT JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    LEFT JOIN #ExchangeOANDA AS oa ON b.rptDate = oa.ExchangeDate
										    AND b.CurrencyId = oa.ExchangeID
			    INNER JOIN @PartyChargeInfo AS p ON sb.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency AS lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID
																						AND b.CurrencyId = lc.CurrencyID
			    INNER JOIN @PartyCharge3rdInfo AS rd ON sb.ProductID = rd.ProductID
											    AND b.SiteID = rd.LicenseeID
											    AND b.rptDate BETWEEN rd.FromDate AND rd.ToDate
				LEFT JOIN #tmpVendorGlobalSetting v ON b.ProductID = v.ProductID 
																	AND v.Sporttype = b.SportType 
																	AND v.Bettype = b.BetType
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , p.ProductId
		 );	

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
	  , @Products = 'CC';
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
			 , 0
		 FROM #FeeData;		 

    WITH paySupplier
	    AS (
	    SELECT PartyId
		    , SUM(MemberWL) AS MemberWL
		    , SUM(PayToSupplier) AS PayToSupplier
	    FROM #DailyPayAmmount
	    GROUP BY PartyId)
	    UPDATE #FinalResult
			 SET
				#FinalResult.PayToSupplier = p.pay
	    FROM
		    (
			   SELECT SUM(CASE
						   WHEN paySupplier.MemberWL > 0
						   THEN 0
						   ELSE paySupplier.PayToSupplier
					    END) AS pay
			   FROM paySupplier
		    ) AS p
	    WHERE #FinalResult.RptDate = 'FullRange';

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
	DROP TABLE #FeeData
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #tmpSite
	DROP TABLE #DailyPayAmmount
END
GO

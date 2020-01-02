/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_AB_Deposit
	@FromDate       DATE 
   , @ToDate         DATE 
   , @DepositType    SMALLINT = 2
AS;
/*  
	Created:	20170213@Harper  
    Task :		House month-to-date Net Income report for All Bet
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20170505@Harper: Change formula for Currency Play [RedmineID: #76156]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
	
    Param's Explanation:   
	   - DepositType  
				    = 0 Credit 
				    = 1 Deposit Only
				    = 2 All

	EXEC Acc_Rpt_HouseNetIncome_AB_Deposit '20170201', '20170228'   
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
    EXECUTE bodb_licensee..LA_PartyListSel;

    DECLARE @tmpParty TABLE(
	    PartyID       INT
	  , IsDeposit     BIT
	  , LicenseeID    INT
	  , ParentID      INT
	  , Rate          FLOAT
	  , ChargeType    INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , LicenseeID)
		 SELECT DISTINCT
			   p.PartyID
			 , pd.IsDeposit
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 1
				  THEN p.OldRefID
				  ELSE lb.LabelID
			   END AS LicenseeID
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID
																			 AND map.SystemID = 2 -- LA
			LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
		 WHERE p.PartyType = 1 -- Licensee
			  AND ci.ProductID = 21 -- AB		
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
				(@PartyIDs, @FDate, @TDate, 'AB', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE ci.isDeposit = 1
				 AND DI_Rate > 0
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

    CREATE TABLE #PlayCurrencySettings(
	    SiteId            INT
	  , MemberCurrency    INT
	  , PlayCurrency      INT
	  , FromDate          DATETIME
	  , ToDate            DATETIME);

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

    INSERT INTO #PlayCurrencySettings
		 SELECT SiteId
			 , MemberCurrency
			 , PlayCurrency
			 , FromDate
			 , ToDate
		 FROM OPENQUERY(DB06, 'SELECT SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType = 211');
    -- End region

    CREATE TABLE #TempDataAB(
	    PartyId            INT
	  , rptDate            DATETIME
	  , CurrencyId         INT
	  , MemberWL           MONEY
	  , AComm              MONEY
	  , ProductId          TINYINT
	  , AmountToCompany    MONEY);

    INSERT INTO #TempDataAB(PartyId
					 , rptDate
					 , CurrencyId
					 , MemberWL
					 , AComm
					 , ProductId
					 , AmountToCompany)
		 (
			SELECT p.PartyId
				, b.rptDate
				, b.CurrencyID
				, SUM(ISNULL(b.MemberWL, 0))
				, SUM(ISNULL(b.CommissionA, 0)) * e.Rate
				, p.ProductId
				, SUM(-ISNULL(b.MemberWL, 0) * p.Rate) * e.Rate
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH (NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
									   AND b.CurrencyId = e.ExchangeID
			    INNER JOIN @PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
											AND
											    (p.Bettype = -1
												OR p.Bettype = b.Bettype)
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , b.CurrencyID
				  , p.ProductId
				  , e.Rate
		 );

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataAB(PartyId, ProductId);
    -- Region: Result	

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , PayToSupplier    MONEY
	  , CurrencyPlay     MONEY);
    -- Pay to Supplier for Credit + Deposit (GMT +8)

    DECLARE @DailyPayAmt TABLE(
	    RptDate              DATE
	  , IsDeposit            INT
	  , AmountDailyBased     MONEY
	  , AmountDailySystem    MONEY);

    DECLARE @CommissionRate    FLOAT;

    SELECT @CommissionRate = ci.DI_Rate
    FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd
	    (@FDate, @TDate, 'AB', 'OA') AS ci
    WHERE ci.ChargeType = 11;

    WITH rate3rd
	    AS (
	    SELECT DISTINCT
			 ci.IsDeposit
		    , ci.ProductID
		    , ci.DI_Rate
		    , ci.Fromdate
		    , ci.ToDate
		    , ci.ChargeType
		    , p.LicenseeID
	    FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd
		    (@FDate, @TDate, 'AB', 'OA') AS ci
		   INNER JOIN @tmpParty AS p ON p.ParentID = ci.PartyID
	    WHERE ci.ChargeType IN(9, 10)
			AND ci.IsDeposit = CASE
							   WHEN @DepositType = 2
							   THEN ci.IsDeposit
							   ELSE @DepositType
						    END),
	    PayToSupplierDaily
	    AS (
	    SELECT b.RptDate3rd
		    , p.IsDeposit
		    , b.CurrencyId
		    , ISNULL(c.PlayCurrency, b.CurrencyId) AS PlayCurrency
		    , SUM(CASE
				    WHEN p.IsDeposit = 1
				    THEN b.Winloss * p.DI_Rate
				    ELSE(b.Winloss + b.ValidBetAmount * @CommissionRate) * p.DI_Rate
				END) AS PayDaily
	    FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT AS b WITH (NOLOCK)
		   INNER JOIN rate3rd AS p ON p.LicenseeID = b.SiteID
								AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
		   INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH (NOLOCK) ON b.SiteId = s.SiteID
		   LEFT JOIN #PlayCurrencySettings AS c ON c.SiteId = s.IbcSiteID
										   AND b.CurrencyId = c.MemberCurrency
										   AND b.RptDate3rd BETWEEN c.FromDate AND c.ToDate
	    WHERE b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.BetTypeId BETWEEN 2401 AND 2499 -- AB
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund				
	    GROUP BY b.RptDate3rd
			 , p.IsDeposit
			 , b.CurrencyId
			 , ISNULL(c.PlayCurrency, b.CurrencyId))
	    INSERT INTO @DailyPayAmt(RptDate
						  , IsDeposit
						  , AmountDailyBased
						  , AmountDailySystem)
			 SELECT p.RptDate3rd
				 , p.IsDeposit
				 , p.PayDaily * oe.Rate
				 , p.PayDaily * pe.Rate
			 FROM PayToSupplierDaily AS p
				INNER JOIN #ExchangeOANDA AS oe ON oe.ExchangeDate = p.RptDate3rd
											AND oe.ExchangeID = p.CurrencyId
				INNER JOIN #ExchangeOANDA AS pe ON pe.ExchangeDate = p.RptDate3rd
											AND pe.ExchangeID = p.PlayCurrency;	

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
	  , @Products = 'AB';

    WITH paySupplier
	    AS (
	    SELECT SUM(CASE
				    WHEN AmountDailyBased > 0
					    AND IsDeposit = 1
				    THEN 0
				    ELSE AmountDailyBased
				END) AS AmountDailyBased
		    , SUM(CASE
				    WHEN AmountDailySystem > 0
					    AND IsDeposit = 1
				    THEN 0
				    ELSE AmountDailySystem
				END) AS AmountDailySystem
	    FROM
		    (
			   SELECT SUM(AmountDailyBased) AS AmountDailyBased
				   , IsDeposit
				   , SUM(AmountDailySystem) AS AmountDailySystem
			   FROM @DailyPayAmt
			   GROUP BY IsDeposit
		    ) AS s)
	    INSERT INTO #FinalResult(rptDate
						  , LicenseeWL
						  , PayToSupplier
						  , CurrencyPlay)
			 SELECT 'FullRange'
				 ,
				   (
					  SELECT CASE
							   WHEN SUM(AmountToCompany) < 0
							   THEN 0
							   ELSE SUM(WLFeeApplied)
						    END
					  FROM #FeeData
				   )
				 ,
				   (
					  SELECT AmountDailyBased
					  FROM paySupplier
				   )
				 ,
				   (
					  SELECT AmountDailySystem - AmountDailyBased
					  FROM paySupplier
				   );

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL
							, PayToSupplier
							, CurrencyPlay)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT SUM(AmountToCompany)
						FROM #TempDataAB
						WHERE rptDate = @tmpDate
					 )
				    ,
					 (
						SELECT SUM(AmountDailyBased)
						FROM @DailyPayAmt
						WHERE RptDate = @tmpDate
					 )
				    ,
					 (
						SELECT SUM(AmountDailySystem - AmountDailyBased)
						FROM @DailyPayAmt
						WHERE RptDate = @tmpDate
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
							'(SELECT ''AB'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''AB'', 4, ''Pay to supplier'', PayToSupplier' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''AB'', 5, ''Currency Play'', CurrencyPlay ) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataAB
	DROP TABLE #PlayCurrencySettings
	DROP TABLE #FinalResult
	DROP TABLE #FeeData
END
GO

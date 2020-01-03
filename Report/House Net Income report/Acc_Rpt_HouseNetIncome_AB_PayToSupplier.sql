/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_AB_PayToSupplier
	@FromDate       DATE 
   , @ToDate         DATE 
   , @DepositType    SMALLINT = 2
AS;
/*  
	Created:	20200102@Robert  
    Task :		#125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
    DB:			DBEXT/bodb02  
   
    Revisions:  		
		- 20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
	
    Param's Explanation:   
	   - DepositType  
				    = 0 Credit 
				    = 1 Deposit Only
				    = 2 All

	EXEC Acc_Rpt_HouseNetIncome_AB_PayToSupplier '20170201', '20170228'   
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

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
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID
																			AND map.SystemID = 2 -- LA
			LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
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

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;

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

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , PayToSupplier    MONEY
	  , CurrencyPlay     MONEY);

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
	    AS (SELECT DISTINCT 
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
	    AS (SELECT b.RptDate3rd
			   , p.IsDeposit
			   , b.CurrencyId
			   , ISNULL(c.PlayCurrency, b.CurrencyId) AS PlayCurrency
			   , SUM(CASE
					   WHEN p.IsDeposit = 1
					   THEN b.Winloss * p.DI_Rate
					   ELSE(b.Winloss + b.ValidBetAmount * @CommissionRate) * p.DI_Rate
				    END) AS PayDaily
		   FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT AS b WITH(NOLOCK)
			  INNER JOIN rate3rd AS p ON p.LicenseeID = b.SiteID
								    AND b.RptDate3rd BETWEEN p.FromDate AND p.ToDate
			  INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
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

    WITH paySupplier
	    AS (SELECT SUM(CASE
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
						  , PayToSupplier
						  , CurrencyPlay)
			 SELECT 'FullRange'
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
							, PayToSupplier
							, CurrencyPlay)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
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

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +							
							'(SELECT ''AB'', 4, ''Pay to supplier'', PayToSupplier' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''AB'', 5, ''Currency Play'', CurrencyPlay ) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)
	
	DROP TABLE #ExchangeOANDA	
	DROP TABLE #PlayCurrencySettings
	DROP TABLE #FinalResult	
END
GO

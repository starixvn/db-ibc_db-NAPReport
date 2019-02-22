/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CO_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20170518@Harper  
    Task :		House month-to-date Net Income report for Cashout
    DB:			DBEXT.bodb02  
   
    Revisions:  
		- 20170518@Harper: Create new SP for House Daily Winloss [RedmineID: #76695]
		- 20171019@Harper: Change for CO 100% [RedmineID: #84331]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
	
	Param's Explanation:   		

	EXEC Acc_Rpt_HouseNetIncome_CO_Deposit '20161230', '20161230'
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Get active Licensees

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), pa.PartyID)
    FROM
	    (
		   SELECT DISTINCT
				p.PartyID
		   FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			  INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			  INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
			  INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID
																			   AND map.SystemID = 2 -- LA
		   WHERE p.PartyType = 1 -- Licensee
			    AND pd.IsDeposit = 1
			    AND ci.ProductID = 25 -- Cashout
			    AND pd.IsDeposit = 1
			    AND
				   (ci.FromDate BETWEEN @FDate AND @TDate
				    OR ci.ToDate BETWEEN @FDate AND @TDate
				    OR ci.FromDate < @FDate
					  AND @TDate < ci.ToDate)
	    ) AS pa;
    -- Get Licensees has charge rate

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
				(@PartyIDs, @FDate, @TDate, 'CO', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 --exclude RB
		 );
    -- Get Exchange

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
    -- Get Sum data

    CREATE TABLE #TempDataCO(
	    rptDate     DATETIME
	  , MemberWL    MONEY);

    INSERT INTO #TempDataCO(rptDate
					 , MemberWL)
		 SELECT b.rptDate
			 , SUM((ISNULL(b.MemberWL, 0) + ISNULL(b.GrossWL, 0)) * e.Rate) AS MemberWL -- For CO: get 100%
		 FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH (NOLOCK)
			INNER JOIN #ExchangeOANDA AS e ON e.ExchangeDate = b.rptDate
									    AND e.ExchangeID = b.CurrencyId
			INNER JOIN
			 (
				SELECT DISTINCT
					  ProductID
					, LicenseeId
					, FromDate
					, ToDate
					, Bettype
				FROM @PartyChargeInfo
			 ) AS ci ON b.ProductID = ci.ProductID
					  AND ci.LicenseeId = b.SiteId
					  AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
					  AND
						 (ci.Bettype = -1
						  OR ci.Bettype = b.Bettype)
		 WHERE b.rptDate BETWEEN @FDate AND @TDate
			  AND b.Bettype IN(913, 914) -- don't need to follow formula in LA Sys
			  AND b.CurrencyId <> 20
			  AND b.StatusId NOT IN(-1, 101, 102, 103)
			  AND b.CustomerCategory IN(1003, 1004)
		 GROUP BY b.rptDate;

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , MemberWL         MONEY
	  , PayToSupplier    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , MemberWL
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , -SUM(MemberWL)
			 , 0
		 FROM #TempDataCO;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, MemberWL
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT ISNULL(-SUM(MemberWL), 0)
						FROM #TempDataCO
						WHERE rptDate = @tmpDate
					 ) -- LicenseeWL
				    , 0; -- PayToSupplier
		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''CO'', 1, ''House Income'', MemberWL' + CHAR(13) +
							') c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'	
	EXEC(@SQL)

	-- Region: Drop tmp table
	DROP TABLE #ExchangeOANDA
	DROP TABLE #TempDataCO
	DROP TABLE #FinalResult
END
GO


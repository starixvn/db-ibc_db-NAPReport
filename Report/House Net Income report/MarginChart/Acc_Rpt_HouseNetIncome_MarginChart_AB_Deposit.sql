/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_AB_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin
    Source :		Acc_Rpt_HouseNetIncome_AB_Deposit
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20191107@Robert -  House Net Income, Licensee Performance Email/Letstalk Report Integration, Remove credit [122516]
		- 20191202@Robert - Non - Sport Margin chart: data of Allbet and Gold Deluxe should be corrected [124697]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_AB_Deposit '2018-04-01', '2018-04-30'
  
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @tmpParty TABLE(
	    PartyID       INT
	  , IsDeposit     BIT
	  , LicenseeID    INT
	  , ParentID      INT
	  , Rate          FLOAT
	  , ChargeType    INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , LicenseeID
				    , ParentID)
		 SELECT DISTINCT 
			   p.PartyID
			 , pd.IsDeposit
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 1
				  THEN p.OldRefID
				  ELSE lb.LabelID
			   END AS LicenseeID
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 0
				  THEN 999
				  ELSE ci.ToParty
			   END -- credit
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

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;

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
				(@PartyIDs, @FDate, @TDate, 'AB', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference AS sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE ci.isDeposit = 1
				 AND DI_Rate > 0
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
				, SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate)) * e.Rate
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
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
				 AND b.StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptdate
				  , b.SiteId
				  , p.PartyId
				  , b.CurrencyID
				  , p.ProductId
				  , e.Rate
		 );

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataAB(PartyId, ProductId);

    CREATE TABLE #FinalResult(
	    RptDate       VARCHAR(10)
	  , LicenseeWL    MONEY);

    INSERT INTO #FinalResult(rptDate
					  , LicenseeWL)
		 SELECT 'FullRange'
			 , 0;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, LicenseeWL)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT SUM(AmountToCompany)
						FROM #TempDataAB
						WHERE rptDate = @tmpDate
					 ) AS LicenseeWL;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''AB'', 1, ''House Income'', LicenseeWL ) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +							
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	
	DROP TABLE #Exchange
	DROP TABLE #TempDataAB
	DROP TABLE #FinalResult
END
GO


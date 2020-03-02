/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SG_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20200224@Kean  
    Task :		Integrate SG (Spadegaming) product [RedmineID: #123734] 
    DB:			DBEXT/bodb02  
   
    Revisions:  
	   - 20200224@Kean: #123734 - House Net Income - Integrate SG (Spadegaming) product

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_SG_Deposit '20160901', '20160930'
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Active licensees

    CREATE TABLE #TempPartyList (
	    PartyId       INT
	  , PartyName     VARCHAR(200)
	  , BranchName    VARCHAR(200)
	  , ParentId      INT);

    INSERT INTO #TempPartyList(PartyId, PartyName, BranchName, ParentId)
    EXECUTE bodb_licensee.dbo.LA_PartyListSel;

    CREATE TABLE #tmpParty (
	    PartyID      INT
	  , IsDeposit    BIT
	  , ParentID     INT);

    INSERT INTO #tmpParty(PartyID
				    , IsDeposit)
		 SELECT DISTINCT
			   ci.FromParty
			 , pd.IsDeposit
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		 WHERE p.PartyType = 1
			  AND ci.ProductId = 36 -- Spade Gaming
			  AND EXISTS
					   (
						  SELECT 1
						  FROM bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH (NOLOCK)
						  WHERE map.ChargeID = ci.ChargeID
							   AND map.SystemID = 2
					   )
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
					AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM #tmpParty
    WHERE IsDeposit = 1;
    -- End region

    UPDATE p
		 SET
			p.ParentID = f.ParentId
    FROM #tmpParty p
	   INNER JOIN #TempPartyList f ON p.PartyID = f.PartyID;
    -- Region: ChargeInfo

    CREATE TABLE #PartyChargeInfo (
	    PartyId       INT
	  , LicenseeId    INT
	  , ParentID	  INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

	CREATE TABLE #PartyCharge3rdInfo (		
			LicenseeId	INT,
			Rate		MONEY,			
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			ProductID	INT
			)

    INSERT INTO #PartyChargeInfo(PartyId, LicenseeId, ParentID, IsDeposit, ProductID, Rate, Fromdate, Todate, Bettype)
			SELECT ci.PartyID
				, ci.LicenseeID, p.ParentID, ci.isDeposit, ci.ProductID
				, ci.DI_Rate, ci.Fromdate, ci.ToDate
				, ISNULL(sbr.Bettype, ci.Bettype)
			FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FDate, @TDate, 'SG', 'OA', 1) AS ci
				INNER JOIN #tmpParty p ON ci.PartyID = p.PartyID
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE DI_Rate > 0
				 AND ProductId <> 1 --exclude RB

	INSERT INTO #PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FDate, @TDate, 'SG', 'OA') ci	
			INNER JOIN #PartyChargeInfo p ON p.ParentID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1			
	)
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

    CREATE TABLE #TempDataSG(
			PartyId			INT,
			rptDate			DATETIME,
			MemberWL		MONEY,
			PayToSupplier	MONEY,
			AmountToCompany MONEY);

    INSERT INTO #TempDataSG(PartyId, RptDate, MemberWL, PayToSupplier, AmountToCompany)
			SELECT p.PartyId
				, b.rptdate
				, SUM(ISNULL(b.MemberWL, 0) * oa.Rate)
				, SUM(ISNULL(b.MemberWL, 0) * rd.Rate * oa.Rate)
				, SUM(-ISNULL(b.MemberWL, 0) * p.Rate * e.Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH (NOLOCK)
			    INNER JOIN #Exchange AS e ON b.rptDate = e.ExchangeDate
										AND b.CurrencyId = e.ExchangeID
				INNER JOIN #ExchangeOANDA oa ON b.rptDate = oa.ExchangeDate 
										AND b.CurrencyId = oa.ExchangeID
			    INNER JOIN #PartyChargeInfo AS p ON b.ProductId = p.ProductID
											AND p.LicenseeId = b.SiteId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
											AND
											    (p.Bettype = -1
												OR p.Bettype = b.Bettype)
				INNER JOIN #PartyCharge3rdInfo rd ON b.ProductID = rd.ProductID
													AND b.SiteID = rd.LicenseeID
													AND (b.rptDate BETWEEN rd.FromDate AND rd.ToDate)
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 103) -- Exclude Reject , Void, Refund
			GROUP BY p.PartyId, b.rptdate

    CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempDataSG(PartyId);

    -- Region: Result	

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , LicenseeWL       MONEY
	  , PayToSupplier    MONEY);
    -- Pay to Supplier using OANDA rate (CurrencyID = 2 => MYR)

    CREATE TABLE #FeeData(
	    PartyId            INT
	  , ProductID          INT
	  , AComm              MONEY
	  , MinFeeApplied      MONEY
	  , WLFeeApplied       MONEY
	  , AmountToCompany    MONEY);

    INSERT INTO #FeeData(PartyId, ProductID, AComm, MinFeeApplied, WLFeeApplied, AmountToCompany)
    EXEC dbo.Acc_Rpt_HouseNetIncome_LicenseeFee
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @Products = 'SG';

    INSERT INTO #FinalResult(RptDate, LicenseeWL, PayToSupplier)
		 SELECT 'FullRange'
				 , ISNULL(SUM(WLFeeApplied), 0)
				 , 0
		 FROM #FeeData;
	;WITH paySupplier AS (
					SELECT PartyId, SUM(MemberWL) AS MemberWL, SUM(PayToSupplier) AS PayToSupplier
					FROM #TempDataSG
					GROUP BY PartyId
				)
	UPDATE #FinalResult
	SET #FinalResult.PayToSupplier = p.pay
	FROM (
			SELECT SUM(CASE WHEN paySupplier.MemberWL > 0 THEN 0 ELSE paySupplier.PayToSupplier END) AS pay 
			FROM paySupplier
		) AS p
	WHERE #FinalResult.RptDate = 'FullRange'


    DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
				SUM(AmountToCompany), -- LicenseeWL
				SUM(PayToSupplier) -- PayToSupplier
		FROM #TempDataSG 
		WHERE rptDate = @tmpDate

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult;
    -- End region
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SG'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #TempDataSG
	DROP TABLE #FinalResult
	DROP TABLE #FeeData
	DROP TABLE #PartyChargeInfo
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #TempPartyList
	DROP TABLE #tmpParty
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_SG_Deposit] TO [bodbAdminNet]
GO
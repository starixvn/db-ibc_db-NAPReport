/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit]
	@FromDate	DATE ,
	@ToDate	DATE ,
	@ProductList VARCHAR(MAX) = ''
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:				DBWH/bodb_dwrs  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20180806@Harper - DHWL Margin Chart - Create new message notification to NSD group based on Product List [#RedmineID: 98611]
		- 20180813@Harper - DHWL Non-sports Margin Chart - Integrate OneRNG Jackpot & Pragmatic [#RedmineID: 97562]
		- 20180912@Harper - DHWL Non-sports Margin Chart - Integrate Pocker Games [#RedmineID: 100426]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]		
		- 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
		- 20191121@Robert: #123733 - Email/Letstalk Reports - Integrate PP Tournament (Exclude bettype 4299)
		- 20200225@Kean: #128007 - Changes on the rate of Pay to suppliers

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB' - if group is NSD Group

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit '2018-05-01', '2018-05-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @SiteCN88    INT;

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88';

	DECLARE @Credit VARCHAR(MAX) = 'NG,VS,KN,LT,VS2,VB,CS,NG2,AB,GD,CB,PP,CC'  
		
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #tmpProduct		(ProductPrefix VARCHAR(20))

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	-- Get Product List
	
	IF LEN(ISNULL(@ProductList, '')) > 0 
	BEGIN
		INSERT INTO #tmpProduct ( ProductPrefix )		
		SELECT val AS ProductPrefix		
		FROM dbo.strSplit(@ProductList, ',')
	END

	CREATE CLUSTERED INDEX [PK_tmp_CurrencyDaily] ON #Exchange( ExchangeDate, ExchangeID )

	DECLARE @OpenQuery NVARCHAR(1000)
	SELECT @OpenQuery = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBEXT, '
						+ N'''SELECT ExchangeDate, ExchangeID, BaseCurrencyRate '
						+ N'FROM bodb02.dbo.LA_f_ExchangeDailySel('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''MYR'''''			
						+ N')'')'
					
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQuery)
	
	CREATE TABLE #ChargeInfo3rd(
	    ProductID         INT
	  , Rate              MONEY
	  , FromDate          SMALLDATETIME
	  , ToDate            SMALLDATETIME
	  , MinAmount         MONEY
	  , MaxAmount         MONEY
	  , BaseCurrencyId    INT);
	
	DECLARE @OpenQueryCharge NVARCHAR(1000)
	SELECT @OpenQueryCharge = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''PP'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID
						, Rate, FromDate, ToDate
					    , MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQueryCharge);	
	-- End region

	CREATE TABLE #FinalResult (
		RptDate		VARCHAR(10),
		HouseWL		MONEY,
		ExtraPT		MONEY,
		PayToSupplier MONEY,
		TurnOver	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate


	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- KN + LT + MacauGame + VS + VS2: with Exchange Oanda Rate
	CREATE TABLE #PayToSupplierRate (ProductID INT, Rate MONEY)
	CREATE TABLE #PayToSupplierRate_CN88 (ProductID INT, Rate MONEY)

	INSERT INTO #PayToSupplierRate( ProductID, Rate )
	VALUES  (3, 0.5)    -- NG, HP5
		   ,(5, 0.01)   -- VS
		   ,(8, 0.03)   -- Keno
		   ,(28, 0.03)  -- LT
		   ,(27, 0.01)  -- VS2
		   ,(22, 0.02)  -- MacauG
		   ,(23, 0.5)   -- NG2
		   ,(34, 0.025) -- CC

	INSERT INTO #PayToSupplierRate_CN88( ProductID, Rate )
	VALUES  (3, 0.015)    -- NG, HP5
		   ,(5, 0.01)   -- VS
		   ,(8, 0.015)   -- Keno
		   ,(28, 0.015)  -- LT
		   ,(27, 0.01)  -- VS2 
			
	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct 
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0,0,0,2,'',@Credit,0) sel
	WHERE ISNULL(@ProductList, '') = ''
		OR EXISTS (SELECT 1 FROM #tmpProduct p WHERE sel.ProductPrefix = p.ProductPrefix) 

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, SiteID INT , ProductID INT, Bettype INT
								, HouseWL MONEY, MemberWL MONEY, MemberWLOANDA MONEY
								, PayToSupplier MONEY, TurnOver MONEY, ExtraPT MONEY)
	
	INSERT INTO #TmpHouseWL (rptDate, SiteID, ProductID, Bettype, HouseWL, MemberWL, MemberWLOANDA, TurnOver, ExtraPT)
	SELECT 
		b.rptDate,
		b.SiteID,
		sb.ProductID,
		b.BetType,
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(-SUM((b.WinlossIBC + b.CommissionS) * ex.rate),0) END AS HouseWL, -- Don't need to caculate for CB
		-- Get value to be calculate for Pay To Supplier
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM(b.WinlossP * ex.Rate),0) END AS MemberWL,
		-- 
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM(b.WinlossP * oanda.Rate),0) END AS MemberWLOANDA,		
		ISNULL(SUM((CASE WHEN TurnoverIBC = 0 THEN 0  ELSE TurnoverIBC - ExtraTO END ) 
				* ( CASE WHEN VarianceVR > 0 THEN( VarianceVR + 1 ) ELSE 1 END )
				* ex.Rate),0) AS TurnOver,
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.Rate),0) END AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
	INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID	
	WHERE 
		b.rptDate >= @FDate AND b.rptDate <= @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
		AND b.BetType NOT IN (4299, 4300)
	GROUP BY b.rptDate, b.SiteID, sb.ProductID, b.BetType
	OPTION (RECOMPILE)
	
	-- BEGIN - Calculate PayToSupplier for Pragmatic (PP)
	CREATE TABLE #tmpPayToSupplier_PP(
	    RptDate               VARCHAR(10),
		PayToSupplier_PP_Daily        MONEY);

	INSERT INTO #tmpPayToSupplier_PP(RptDate, PayToSupplier_PP_Daily)
	SELECT wl.RptDate, (CASE WHEN (MemberWLOANDA < 0 AND (ci.MinAmount * ex.Rate) = 0) OR (MemberWLOANDA >= (ci.MinAmount * ex.Rate)) THEN 
								CASE WHEN MemberWLOANDA > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
									 ELSE MemberWLOANDA - (ci.MinAmount * ex.Rate) END
							ELSE 0 END) * ci.Rate AS PayToSupplier_PP_Daily
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #TmpHouseWL AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate

		-- Get DetailDaily Data & FullRange Data
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier
							, TurnOver
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	, (SELECT SUM(t.HouseWL) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  HouseWL
	, (SELECT SUM(t.ExtraPT) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  ExtraPT

	, ((SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 23 AND  t.rptDate = @tmpDate) -- NG2, NG
		+ (SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 3 AND t.SiteID <> @SiteCN88 AND  t.rptDate = @tmpDate) -- NG2, NG

		+ (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0)  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID IN (22,34)  AND  t.rptDate = @tmpDate) -- MacauG, CC 
		+ (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0)  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID IN (5,8,28,27) 
										AND t.SiteID <> @SiteCN88 AND  t.rptDate = @tmpDate) -- VS,KN,LT,VS2

		+ (SELECT ISNULL(-SUM(t.PayToSupplier_PP_Daily),0) FROM #tmpPayToSupplier_PP AS t WHERE t.rptDate = @tmpDate) -- PP

		+ (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
									     WHERE t.ProductID IN (5,8,28,27) 
										 AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) --VS,KN,LT,VS2 for CN88
		+ (SELECT ISNULL(SUM(t.MemberWL * r.Rate),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 3 
										 AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) --NG,HP5for CN88
		) AS  PayToSupplier

	, (SELECT SUM(t.TurnOver) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  TurnOver;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END; 

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
			
	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
	SELECT 'FullRange', 0, 0, 0, 0		

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''NonSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 8, ''Turn Over'', TurnOver' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #tmpProduct
	DROP TABLE #PayToSupplierRate
	DROP TABLE #PayToSupplierRate_CN88
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpPayToSupplier_PP

END
GO

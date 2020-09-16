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
		- 20200224@Kean: #123734 - House Net Income - Integrate SG (Spadegaming) product
		- 20200313@Kean - Change the "Pay to supplier" formula of SG And CC(New Bettype 1902) - #126465
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200410@Kean - Email/Letstalk Reports - Integrate BBIN product [#131364]
		- 20200403@Kean - Integrate Mini Game Xoc Dia of CC(New Bettype 1903) - #131507
		- 20200408@Kean - Add 12 New Slot Games for Macau Game - (#131755)
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200422@Kean - Integrate Mini Game 3D Lottery of CC(New Bettype 1904) - #132790
		- 20200423@Kean - Email/Letstalk Reports - Integrate IBCBet Live Casino product (#130690)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate Midas Hi-Lo Game (#133594)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO ION Live Casino (#132331)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO RNG War (#132019)
		- 20200521@Ned.Le - Re-Integrate Fishing World product for letstalk (#134533)
		- 20200529@Ned.Le - House Net Income Email/Letstalk - Change timezone to calculate monthly Pay To Supplier (#134867)
		- 20200701@Kean.Nguyen - House Net Income Email/Letstalk - Change formula to Calculate Margin (#136792)
		- 20200714@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)
		- 20200811@Kean - Email/Letstalk Reports - Integrate PG Soft (#137764)
		- 20200827@Kean - Email/Letstalk Reports - Integrate 10 New BluePrint Games (#140459)
		- 20200916@Roy: Email/Letstalk Reports - Integrate Joker Gaming (#131602)
		- 20200916@Roy: Email/Letstalk Reports - Integrate WM Live Casino (#131593)

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB' - if group is NSD Group

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit '2018-05-01', '2018-05-31'
  
*/

BEGIN

	SET NOCOUNT ON

	-- Declare variables
    DECLARE @FDate    DATE,
			@TDate    DATE

    SELECT @FDate = @FromDate,
		   @TDate = @ToDate

	DECLARE @SiteCN88 INT

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88'

	DECLARE @ProductCodeAll VARCHAR(MAX) = 'NG,VS,KN,LT,VS2,VB,CS,NG2,AB,GD,CB,PP,CC,SG,VRG,SAG,SBC,SXG,BBIN,TG,IBCLC,ION,RNGW,FW,PGS,JK,WM'
	DECLARE @ProductCodeGMT4 VARCHAR(1000) = 'VB,CC,BBIN,TG,IBCLC,ION,RNGW,PGS,JK,WM'
	DECLARE @ProductCodeGMT VARCHAR(1000) = 'AB,FW,PP,SG,SAG,SXG'

	-- #tmpBettypeGroup
	CREATE TABLE #tmpBettypeGroup (
		BettypeGroupID SMALLINT,
		ProductID INT,
		Bettype INT
	)

	INSERT INTO #tmpBettypeGroup (BettypeGroupID, ProductID, Bettype)
	SELECT bg.BettypeGroupID, pb.ProductID, bg.Bettype
	FROM bodb_Account.dbo.BettypeGroup bg (NOLOCK)
		 LEFT JOIN bodb_Account.dbo.Product_Bettype pb (NOLOCK) ON bg.Bettype = pb.Bettype
		 LEFT JOIN bodb_Account.dbo.Bettype b (NOLOCK) ON bg.Bettype = b.typeid
	WHERE bg.BettypeGroupID IN (6, 10)

	-- #Exchange
	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	
	INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange( ExchangeDate, ExchangeID)

	-- #ExchangeOANDA
	CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

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
					
	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQuery)

	-- #tmpProduct
	CREATE TABLE #tmpProduct (ProductPrefix VARCHAR(20))

	IF LEN(ISNULL(@ProductList, '')) > 0 
	BEGIN
		INSERT INTO #tmpProduct (ProductPrefix)
		SELECT val AS ProductPrefix		
		FROM dbo.strSplit(@ProductList, ',')
	END

	-- #tmpVendorGlobalSetting
	CREATE TABLE #tmpVendorGlobalSetting (ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 
	
	;WITH CTE_ProductSport AS (
		SELECT DISTINCT
			   p.ProductID, sbm.Sporttype, p.ProductPrefix, p.VendorID
		FROM bodb02.dbo.Products p (NOLOCK)
	         INNER JOIN bodb02.dbo.SportBettypeMatrix sbm (NOLOCK) ON p.ProductID = sbm.ProductID
		WHERE p.ProductPrefix IN (SELECT val FROM bodb02.dbo.strSplit(@ProductCodeGMT4, ','))
	)
	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		   ,v.[VName]
		   ,v.[NumberValue]
		   ,v.[sporttype]
		   ,v.[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
		 INNER JOIN CTE_ProductSport p WITH(NOLOCK) ON v.[VendorId] = p.VendorID AND v.Sporttype = p.Sporttype
	WHERE v.[VName] IN ('3rdCreditWLShareRate',																						-- All Product
					    '3rdCreditWLShareRateTX', '3rdCreditWLShareRateXD', '3rdCreditWLShareRate3D', '3rdCreditWLShareRateHL', 	-- 1902,1903,1904,1905 of Card Club
					    '3rdCreditWLShareRateION')																					-- WL Share Rale of ION
	
	-- #ChargeInfo3rd
	CREATE TABLE #ChargeInfo3rd(
	    ProductID         INT
	  , Rate              MONEY
	  , FromDate          SMALLDATETIME
	  , ToDate            SMALLDATETIME
	  , MinAmount         MONEY
	  , MaxAmount         MONEY
	  , BaseCurrencyId    INT)
	
	DECLARE @OpenQueryCharge NVARCHAR(1000)
	SELECT @OpenQueryCharge = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N','''''+ @ProductCodeGMT4 + ''''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQueryCharge)

	INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate)
	SELECT v.ProductID, v.ChargeRate3rd, @FDate, @TDate
		   FROM #tmpVendorGlobalSetting v
	WHERE v.ProductID NOT IN (SELECT ProductID FROM #ChargeInfo3rd)
	      AND v.VName IN ('3rdCreditWLShareRate','3rdCreditWLShareRateION')

	-- #SportBettypeMatrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct 
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0,0,0,2,'',@ProductCodeAll,0) sel
	WHERE ISNULL(@ProductList, '') = ''
		  OR EXISTS (SELECT 1 FROM #tmpProduct p WHERE sel.ProductPrefix = p.ProductPrefix)
	
	DELETE t
	FROM #SportBettypeMatrix t
	WHERE t.Bettype IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 32)

	-- BEGIN - Calculating

	-- + KN & LT & MacauGame & VS & VS2: with Exchange Oanda Rate
	CREATE TABLE #PayToSupplierRate (ProductID INT, Rate MONEY)
	CREATE TABLE #PayToSupplierRate_CN88 (ProductID INT, Rate MONEY)

	INSERT INTO #PayToSupplierRate (ProductID, Rate)
	VALUES (3, 0.5)			-- NG, HP5
		   ,(5, 0.01)		-- VS
		   ,(8, 0.03)		-- Keno
		   ,(28, 0.03)		-- LT
		   ,(27, 0.01)		-- VS2
		   --,(22, 0.02)	-- MacauG
		   ,(23, 0.5)		-- NG2

	INSERT INTO #PayToSupplierRate_CN88 (ProductID, Rate)
	VALUES (3, 0.015)		-- NG, HP5
		   ,(5, 0.01)		-- VS
		   ,(8, 0.015)		-- Keno
		   ,(28, 0.015)		-- LT
		   ,(27, 0.01)		-- VS2 
			
	-- + #TmpHouseWL
	CREATE TABLE #TmpHouseWL (rptDate DATE, SiteID INT, ProductID INT, SportType INT, Bettype INT,
							  HouseWL MONEY, MemberWL MONEY, MemberWLOANDA MONEY, TurnOver MONEY, ExtraPT MONEY)
	
	INSERT INTO #TmpHouseWL (rptDate, SiteID, ProductID, SportType, Bettype,
							 HouseWL, MemberWL, MemberWLOANDA, TurnOver, ExtraPT)
	SELECT b.rptDate,
		   b.SiteID,
		   sb.ProductID,
		   b.SportType,
		   b.BetType,
		  CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(-SUM((b.WinlossIBC + b.CommissionS) * ex.rate),0) END AS HouseWL,
		  CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM(b.WinlossP * ex.Rate),0) END AS MemberWL,
		  CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM(b.WinlossP * oanda.Rate),0) END AS MemberWLOANDA,		
		  ISNULL(SUM((CASE WHEN TurnoverIBC = 0 THEN 0  ELSE TurnoverIBC - ExtraTO END )
				     * ( CASE WHEN VarianceVR > 0 THEN( VarianceVR + 1 ) ELSE 1 END )
				     * ex.Rate * (CASE WHEN b.TicketStatus in (12,13) THEN 0.5 ELSE 1 END)), 0) AS TurnOver,
		  CASE WHEN sb.ProductID = 15 THEN 0 ELSE ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.Rate),0) END AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		 INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		 LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		 LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
	WHERE b.rptDate >= @FDate AND b.rptDate <= @TDate
		  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14, 3)
		  AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0) -- Credit data only
	GROUP BY b.rptDate, b.SiteID, sb.ProductID, b.SportType, b.BetType
	OPTION (RECOMPILE);

	-- + #tmpPayToSupplier_Daily
	CREATE TABLE #tmpPayToSupplier_Daily(
		ProductId				INT,
	    RptDate					DATE,
		PayToSupplier_Daily		MONEY)

	INSERT INTO #tmpPayToSupplier_Daily (ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID,
		   t.rptDate,
		   CASE WHEN t.ProductID = 22 THEN  SUM(t.MemberWLOANDA * (CASE WHEN bg.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END))
		        ELSE SUM(t.MemberWLOANDA * (CASE WHEN t.ProductID = 34 AND t.Bettype IN (1902,1903,1904,1905) THEN ISNULL(v.ChargeRate3rd,0) ELSE ISNULL(ci.Rate,0) END)) END PayToSupplier_Daily
	FROM #TmpHouseWL AS t
		 INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
		 LEFT JOIN bodb_Account.dbo.BettypeGroup bg (NOLOCK) ON t.BetType = bg.Bettype AND bg.BettypeGroupID = 11
		 LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
												AND v.Sporttype = t.SportType 
												AND v.Bettype = t.BetType
												AND v.VName IN ('3rdCreditWLShareRateTX','3rdCreditWLShareRateXD','3rdCreditWLShareRate3D','3rdCreditWLShareRateHL')
	WHERE t.ProductID IN (SELECT ProductID
		                  FROM bodb02.dbo.Products
						  WHERE ProductPrefix IN (SELECT val FROM bodb02.dbo.strSplit(@ProductCodeGMT4, ',')))
	GROUP BY t.ProductID,
	         t.rptDate

	-- + #tmpPayToSupplier_GMT
	CREATE TABLE #tmpPayToSupplier_GMT(
		ProductCode			VARCHAR(10),
	    RptDate             VARCHAR(10),
		PayToSupplier_Daily	MONEY,
		CurrencyPlay_Daily	MONEY)
	
	INSERT INTO #tmpPayToSupplier_GMT(ProductCode, RptDate, PayToSupplier_Daily, CurrencyPlay_Daily)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier @FromDate = @FDate,
															   @ToDate = @TDate,
															   @ProductCodes = @ProductCodeGMT,
															   @DepositType = 0,
															   @Site = '',
															   @IsOldView = 0
	
	IF (ISNULL(@ProductList, '') <> '')
	BEGIN
		DELETE t
		FROM #tmpPayToSupplier_GMT t
		WHERE t.ProductCode NOT IN (SELECT ProductPrefix FROM #tmpProduct)
	END

	-- END - Calculating

	-- #FinalResult
	CREATE TABLE #FinalResult (
		RptDate		  VARCHAR(10),
		HouseWL		  MONEY,
		ExtraPT		  MONEY,
		PayToSupplier MONEY,
		TurnOver	  MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

    WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106) AS RptDate,
			   (SELECT SUM(t.HouseWL) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS HouseWL,
			   (SELECT SUM(t.ExtraPT) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS ExtraPT,
			   ((SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0)
			     FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
                 WHERE t.ProductID = 23 AND  t.rptDate = @tmpDate) -- NG2
		         +
				 (SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0)
				  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
				  WHERE t.ProductID = 3 AND t.SiteID <> @SiteCN88 AND  t.rptDate = @tmpDate) --NG
				 +
				 (SELECT ISNULL(SUM(t.PayToSupplier_Daily),0)
				  FROM #tmpPayToSupplier_Daily AS t 
				  WHERE t.ProductID IN (SELECT ProductID
										FROM bodb02.dbo.Products
										WHERE ProductPrefix IN (SELECT val FROM bodb02.dbo.strSplit(@ProductCodeGMT4, ',')))
						AND  t.rptDate = @tmpDate) -- List of GMT4 Products
				 +
				 (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0)
				  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
				  WHERE t.ProductID IN (5,8,28,27) AND t.SiteID <> @SiteCN88 AND t.rptDate = @tmpDate) -- VS, KN, LT, VS2
				 +
				 (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0)
				  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
				  WHERE t.ProductID IN (5,8,28,27) 
						AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) -- VS, KN, LT, VS2 for CN88
		         +
				 (SELECT ISNULL(SUM(t.MemberWL * r.Rate),0)
				  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
				  WHERE t.ProductID = 3 AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) -- NG, HP5 for CN88
				 +
				 (SELECT ISNULL(SUM(t.PayToSupplier_Daily),0)
				  FROM #tmpPayToSupplier_GMT AS t
				  WHERE t.rptDate = CONVERT(VARCHAR(2), @tmpDate, 106)) -- List of GMT8-GMT0 Products
			   ) AS PayToSupplier,
			   (SELECT SUM(t.TurnOver) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  TurnOver

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult

	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
	SELECT 'FullRange', 0, 0, 0, 0

	-- Return data
	DECLARE @SQL VARCHAR(1000)

	SELECT @SQL =
		'SELECT * ' + CHAR(13) +
		'FROM (SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
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
	DROP TABLE #tmpBettypeGroup
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #tmpProduct
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #PayToSupplierRate
	DROP TABLE #PayToSupplierRate_CN88
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpPayToSupplier_Daily
	DROP TABLE #tmpPayToSupplier_GMT

END
GO

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

	DECLARE @Credit VARCHAR(MAX) = 'NG,VS,KN,LT,VS2,VB,CS,NG2,AB,GD,CB,PP,CC,SG,VRG,SAG,SBC,SXG,BBIN,TG,IBCLC,ION,RNGW,FW'
		
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #tmpProduct		(ProductPrefix VARCHAR(20))
	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 
	
	;WITH CTE_ProductSport AS (
		SELECT DISTINCT
			   p.ProductID, sbm.Sporttype, p.ProductPrefix, p.VendorID
		FROM bodb02.dbo.Products p (NOLOCK)
	         INNER JOIN bodb02.dbo.SportBettypeMatrix sbm (NOLOCK) ON p.ProductID = sbm.ProductID
	WHERE p.ProductPrefix IN ('PP', 'CC', 'SG', 'SAG', 'SXG', 'BBIN', 'TG', 'IBCLC', 'ION', 'RNGW')
	)
	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,v.[VName]
		  ,v.[NumberValue]
		  ,v.[sporttype]
		  ,v.[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN CTE_ProductSport p WITH(NOLOCK) ON v.[VendorId] = p.VendorID
												  AND (v.Sporttype = p.Sporttype	-- For ['CC', 'SAG', 'SXG', 'BBIN', 'TG', 'IBCLC', 'ION', 'RNGW']
												       OR v.Sporttype IS NULL)		-- For ['PP', 'SG']
	WHERE v.[VName] IN ('3rdCreditWLShareRate', '3rdCreditWLShareRateTX', '3rdCreditWLShareRateXD', '3rdCreditWLShareRate3D', '3rdCreditWLShareRateHL', '3rdCreditRebateRate', '3rdCreditWLShareRateION')

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

	-- BEGIN: Rebate Rate of Sexy Gaming FROM LA
	CREATE TABLE #tmpRebateRate (DI_Rate MONEY)
	DECLARE @OpenQueryRebateRate NVARCHAR(1000), @RebateRate    MONEY
	SELECT @OpenQueryRebateRate = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT ci.DI_Rate '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''SAG'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'WHERE ci.ChargeType = 11 AND ci.IsDeposit = 0'
						+ N''')';

	INSERT INTO #tmpRebateRate(DI_Rate)
    EXECUTE (@OpenQueryRebateRate);

    SELECT TOP 1 @RebateRate = DI_Rate
    FROM #tmpRebateRate
	-- END: Rebate Rate of Sexy Gaming FROM LA
	
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
						+ N',''''PP,CC,SG,SAG,SXG,BBIN,TG,IBCLC,ION,RNGW'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd(ProductID
						, Rate, FromDate, ToDate
					    , MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQueryCharge);

	-- Get ChargeRate3rd from VendorGlobalSetting table IF NOT EXIST FROM LA
	INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate)
	SELECT v.ProductID, v.ChargeRate3rd, @FDate, @TDate
	FROM #tmpVendorGlobalSetting v
	WHERE v.ProductID NOT IN (SELECT ProductID FROM #ChargeInfo3rd)	
	AND v.VName IN ('3rdCreditWLShareRate','3rdCreditWLShareRateION')
	-- End region

	CREATE TABLE #FinalResult (
		RptDate		  VARCHAR(10),
		HouseWL		  MONEY,
		ExtraPT		  MONEY,
		PayToSupplier MONEY,
		TurnOver	  MONEY,
		CurrencyPlay  MONEY
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
		  -- ,(22, 0.02)  -- MacauG
		   ,(23, 0.5)   -- NG2

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
		 
	-- Mapping Site between DW and Licensees
	CREATE TABLE #tmpSite(SiteID_DW INT,SiteID_Li INT,SiteName VARCHAR(100))

	INSERT INTO #tmpSite(SiteID_DW,SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = 0;

	UPDATE tmpS
	SET tmpS.SiteID_Li = l.SiteID
	FROM #tmpSite tmpS
	INNER JOIN DBLIC.bodb_licensee.dbo.view_site_list l WITH(NOLOCK)
		ON tmpS.SiteName  = RTRIM(LTRIM(l.SiteName));

	-- BEGIN: GET DATA
	CREATE TABLE #TmpHouseWL (rptDate DATE, SiteID INT , ProductID INT, SportType INT, Bettype INT
								, HouseWL MONEY, MemberWL MONEY, MemberWLOANDA MONEY
								, PayToSupplier MONEY, TurnOver MONEY, ExtraPT MONEY)
	DECLARE @OpenQuery_BettingByProduct NVARCHAR(MAX);
	CREATE TABLE #tmpRpt_BettingByProduct(rptDate DATE, SiteID INT, ProductId INT, CurrencyId INT, ValidBetAmount MONEY)
	
	INSERT INTO #TmpHouseWL (rptDate, SiteID, ProductID, SportType, Bettype, HouseWL, MemberWL, MemberWLOANDA, TurnOver, ExtraPT)
	SELECT 
		b.rptDate,
		b.SiteID,
		sb.ProductID,
		b.SportType,
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
	LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
	LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID	
	WHERE 
		b.rptDate >= @FDate AND b.rptDate <= @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
		AND b.BetType NOT IN (4299, 4300)
	GROUP BY b.rptDate, b.SiteID, sb.ProductID, b.SportType, b.BetType
	OPTION (RECOMPILE);

	SELECT @OpenQuery_BettingByProduct = 'SELECT rptDate, SiteID, ProductId, CurrencyId, ValidBetAmount
				FROM    OPENQUERY(DBLIC, 	
				''SELECT rptDate, SiteID, ProductId, CurrencyId, ValidBetAmount
					FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK) 
					WHERE b.CurrencyID NOT IN(20, 27, 28)
					AND b.customercategory NOT IN(27, 28)
					AND b.StatusId NOT IN(-1, 101, 102)
					AND b.ProductId = 39
					AND rptDate BETWEEN '''''+ CONVERT(VARCHAR(10),@FDate,101)+''''' AND ''''' + CONVERT(VARCHAR(10),@TDATE,101) +''''''')';

		INSERT INTO #tmpRpt_BettingByProduct(rptDate, SiteID, ProductId, CurrencyId, ValidBetAmount)
		EXECUTE (@OpenQuery_BettingByProduct)
	-- END: GET DATA

	-- BEGIN - Calculate PayToSupplier for CC, SG, SAG, SXG, PP,TG,IBCLC,ION,RNGW
	CREATE TABLE #tmpPayToSupplier_Daily(
		ProductId					INT,
	    RptDate						DATE,
		PayToSupplier_Daily        MONEY);

	-- Valid Bets Rebate Of SAG From LA 
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(ISNULL(t.ValidBetAmount,0) * ISNULL(ci.Rate,0) * ISNULL(@RebateRate,v.ChargeRate3rd) * ISNULL(oanda.rate,0)) 
							FROM #tmpRpt_BettingByProduct AS t
							INNER JOIN #tmpSite s ON t.SiteID = s.SiteID_Li
							INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							LEFT JOIN #ExchangeOANDA oanda ON t.rptdate = oanda.exchangedate AND t.currencyid = oanda.ExchangeID
							LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
																	AND v.VName = '3rdCreditRebateRate'
							WHERE t.ProductID IN (SELECT s.ProductID FROM #SportBettypeMatrix s WHERE s.ProductID = 39)  
							GROUP BY t.ProductID, t.rptDate
	-- CC, SG, SAG, SXG, BBIN, TG, IBCLC, ION, RNGW
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(t.MemberWLOANDA * (CASE WHEN t.ProductID = 34 AND t.Bettype IN (1902,1903,1904,1905) THEN ISNULL(v.ChargeRate3rd,0) 
															ELSE ISNULL(ci.Rate,0) END)) 
							FROM #TmpHouseWL AS t
							INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
																	AND v.Sporttype = t.SportType 
																	AND v.Bettype = t.BetType
																	AND v.VName IN ('3rdCreditWLShareRateTX','3rdCreditWLShareRateXD','3rdCreditWLShareRate3D','3rdCreditWLShareRateHL')
							WHERE t.ProductID IN (34, 36, 39, 45, 40, 47, 46, 52, 50)
							GROUP BY t.ProductID, t.rptDate
	-- Macau Games
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(t.MemberWLOANDA * (CASE WHEN BetType IN (4051,4052,4053,4054,4055) THEN 0.03 ELSE 0.02 END)) 
							FROM #TmpHouseWL AS t
							WHERE t.ProductID IN (22)
							GROUP BY t.ProductID, t.rptDate
	-- PP
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT 32 ProductID, wl.RptDate, (CASE WHEN (MemberWLOANDA < 0 AND (ci.MinAmount * ex.Rate) = 0) OR (MemberWLOANDA >= (ci.MinAmount * ex.Rate)) THEN 
								CASE WHEN MemberWLOANDA > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
									 ELSE MemberWLOANDA - (ci.MinAmount * ex.Rate) END
							ELSE 0 END) * ci.Rate AS PayToSupplier_Daily
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #TmpHouseWL AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate
	-- END - Calculate PayToSupplier for CC, SG, SAG, SXG, PP, TG, IBCLC, ION, RNGW
	
	-- BEGIN - Calculate PayToSupplier for AB
	CREATE TABLE #tmpPayToSupplier_Daily_AB (RptDate				  VARCHAR(10),
											 PayToSupplier_Daily_AB   MONEY,
											 CurrencyPlay_Daily_AB    MONEY);
	
	INSERT INTO #tmpPayToSupplier_Daily_AB (RptDate, PayToSupplier_Daily_AB, CurrencyPlay_Daily_AB)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_MarginChart_PayToSupplier @FromDate = @FDate, @ToDate = @TDate, @ProductPrefix = 'AB', @DepositType = 0
	-- END - Calculate PayToSupplier for AB
	
	-- BEGIN - Calculate PayToSupplier for FW
	CREATE TABLE #tmpPayToSupplier_Daily_FW (RptDate				  VARCHAR(10),
											 PayToSupplier_Daily_FW   MONEY,
											 CurrencyPlay_Daily_FW    MONEY);
	
	INSERT INTO #tmpPayToSupplier_Daily_FW (RptDate, PayToSupplier_Daily_FW, CurrencyPlay_Daily_FW)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_MarginChart_PayToSupplier @FromDate = @FDate, @ToDate = @TDate, @ProductPrefix = 'FW', @DepositType = 0
	-- END - Calculate PayToSupplier for FW

	-- Get DetailDaily Data & FullRange Data
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier
							, TurnOver
							, CurrencyPlay
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	, (SELECT SUM(t.HouseWL) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  HouseWL
	, (SELECT SUM(t.ExtraPT) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  ExtraPT

	, ((SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 23 AND  t.rptDate = @tmpDate) -- NG2, NG
		+ (SELECT ISNULL(SUM((t.HouseWL + t.ExtraPT) * r.Rate) * (-1),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 3 AND t.SiteID <> @SiteCN88 AND  t.rptDate = @tmpDate) -- NG2, NG
		+ (SELECT ISNULL(SUM(t.PayToSupplier_Daily),0) FROM #tmpPayToSupplier_Daily AS t 
											 WHERE t.ProductID IN (22, 34, 36, 39, 45, 40, 47, 46, 52, 50)  AND  t.rptDate = @tmpDate) -- MacauG, CC, SG, SA, SXG, TG, BBIN, IBCLC, ION, RNGW
		+ (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0)  FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate r ON t.ProductID = r.ProductID
									     WHERE t.ProductID IN (5,8,28,27) 
										AND t.SiteID <> @SiteCN88 AND  t.rptDate = @tmpDate) -- VS,KN,LT,VS2

		+ (SELECT ISNULL(-SUM(t.PayToSupplier_Daily),0) FROM #tmpPayToSupplier_Daily AS t 
														WHERE t.ProductID IN (32) AND t.rptDate = @tmpDate) -- PP

		+ (SELECT ISNULL(SUM(t.MemberWLOANDA * r.Rate),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
									     WHERE t.ProductID IN (5,8,28,27) 
										 AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) --VS,KN,LT,VS2 for CN88
		+ (SELECT ISNULL(SUM(t.MemberWL * r.Rate),0) FROM #TmpHouseWL AS t INNER JOIN #PayToSupplierRate_CN88 r ON t.ProductID = r.ProductID
									     WHERE t.ProductID = 3 
										 AND t.rptDate = @tmpDate AND t.SiteID = @SiteCN88) --NG,HP5 for CN88
		+ (SELECT ISNULL(SUM(PayToSupplier_Daily_AB),0) FROM #tmpPayToSupplier_Daily_AB AS t
									     WHERE t.rptDate = CONVERT(VARCHAR(2), @tmpDate, 106)) --AB
		+ (SELECT ISNULL(SUM(PayToSupplier_Daily_FW),0) FROM #tmpPayToSupplier_Daily_FW AS t
									     WHERE t.rptDate = CONVERT(VARCHAR(2), @tmpDate, 106)) --FW
		) AS  PayToSupplier

	, (SELECT SUM(t.TurnOver) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  TurnOver
	, (SELECT SUM(t.CurrencyPlay_Daily_AB) FROM #tmpPayToSupplier_Daily_AB AS t WHERE t.rptDate = CONVERT(VARCHAR(2), @tmpDate, 106)) AS  TurnOver;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END; 

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
			
	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver, CurrencyPlay)
	SELECT 'FullRange', 0, 0, 0, 0, 0

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
							'SELECT ''NonSport'', 4, ''Pay to supplier'', PayToSupplier' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 10, ''Currency Play'', CurrencyPlay) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #tmpRpt_BettingByProduct
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #tmpProduct
	DROP TABLE #tmpSite
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #PayToSupplierRate
	DROP TABLE #PayToSupplierRate_CN88
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpRebateRate
	DROP TABLE #tmpPayToSupplier_Daily
	DROP TABLE #tmpPayToSupplier_Daily_AB
	DROP TABLE #tmpPayToSupplier_Daily_FW

END
GO

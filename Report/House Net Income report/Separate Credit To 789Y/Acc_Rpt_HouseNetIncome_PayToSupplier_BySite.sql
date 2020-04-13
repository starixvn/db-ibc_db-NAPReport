/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier_BySite]
	@FromDate DATE,
	@ToDate	DATE,
	@DepositType BIT = 0,
	@Site       VARCHAR(20) = ''
AS  
/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200224@Kean - Add SG product - #123734
		- 20200313@Kean - Change the "Pay to supplier" formula of SG AND CC(New Bettype 1902) - #126465
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200410@Kean - Email/Letstalk Reports - Integrate BBIN product [#131364]
		- 20200403@Kean - Integrate Mini Game Xoc Dia of CC(New Bettype 1903) - #131507
		- 20200408@Kean - Add 12 New Slot Games for Macau Game - (#131755)
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
	
	Param's Explanation:   
	- DepositType  
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '789Y' -- 789Y site of Credit   
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate DATE, @TDate DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- #Exchange
	DECLARE @SiteCN88    INT;

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88';

    CREATE TABLE #Exchange(ExchangeDate    DATE, ExchangeID      INT, Rate            FLOAT);
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE TABLE #tmpProduct(ProductID INT, ProductCode VARCHAR(100), VendorID INT)
	CREATE TABLE #tmpVendorGlobalSetting(ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 

	INSERT INTO #tmpProduct(ProductID, ProductCode, VendorID)
	SELECT ProductID, ProductPrefix, VendorID
	FROM bodb02.dbo.Products WITH(NOLOCK)
	WHERE ProductPrefix IN ( 'PP', 'CC', 'SG', 'SAG', 'SXG', 'BBIN', 'TG')
	
	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		  ,[VName]
		  ,[NumberValue]
		  ,[sporttype]
		  ,[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN #tmpProduct p ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCreditWLShareRate'
					, '3rdCreditWLShareRateTX', '3rdCreditWLShareRateXD' -- 1902,1903 of Card Club
					, '3rdCreditRebateRate') -- Rebate Rate of SA Gaming

    INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
		 SELECT ExchangeDate, Currency, Rate
		 FROM bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
		 WHERE ExchangeDate BETWEEN @FDate AND @TDate;

	DECLARE @OpenQueryExchange NVARCHAR(1000)
	SELECT @OpenQueryExchange = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBEXT, '
						+ N'''SELECT ExchangeDate, ExchangeID, BaseCurrencyRate '
						+ N'FROM bodb02.dbo.LA_f_ExchangeDailySel('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''MYR'''''			
						+ N')'')'
					
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQueryExchange)

	-- BEGIN: Rebate Rate of SA Gaming FROM LA
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
	-- END: Rebate Rate of SA Gaming FROM LA

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
						+ N',''''PP,CC,SG,SAG,SXG,BBIN,TG'''''
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
	AND v.VName = '3rdCreditWLShareRate'
	
	-- Mapping Site between DW and Licensees
	CREATE TABLE #tmpSite(SiteID_DW INT,SiteID_Li INT,SiteName VARCHAR(100))

	INSERT INTO #tmpSite(SiteID_DW,SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = @DepositType
		AND (@Site = '' OR [site] = @Site)
		AND siteid <> @SiteCN88;

	UPDATE tmpS
	SET tmpS.SiteID_Li = l.SiteID
	FROM #tmpSite tmpS
	INNER JOIN DBLIC.bodb_licensee.dbo.view_site_list l WITH(NOLOCK)
		ON tmpS.SiteName  = RTRIM(LTRIM(l.SiteName));	

    -- #FinalResult
	CREATE TABLE #FinalResult(
	    RptDate               VARCHAR(10)
	  , PayToSupplier_NG        MONEY
	  , PayToSupplier_H5        MONEY
	  , PayToSupplier_VS        MONEY
	  , PayToSupplier_RNGKeno        MONEY
	  , PayToSupplier_NG2        MONEY
	  , PayToSupplier_MacauG        MONEY
	  , PayToSupplier_LT        MONEY
	  , PayToSupplier_EX        MONEY--
	  , PayToSupplier_VS2        MONEY
	  , PayToSupplier_1RNG        MONEY
	  , PayToSupplier_1RNG_JP        MONEY
	  , PayToSupplier_PP        MONEY
	  , PayToSupplier_CC        MONEY
	  , PayToSupplier_SP        MONEY
	  , PayToSupplier_SG        MONEY
	  , PayToSupplier_SA        MONEY
	  , PayToSupplier_SXG        MONEY
	  , PayToSupplier_BBIN        MONEY
	  , PayToSupplier_TG        MONEY);

	  DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;
    -- #SportBettypeMatrix

    CREATE TABLE #SportBettypeMatrix(
	    ProductID    INT
		, Bettype      INT);

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype)
		SELECT DISTINCT ProductID
			 , BetType
		FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
		WHERE ProductID IN (3, 5, 8, 23, 22, 21, 12, 28, 27, 6, 32, 34, 36, 39, 45, 47, 40)
		 AND BetType NOT IN (4299, 4300) -- PP

	-- BEGIN: GET DATA
	CREATE TABLE #tmpFactSiteWinloss(
		rptDate      DATE
		, ProductID INT
		, SportType    INT
		, BetType    INT
		, HouseWL      MONEY
		, MemberWLOANDA MONEY);

	DECLARE @OpenQuery_BettingByProduct NVARCHAR(MAX);
	CREATE TABLE #tmpRpt_BettingByProduct(
			rptDate	DATE NULL
			, SiteID	INT NULL
			, ProductId	INT NULL
			, CurrencyId	INT NULL
			, ValidBetAmount MONEY NULL)
				
    INSERT INTO #tmpFactSiteWinloss(rptDate
				   , ProductID
				   , SportType
				   , BetType
				   , HouseWL
				   , MemberWLOANDA)
		 SELECT b.rptDate
			 ,  sb.ProductID
			 ,  CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END SportType
			 ,  b.BetType
			 ,ISNULL(-SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate), 0) AS  HouseWL
			 ,ISNULL(SUM(b.WinlossP * oanda.Rate), 0) AS  MemberWLOANDA
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
			INNER JOIN #tmpSite AS s ON b.SiteID = s.SiteID_DW
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20  
		 GROUP BY b.rptDate
			    , sb.ProductID
				, CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END
				, b.BetType OPTION(RECOMPILE);

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

	-- BEGIN - Calculate PayToSupplier for CC, SG, SAG, SXG, PP, BBIN, TG
	CREATE TABLE #tmpPayToSupplier_Daily(
		ProductId					INT,
	    RptDate						DATE,
		PayToSupplier_Daily        MONEY);

	CREATE TABLE #tmpPayToSupplier_MTD(
		ProductId					INT,
		MemberWLOANDA				MONEY,
		PayToSupplier_PP_MTD        MONEY);

	-- For Daily
	-- Valid Bets Rebate Of SAG From LA 
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(t.ValidBetAmount * ISNULL(ci.Rate,0) * ISNULL(@RebateRate,v.ChargeRate3rd) * ISNULL(oanda.rate,0)) 
							FROM #tmpRpt_BettingByProduct AS t
							INNER JOIN #tmpSite s ON t.SiteID = s.SiteID_Li
							INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode IN ('SAG')
							LEFT JOIN #ExchangeOANDA oanda ON t.rptdate = oanda.exchangedate AND t.currencyid = oanda.ExchangeID
							LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
																	AND v.VName = '3rdCreditRebateRate'
							WHERE t.ProductID IN (39) 
							GROUP BY t.ProductID, t.rptDate

	-- CC, SG, SAG, SXG, BBIN, TG
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(t.MemberWLOANDA * (CASE WHEN t.ProductID = 34 AND t.Bettype IN (1902, 1903) THEN ISNULL(v.ChargeRate3rd,0) 
															ELSE ISNULL(ci.Rate,0) END)) 
							FROM #tmpFactSiteWinloss AS t
							INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
							INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode IN ('CC', 'SG', 'SAG', 'SXG', 'BBIN', 'TG')
							LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
																	AND v.Sporttype = t.SportType 
																	AND v.Bettype = t.BetType
																	AND v.VName IN ('3rdCreditWLShareRateTX','3rdCreditWLShareRateXD')
							WHERE t.ProductID IN (34, 36, 39, 45, 47, 40)
							GROUP BY t.ProductID, t.rptDate

	-- Macau Games
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID, t.rptDate, SUM(t.MemberWLOANDA * (CASE WHEN BetType IN (4051,4052,4053,4054,4055) THEN 0.03 ELSE 0.02 END)) 
							FROM #tmpFactSiteWinloss AS t
							WHERE t.ProductID IN (22)
							GROUP BY t.ProductID, t.rptDate

	-- PP
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT 32 ProductID, wl.RptDate, (CASE WHEN (MemberWLOANDA < 0 AND (ci.MinAmount * ex.Rate) = 0) OR (MemberWLOANDA >= (ci.MinAmount * ex.Rate)) THEN 
								CASE WHEN MemberWLOANDA > (MaxAmount * ex.Rate) THEN (ci.MaxAmount - ci.MinAmount) * ex.Rate
									 ELSE MemberWLOANDA - (ci.MinAmount * ex.Rate) END
							ELSE 0 END) * ci.Rate AS PayToSupplier_PP_Daily
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #tmpFactSiteWinloss AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'PP'
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate

	-- For Monthly
	-- Macau Games
	INSERT INTO #tmpPayToSupplier_MTD(ProductId, MemberWLOANDA, PayToSupplier_PP_MTD)
	SELECT t.ProductID, SUM(MemberWLOANDA), SUM(t.MemberWLOANDA * (CASE WHEN BetType IN (4051,4052,4053,4054,4055) THEN 0.03 ELSE 0.02 END)) 
							FROM #tmpFactSiteWinloss AS t
							WHERE t.ProductID IN (22)
							GROUP BY t.ProductID
	--PP
	INSERT INTO #tmpPayToSupplier_MTD(ProductId, MemberWLOANDA, PayToSupplier_PP_MTD)
	SELECT 32 ProductID, SUM(MemberWL_MTD) MemberWLOANDA,
						SUM((CASE WHEN MemberWL_MTD >= MinAmount THEN 
								CASE WHEN MemberWL_MTD > MaxAmount THEN (MaxAmount - MinAmount)
									 ELSE MemberWL_MTD - MinAmount END
							ELSE 0 END) * Rate)  AS PayToSupplier_PP_MTD
		FROM (
		SELECT ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount * ex.Rate as MinAmount, MaxAmount * ex.Rate as MaxAmount, SUM(MemberWLOANDA)  MemberWL_MTD
		FROM (
				SELECT RptDate, SUM(t.MemberWLOANDA * (-1))  MemberWLOANDA
				FROM #tmpFactSiteWinloss AS t 
				WHERE t.ProductID = 32 GROUP BY RptDate ) wl
			INNER JOIN #ChargeInfo3rd ci ON wl.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID AND p.ProductCode = 'PP'
			INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate
			GROUP BY ci.Rate, ci.FromDate, ci.ToDate, ci.MinAmount * ex.Rate, MaxAmount * ex.Rate
					) as temp
	-- END - Calculate PayToSupplier for CC, SG, SAG, SXG, PP, BBIN
		
	-- Get DetailDaily Data & FullRange Data
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
						  ,	PayToSupplier_NG        
						  , PayToSupplier_H5        
						  , PayToSupplier_VS        
						  , PayToSupplier_RNGKeno        
						  , PayToSupplier_NG2        
						  , PayToSupplier_MacauG                
						  , PayToSupplier_LT
						  , PayToSupplier_EX        
						  , PayToSupplier_VS2        
						  , PayToSupplier_1RNG
						  , PayToSupplier_1RNG_JP        
						  , PayToSupplier_PP   
						  , PayToSupplier_CC
						  , PayToSupplier_SP
						  , PayToSupplier_SG
						  , PayToSupplier_SA
						  , PayToSupplier_SXG
						  , PayToSupplier_BBIN
						  , PayToSupplier_TG
						  )
SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND  t.rptDate = @tmpDate) AS  PayToSupplier_NG
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate)  AS  PayToSupplier_H5
	,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate)  AS  PayToSupplier_VS
	,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate)  AS  PayToSupplier_RNGKeno
	,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 23 AND t.rptDate = @tmpDate) AS  PayToSupplier_NG2
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate) AS  PayToSupplier_MacauG
	,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate) AS  PayToSupplier_LT
	, 0 PayToSupplier_EX
	,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate) AS  PayToSupplier_VS2
	, 0 PayToSupplier_1RNG
	, 0 PayToSupplier_1RNG_JP
	,(SELECT -SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 32 AND t.rptDate = @tmpDate) AS  PayToSupplier_PP
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 34 AND t.rptDate = @tmpDate) AS  PayToSupplier_CC
	, 0 PayToSupplier_SP
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 36 AND t.rptDate = @tmpDate) AS  PayToSupplier_SG
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 39 AND t.rptDate = @tmpDate) AS  PayToSupplier_SA
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 45 AND t.rptDate = @tmpDate) AS PayToSupplier_SXG
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 47 AND t.rptDate = @tmpDate) AS PayToSupplier_BBIN
	,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 40 AND t.rptDate = @tmpDate) AS  PayToSupplier_TG

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END; 

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult; 
	
INSERT INTO #FinalResult(RptDate
					, PayToSupplier_NG        
					, PayToSupplier_H5        
					, PayToSupplier_VS        
					, PayToSupplier_RNGKeno        
					, PayToSupplier_NG2        
					, PayToSupplier_MacauG               
					, PayToSupplier_LT
					, PayToSupplier_EX        
					, PayToSupplier_VS2        
					, PayToSupplier_1RNG
					, PayToSupplier_1RNG_JP        
					, PayToSupplier_PP   
					, PayToSupplier_CC
					, PayToSupplier_SP
					, PayToSupplier_SG
					, PayToSupplier_SA
					, PayToSupplier_SXG
					, PayToSupplier_BBIN
					, PayToSupplier_TG)
		 SELECT 'FullRange'
			, SUM(PayToSupplier_NG)        
			, SUM(PayToSupplier_H5)
			, 0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 5)
			, 0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 8)
			, SUM(PayToSupplier_NG2)
			, (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(PayToSupplier_PP_MTD) END FROM #tmpPayToSupplier_MTD AS t WHERE t.ProductID = 22)
			, 0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 28)
			, 0
			, 0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 27)               
			, 0
			, 0        
			, (SELECT CASE WHEN SUM(MemberWLOANDA) < 0 THEN 0 ELSE -SUM(PayToSupplier_PP_MTD) END FROM #tmpPayToSupplier_MTD AS t WHERE t.ProductID = 32)
			, CASE WHEN SUM(PayToSupplier_CC) > 0 THEN 0 ELSE SUM(PayToSupplier_CC) END
			, 0
			, CASE WHEN SUM(PayToSupplier_SG) > 0 THEN 0 ELSE SUM(PayToSupplier_SG) END
			, SUM(PayToSupplier_SA)
			, SUM(PayToSupplier_SXG)
			, SUM(PayToSupplier_BBIN)
			, CASE WHEN SUM(PayToSupplier_TG) > 0 THEN 0 ELSE SUM(PayToSupplier_TG) END
		 FROM #FinalResult;

    -- Select the output
    DECLARE @SQL    VARCHAR(max);
    SELECT @SQL = 'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''NG'', 1, ''PayToSupplier'', PayToSupplier_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 2, ''PayToSupplier'', PayToSupplier_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 3, ''PayToSupplier'', PayToSupplier_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGKeno'', 4, ''PayToSupplier'', PayToSupplier_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG2'', 5, ''PayToSupplier'', PayToSupplier_NG2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''MacauG'', 6, ''PayToSupplier'', PayToSupplier_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 7, ''PayToSupplier'', PayToSupplier_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 8, ''PayToSupplier'', PayToSupplier_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 9, ''PayToSupplier'', PayToSupplier_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG'', 10, ''PayToSupplier'', PayToSupplier_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''1RNG-JP'', 11, ''PayToSupplier'', PayToSupplier_1RNG_JP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''PP'', 12, ''PayToSupplier'', PayToSupplier_PP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 13, ''PayToSupplier'', PayToSupplier_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''SP'', 14, ''PayToSupplier'', PayToSupplier_SP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SG'', 15, ''PayToSupplier'', PayToSupplier_SG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SAG'', 16, ''PayToSupplier'', PayToSupplier_SA' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''SXG'', 17, ''PayToSupplier'', PayToSupplier_SXG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''BBIN'', 18, ''PayToSupplier'', PayToSupplier_BBIN' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''TG'', 21, ''PayToSupplier'', PayToSupplier_TG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13)    
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13)

    CREATE TABLE #tmpPayToSupplier_MetricGaming(
	    RptDate               VARCHAR(10),
		PayToSupplier_MG        MONEY);

	INSERT INTO #tmpPayToSupplier_MetricGaming(rptDate, PayToSupplier_MG)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming 
				@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	CREATE TABLE #tmpPayToSupplier_MuayThai(
	    RptDate               VARCHAR(10),
		PayToSupplier_MT        MONEY);

	INSERT INTO #tmpPayToSupplier_MuayThai(rptDate, PayToSupplier_MT)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMuayThai
			@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
			
	CREATE TABLE #tmpPayToSupplier_BetBuilder(
	    RptDate               VARCHAR(10),
		PayToSupplier_BB        MONEY);

	INSERT INTO #tmpPayToSupplier_BetBuilder(rptDate, PayToSupplier_BB)
		EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder
			@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site			 

	DECLARE @SQL_MetricGaming    VARCHAR(max)
			,@SQL_MuayThai    VARCHAR(max)
			,@SQL_BetBuilder    VARCHAR(max);

    SELECT @SQL_MetricGaming = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MetricGaming' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 18, ''PayToSupplier'', PayToSupplier_MG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);
	SELECT @SQL_MuayThai = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MuayThai' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''OS'', 19, ''PayToSupplier'', PayToSupplier_MT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);
	SELECT @SQL_BetBuilder = 'SELECT * ' + CHAR(13) 
			+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_BetBuilder' + CHAR(13) 
			+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 20, ''PayToSupplier'', PayToSupplier_BB) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
			+ 'PIVOT' + CHAR(13) 
			+ '(' + CHAR(13) 
			+ 'MAX(value)' + CHAR(13) 
			+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
			+ ') piv' + CHAR(13);

	EXEC (@SQL_MetricGaming + ' UNION ALL ' + @SQL_MuayThai + ' UNION ALL ' + @SQL_BetBuilder + ' UNION ALL ' + @SQL );

	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_AB_PayToSupplier
		@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_GD_PayToSupplier
		@FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site

	-- Drop temp tables
	DROP TABLE #tmpPayToSupplier_MetricGaming;
	DROP TABLE #tmpPayToSupplier_MuayThai;
	DROP TABLE #tmpPayToSupplier_BetBuilder;
    -- Drop temp tables
    DROP TABLE #SportBettypeMatrix;
    DROP TABLE #Exchange;
	DROP TABLE #ExchangeOANDA;
	DROP TABLE #tmpProduct;
	DROP TABLE #tmpVendorGlobalSetting;
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpRebateRate
	DROP TABLE #tmpSite
    DROP TABLE #FinalResult;
    DROP TABLE #tmpFactSiteWinloss;
	DROP TABLE #tmpRpt_BettingByProduct
	DROP TABLE #tmpPayToSupplier_Daily;
	DROP TABLE #tmpPayToSupplier_MTD;

END
GO
GRANT EXECUTE ON [dbo].Acc_Rpt_HouseNetIncome_PayToSupplier_BySite TO [dwrs]
/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PayToSupplier_BySite]
	@FromDate DATE,
	@ToDate	DATE,
	@DepositType BIT = 0,
	@Site VARCHAR(20) = ''
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
		- 20200422@Kean - Integrate Mini Game 3D Lottery of CC(New Bettype 1904) - #132790
		- 20200423@Kean - Email/Letstalk Reports - Integrate IBCBet Live Casino product (#130690)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate Midas Hi-Lo Game (#133594)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO ION Live Casino (#132331)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO RNG War (#132019)
		- 20200521@Ned.Le - Re-Integrate Fishing World product for letstalk (#134533)
		- 20200529@Ned.Le - House Net Income Email/Letstalk - Change timezone to calculate monthly Pay To Supplier (#134867)
		- 20200714@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)
						    * Remove the hardcoding of bettype=4299|4300 (FACT table already care about these bettypes)
	
	Param's Explanation:   
	- DepositType  
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_PayToSupplier_BySite '20180601', '20180619', 1, '789Y' -- 789Y site of Credit   
  
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

	DECLARE @ProductIDAll VARCHAR(1000) = '3,5,8,23,22,21,12,28,27,6,32,34,36,39,45,47,40,46,52,50,24'
	DECLARE @ProductCodeGMT4 VARCHAR(1000) = 'CC,BBIN,TG,IBCLC,ION,RNGW'
	DECLARE @ProductCodeGMT VARCHAR(1000) = 'AB,FW,PP,SG,SAG,SXG'

    -- #Exchange
    CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

    INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	-- #ExchangeOANDA
	CREATE TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

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
					
	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQueryExchange)

	-- #tmpProduct
	CREATE TABLE #tmpProduct (ProductID INT, Sporttype INT, ProductCode VARCHAR(100), VendorID INT)

	INSERT INTO #tmpProduct (ProductID, Sporttype, ProductCode, VendorID)
	SELECT DISTINCT p.ProductID, sbm.Sporttype, p.ProductPrefix, p.VendorID
	FROM bodb02.dbo.Products p (NOLOCK)
	     INNER JOIN bodb02.dbo.SportBettypeMatrix sbm (NOLOCK) ON p.ProductID = sbm.ProductID
	WHERE p.ProductPrefix IN (SELECT val FROM bodb02.dbo.strSplit(@ProductCodeGMT4, ','))

	-- #tmpVendorGlobalSetting
	CREATE TABLE #tmpVendorGlobalSetting (ProductID INT, VName VARCHAR(50), ChargeRate3rd DECIMAL(19, 8), Sporttype SMALLINT, Bettype SMALLINT) 
	
	INSERT INTO #tmpVendorGlobalSetting(ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID
		   ,v.[VName]
		   ,v.[NumberValue]
		   ,v.[sporttype]
		   ,v.[bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	INNER JOIN #tmpProduct p ON v.[VendorId] = p.VendorID AND v.Sporttype = p.Sporttype
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
	
	-- #tmpSite
	CREATE TABLE #tmpSite (SiteID_DW INT, SiteID_Li INT, SiteName VARCHAR(100))

	INSERT INTO #tmpSite (SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName 
	FROM bodb_account.dbo.tbl_site WITH(NOLOCK)
	WHERE isDeposit = @DepositType
		  AND (@Site = '' OR [site] = @Site)
		  AND siteid <> @SiteCN88

	UPDATE tmpS
	SET tmpS.SiteID_Li = l.SiteID
	FROM #tmpSite tmpS
	INNER JOIN DBLIC.bodb_licensee.dbo.view_site_list l WITH(NOLOCK) ON tmpS.SiteName  = RTRIM(LTRIM(l.SiteName))
    
	-- #SportBettypeMatrix
    CREATE TABLE #SportBettypeMatrix(ProductID INT, Bettype INT)

    INSERT INTO #SportBettypeMatrix(ProductID, Bettype)
	SELECT DISTINCT ProductID, BetType
	FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE ProductID IN (SELECT CAST(val AS INT) val FROM bodb02.dbo.strSplit(@ProductIDAll, ','))

	-- #tmpFactSiteWinloss
	CREATE TABLE #tmpFactSiteWinloss (rptDate		DATE,
									  ProductID		INT,
									  SportType		INT,
									  BetType		INT,
									  HouseWL		MONEY,
									  MemberWLOANDA MONEY)
				
    INSERT INTO #tmpFactSiteWinloss (rptDate,
									 ProductID,
									 SportType,
									 BetType,
									 HouseWL,
									 MemberWLOANDA)
	SELECT b.rptDate, 
		   sb.ProductID,
		   CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END SportType,
		   b.BetType,
		   ISNULL(-SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate), 0) AS  HouseWL,
		   ISNULL(SUM(b.WinlossP * oanda.Rate), 0) AS  MemberWLOANDA
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
		 INNER JOIN #SportBettypeMatrix AS sb ON b.Bettype = sb.Bettype
	     INNER JOIN #tmpSite AS s ON b.SiteID = s.SiteID_DW
	     LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
	     LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
	WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
		  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		  AND b.CurrencyID <> 20  
	GROUP BY b.rptDate,
			 sb.ProductID,
			 CASE WHEN b.BetType IN (9, 29) THEN -2 ELSE b.SportType END,
			 b.BetType OPTION(RECOMPILE)

	-- BEGIN - Calculate PayToSupplier for GMT4 Product

	-- + Create temp table
	CREATE TABLE #tmpPayToSupplier_Daily(
		ProductId				INT,
	    RptDate					DATE,
		PayToSupplier_Daily     MONEY)

	CREATE TABLE #tmpPayToSupplier_MTD(
		ProductId				INT,
		MemberWLOANDA			MONEY,
		PayToSupplier_PP_MTD    MONEY)

	-- + For Daily - CC, BBIN, TG, IBCLC, ION, RNGW
	INSERT INTO #tmpPayToSupplier_Daily (ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID,
		   t.rptDate,
		   SUM(t.MemberWLOANDA
		       * (CASE WHEN t.ProductID = 34 AND t.Bettype IN (1902, 1903, 1904, 1905) THEN ISNULL(v.ChargeRate3rd,0) ELSE ISNULL(ci.Rate,0) END)) PayToSupplier_Daily
	FROM #tmpFactSiteWinloss AS t
		 INNER JOIN #ChargeInfo3rd AS ci ON t.ProductID = ci.ProductID AND t.rptDate BETWEEN ci.FromDate AND ci.ToDate
		 INNER JOIN #tmpProduct p on ci.ProductID = p.ProductID
         LEFT JOIN #tmpVendorGlobalSetting v ON t.ProductID = v.ProductID 
											    AND v.Sporttype = t.SportType 
												AND v.Bettype = t.BetType
												AND v.VName IN ('3rdCreditWLShareRateTX','3rdCreditWLShareRateXD','3rdCreditWLShareRate3D','3rdCreditWLShareRateHL')
	GROUP BY t.ProductID,
		     t.rptDate

	-- + For Daily - Macau Games
	INSERT INTO #tmpPayToSupplier_Daily(ProductId, RptDate, PayToSupplier_Daily)
	SELECT t.ProductID,
		   t.rptDate,
		   SUM(t.MemberWLOANDA * (CASE WHEN BetType IN (4051,4052,4053,4054,4055) THEN 0.03 ELSE 0.02 END)) 
	FROM #tmpFactSiteWinloss AS t
	WHERE t.ProductID IN (22)
	GROUP BY t.ProductID,
			 t.rptDate

	-- + For Monthly - Macau Games
	INSERT INTO #tmpPayToSupplier_MTD(ProductId, MemberWLOANDA, PayToSupplier_PP_MTD)
	SELECT t.ProductID,
		   SUM(MemberWLOANDA),
		   SUM(t.MemberWLOANDA * (CASE WHEN BetType IN (4051,4052,4053,4054,4055) THEN 0.03 ELSE 0.02 END))
	FROM #tmpFactSiteWinloss AS t
	WHERE t.ProductID IN (22)
	GROUP BY t.ProductID

	-- END - Calculate PayToSupplier for GMT4 Product

	-- #FinalResult
	CREATE TABLE #FinalResult(
	    RptDate					VARCHAR(10)
	  , PayToSupplier_NG        MONEY
	  , PayToSupplier_H5        MONEY
	  , PayToSupplier_VS        MONEY
	  , PayToSupplier_RNGKeno   MONEY
	  , PayToSupplier_NG2       MONEY
	  , PayToSupplier_MacauG    MONEY
	  , PayToSupplier_LT        MONEY
	  , PayToSupplier_EX        MONEY
	  , PayToSupplier_VS2       MONEY
	  , PayToSupplier_1RNG      MONEY
	  , PayToSupplier_1RNG_JP   MONEY
	  , PayToSupplier_CC        MONEY
	  , PayToSupplier_SP        MONEY
	  , PayToSupplier_BBIN      MONEY
	  , PayToSupplier_TG        MONEY
	  , PayToSupplier_IBCLC     MONEY
	  , PayToSupplier_ION       MONEY
	  , PayToSupplier_RNGW      MONEY)

	DECLARE @tmpDate     DATE,
			@DateList    VARCHAR(200) = '[FullRange]'

    SELECT @tmpDate = @FDate

    WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult(RptDate
								 ,PayToSupplier_NG
								 ,PayToSupplier_H5   
								 ,PayToSupplier_VS
								 ,PayToSupplier_RNGKeno
								 ,PayToSupplier_NG2
								 ,PayToSupplier_MacauG
								 ,PayToSupplier_LT
								 ,PayToSupplier_EX
								 ,PayToSupplier_VS2
								 ,PayToSupplier_1RNG
								 ,PayToSupplier_1RNG_JP
								 ,PayToSupplier_CC
								 ,PayToSupplier_SP
								 ,PayToSupplier_BBIN
								 ,PayToSupplier_TG
								 ,PayToSupplier_IBCLC
								 ,PayToSupplier_ION
								 ,PayToSupplier_RNGW)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106)																										 AS RptDate
			   ,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 3 AND t.SportType <> 164 AND t.rptDate = @tmpDate) AS PayToSupplier_NG
	           ,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 3 AND t.SportType = 164 AND  t.rptDate = @tmpDate) AS PayToSupplier_H5
	           ,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 5 AND t.rptDate = @tmpDate)						 AS PayToSupplier_VS
	           ,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 8 AND t.rptDate = @tmpDate)						 AS PayToSupplier_RNGKeno
	           ,(SELECT SUM(t.HouseWL) * 0.5 * (-1) FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 23 AND t.rptDate = @tmpDate)						 AS PayToSupplier_NG2
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 22 AND t.rptDate = @tmpDate)					 AS PayToSupplier_MacauG
	           ,(SELECT SUM(t.MemberWLOANDA) * 0.03 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 28 AND t.rptDate = @tmpDate)						 AS PayToSupplier_LT
	           ,0																																		 AS PayToSupplier_EX
	           ,(SELECT SUM(t.MemberWLOANDA) * 0.01 FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 27 AND t.rptDate = @tmpDate)						 AS PayToSupplier_VS2
	           ,0																																		 AS PayToSupplier_1RNG
	           ,0																																		 AS PayToSupplier_1RNG_JP
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 34 AND t.rptDate = @tmpDate)					 AS PayToSupplier_CC
	           ,0																																		 AS PayToSupplier_SP
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 47 AND t.rptDate = @tmpDate)                    AS PayToSupplier_BBIN
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 40 AND t.rptDate = @tmpDate)                    AS PayToSupplier_TG
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 46 AND t.rptDate = @tmpDate)                    AS PayToSupplier_IBCLC
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 52 AND t.rptDate = @tmpDate)                    AS PayToSupplier_ION
	           ,(SELECT SUM(t.PayToSupplier_Daily) FROM #tmpPayToSupplier_Daily AS t WHERE t.ProductID = 50 AND t.rptDate = @tmpDate)                    AS PayToSupplier_RNGW

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult
	
	INSERT INTO #FinalResult(RptDate
							 ,PayToSupplier_NG
							 ,PayToSupplier_H5   
							 ,PayToSupplier_VS
							 ,PayToSupplier_RNGKeno
							 ,PayToSupplier_NG2
							 ,PayToSupplier_MacauG
							 ,PayToSupplier_LT
							 ,PayToSupplier_EX
							 ,PayToSupplier_VS2
							 ,PayToSupplier_1RNG
							 ,PayToSupplier_1RNG_JP
							 ,PayToSupplier_CC
							 ,PayToSupplier_SP
							 ,PayToSupplier_BBIN
							 ,PayToSupplier_TG
							 ,PayToSupplier_IBCLC
							 ,PayToSupplier_ION
							 ,PayToSupplier_RNGW)
	SELECT 'FullRange'																																	AS RptDate
	       ,SUM(PayToSupplier_NG)																														AS PayToSupplier_NG  
	       ,SUM(PayToSupplier_H5)																														AS PayToSupplier_H5
	       ,0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 5)		AS PayToSupplier_VS
	       ,0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 8)		AS PayToSupplier_RNGKeno
	       ,SUM(PayToSupplier_NG2)																														AS PayToSupplier_NG2
	       ,(SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(PayToSupplier_PP_MTD) END FROM #tmpPayToSupplier_MTD AS t WHERE t.ProductID = 22)	AS PayToSupplier_MacauG
	       ,0.03 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 28)	AS PayToSupplier_LT
	       ,0																																			AS PayToSupplier_EX
	       ,0.01 * (SELECT CASE WHEN SUM(MemberWLOANDA) > 0 THEN 0 ELSE SUM(MemberWLOANDA) END FROM #tmpFactSiteWinloss AS t WHERE t.ProductID = 27)    AS PayToSupplier_VS2     
	       ,0																																			AS PayToSupplier_1RNG
	       ,0																																			AS PayToSupplier_1RNG_JP
	       ,CASE WHEN SUM(PayToSupplier_CC) > 0 THEN 0 ELSE SUM(PayToSupplier_CC) END																    AS PayToSupplier_CC
	       ,0																																			AS PayToSupplier_SP
	       ,SUM(PayToSupplier_BBIN)																														AS PayToSupplier_BBIN
	       ,CASE WHEN SUM(PayToSupplier_TG) > 0 THEN 0 ELSE SUM(PayToSupplier_TG) END																	AS PayToSupplier_TG
	       ,SUM(PayToSupplier_IBCLC)																													AS PayToSupplier_IBCLC
	       ,SUM(PayToSupplier_ION)																														AS PayToSupplier_ION
	       ,CASE WHEN SUM(PayToSupplier_RNGW) > 0 THEN 0 ELSE SUM(PayToSupplier_RNGW) END																AS PayToSupplier_RNGW
	FROM #FinalResult

	-- BEGIN - Calculate PayToSupplier for the rest other Products

	-- + #tmpPayToSupplier_MetricGaming
    CREATE TABLE #tmpPayToSupplier_MetricGaming (RptDate VARCHAR(10), PayToSupplier_MG MONEY)
	INSERT INTO #tmpPayToSupplier_MetricGaming (rptDate, PayToSupplier_MG)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming @FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	
	-- + #tmpPayToSupplier_MuayThai
	CREATE TABLE #tmpPayToSupplier_MuayThai (RptDate VARCHAR(10), PayToSupplier_MT MONEY)
	INSERT INTO #tmpPayToSupplier_MuayThai (rptDate, PayToSupplier_MT)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMuayThai @FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	
	-- + #tmpPayToSupplier_BetBuilder
	CREATE TABLE #tmpPayToSupplier_BetBuilder (RptDate VARCHAR(10), PayToSupplier_BB MONEY)
	INSERT INTO #tmpPayToSupplier_BetBuilder (rptDate, PayToSupplier_BB)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder @FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site

	-- + #tmpPayToSupplier_GMT
	CREATE TABLE #tmpPayToSupplier_GMT(
		ProductCode			VARCHAR(10),
	    RptDate             VARCHAR(10),
		PayToSupplier		MONEY,
		CurrencyPlay		MONEY)
	
	INSERT INTO #tmpPayToSupplier_GMT(ProductCode, RptDate, PayToSupplier, CurrencyPlay)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier @FromDate = @FDate,
															   @ToDate = @TDate,
															   @ProductCodes = @ProductCodeGMT,
															   @DepositType = @DepositType,
															   @Site = @Site,
															   @IsOldView = 0

	-- END - Calculate PayToSupplier for the rest other Products

	-- BEGIN - Return data
	
    -- + List of Products that use GMT-4
    DECLARE @SQL_GMT4 VARCHAR(MAX)
    SELECT @SQL_GMT4 =
	'SELECT * ' + CHAR(13) 
    + 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) 
    + 'CROSS APPLY' + CHAR(13) + '(SELECT ''NG'', 1, ''PayToSupplier'', PayToSupplier_NG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''H5'', 2, ''PayToSupplier'', PayToSupplier_H5' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS'', 3, ''PayToSupplier'', PayToSupplier_VS' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''KN'', 4, ''PayToSupplier'', PayToSupplier_RNGKeno' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''NG2'', 5, ''PayToSupplier'', PayToSupplier_NG2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VB'', 6, ''PayToSupplier'', PayToSupplier_MacauG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''LT'', 7, ''PayToSupplier'', PayToSupplier_LT' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''EX'', 8, ''PayToSupplier'', PayToSupplier_EX' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''VS2'', 9, ''PayToSupplier'', PayToSupplier_VS2' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CS'', 10, ''PayToSupplier'', PayToSupplier_1RNG' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''JP'', 11, ''PayToSupplier'', PayToSupplier_1RNG_JP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''CC'', 12, ''PayToSupplier'', PayToSupplier_CC' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''NPH'', 13, ''PayToSupplier'', PayToSupplier_SP' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''BBIN'', 14, ''PayToSupplier'', PayToSupplier_BBIN' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''TG'', 15, ''PayToSupplier'', PayToSupplier_TG' + CHAR(13)
    + 'UNION ALL' + CHAR(13) + 'SELECT ''IBCLC'', 16, ''PayToSupplier'', PayToSupplier_IBCLC' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''ION'', 17, ''PayToSupplier'', PayToSupplier_ION' + CHAR(13)
	+ 'UNION ALL' + CHAR(13) + 'SELECT ''RNGW'', 18, ''PayToSupplier'', PayToSupplier_RNGW) c (ProductCode, [Order], Figure, value)) a' + CHAR(13)
    + 'PIVOT' + CHAR(13) 
    + '(' + CHAR(13) 
    + 'MAX(value)' + CHAR(13) 
    + 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
    + ') piv' + CHAR(13)
	
	-- + List of exception Products
	DECLARE @SQL_MetricGaming   VARCHAR(MAX),
			@SQL_MuayThai    	VARCHAR(MAX),
			@SQL_BetBuilder		VARCHAR(MAX)

    SELECT @SQL_MetricGaming =
		'SELECT * ' + CHAR(13) 
		+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MetricGaming' + CHAR(13) 
		+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 100, ''PayToSupplier'', PayToSupplier_MG) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
		+ 'PIVOT' + CHAR(13) 
		+ '(' + CHAR(13) 
		+ 'MAX(value)' + CHAR(13) 
		+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
		+ ') piv' + CHAR(13)
	
	SELECT @SQL_MuayThai =
		'SELECT * ' + CHAR(13) 
		+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_MuayThai' + CHAR(13) 
		+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''OS'', 101, ''PayToSupplier'', PayToSupplier_MT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
		+ 'PIVOT' + CHAR(13) 
		+ '(' + CHAR(13) 
		+ 'MAX(value)' + CHAR(13) 
		+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
		+ ') piv' + CHAR(13)
	
	SELECT @SQL_BetBuilder =
		'SELECT * ' + CHAR(13) 
		+ 'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #tmpPayToSupplier_BetBuilder' + CHAR(13) 
		+ 'CROSS APPLY' + CHAR(13) + '(SELECT ''Soccer'', 102, ''PayToSupplier'', PayToSupplier_BB) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) 
		+ 'PIVOT' + CHAR(13) 
		+ '(' + CHAR(13) 
		+ 'MAX(value)' + CHAR(13) 
		+ 'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) 
		+ ') piv' + CHAR(13)
	
	-- + List of Products that use GMT+8 and GMT0
	DECLARE @SQL_GMT VARCHAR(MAX)
	SELECT @SQL_GMT = 
	'
	;WITH
	CTE_UnionAll AS (
		SELECT ProductCode, RptDate, ''PayToSupplier'' Figure, PayToSupplier value FROM #tmpPayToSupplier_GMT
		UNION ALL
		SELECT ProductCode, RptDate, ''CurrencyPlay'' Figure, CurrencyPlay value FROM #tmpPayToSupplier_GMT WHERE ProductCode = ''AB''
	),
	CTE_Pivot AS (
		SELECT ProductCode, Figure, ' + @DateList + ' FROM
		(
			SELECT ProductCode, RptDate, Figure, value FROM CTE_UnionAll
		) tab1
		PIVOT
		(
			MAX(value)
			FOR RptDate IN (' + @DateList + ')
		) tab2
	)
	SELECT ProductCode,
		   (200 + ROW_NUMBER() OVER(ORDER BY ProductCode)) [Order],
		   Figure,
		   ' + @DateList + '
	FROM CTE_Pivot
	'
	
	-- + Execute query
	--   * Normal
	EXEC (@SQL_MetricGaming + ' UNION ALL '
		  + @SQL_MuayThai + ' UNION ALL '
		  + @SQL_BetBuilder + ' UNION ALL '
		  + @SQL_GMT4)
	--   * GMT8 and GMT0
	EXEC (@SQL_GMT)
	--   * GD
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_GD_PayToSupplier @FromDate = @FDate, @ToDate = @TDate, @DepositType = @DepositType, @Site = @Site
	
	-- END - Return data
	
	-- Drop temp tables
    DROP TABLE #SportBettypeMatrix
    DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #tmpProduct
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #tmpSite
    DROP TABLE #FinalResult
    DROP TABLE #tmpFactSiteWinloss
	DROP TABLE #tmpPayToSupplier_Daily
	DROP TABLE #tmpPayToSupplier_MTD
	DROP TABLE #tmpPayToSupplier_MetricGaming
	DROP TABLE #tmpPayToSupplier_MuayThai
	DROP TABLE #tmpPayToSupplier_BetBuilder
	DROP TABLE #tmpPayToSupplier_GMT

END
GO

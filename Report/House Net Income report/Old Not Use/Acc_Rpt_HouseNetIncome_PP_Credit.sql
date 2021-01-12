/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PP_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS

/*  	
	Created:	20180612@Harper  
    Task :		House month-to-date Net Income report for Pramatic product
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20180618@Harper - HDWL Letstalk - Implement report for Pramatic product [#RedmineID: 94403]
		- 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
		- 20191121@Robert: #123733 - Email/Letstalk Reports - Integrate PP Tournament (Exclude bettype 4299)
		- 20200529@Ned.Le: House Net Income Email/Letstalk - Change timezone to calculate monthly Pay To Supplier (#134867)
		- 20200714@Ned.Le: Email/Letstalk Reports - Integrate Jackpot Games (#137280)
						   * Remove the hardcoding of bettype=4299|4300 (FACT table already care about these bettypes)
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_PP_Credit '20180601', '20180619'   
*/

BEGIN

	SET NOCOUNT ON  

	-- Declare variables
    DECLARE @FDate    DATE,
			@TDate    DATE

    SELECT @FDate = @FromDate,
		   @TDate = @ToDate

	DECLARE @tmpDate     DATE,
			@DateList    VARCHAR(200) = '[FullRange]'

    SELECT @tmpDate = @FDate

	DECLARE @ProductID INT = 32,
			@ProductPrefix VARCHAR(5) = 'PP'
	
	-- #Exchange
    CREATE TABLE #Exchange (ExchangeDate    DATE,
						    ExchangeID      INT,
						    Rate            FLOAT)

    INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID)

	-- #FinalResult
    CREATE TABLE #FinalResult (RptDate          VARCHAR(10),
							   HouseWL          MONEY,
							   ExtraPT          MONEY,
							   PayToSupplier    MONEY)
    
    WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult
	
	-- #SportBettypeMatrix
    CREATE TABLE #SportBettypeMatrix (ProductID     INT,
									  Bettype       INT,
									  EventType     INT,
									  SubProduct    VARCHAR(500))

    INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(@ProductID, 0, 0, 2, '', @ProductPrefix, 0)
	
	-- #TmpHouseWL
    CREATE TABLE #TmpHouseWL(rptDate          DATE,
							 HouseWL          MONEY,
							 ExtraPT          MONEY)

    INSERT INTO #TmpHouseWL (rptDate, HouseWL, ExtraPT)
	SELECT b.rptDate,
		  -SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL,
		  SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
		 LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		  AND b.BetType IN (SELECT Bettype FROM #SportBettypeMatrix)
		  AND b.SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0)
	GROUP BY b.rptDate
	OPTION(RECOMPILE)

	-- BEGIN - Calcualting for #FinalResult

	-- + Update HouseWL and ExtraPT for each day
	UPDATE f
	SET f.HouseWL = f.HouseWL + wl.HouseWL,
		f.ExtraPT = f.ExtraPT + wl.ExtraPT
	FROM #FinalResult f
		 INNER JOIN #TmpHouseWL wl ON f.RptDate = CONVERT(VARCHAR(2), wl.rptDate, 106)

	-- + Calculate FullRange for HouseWL and ExtraPT
    INSERT INTO #FinalResult(RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange' RptDate,
		   SUM(f.HouseWL) HouseWL,
		   SUM(f.ExtraPT) ExtraPT,
		   0 PayToSupplier
	FROM #FinalResult AS f

	-- + Calculate PayToSupplier
	CREATE TABLE #PayToSupplier (ProductCode VARCHAR(10), rptDate VARCHAR(10), PayToSupplier MONEY, CurrencyPlay MONEY)
	INSERT INTO #PayToSupplier (ProductCode, rptDate, PayToSupplier, CurrencyPlay)
	EXEC DBEXT.bodb02.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier @FromDate = @FDate,
															   @ToDate = @TDate,
															   @ProductCodes = @ProductPrefix,
															   @DepositType = 0,
															   @Site = '',
															   @IsOldView = 0

	UPDATE f
	SET f.PayToSupplier = f.PayToSupplier + p.PayToSupplier
	FROM #FinalResult f
		 INNER JOIN #PayToSupplier p ON f.rptDate = p.rptDate

    -- END - Calcualting #FinalResult
	
	-- Return data
	DECLARE @SQL VARCHAR(1000)

	SELECT @SQL =
		   'SELECT * ' + CHAR(13) +
		   'FROM (SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
		   'CROSS APPLY' + CHAR(13) +
		   '(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', HouseWL' + CHAR(13) +
		   'UNION ALL' + CHAR(13) +
		   'SELECT ''' + @ProductPrefix + ''', 2, ''Extra PT'', ExtraPT' + CHAR(13) +							
		   'UNION ALL' + CHAR(13) +
		   'SELECT ''' + @ProductPrefix + ''', 3, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
		   'PIVOT' + CHAR(13) +
		   '(' + CHAR(13) +
		   'MAX(value)' + CHAR(13) +
		   'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
		   ') piv' + CHAR(13) +
		   'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop temp tables
	DROP TABLE #Exchange
	DROP TABLE #FinalResult
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #PayToSupplier

END
GO

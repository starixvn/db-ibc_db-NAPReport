/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

CREATE PROCEDURE dbo.Acc_Rpt_HouseNetIncome_VS3_Credit
	@FromDate DATE,
	@ToDate	DATE
AS
  
/*
	Created:	20201201@Ned.Le
    Task :		Get data of VS3 product for HNI report
    DB:			DBWH/bodb_dwrs
   
    Revisions:
		20201201@Ned.Le: Email/Letstalk Reports - Integrate Leap Gaming Virtual Sports (#131369)

	Param's Explanation:   

	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_VS3_Credit '20201101', '20201130'
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

	DECLARE @ProductID INT = 49,
			@ProductPrefix VARCHAR(5) = 'VS3'

	DECLARE @OpenQuery VARCHAR(MAX)
	DECLARE @SQL VARCHAR(MAX)
	
	-- #Exchange
    CREATE TABLE #Exchange (ExchangeDate    DATE,
						    ExchangeID      INT,
						    Rate            FLOAT)

    INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily (NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID)

	-- #ExchangeOANDA
	CREATE TABLE #ExchangeOANDA (ExchangeDate    DATE,
								 ExchangeID      INT,
								 Rate            FLOAT)
    
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

	-- #tmpVendorGlobalSetting & #ChargeInfo3rd
	CREATE TABLE #tmpProduct (ProductID INT,
		                      ProductCode VARCHAR(100),
							  VendorID INT)

	INSERT INTO #tmpProduct (ProductID, ProductCode, VendorID)
	SELECT ProductID, ProductPrefix, VendorID
	FROM bodb02.dbo.Products (NOLOCK)
	WHERE ProductPrefix = @ProductPrefix

	CREATE TABLE #tmpVendorGlobalSetting (ProductID INT,
	                                      VName VARCHAR(50),
										  ChargeRate3rd DECIMAL(19, 8),
										  Sporttype SMALLINT,
										  Bettype SMALLINT)
	
	INSERT INTO #tmpVendorGlobalSetting (ProductID, VName, ChargeRate3rd, Sporttype, Bettype)
	SELECT p.ProductID,
	       [VName],
		   [NumberValue],
		   [sporttype],
		   [bettype]
	FROM DBCUST.[CustDB].[dbo].[VendorGlobalSetting] v WITH(NOLOCK)
	     INNER JOIN #tmpProduct p ON v.[VendorId] = p.VendorID
	WHERE v.[VName] IN ('3rdCreditWLShareRate')

    CREATE TABLE #ChargeInfo3rd (ProductID         INT,
								 Rate              MONEY,
								 FromDate          SMALLDATETIME,
								 ToDate            SMALLDATETIME,
								 MinAmount         MONEY,
								 MaxAmount         MONEY,
								 BaseCurrencyId    INT)

	SELECT @OpenQuery = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N','''''+ @ProductPrefix + ''''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
    INSERT INTO #ChargeInfo3rd (ProductID, Rate, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId)
    EXECUTE (@OpenQuery)
	
	INSERT INTO #ChargeInfo3rd (ProductID, Rate, FromDate, ToDate)
	SELECT v.ProductID, v.ChargeRate3rd, @FDate, @TDate
	FROM #tmpVendorGlobalSetting v
	WHERE v.ProductID NOT IN (SELECT ProductID FROM #ChargeInfo3rd)
	      AND v.VName = '3rdCreditWLShareRate'

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
							 ExtraPT          MONEY,
							 MemberWLOANDA	  MONEY)

    INSERT INTO #TmpHouseWL (rptDate, HouseWL, ExtraPT, MemberWLOANDA)
	SELECT b.rptDate,
		   -SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL,
		   SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT,
		   SUM(b.WinlossP * ISNULL(e.Rate,0)) AS MemberWLOANDA
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
		 LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		 LEFT JOIN #ExchangeOANDA e ON e.ExchangeDate = b.RptDate AND e.ExchangeID = b.CurrencyID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		  AND b.BetType IN (SELECT Bettype FROM #SportBettypeMatrix)
		  AND b.SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0)
	GROUP BY b.rptDate
	OPTION(RECOMPILE)

	-- BEGIN - Calcualting for #FinalResult

	-- + Update data for each day
	;WITH CTE_tmpHouseWL AS (
		SELECT CONVERT(VARCHAR(2), wl.rptDate, 106) rptDate,
			   SUM(wl.HouseWL) HouseWL,
			   SUM(wl.ExtraPT) ExtraPT,
			   SUM(wl.MemberWLOANDA * ci.Rate) AS PayToSupplier
		FROM #TmpHouseWL wl
			 INNER JOIN #ChargeInfo3rd ci ON wl.rptDate BETWEEN ci.FromDate AND ci.ToDate
	    GROUP BY CONVERT(VARCHAR(2), wl.rptDate, 106)
	)
	UPDATE f
	SET f.HouseWL = f.HouseWL + wl.HouseWL,
		f.ExtraPT = f.ExtraPT + wl.ExtraPT,
		f.PayToSupplier = f.PayToSupplier + wl.PayToSupplier
	FROM #FinalResult f
		 INNER JOIN CTE_tmpHouseWL wl ON f.RptDate = CONVERT(VARCHAR(2), wl.rptDate, 106)

	-- + Calculate data for FullRange
    INSERT INTO #FinalResult(RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange' RptDate,
		   SUM(f.HouseWL) HouseWL,
		   SUM(f.ExtraPT) ExtraPT,
		   SUM(f.PayToSupplier) PayToSupplier
	FROM #FinalResult AS f

	-- Return data
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''' + @ProductPrefix + ''', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 2, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''' + @ProductPrefix + ''', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #tmpProduct
	DROP TABLE #tmpVendorGlobalSetting
	DROP TABLE #ChargeInfo3rd
	DROP TABLE #FinalResult
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL

END

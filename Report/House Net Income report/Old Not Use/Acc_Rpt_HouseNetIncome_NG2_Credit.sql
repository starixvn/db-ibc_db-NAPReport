/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_NG2_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS
/*  Created: 20161221@Harper
    Task : House month-to-date Net Income report for Number Game 2 product
    DB: DBWH/bodb_dwrs
   
    Revisions:
		20201002@Ned.Le: Email/Letstalk Reports - Change Card Club into Arcadia Gaming (#142831)
		20201023@Roy: HNI Email/Letstalk - Adjust royalty fee term for RNG Keno, Lottery, Table Game, Number Game, NG2, Happy 5 (#143589)

	Param's Explanation:
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @ProductPrefix VARCHAR(5) = 'NG2'
	DECLARE @ProductID INT = 23
	
	-- #Exchange
	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT,Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate	

	-- #FinalResult
	CREATE TABLE #FinalResult (
		RptDate			VARCHAR(10),
		HouseWL			MONEY,
		ExtraPT			MONEY,
		PayToSupplier	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- #SportBettypeMatrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(@ProductID, 0, 0, 2, '', @ProductPrefix, 0)

	-- #TmpHouseWL
	CREATE TABLE #TmpHouseWL(
		rptDate DATE,
		HouseWL MONEY,
		ExtraPT MONEY
	)

	INSERT INTO #TmpHouseWL(
		rptDate,
		HouseWL,
		ExtraPT
	)
	SELECT b.rptDate,
		   -SUM((b.WinlossIBC + b.CommissionS) * ISNULL(ex.rate,0)) AS HouseWL,
		   SUM((b.ExtraWL + b.ExtraComm) * ISNULL(ex.rate,0)) AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
		 LEFT JOIN #Exchange AS ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		  AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
		  AND b.BetType IN (SELECT Bettype FROM #SportBettypeMatrix )
		  AND b.SiteID IN (SELECT SiteID FROM bodb_account.dbo.tbl_site WITH(NOLOCK) WHERE isDeposit = 0)
	GROUP BY b.rptDate
	OPTION(RECOMPILE)
	
	-- Update data for #FinalResult
	UPDATE f
	SET f.HouseWL = f.HouseWL + wl.HouseWL,
		f.ExtraPT = f.ExtraPT + wl.ExtraPT
	FROM #FinalResult f
		 INNER JOIN #TmpHouseWL wl ON f.RptDate = CONVERT(VARCHAR(2), wl.rptDate, 106)

	UPDATE f
	SET f.PayToSupplier = (wl.HouseWL + (CASE WHEN wl.rptDate >= '2020-11-01' THEN 0 ELSE wl.ExtraPT END) ) * (-0.5)
	FROM #FinalResult f
		 INNER JOIN #TmpHouseWL wl ON f.RptDate = CONVERT(VARCHAR(2), wl.rptDate, 106)

	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange', SUM(HouseWL), SUM(ExtraPT), SUM(PayToSupplier)
	FROM #FinalResult	
	
	-- Output data
	DECLARE @SQL VARCHAR(1000)
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
	DROP TABLE #FinalResult
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL

END
GO

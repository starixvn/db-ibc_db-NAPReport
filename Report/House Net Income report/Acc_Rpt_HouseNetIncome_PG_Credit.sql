/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PG_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Created: 20180829@Harper 
    Task : House month-to-date Net Income report for Pocker Games product
    DB: DBWH/bodb_dwrs  
   
    Revisions: 
		- 20180829@Harper: Implement new product Pocker Games [RedmineID: #100426]

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_PG_Credit '2018-07-01', '2018-07-31'
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	
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
	-- End region

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

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(33,0,0,2,'','PG',0)
	
	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, ExtraPT MONEY, PartnerFee MONEY)

	INSERT INTO #TmpHouseWL (rptDate, HouseWL, ExtraPT, PartnerFee)
	SELECT 
		b.rptDate,
		-SUM((b.WinlossIBC + commissionS) * ex.rate) HouseWL,
		SUM((b.ExtraWL + b.ExtraComm) * ex.Rate)  AS ExtraPT,
		-SUM(b.PartnerFee * oanda.Rate) AS PartnerFee
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		INNER JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
	GROUP BY b.rptDate
	OPTION (RECOMPILE)
	
	UPDATE f
	SET HouseWL = f.HouseWL + ISNULL(wl.HouseWL, 0),		
		ExtraPT = f.ExtraPT + ISNULL(wl.ExtraPT, 0),
		PayToSupplier = f.PayToSupplier + ISNULL(wl.PartnerFee, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange', SUM(HouseWL), SUM(ExtraPT), SUM(PayToSupplier)
	FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''PG'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''PG'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''PG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_PG_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_PG_Credit] TO [vnteam]
GO
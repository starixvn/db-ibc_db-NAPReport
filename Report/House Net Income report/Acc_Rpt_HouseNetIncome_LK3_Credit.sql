/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_LK3_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Created: 20170905@Harper 
    Task : House month-to-date Net Income report for Lucky 3 product
    DB: DBWH/bodb_dwrs  
   
    Revisions: 
		- 20170905@Harper: Implement new product LK3 [RedmineID: #79612]

	Param's Explanation:   
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			Rate			FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate	

	-- End region

	CREATE TABLE #FinalResult (
		RptDate			VARCHAR(10),
		HouseWL			MONEY,		
		PayToSupplier	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(26,0,0,2,'','LK3',0)
	
	-- House WL
	CREATE TABLE #TmpHouseWLLK3 (rptDate DATE, HouseWL MONEY)
	INSERT INTO #TmpHouseWLLK3 (rptDate, HouseWL)
	SELECT 
		b.rptDate,
		ISNULL(-SUM((winlossP+winlossS+winlossM+winlossA+commissionS)*ex.rate),0) HouseWL
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON s.siteid = b.SiteID
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND s.isDeposit = 0 -- Credit data only
		AND Sb.ProductID = 26
		AND b.status <> 14
	GROUP BY b.rptDate
	OPTION (RECOMPILE)

	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL
	FROM #FinalResult f
		INNER JOIN #TmpHouseWLLK3 wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	UPDATE f
	SET f.PayToSupplier = wl.HouseWL * (-0.4)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWLLK3 wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	-- FullRange Amount
	INSERT INTO #FinalResult (RptDate, HouseWL, PayToSupplier)
	SELECT 'FullRange', SUM(HouseWL), SUM(PayToSupplier)
	FROM #FinalResult	
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''LK3'', 1, ''House Income'', HouseWL' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''LK3'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWLLK3
	DROP TABLE #Exchange
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_LK3_Credit] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_LK3_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_LK3_Credit] TO [vnteam]
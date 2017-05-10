USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Macau_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20170213@Harper  
    Task :		House month-to-date Net Income report for Macau
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_VG_Credit '20161201', '20161230' 
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

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
		RptDate		VARCHAR(10),
		HouseWL		MONEY,
		ExtraPT		MONEY,
		PayToSupplier MONEY
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
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(3,0,0,2,'','VG',0)

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.extraWinloss) AS ExtraPT
		FROM bodb_account.dbo.rptGroupWinloss b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 14 --VG in Products table
				AND b.statusid <> 14
		GROUP BY b.rptDate
	)
	UPDATE f
	SET ExtraPT = e.ExtraPT
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, MemberWLOANDA MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, MemberWLOANDA)
	SELECT 
		b.rptDate,
		ISNULL(-SUM((winlossP+winlossS+winlossM+winlossA+commissionS)*ex.rate),0) HouseWL,
		SUM(ISNULL(b.WinlossP, 0) * oa.Rate) AS MemberWLOANDA
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		INNER JOIN #ExchangeOANDA oa ON b.rptDate = oa.ExchangeDate AND b.CurrencyID = oa.ExchangeID
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON s.siteid = b.SiteID
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND s.isDeposit = 0 -- Credit data only
		AND Sb.ProductID = 14 -- VG in Products table
		AND b.status <> 14
	GROUP BY b.rptDate
	OPTION (RECOMPILE)

	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange', SUM(HouseWL), SUM(ExtraPT), 0
	FROM #FinalResult

	DECLARE @SumPayToSupplier MONEY
	SELECT @SumPayToSupplier = SUM(MemberWLOANDA) FROM #TmpHouseWL

	UPDATE #FinalResult 
	SET PayToSupplier = 0.02 * (CASE WHEN @SumPayToSupplier > 0 THEN 0 ELSE @SumPayToSupplier END)

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''VG'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VG'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VG'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_VG_Credit] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_VG_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_VG_Credit] TO vnteam
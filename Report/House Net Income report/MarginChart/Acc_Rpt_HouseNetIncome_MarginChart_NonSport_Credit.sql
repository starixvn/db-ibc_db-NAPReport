/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:				DBWH/bodb_dwrs  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit '2018-05-01', '2018-05-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE CLUSTERED INDEX [PK_tmp_CurrencyDaily] ON #Exchange( ExchangeDate, ExchangeID )

	IF OBJECT_ID('TempDB..##ExchangeOANDA','U') IS NOT NULL
		DROP TABLE ##ExchangeOANDA

	DECLARE @OpenQuery NVARCHAR(1000)
	SELECT @OpenQuery = N'SELECT * ' 
						+ N'INTO ##ExchangeOANDA '
						+ N'FROM OPENQUERY(DBEXT, '
						+ N'''SELECT ExchangeDate, ExchangeID, BaseCurrencyRate '
						+ N'FROM bodb02.dbo.LA_f_ExchangeDailySel('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''MYR'''''			
						+ N')'')'
					
	EXECUTE (@OpenQuery)
	-- End region

	CREATE TABLE #FinalResult (
		RptDate		VARCHAR(10),
		HouseWL		MONEY,
		ExtraPT		MONEY,
		PayToSupplier MONEY,
		TurnOver	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- KN + LT + MacauGame + VS + VS2: with Exchange Oanda Rate
	CREATE TABLE #PayToSupplierRate (ProductID INT, Rate MONEY)

	INSERT INTO #PayToSupplierRate( ProductID, Rate )
	VALUES  (8, 0.03), (28, 0.03), (22, 0.02), (5, 0.01), (27, 0.01)
			, (3, 0.4), (23, 0.5)

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0,0,0,2,'','KN,LT,VB,VS,VS2,NG,CS,NG2,AB,FW,GD,LK3',0)
	
	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, ProductID INT, CurrencyID INT, HouseWL MONEY, MemberWL MONEY, MemberWLReal MONEY, MemberWLOANDA MONEY, PayToSupplier MONEY, TurnOver MONEY, ExtraPT MONEY)
	
	INSERT INTO #TmpHouseWL (rptDate, ProductID, CurrencyID, HouseWL, MemberWL, MemberWLReal, TurnOver, ExtraPT)
	SELECT 
		b.rptDate,
		sb.ProductID,
		b.CurrencyID,
		-SUM((b.WinlossIBC + b.CommissionS) * ex.rate) HouseWL,
		SUM(b.WinlossP) AS MemberWL,
		SUM(b.WinlossP * ex.Rate) AS MemberWLReal,		
		SUM((CASE WHEN TurnoverIBC = 0 THEN 0  ELSE TurnoverIBC - ExtraTO END ) * ( CASE WHEN VarianceVR > 0 THEN( VarianceVR + 1 ) ELSE 1 END ) * ex.Rate) AS TurnOver,
		SUM((b.ExtraWL + b.ExtraComm) * ex.Rate) AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
	GROUP BY b.rptDate, sb.ProductID, b.CurrencyID
	OPTION (RECOMPILE)
	
	-- OANDA Rate: KN + LT + MacauGame + VS + VS2
	UPDATE b
	SET b.PayToSupplier = b.MemberWL * r.Rate * oanda.BaseCurrencyRate
	FROM #TmpHouseWL b
		INNER JOIN ##ExchangeOANDA oanda ON b.rptDate = oanda.ExchangeDate AND b.CurrencyId = oanda.ExchangeID
		INNER JOIN #PayToSupplierRate r ON b.ProductID = r.ProductID
	WHERE b.ProductID IN (5, 8, 22, 27, 28) -- Need caculate based on oanda rate

	-- NG, NG2
	UPDATE b
	SET b.PayToSupplier = - (b.HouseWL + ExtraPT) * r.Rate
	FROM #TmpHouseWL b		
		INNER JOIN #PayToSupplierRate r ON b.ProductID = r.ProductID
	WHERE b.ProductID IN (3, 23)

	-- Final Return
	;WITH totalcte AS (
						SELECT rptDate
							, SUM(HouseWL) AS HouseWL, SUM(ExtraPT) AS ExtraPT
							, SUM(TurnOver) AS TurnOver, SUM(PayToSupplier) AS PayToSupplier
						FROM #TmpHouseWL
						GROUP BY rptDate
					)
	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL,
		ExtraPT = f.ExtraPT + wl.ExtraPT,
		TurnOver = f.TurnOver + wl.TurnOver,
		PayToSupplier = f.PayToSupplier + wl.PayToSupplier
	FROM #FinalResult f
		INNER JOIN totalcte wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate
			
	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
	SELECT 'FullRange', 0, 0, 0, 0	

	DROP TABLE ##ExchangeOANDA

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
							'SELECT ''NonSport'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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

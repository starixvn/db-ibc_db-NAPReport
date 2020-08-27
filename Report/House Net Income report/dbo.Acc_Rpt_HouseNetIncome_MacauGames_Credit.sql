/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MacauGames_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20170213@Harper  
    Task :		House month-to-date Net Income report for Macau Game
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
	
	Param's Explanation:
	- 20200408@Kean - Add 12 New Slot Games for Macau Game - (#131755)
	- 20200827@Kean - Email/Letstalk Reports - Integrate 10 New BluePrint Games (#140459)  

	EXEC Acc_Rpt_HouseNetIncome_VB_Credit '20161201', '20161230' 
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

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(22,0,0,2,'','VB',0)

	-- House WL
	-- BEGIN: GET DATA
	CREATE TABLE #TmpHouseWL(
		rptDate      DATE
		, BetType    INT
		, HouseWL      MONEY
		, ExtraPT    MONEY
		, MemberWLOANDA MONEY);
	INSERT INTO #TmpHouseWL(rptDate
				   , BetType
				   , HouseWL
				   , ExtraPT
				   , MemberWLOANDA)
		 SELECT b.rptDate
			 ,  b.BetType
			 , ISNULL(-SUM((winlossP + winlossS + winlossM + winlossA + commissionS) * ex.rate), 0) AS HouseWL
			 , ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.rate), 0) AS ExtraPT
			 , ISNULL(SUM(b.WinlossP * oanda.Rate), 0) AS  MemberWLOANDA
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH(NOLOCK)
			INNER JOIN bodb_Account.dbo.tbl_Site AS s WITH (NOLOCK) ON s.siteid = b.SiteID
			LEFT JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
								    AND b.currencyid = ex.ExchangeID
			LEFT JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDATE
			  AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
			  AND b.CurrencyID <> 20
			  AND s.isDeposit = 0 /* Credit data only*/
			  AND b.bettype IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 22 )  
		 GROUP BY b.rptDate
				, b.BetType OPTION(RECOMPILE);
	
	CREATE TABLE #tmpPayToSupplier_Daily(
	    RptDate						DATE
		, PayToSupplier_Daily        MONEY);
	CREATE TABLE #tmpPayToSupplier_MTD(
		MemberWLOANDA				MONEY,
		PayToSupplier_PP_MTD        MONEY);

	INSERT INTO #tmpPayToSupplier_Daily(RptDate, PayToSupplier_Daily)
	SELECT rptDate, SUM(MemberWLOANDA * (CASE WHEN bg.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END))
	FROM #TmpHouseWL t
	LEFT JOIN bodb_Account.dbo.BettypeGroup bg (NOLOCK) ON t.BetType = bg.Bettype AND bg.BettypeGroupID = 11
	GROUP BY rptDate

	INSERT INTO #tmpPayToSupplier_MTD(MemberWLOANDA, PayToSupplier_PP_MTD)
	SELECT SUM(MemberWLOANDA), SUM(MemberWLOANDA * (CASE WHEN bg.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END))
	FROM #TmpHouseWL t
	LEFT JOIN bodb_Account.dbo.BettypeGroup bg (NOLOCK) ON t.BetType = bg.Bettype AND bg.BettypeGroupID = 11
	
	SELECT @tmpDate = @FDate;
    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , (SELECT SUM(t.HouseWL) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  HouseWL
				    , (SELECT SUM(t.ExtraPT) FROM #TmpHouseWL AS t WHERE t.rptDate = @tmpDate) AS  ExtraPT
				    , (SELECT ISNULL(SUM(PayToSupplier_Daily),0) FROM #tmpPayToSupplier_Daily AS t WHERE t.rptDate = @tmpDate);

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
	
	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier)
	SELECT 'FullRange'
	, SUM(HouseWL)
	, SUM(ExtraPT)
	, (SELECT SUM(PayToSupplier_PP_MTD) FROM #tmpPayToSupplier_MTD)
	FROM #FinalResult	

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''VB'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VB'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''VB'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #tmpPayToSupplier_Daily
	DROP TABLE #tmpPayToSupplier_MTD
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
END
GO
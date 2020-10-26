/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs,bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_KN_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Created: Victor  
	Date: 2016-08-08  
    Task : House month-to-date Net Income report
    DB: DBWH/bodb_dwrs  
   
    Revisions: 
		- 20160916@Harper - #64211 - Caculate value for PayToSupplier for Credit
		- 20160922@Harper - #64429 - Edit status ID
		- 20160923@Harper - #64582, #64799 - PayToSupplier should use ExchangeOANDA
		- 20200225@Kean: #128007 - Changes on the rate of Pay to suppliers
		- 20201023@Roy: #143589 - HNI Email/Letstalk - Adjust royalty fee term for RNG Keno, Lottery, Table Game, Number Game, NG2, Happy 5
	Param's Explanation:   
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @SiteCN88    INT;

	SELECT TOP 1 @SiteCN88 = SiteId
	FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	WHERE [site] = 'CN88';
	
	-- Region: Get exchange rate info
	CREATE TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

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
		RptDate			VARCHAR(10),
		HouseWL			MONEY,
		ExtraPT			MONEY,
		PayToSupplier	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(8,0,0,2,'','KN',0)

	CREATE TABLE #RawData(
	    SiteId     INT
	  , RptDate    DATE
	  , MemberWLOANDA   MONEY
	  , ExtraPT    MONEY
	  , HouseWL    MONEY);

    INSERT INTO #RawData(SiteId
				   , rptDate
				   , MemberWLOANDA
				   , ExtraPT
				   , HouseWL)
		 SELECT b.SiteID
			 , b.rptDate
			 , ISNULL(SUM((winlossP) * oanda.rate),0) MemberWLOANDA
			 , ISNULL(SUM((b.ExtraWL + b.ExtraComm) * ex.rate), 0) AS                                  ExtraPT
			 , ISNULL(-SUM((winlossP + winlossS + winlossM + winlossA + commissionS) * ex.rate), 0) AS HouseWL
		 FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									AND b.currencyid = ex.ExchangeID
			INNER JOIN #ExchangeOANDA oanda ON b.rptdate = oanda.exchangedate AND b.currencyid = oanda.ExchangeID
			INNER JOIN bodb_Account.dbo.tbl_Site AS s WITH (NOLOCK) ON s.siteid = b.SiteID
		 WHERE b.rptDate >= @FDate AND b.rptDate <= @TDate 
				AND s.isDeposit = 0 -- Credit data only
				AND b.bettype IN (SELECT sb.Bettype FROM #SportBettypeMatrix sb WHERE sb.ProductID = 8 )
				AND b.TicketStatus <> 14
		 GROUP BY b.SiteID
			   , b.rptDate OPTION(RECOMPILE);

    CREATE NONCLUSTERED INDEX IX_RawData ON #RawData(SiteId, rptDate);
	
	SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , (SELECT SUM(t.HouseWL) FROM #RawData AS t WHERE t.rptDate = @tmpDate) AS  HouseWL
				    , (SELECT SUM(t.ExtraPT) FROM #RawData AS t WHERE t.rptDate = @tmpDate) AS  ExtraPT
				    , (SELECT ISNULL(SUM(MemberWLOANDA) * (CASE WHEN @tmpDate >= '2020-07-01' THEN 0.036 ELSE 0.03 END),0) FROM #RawData AS t WHERE t.rptDate = @tmpDate AND t.SiteId <> @SiteCN88)
					+ (SELECT ISNULL(SUM(MemberWLOANDA) * 0.015,0) FROM #RawData AS t WHERE t.rptDate = @tmpDate AND t.SiteId =  @SiteCN88);

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;

	INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, PayToSupplier)
		SELECT 'FullRange'
			, SUM(HouseWL) AS  HouseWL
			, SUM(ExtraPT) AS  ExtraPT
			, SUM(PayToSupplier) AS PayToSupplier
		FROM #FinalResult;

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''KN'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''KN'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''KN'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #RawData
END
GO
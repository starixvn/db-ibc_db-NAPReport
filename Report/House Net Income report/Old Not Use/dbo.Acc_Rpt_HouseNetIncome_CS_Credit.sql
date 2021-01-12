/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CS_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Created: Victor  
	Date: 2016-08-08  
    Task : House month-to-date Net Income report
    DB: DBWH/bodb_dwrs  
   
    Revisions:		
		- 20180619@Harper: Update formula for RNG to remove data of JP [RedmineID: #94403]

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

	CREATE CLUSTERED INDEX [PK_tmp_CurrencyDaily] ON #Exchange( ExchangeDate, ExchangeID )
	-- End region

	CREATE TABLE #FinalResult (
		RptDate		VARCHAR(10),
		HouseWL		MONEY,
		ExtraPT		MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(6,0,0,2,'','CS',0)
	
	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, ExtraPT MONEY, DiffContribution DECIMAL(19, 8))

	INSERT INTO #TmpHouseWL (rptDate, HouseWL, ExtraPT)
	SELECT 
		b.rptDate,
		-SUM((b.WinlossIBC + commissionS) * ex.rate) HouseWL,
		SUM((b.ExtraWL + b.ExtraComm) * ex.Rate)  AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
	GROUP BY b.rptDate
	OPTION (RECOMPILE)

	-- Caculate the diffence value for Jackpot Contribution for Deposit site
	--INSERT INTO #TmpHouseWL (rptDate, DiffContribution)
	--SELECT 
	--	b.rptDate,
	--	SUM((b.WinlossIBC - b.WinlossS - b.WinlossM)* ex.Rate)	-- ContributionRate * betStake + awinlost
	--FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
	--	INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
	--WHERE 
	--	b.rptDate BETWEEN @FDate AND @TDate 		
	--	AND b.BetType IN (2198, 2398, 2998) -- Jackpot Contribution
	--	AND b.TicketStatus NOT IN (-1,18,9,10,14)
	--	AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 1 )-- Deposit data only
	--GROUP BY b.rptDate	

	UPDATE f
	SET HouseWL = f.HouseWL + ISNULL(wl.HouseWL, 0) + ISNULL(wl.DiffContribution, 0),
		ExtraPT = f.ExtraPT + ISNULL(wl.ExtraPT, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT)
	SELECT 'FullRange', SUM(HouseWL), SUM(ExtraPT)
	FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''CS'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''CS'', 2, ''Extra PT'', ExtraPT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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

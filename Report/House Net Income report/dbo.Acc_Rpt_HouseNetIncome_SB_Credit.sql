USE [bodb_dwrs]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit]    Script Date: 5/29/2019 8:03:42 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_HouseNetIncome_SB_Credit    Script Date: 7/4/2016 1:05:20 PM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Created: Victor  
	Date: 2016-05-27  
    Task : House month-to-date Net Income report
    DB: DBWH/bodb_dwrs  
   
    Revisions:	
		- 20160922@Harper - #64429 - Edit status ID
		- 20190529@Dan: tuning to prevent wrong excution plan (scan all table)
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
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('BT-Sold','BT-Bought','BT-Comm')

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.extraWinloss) AS ExtraPT
		FROM bodb_account.dbo.rptGroupWinloss b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 1
				AND b.statusid <> 14
		GROUP BY b.rptDate
	)
	UPDATE f
	SET ExtraPT = e.ExtraPT
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL)
	SELECT 
		b.rptDate,
		ISNULL(-SUM((winlossP+winlossS+winlossM+winlossA+commissionS)*ex.rate),0) HouseWL
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		LEFT JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDATE
		AND b.TicketStatus != 14
		AND SiteID IN (	select siteid from bodb_Account.dbo.tbl_Site WHERE isDeposit = 0) -- Credit data only
		AND b.BetType IN (select bettype from #SportBettypeMatrix sb WHERE ProductID = 1) --SB only
	GROUP BY b.rptDate
	OPTION (RECOMPILE)

	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL
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
							'(SELECT ''SB'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 3, ''Extra PT'', ExtraPT) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit] TO [dwrs]
GO

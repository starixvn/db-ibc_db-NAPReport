/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Soccer [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Credit '2018-12-01', '2018-12-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)		

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate	
	-- End region		

	-- Region: Handle data of Soccer
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		HouseWL				MONEY,
		ExtraPT				MONEY,
		TurnOver			MONEY		
	)

	INSERT INTO #FinalResult (rptDate, HouseWL, ExtraPT, TurnOver)
	SELECT 'FullRange', 0, 0, 0

	-- Date list to draw chart
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN		
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)		
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
		
	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
	
	-- House WL of Soccer + Parlay + Metrix Gaming
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, TurnOver MONEY, ExtraPT MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, TurnOver, ExtraPT)
	SELECT 
		b.rptDate,
		ISNULL(-SUM(CASE WHEN b.SiteID NOT IN (-2, -4)THEN (b.WinlossIBC + b.CommissionS) ELSE 0 END * ex.rate), 0) HouseWL,
		SUM((ISNULL(b.TurnoverIBC, 0) - ISNULL(b.ExtraTO, 0)) * ex.Rate) AS TurnOver,
		SUM((ISNULL(b.ExtraWL, 0) + ISNULL(b.ExtraComm, 0)) * ex.Rate) AS ExtraPT
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
		INNER JOIN #SportBettypeMatrix s ON b.bettype = s.Bettype -- Get all data of SB		
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		--AND b.status <> 14	
		AND (
				b.bettype IN (9, 29) -- Parlay
				OR (s.EventType IN (1, 2, 4) AND s.SubProduct = 'MG-SuperLive') -- Metrix Gaming
				OR (s.EventType IN (1, 2, 4) AND s.SubProduct <> 'MG-SuperLive' 
					AND EXISTS (SELECT 1 
								FROM bodb_Account.dbo.League l  WITH(NOLOCK)
								WHERE b.LeagueId = l.LeagueId AND l.sportid = 1)
								) -- Soccer
			)
	GROUP BY b.rptDate	
	OPTION (RECOMPILE)
	
	UPDATE f
	SET f.HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0),
		f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0),
		f.ExtraPT = ISNULL(f.ExtraPT, 0) + ISNULL(wl.ExtraPT, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate		
	
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''Soccer'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Credit] TO vnteam
GO
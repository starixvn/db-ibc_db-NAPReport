/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Other Sport[#RedmineID: 89632]
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit '2017-12-01', '2017-12-31'
  
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
		TurnOver			MONEY,
		ExtraTO				MONEY	
	)

	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver, ExtraTO)
	SELECT 'FullRange', 0, 0, 0, 0

	-- Date list to draw chart
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver, ExtraTO)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.ExtraWLAfterComm_RM) AS ExtraPT, SUM(b.ExtraTO_RM) AS ExtraTO
		FROM bodb_account.dbo.rptExtraPTBySite b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 1
				AND sb.EventType IN( 1, 2, 4 )
				AND b.statusid <> 14
				AND EXISTS( 
							SELECT TOP 1 1
							FROM bodb_Account.dbo.League l  WITH(NOLOCK)
							WHERE b.LeagueId = l.LeagueId
								AND l.sportid > 1)
		GROUP BY b.rptDate
	)
	UPDATE f
	SET f.ExtraPT = e.ExtraPT,
		f.ExtraTO = e.ExtraTO
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL of Other Sport
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, TurnOver MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, TurnOver)
	SELECT 
		b.rptDate,
		ISNULL(-SUM(CASE WHEN b.SiteID NOT IN (-2, -4)THEN (winlossP + winlossS + winlossM + winlossA + commissionS) ELSE 0 END * ex.rate), 0) HouseWL,
		ISNULL(SUM(b.TurnoverIBC * ex.Rate), 0) TurnOver
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID	
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND b.status <> 14	
		AND EXISTS( 
					SELECT TOP 1 1
					FROM #SportBettypeMatrix AS sb
					WHERE sb.BetType = b.BetType				                     
						AND sb.ProductID = 1							
						AND sb.EventType IN( 1, 2, 4 )
					)       
		AND EXISTS( 
            SELECT TOP 1 1
            FROM bodb_Account.dbo.League l  WITH(NOLOCK)
            WHERE b.LeagueId = l.LeagueId
				AND l.sportid > 1)
	GROUP BY b.rptDate	
	OPTION (RECOMPILE)
	
	UPDATE f
	SET HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0),
		f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0) - ISNULL(f.ExtraTO, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate		
				
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''OtherSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit] TO vnteam
GO
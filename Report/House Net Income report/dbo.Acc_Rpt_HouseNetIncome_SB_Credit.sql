/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

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
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
		- 20180131@Harper - Fix Daily HAIFA data [#RedmineID: 90263]

	Param's Explanation: 
	
	EXEC Acc_Rpt_HouseNetIncome_SB_Credit '2017-12-01', '2017-12-31'
  
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
		ExtraPT		MONEY,
		TurnOver	MONEY,
		ExtraTO		MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
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
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('BT-Sold','BT-Bought','BT-Comm')

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.ExtraWLAfterComm_RM) AS ExtraPT, SUM(b.ExtraTO_RM) AS ExtraTO
		FROM bodb_account.dbo.rptExtraPTBySite b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 1
				AND b.statusid <> 14
		GROUP BY b.rptDate
	)
	UPDATE f
	SET f.ExtraPT = e.ExtraPT,
		f.ExtraTO = e.ExtraTO
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, TurnOver MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, TurnOver)
	SELECT 
		b.rptDate,
		ISNULL(-SUM((winlossP+winlossS+winlossM+winlossA+commissionS) * ex.rate),0) HouseWL,
		ISNULL(SUM(b.TurnoverIBC * ex.Rate), 0) TurnOver
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype AND Sb.ProductID = 1
		INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON s.siteid = b.SiteID
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND b.status <> 14
		AND s.isDeposit = 0 -- Credit data only
	GROUP BY b.rptDate
	OPTION (RECOMPILE)

	;WITH TurnOver AS
	(	SELECT b.rptDate
			,ISNULL(SUM(b.TurnoverIBC * ex.Rate), 0) TurnOver
		FROM bodb_Account.dbo.mcSiteDaily b WITH ( NOLOCK )  
            INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype AND Sb.ProductID = 1
            LEFT JOIN bodb_Account.dbo.League l WITH ( NOLOCK ) ON b.LeagueId = l.LeagueId  
        WHERE b.rptDate BETWEEN @FDate AND @TDate  
            AND b.status <> 14  
            AND b.SiteId IN( -2, -4 )              
            AND sb.EventType IN( 1, 2, 4 )  
		GROUP BY b.rptDate
	)
	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL,
		f.TurnOver = f.TurnOver + wl.TurnOver + t.TurnOver - f.ExtraTO
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate
		INNER JOIN TurnOver t ON CONVERT(VARCHAR(2), t.rptDate, 106) = f.RptDate

	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver)
	SELECT 'FullRange', SUM(HouseWL), SUM(ExtraPT), SUM(TurnOver)
	FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SB'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_SB_Credit] TO vnteam
GO
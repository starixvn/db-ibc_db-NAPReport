/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyVariance_OtherSports_Credit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  Creator: Kean  
	Date: 2019-01-28  
    Task : Letstalk daily Report for Variance OtherSports - Credit
    DB: DBWH/bodb_dwrs  
   
    Revisions:
	- 20190128@Kean: Initialize Letstalk daily Report for Variance (#108438)

	Param's Explanation:   
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = bodb_dwrs.dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( ProductId  INT NOT NULL,
                                    BetType    SMALLINT NOT NULL,
                                    EventType  INT NOT NULL,
                                    SubProduct VARCHAR(50) NOT NULL,
                                    RefTable   INT,
                                    CasinoType INT );
        INSERT INTO #SportBetType
               SELECT ProductId,
                      BetType,
                      EventType,
                      SubProduct,
                      RefTable,
                      CasinoType
               FROM bodb02.dbo.f_SportBetTypeMatrix_Sel( 0, 0, 0, 2, '', '', @isTest );
        CREATE CLUSTERED INDEX [PK_tmp_SportBetType] ON #SportBetType( BetType, ProductID, SubProduct );
    END;

	BEGIN --#CurrencyDaily
		CREATE TABLE #CurrencyDaily( ExchangeDate DATE,
									 Currency     INT,
									 Rate         FLOAT);
		INSERT INTO #CurrencyDaily
					SELECT ExchangeDate, Currency, Rate
					FROM bodb_account.dbo.tbl_currency_daily AS ex WITH ( NOLOCK )
					WHERE ExchangeDate BETWEEN @FDate AND @TDate;
		CREATE CLUSTERED INDEX [PK_tmp_CurrencyDaily] ON #CurrencyDaily( ExchangeDate, Currency );
	END;

	
	CREATE TABLE #FinalResult (
		RptDate		VARCHAR(10),
		VarianceWL		DECIMAL(19,4),
		VarianceTO		DECIMAL(19,4)
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, VarianceWL, VarianceTO)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, VarianceWL DECIMAL(19,4), VarianceTO DECIMAL(19,4))
	INSERT INTO #TmpHouseWL (rptDate, VarianceWL, VarianceTO)
	SELECT 
		b.rptDate,
		-SUM((b.WinlossIBC - b.ExtraWL
								+ CASE WHEN b.VarianceVR < 0 THEN (b.CommissionS - b.ExtraComm) ELSE 0 END) * b.VarianceVR * ex.Rate) [Variance Winloss],
		SUM((CASE WHEN b.TurnoverIBC = 0 THEN 0 ELSE b.TurnoverIBC - b.ExtraTO END) * ABS(b.VarianceVR) * ex.Rate) [Variance Turnover]
	FROM bodb_Account.dbo.FactSiteWinloss AS b WITH ( NOLOCK )
        LEFT JOIN #CurrencyDaily AS ex WITH ( NOLOCK ) ON b.rptDate = ex.ExchangeDate
                                                                                       AND b.CurrencyID = ex.Currency
        INNER JOIN bodb_Account.dbo.tbl_Site s WITH (NOLOCK) ON s.siteid = b.SiteID
    WHERE b.rptdate >= @FDate AND rptdate <= @TDate
       AND b.TicketStatus NOT IN (-1,18,9,10,14)  
	   AND b.CurrencyID <> 20
	   AND (b.SiteID = -2 OR s.isDeposit = 0) -- Credit data only
	   AND EXISTS( 
                             SELECT TOP 1 1
                             FROM #SportBetType AS sb
                             WHERE sb.BetType = b.BetType
                               AND sb.ProductID = 1
                               AND sb.SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
                               AND sb.EventType IN( 1, 2, 4 ))
                 AND b.SportType > 1
	GROUP BY b.rptDate
		OPTION (RECOMPILE)

	UPDATE f
	SET VarianceWL = f.VarianceWL + wl.VarianceWL
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

    UPDATE f
	SET VarianceTO = f.VarianceTO + wl.VarianceTO
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate

	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, VarianceWL, VarianceTO)
	SELECT 'FullRange', SUM(VarianceWL), SUM(VarianceTO)
	FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''OS'', 1, ''House Income'', VarianceWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OS'', 2, ''Turn Over'', VarianceTO) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #TmpHouseWL
	DROP TABLE #FinalResult
	DROP TABLE #CurrencyDaily
	DROP TABLE #SportBetType
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyVariance_OtherSports_Credit] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyVariance_OtherSports_Credit] TO [dwrs]
GO
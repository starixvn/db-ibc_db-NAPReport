/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfByNonSport
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: Get House Performance By Non-Sport At Exec Time
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfByNonSport
			@ExecTime4GMT = '2022-06-29 03:00:00'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @DayOffset INT
		,@WLDate SMALLDATETIME
		,@Title VARCHAR(50)
		,@MsgInfo VARCHAR(MAX) = ''

	SET @DayOffset = (
			CASE 
				WHEN DATEPART(HOUR, @ExecTime4GMT) >= 2
					THEN 0
				ELSE - 1
				END
			)
	SET @WLDate = DATEADD(dd, DATEDIFF(dd, 0, @ExecTime4GMT), @DayOffset)

	--Build Exec Time as Text
	IF (@DayOffset = 0)
	BEGIN
		SET @Title = CONVERT(VARCHAR(5), @WLDate, 1)
		SET @Title = @Title + ' ' + LTRIM(RTRIM((RIGHT(CONVERT(VARCHAR, @ExecTime4GMT, 100), 7)))) + ' GMT-4'
	END
	ELSE
	BEGIN
		SET @Title = CONVERT(VARCHAR, @WLDate, 101)
	END
	SET @Title = @Title + ' (ID #34)'

	--Make sure WLDate only in range [bettrans]
	IF EXISTS (
			SELECT 1
			FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.[Age_SelBalanceUpDay]')
			WHERE @WLDate <= MoveBetsDay
			)
	BEGIN
		SELECT @Title AS Title
			,@MsgInfo AS MsgInfo

		RETURN
	END

	CREATE TABLE #tmpMarginNonSport (
		ProductName VARCHAR(50)
		,TurnOver MONEY
		,Margin MONEY
		,HouseWinlost MONEY
		,ProductCode VARCHAR(50)
		,ProductGroup VARCHAR(10)
		)

	INSERT INTO #tmpMarginNonSport (
		ProductName
		,TurnOver
		,Margin
		,HouseWinlost
		)
	EXEC Acc_ResetWinning_MarginByNonSport @Winlostdate = @WLDate
	
	-- merge vgaming into sc
	;WITH _s AS (
		SELECT TurnOver_SC = SUM(TurnOver)
			,HouseWinlost_SC = SUM(HouseWinlost)
		FROM #tmpMarginNonSport
		WHERE ProductName IN (
				'Saba.games'
				,'Vgaming'
				)
		)
	UPDATE #tmpMarginNonSport
	SET TurnOver = TurnOver_SC
		,HouseWinlost = HouseWinlost_SC
		,Margin = HouseWinlost_SC * 100 / TurnOver_SC
	FROM _s
	WHERE ProductName = 'Saba.games'

	DELETE #tmpMarginNonSport
	WHERE ProductName = 'Vgaming'

	-- /merge vgaming into sc
	--2021-12-24: remove saba promotion from NS
	DELETE #tmpMarginNonSport
	WHERE ProductName = 'Saba Promotion'

	UPDATE #tmpMarginNonSport
	SET ProductCode = CASE 
			WHEN ProductName = 'All Non Sports'
				THEN 'ALL'
			WHEN ProductName = 'Bet Builder'
				THEN 'BetB'
			WHEN ProductName = 'Metric Gaming - Super Live'
				THEN 'MetricG'
			WHEN ProductName = 'Number Game'
				THEN 'NumG'
			WHEN ProductName = 'Virtual Sports'
				THEN 'VirtSpo'
			WHEN ProductName = 'RNG Casino'
				THEN '1RNG'
			WHEN ProductName = 'RNG Keno'
				THEN 'MKeno'
			WHEN ProductName = 'Colossus Bets'
				THEN 'CB'
			WHEN ProductName = 'Allbet'
				THEN 'AllB'
			WHEN ProductName = 'Macau Games'
				THEN 'MacauG'
			WHEN ProductName = 'Fishing World'
				THEN 'FishW'
			WHEN ProductName = 'Cash Out'
				THEN 'CashO'
			WHEN ProductName = 'Virtual Sports 2'
				THEN 'VirtSpo2'
			WHEN ProductName = 'Lottery'
				THEN 'MLotte'
					--WHEN ProductName = 'Card Club' THEN 'CardC'
			WHEN ProductName = 'Arcadia Gaming'
				THEN 'ArcaGam'
			WHEN ProductName = 'PG Soft'
				THEN 'PGSoft'
			WHEN ProductName = 'Virtual Games'
				THEN 'VirtG'
			WHEN ProductName = 'Table Game'
				THEN 'TableG'
			WHEN ProductName = 'Saba.games'
				THEN 'SabaG'
			WHEN ProductName = 'Togel 4D'
				THEN 'Togel4D'
			WHEN ProductName = 'PP'
				THEN 'PragP'
			WHEN ProductName = 'SG'
				THEN 'SpadeG'
			WHEN ProductName = 'IBCBet Live Casino'
				THEN 'IBCLC'
			WHEN ProductName = 'SA Gaming'
				THEN 'SAG'
			WHEN ProductName = 'RNG War'
				THEN 'RNGWar'
			WHEN ProductName = 'Gold Deluxe'
				THEN 'GoldD'
			WHEN ProductName = 'AG Casino'
				THEN 'AG'
			WHEN ProductName = 'Sports Lottery'
				THEN 'SportsLott'
			WHEN ProductName = 'PP Live Casino'
				THEN 'PP LC'
			WHEN ProductName = 'AE Sexy'
				THEN 'AESexy'
			WHEN ProductName = 'Habanero'
				THEN 'Haban'
			WHEN ProductName = 'AdvantPlay'
				THEN 'AdPlay'
			WHEN ProductName = 'AdvantPlay Mini'
				THEN 'AdPlayMini'
			WHEN ProductName = 'Virtual Sports 3'
				THEN 'VirtSpo3'
			WHEN ProductName = 'Funky Games'
				THEN 'FunkyG'
			WHEN ProductName = 'Saba Casino'
				THEN 'SabaCas'
			ELSE ProductName
			END
		,ProductGroup = CASE 
			WHEN ProductName = 'All Non Sports'
				THEN '-'
			WHEN ProductName = 'Allbet'
				THEN 'LC'
			WHEN ProductName = 'AE Sexy'
				THEN 'LC'
			WHEN ProductName = 'IBCBet Live Casino'
				THEN 'LC'
			WHEN ProductName = 'SA Gaming'
				THEN 'LC'
			WHEN ProductName = 'BBIN'
				THEN 'LC'
			WHEN ProductName = 'ION'
				THEN 'LC'
			WHEN ProductName = 'Gold Deluxe'
				THEN 'LC'
			WHEN ProductName = 'AG Casino'
				THEN 'LC'
			WHEN ProductName = 'WM'
				THEN 'LC'
			WHEN ProductName = 'GDG'
				THEN 'LC'
			WHEN ProductName = 'BG'
				THEN 'LC'
			WHEN ProductName = 'PP Live Casino'
				THEN 'LC'
			WHEN ProductName = 'Macau Games'
				THEN 'RNG'
			WHEN ProductName = 'Fishing World'
				THEN 'RNG'
			WHEN ProductName = 'Arcadia Gaming'
				THEN 'RNG'
			WHEN ProductName = 'PG Soft'
				THEN 'RNG'
			WHEN ProductName = 'Virtual Games'
				THEN 'RNG'
			WHEN ProductName = 'Table Game'
				THEN 'RNG'
			WHEN ProductName = 'Saba.games'
				THEN 'RNG'
			WHEN ProductName = 'PP'
				THEN 'RNG'
			WHEN ProductName = 'SG'
				THEN 'RNG'
			WHEN ProductName = 'Joker'
				THEN 'RNG'
			WHEN ProductName = 'RNG War'
				THEN 'RNG'
			WHEN ProductName = 'RNG Casino'
				THEN 'RNG'
			WHEN ProductName = 'MaxGame'
				THEN 'RNG'
			WHEN ProductName = 'Habanero'
				THEN 'RNG'
			WHEN ProductName = 'Vgaming'
				THEN 'RNG'
			WHEN ProductName = 'AdvantPlay'
				THEN 'RNG'
			WHEN ProductName = 'AdvantPlay Mini'
				THEN 'RNG'
			WHEN ProductName = 'CG'
				THEN 'RNG'
			WHEN ProductName = 'Saba Casino'
				THEN 'RNG'
			WHEN ProductName = 'Lottery'
				THEN 'LOTTERY'
			WHEN ProductName = 'Togel 4D'
				THEN 'LOTTERY'
			WHEN ProductName = 'RNG Keno'
				THEN 'LOTTERY'
			WHEN ProductName = 'Number Game'
				THEN 'LOTTERY'
			WHEN ProductName = 'NG2'
				THEN 'LOTTERY'
			WHEN ProductName = 'Sports Lottery'
				THEN 'LOTTERY'
			WHEN ProductName = 'Metric Gaming - Super Live'
				THEN 'OTHERS'
			WHEN ProductName = 'Bet Builder'
				THEN 'OTHERS'
			WHEN ProductName = 'Virtual Sports'
				THEN 'OTHERS'
			WHEN ProductName = 'Colossus Bets'
				THEN 'OTHERS'
			WHEN ProductName = 'Cash Out'
				THEN 'OTHERS'
			WHEN ProductName = 'Virtual Sports 2'
				THEN 'OTHERS'
			WHEN ProductName = 'Virtual Sports 3'
				THEN 'OTHERS'
			WHEN ProductName = 'Funky Games'
				THEN 'OTHERS'
			WHEN ProductName = 'Bitcoin'
				THEN 'OTHERS'
			ELSE 'OTHERS'
			END
	
	---------------------Build msg---------------------
	SELECT @MsgInfo = @MsgInfo + '[NS TO & M]'

	-- generate string for TO & Margin
	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductCode = 'ALL'
	ORDER BY TurnOver DESC

	SELECT @MsgInfo = @MsgInfo + '<br>-----<br>*LC: ' + CASE 
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'LC'

	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'LC'
	ORDER BY TurnOver DESC

	SELECT @MsgInfo = @MsgInfo + '<br>-----<br>*RNG: ' + CASE 
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'RNG'

	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'RNG'
	ORDER BY TurnOver DESC

	SELECT @MsgInfo = @MsgInfo + '<br>-----<br>*Lott/Ken: ' + CASE 
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'LOTTERY'

	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'LOTTERY'
	ORDER BY TurnOver DESC

	SELECT @MsgInfo = @MsgInfo + '<br>-----<br>*OTHERS: ' + CASE 
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'OTHERS'

	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'OTHERS'
	ORDER BY TurnOver DESC
	
	SELECT @Title AS Title
		,REPLACE(@MsgInfo, '<br>', CHAR(13)+CHAR(10)) AS MsgInfo
	
	DROP TABLE #tmpMarginNonSport
END

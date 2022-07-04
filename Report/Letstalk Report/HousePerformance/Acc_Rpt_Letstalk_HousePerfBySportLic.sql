/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfBySportLic
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: Get House Performance By Sport Lic At Exec Time
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfBySportLic
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
	SET @Title = @Title + ' (ID #36)'

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

	CREATE TABLE #tmpMarginLIC (
		SportName VARCHAR(50)
		,LiveIndicator BIT
		,IsSaba TINYINT
		,TurnOver MONEY
		,Margin MONEY
		,HouseWinlost MONEY
	)

	CREATE TABLE #tmpMarginNonSportLIC (
		ProductName VARCHAR(50)
		,TurnOver MONEY
		,Margin MONEY
		,HouseWinlost MONEY
	)

	INSERT INTO #tmpMarginLIC (
		SportName
		,LiveIndicator
		,IsSaba
		,TurnOver
		,Margin
		,HouseWinlost
	)
	EXEC Acc_ResetWinning_MarginBySport_Lic
		@Winlostdate = @wldate
		,@BaseCurrency = 'CNY' --base currency RMB

	INSERT INTO #tmpMarginNonSportLIC (
		ProductName
		,TurnOver
		,Margin
		,HouseWinlost
	)
	EXEC Acc_ResetWinning_MarginByNonSport_Lic
		@Winlostdate = @wldate
		,@BaseCurrency = 'CNY' --base currency RMB

	DELETE #tmpMarginLIC
	WHERE TurnOver IS NULL

	DELETE #tmpMarginNonSportLIC
	WHERE TurnOver IS NULL

	-- Licensee margin
	-- LIC WL
	SELECT @MsgInfo = @MsgInfo + '[TOTAL WL(RMB) & M]'

	SELECT @MsgInfo = @MsgInfo + '<br>' + 'SB: ' + CASE 
			WHEN ABS(- ISNULL(SUM(HouseWinlost), 0)) BETWEEN 0
					AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(- ISNULL(SUM(HouseWinlost), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(- ISNULL(SUM(HouseWinlost), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(- ISNULL(SUM(HouseWinlost), 0) / 1000000.0, 2) AS NUMERIC(6, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), - ISNULL(SUM(HouseWinlost), 0))
			END + '  ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginLIC
	WHERE SportName = 'All Sports'

	SELECT @MsgInfo = @MsgInfo + '<br>' + 'NS: ' + CASE 
			WHEN ABS(- ISNULL(SUM(HouseWinlost), 0)) BETWEEN 0
					AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(- ISNULL(SUM(HouseWinlost), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(- ISNULL(SUM(HouseWinlost), 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(- ISNULL(SUM(HouseWinlost), 0) / 1000000.0, 2) AS NUMERIC(6, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), - ISNULL(SUM(HouseWinlost), 0))
			END + '  ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSportLIC
	WHERE ProductName = 'All Non Sports'

	SELECT @MsgInfo = @MsgInfo + '<br>-------<br>[SB TO(RMB) & M]'

	;WITH _S
	AS (
		SELECT SportName = CASE 
				WHEN SportName = 'All Sports'
					THEN 'ALL'
				WHEN SportName = 'Soccer'
					AND Liveindicator = 1
					AND IsSaba = 0
					THEN 'R.Soc(L)'
				WHEN SportName = 'Soccer'
					AND Liveindicator = 0
					AND IsSaba = 0
					THEN 'R.Soc(NL)'
				WHEN SportName = 'Soccer'
					AND IsSaba = 1
					THEN 'Saba.Soc'
				WHEN SportName = 'Soccer'
					AND IsSaba = 2
					THEN 'Soccer PG' -- Saba Soccer Pingoal
				WHEN SportName = 'Basketball'
					AND IsSaba = 2
					THEN 'Basket PG' -- Saba Basketball Pingoal
				WHEN SportName = 'Basketball'
					AND IsSaba = 0
					THEN 'Real.Bas'
				WHEN SportName = 'Basketball'
					AND IsSaba = 1
					THEN 'Saba.Bas'
				WHEN SportName = 'Tennis'
					THEN 'Tenn'
				WHEN SportName = 'E-Sports'
					THEN 'E-Spo'
				WHEN SportName = 'Cricket'
					THEN 'Cricket'
				WHEN SportName = 'Other Sports'
					THEN 'Others'
				WHEN SportName = 'Parlay'
					THEN 'Parl'
				ELSE SportName
				END
			,rn = CASE 
				WHEN SportName = 'All Sports'
					THEN 1
				WHEN SportName = 'Soccer'
					AND IsSaba = 0
					AND Liveindicator = 1
					THEN 3
				WHEN SportName = 'Soccer'
					AND IsSaba = 0
					AND Liveindicator = 0
					THEN 4
				WHEN SportName = 'Soccer'
					AND IsSaba = 1
					THEN 5
				WHEN SportName = 'Soccer'
					AND IsSaba = 2
					THEN 6
				WHEN SportName = 'Basketball'
					AND IsSaba = 2
					THEN 7
				WHEN SportName = 'Basketball'
					AND IsSaba = 0
					THEN 8
				WHEN SportName = 'Basketball'
					AND IsSaba = 1
					THEN 9
				WHEN SportName = 'Tennis'
					THEN 10
				WHEN SportName = 'E-Sports'
					THEN 11
				WHEN SportName = 'Cricket'
					THEN 12
				WHEN SportName = 'Other Sports'
					THEN 13
				WHEN SportName = 'Parlay'
					THEN 14
				ELSE 15
				END
			,VAL = CASE 
				WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0
						AND 999999
					THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
				WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
					THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(6, 2))))) + 'm'
				ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
				END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
		FROM #tmpMarginLIC
		GROUP BY CASE 
				WHEN SportName = 'All Sports'
					THEN 'ALL'
				WHEN SportName = 'Soccer'
					AND Liveindicator = 1
					AND IsSaba = 0
					THEN 'R.Soc(L)'
				WHEN SportName = 'Soccer'
					AND Liveindicator = 0
					AND IsSaba = 0
					THEN 'R.Soc(NL)'
				WHEN SportName = 'Soccer'
					AND IsSaba = 1
					THEN 'Saba.Soc'
				WHEN SportName = 'Soccer'
					AND IsSaba = 2
					THEN 'Soccer PG' -- Saba Soccer Pingoal
				WHEN SportName = 'Basketball'
					AND IsSaba = 2
					THEN 'Basket PG' -- Saba Basketball Pingoal
				WHEN SportName = 'Basketball'
					AND IsSaba = 0
					THEN 'Real.Bas'
				WHEN SportName = 'Basketball'
					AND IsSaba = 1
					THEN 'Saba.Bas'
				WHEN SportName = 'Tennis'
					THEN 'Tenn'
				WHEN SportName = 'E-Sports'
					THEN 'E-Spo'
				WHEN SportName = 'Cricket'
					THEN 'Cricket'
				WHEN SportName = 'Other Sports'
					THEN 'Others'
				WHEN SportName = 'Parlay'
					THEN 'Parl'
				ELSE SportName
				END
			,CASE 
				WHEN SportName = 'All Sports'
					THEN 1
				WHEN SportName = 'Soccer'
					AND IsSaba = 0
					AND Liveindicator = 1
					THEN 3
				WHEN SportName = 'Soccer'
					AND IsSaba = 0
					AND Liveindicator = 0
					THEN 4
				WHEN SportName = 'Soccer'
					AND IsSaba = 1
					THEN 5
				WHEN SportName = 'Soccer'
					AND IsSaba = 2
					THEN 6
				WHEN SportName = 'Basketball'
					AND IsSaba = 2
					THEN 7
				WHEN SportName = 'Basketball'
					AND IsSaba = 0
					THEN 8
				WHEN SportName = 'Basketball'
					AND IsSaba = 1
					THEN 9
				WHEN SportName = 'Tennis'
					THEN 10
				WHEN SportName = 'E-Sports'
					THEN 11
				WHEN SportName = 'Cricket'
					THEN 12
				WHEN SportName = 'Other Sports'
					THEN 13
				WHEN SportName = 'Parlay'
					THEN 14
				ELSE 15
				END
		
		UNION ALL
		
		SELECT SportName = 'Real.Soc'
			,rn = 2
			,VAL = CASE 
				WHEN ABS(ISNULL(SUM(TurnOver), 0)) BETWEEN 0
						AND 999999
					THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
				WHEN ABS(ISNULL(SUM(TurnOver), 0)) >= 1000000
					THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(SUM(TurnOver), 0) / 1000000.0, 2) AS NUMERIC(6, 2))))) + 'm'
				ELSE CONVERT(VARCHAR(10), ISNULL(SUM(TurnOver), 0))
				END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - SUM(HouseWinlost) * 100 / NULLIF(SUM(TurnOver), 0)), 0) AS VARCHAR(10)) + '%'
		FROM #tmpMarginLIC
		WHERE SportName = 'Soccer'
			AND IsSaba = 0
		)
	SELECT @MsgInfo = @MsgInfo + '<br>' + SportName + ': ' + VAL
	FROM _S
	ORDER BY rn

	-- non sports
	SELECT @MsgInfo = @MsgInfo + '<br>-------<br>[NS TO(RMB) & M]'

	SELECT @MsgInfo = @MsgInfo + '<br>' + CASE 
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
				THEN 'I4D'
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
			END + ': '
		+ CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0
					AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(6, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(CONVERT(DECIMAL(10, 2), - ISNULL(Margin, 0)) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSportLIC
	WHERE TurnOver > 0
	ORDER BY TurnOver DESC

	SELECT @Title AS Title
		,REPLACE(@MsgInfo, '<br>', CHAR(13) + CHAR(10)) AS MsgInfo

	DROP TABLE #tmpMarginLIC
	DROP TABLE #tmpMarginNonSportLIC

END

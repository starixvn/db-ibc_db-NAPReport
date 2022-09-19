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
	
	DECLARE @isTest BIT = 0
		,@SQLStr VARCHAR(MAX)
	
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	SET @SQLStr = 
		'
			SELECT DISTINCT ProductName
				,(CASE WHEN h.ProductGroup = ''Live Casino'' THEN ''LC''
					WHEN h.ProductGroup = ''RNG Casino'' THEN ''RNG''
					WHEN h.ProductGroup = ''Lottery/Keno'' THEN ''Lott/Ken''
					ELSE ''OTHERS''
					END) AS ProductGroup
				,ProductShortName
			FROM bodb_account.dbo.HNISettings AS h WITH (NOLOCK)
			WHERE ProductCategory = ''NonSport''
				AND isTest IN (0,' + CONVERT(VARCHAR,@isTest) +')
		'
	
	CREATE TABLE #tmpHNISettings (
		ProductName VARCHAR(50)
		,ProductShortName VARCHAR(50)
		,ProductGroup VARCHAR(10)
	)
	
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
	
	INSERT INTO #tmpHNISettings (
		ProductName
		,ProductGroup
		,ProductShortName
	)
	EXEC (@SQLStr) AT DBWH
	
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

	UPDATE m
	SET m.ProductCode = CASE 
			WHEN m.ProductName = 'All Non Sports' THEN 'ALL'
			WHEN m.ProductName = 'Bet Builder' THEN 'BetB'
			ELSE ISNULL(p.ProductShortName,m.ProductName)
			END
	,m.ProductGroup = CASE 
			WHEN m.ProductName = 'All Non Sports' THEN '-'
			ELSE ISNULL(p.ProductGroup,'OTHERS')
			END
	FROM #tmpMarginNonSport AS m
		LEFT JOIN #tmpHNISettings AS p ON m.ProductName = p.ProductName
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
		AND ProductGroup = 'Lott/Ken'

	SELECT @MsgInfo = @MsgInfo + '<br>' + ProductCode + ': ' + CASE 
			WHEN ABS(ISNULL(TurnOver, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000.0, 0) AS NUMERIC(4, 0))))) + 'k'
			WHEN ABS(ISNULL(TurnOver, 0)) >= 1000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnOver, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnOver, 0))
			END + ' ' + CAST(ISNULL(CONVERT(DECIMAL(10, 2), - HouseWinlost * 100 / NULLIF(TurnOver, 0)), 0) AS VARCHAR(10)) + '%'
	FROM #tmpMarginNonSport
	WHERE TurnOver > 0
		AND ProductGroup = 'Lott/Ken'
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
	DROP TABLE #tmpHNISettings
END

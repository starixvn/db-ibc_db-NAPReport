/*<info serverAlias="DBEXT-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfByTopLic
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: Get House Performance By Top Lic At Exec Time
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)
		20250826@Cherry: Apply Thousand-Scale Display (#236856)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfByTopLic
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
	SET @Title = @Title + ' (ID #35)'

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

	--- TOP 30 low margin Licensees
	/*
		1. Get the list of top 50 Licensees with highest turnover of the day
		2. Sort the list by lowest margin.
		3. Get the top 30 licensees
		4. Order by TO
	*/
	CREATE TABLE #tmpTopLicenseeMargin (
		Licensee VARCHAR(50)
		,MarginAllSport DECIMAL(19, 4)
		,MarginSoccer DECIMAL(19, 4)
		,MarginBasketball DECIMAL(19, 4)
		,MarginEsport DECIMAL(19, 4)
		,MarginTennis DECIMAL(19, 4)
		,MarginParlay DECIMAL(19, 4)
		,MarginSabaSoccer DECIMAL(19, 4)
		,MarginSabaBasketball DECIMAL(19, 4)
		,MarginOthersport DECIMAL(19, 4)
		,TurnoverAllSport DECIMAL(19, 4)
	)

	INSERT INTO #tmpTopLicenseeMargin (
		Licensee
		,MarginAllSport
		,MarginSoccer
		,MarginBasketball
		,MarginEsport
		,MarginTennis
		,MarginParlay
		,MarginSabaSoccer
		,MarginSabaBasketball
		,MarginOthersport
		,TurnoverAllSport
		)
	EXEC Acc_ResetWinning_TopLicenseeMargin @Winlostdate = @WLDate

	CREATE TABLE #Temp_Top30Final (
		Licensee VARCHAR(50)
		,MarginAllSport DECIMAL(19, 4)
		,TurnoverAllSport DECIMAL(19, 4)
	)

	INSERT INTO #Temp_Top30Final (
		Licensee
		,MarginAllSport
		,TurnoverAllSport
	)
	SELECT TOP 30 Licensee
		,MarginAllSport
		,TurnoverAllSport
	FROM #tmpTopLicenseeMargin
	WHERE Licensee <> 'Other Licensees'
	ORDER BY MarginAllSport

	SET @MsgInfo = '[LIC TO(MYR) Margin]'

	SELECT @MsgInfo = @MsgInfo + '<br>' + Licensee + ' ' + CASE 
			WHEN ABS(ISNULL(TurnoverAllSport, 0)) BETWEEN 0 AND 999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnoverAllSport, 0) / 1000.0, 0) AS NUMERIC(6, 2)))))
			WHEN ABS(ISNULL(TurnoverAllSport, 0)) BETWEEN 1000000 AND 999999999
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnoverAllSport, 0) / 1000000.0, 2) AS NUMERIC(9, 2))))) + 'k'
			WHEN ABS(ISNULL(TurnoverAllSport, 0)) >= 1000000000
				THEN (CONVERT(VARCHAR(10), (CAST(ROUND(ISNULL(TurnoverAllSport, 0) / 1000000000.0, 2) AS NUMERIC(12, 2))))) + 'm'
			ELSE CONVERT(VARCHAR(10), ISNULL(TurnoverAllSport, 0))
			END + ' ' + CAST(CONVERT(DECIMAL(10, 2), ISNULL(MarginAllSport, 0) * 100) AS VARCHAR(10)) + '%'
	FROM #Temp_Top30Final 
	ORDER BY TurnoverAllSport DESC
	
	SELECT @Title AS Title
		,REPLACE(@MsgInfo, '<br>', CHAR(13)+CHAR(10)) AS MsgInfo
	
	DROP TABLE #Temp_Top30Final
	DROP TABLE #tmpTopLicenseeMargin
END

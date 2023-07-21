/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfByTopLic
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: TOP licensees - 30 lowest margin in top 50 biggest TO (Letstalk #35)
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)
		20230720@Roy: Email/Letstalk Reports - Apply Bot API and change HTML UI (#191481)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfByTopLic
			@ExecTime4GMT = '2022-06-29 03:00:00'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @DayOffset INT
		,@WLDate DATE
		,@Title VARCHAR(50)

	SET @DayOffset = ( CASE WHEN DATEPART(HOUR, @ExecTime4GMT) >= 2 THEN 0 ELSE - 1 END )
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

		RETURN
	END
	
	CREATE TABLE #tmpBATrans (TransID BIGINT PRIMARY KEY)
	
	CREATE TABLE #tmpRawData (
		SiteID INT
		,TurnOver DECIMAL(19, 4) DEFAULT 0
		,Winloss DECIMAL(19, 4) DEFAULT 0
	)
	
	INSERT INTO #tmpBATrans (TransID)
	SELECT DISTINCT TransID
	FROM OPENQUERY(DBLIC,'SELECT TransID FROM bodb_licensee.dbo.LicenseeBATransaction_active WITH(NOLOCK)')
	
	INSERT INTO #tmpRawData WITH (TABLOCK)(
		SiteID
		,TurnOver
		,Winloss
	)
	SELECT b.SiteID
		,SUM((CASE WHEN b.TicketStatusID = 3 THEN 0
				WHEN b.TicketStatusID IN (12, 13) THEN (ABS(Stake) / 2)
				ELSE ABS(Stake)
				END) * b.actualrate
		) AS TurnOver
		,- SUM((ISNULL(b.winlost, 0) - ISNULL(b.actual_stake, 0)) * b.actualrate) AS Winloss
	FROM bodb_ODS.dbo.ODS_bettrans AS b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Dep_CustSuper AS s WITH (NOLOCK) ON s.CustID = b.srecommend
		LEFT JOIN #tmpBATrans AS ba ON b.TransID = ba.TransID
	WHERE b.Winlostdate = @WLDate
		AND b.TicketStatusID IN (3,4,8,12,13) --DRAW, LOSE, WON, HALF LOSE, HALF WON
		AND b.Recommend NOT IN (52466,5707545)  -- Exclude 8RM, BARM
		AND b.Currency <> 20
		AND s.Site NOT IN ('Saba789')
		AND ba.TransID IS NULL --Exclude BA tickets
		--get SB include outright, Parlay, Oddspread
		AND b.ProductID = 1
		-- AND b.BetType NOT BETWEEN 801 AND 806 --MG-SuperLive (ProductID = -1)
		-- AND b.BetType NOT BETWEEN 901 AND 904 --Bettrade (ProductID = -2)
		-- AND b.BetType <> 38 --BetBuilder (ProductID = -3)
	GROUP BY b.SiteID
	OPTION (RECOMPILE)
	
	--- TOP 30 low margin Licensees
	/*
		1. Get the list of top 50 Licensees with highest turnover of the day
		2. Sort the list by lowest margin.
		3. Get the top 30 licensees
		4. Order by TO
	*/
	;WITH CTE_TOP_TO AS (
		SELECT SiteID
			,RANK() OVER ( ORDER BY Turnover DESC ) AS RankTO
			,TurnOver
			,Winloss
			,CASE WHEN TurnOver = 0 THEN 0 ELSE CONVERT(DECIMAL(19, 4),(Winloss/TurnOver)) END AS Margin
		FROM #tmpRawData
	)
	,CTE_TOP_Margin AS (
		SELECT TOP 30 SiteID
			,Turnover
			,Margin
		FROM CTE_TOP_TO
		WHERE RankTO <= 50 --top 50 highest TO
		ORDER BY Margin
	)
	SELECT s.Site AS Licensee
		,d.Turnover
		,d.Margin
	FROM CTE_TOP_Margin AS d
		LEFT JOIN bodb_account.dbo.tbl_Site AS s WITH (NOLOCK) ON d.SiteID = s.SiteID
	ORDER BY TurnOver DESC
	
	SELECT @Title AS Title
	
	DROP TABLE #tmpBATrans
	DROP TABLE #tmpRawData
END

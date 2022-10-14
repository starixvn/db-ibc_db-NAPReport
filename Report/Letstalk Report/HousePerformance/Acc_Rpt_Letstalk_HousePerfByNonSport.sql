/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfByNonSport
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: Get House Performance By Non-Sport At Exec Time (ID #34)
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)
		20220916@Roy: Letstalk report ID #32, #34 - Add 8RM info & enhance the UI (#177825)
		20221010@Roy: Letstalk reports - Enhance UI/UX for smartwatch devices (#178950)

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
		,@Footer VARCHAR(20) = 'Report ID #34'

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
		SET @Title = LTRIM(RTRIM((RIGHT(CONVERT(VARCHAR, @ExecTime4GMT, 100), 7))))
	END
	ELSE
	BEGIN
		SET @Title = CONVERT(VARCHAR(5), @WLDate, 1)
	END

	--Make sure WLDate only in range [bettrans]
	IF EXISTS (
			SELECT 1
			FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.[Age_SelBalanceUpDay]')
			WHERE @WLDate <= MoveBetsDay
			)
	BEGIN
		SELECT @Title AS Title
			,@Footer AS Footer
		RETURN
	END
	
	CREATE TABLE #tmpHNISetting (
		ProductID INT
		,ProductName VARCHAR(50)
		,ProductGroup VARCHAR(10)
		,ProductShortName VARCHAR(50)
	)
	
	CREATE TABLE #tmpProductBettype (
		ProductID INT
		,Bettype INT
	)
	
	CREATE TABLE #tmpMarginNonSport (
		ProductID INT
		,WinlossIBC DECIMAL(19,4)
		,TurnoverIBC DECIMAL(19,4)
	)
	
	/*
		insert Dim for non-sport product
			#tmpProductBettype
			#tmpHNISetting
	*/
	INSERT INTO #tmpProductBettype (
		ProductID
		,Bettype
	)
	SELECT DISTINCT ProductID
		,Bettype
	FROM bodb_account.dbo.Product_Bettype WITH (NOLOCK)
	WHERE ProductID NOT IN (1,37) --exclude Sportsbook and Saba Promotion
	
	INSERT INTO #tmpHNISetting (
		ProductID
		,ProductName
		,ProductGroup
		,ProductShortName
	)
	SELECT DISTINCT h.ProductID
		,h.ProductName
		,(CASE WHEN h.ProductGroup = 'Live Casino' THEN 'LC'
			WHEN h.ProductGroup = 'RNG Casino' THEN 'RNG'
			WHEN h.ProductGroup = 'Lottery/Keno' THEN 'LOT/KENO'
			ELSE 'OTHERS'
			END
		) AS ProductGroup
		,h.ProductShortName
	FROM bodb_account.dbo.HNISettings AS h WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON h.ProductID = p.ProductID AND h.ProductName = p.ProductName
	WHERE h.ProductCategory = 'NonSport'
		AND h.ProductID IN (SELECT DISTINCT ProductID FROM #tmpProductBettype)
	
	UNION ALL /*insert Dim for Special non-sport product*/
	
	SELECT DISTINCT pb.ProductID
		,(CASE WHEN sb.SubProduct = 'MG-SuperLive' THEN 'Metric Gaming - Super Live' ELSE sb.SubProduct END) AS ProductName
		,'OTHERS' AS ProductGroup
		,(CASE WHEN sb.SubProduct = 'Bet Builder' THEN 'BetB' ELSE sb.SubProduct END) AS ProductShortName
	FROM #tmpProductBettype AS pb WITH (NOLOCK)
		INNER JOIN bodb02.dbo.SportBettypeMatrix AS sb WITH (NOLOCK) ON pb.Bettype = sb.Bettype
	WHERE sb.SubProduct IN ('MG-SuperLive', 'Bet Builder')
	
	/*insert Dim for Special rule*/
	--Include Bet Builder into [OTHERS] group; show 'BetB' => handle at [Special non-sport product]
	--Combine NumG, Happy 5, Happy 5 LG into Number Game => HNISettings INNER JOIN bodb02.dbo.Products
	--Combine Vgaming into SABA.games
	;WITH CTE_Saba AS (
		SELECT 'Vgaming' AS ProductName
			,ProductGroup
			,ProductShortName
		FROM #tmpHNISetting WITH (NOLOCK)
		WHERE ProductName = 'SABA.games'
	)
	UPDATE vg
	SET vg.ProductGroup = sabag.ProductGroup
		,vg.ProductShortName = sabag.ProductShortName
	FROM #tmpHNISetting AS vg WITH (NOLOCK)
		INNER JOIN CTE_Saba AS sabag ON vg.ProductName = sabag.ProductName
	WHERE vg.ProductName = 'Vgaming'
	
	CREATE CLUSTERED INDEX CIX_tmpProductBettype ON #tmpProductBettype ( Bettype, ProductID)	
	CREATE CLUSTERED INDEX CIX_tmpHNISettings ON #tmpHNISetting ( ProductID )
	
	/*===================================================*/
	;WITH CTE_HWL AS (
		SELECT --***DIMENSION***--
			pb.ProductID
			,CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6)) AS VarianceVR
			--***MEASURE***--
			,SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0
				WHEN bg.BettypeGroupID = 10 THEN mc.ContributionStake3rd + mc.swinlost + mc.mwinlost + mc.awinlost
				ELSE (mc.winlost - mc.actual_stake) + mc.swinlost + mc.mwinlost + mc.awinlost END
				) * mc.actualrate) AS WinlossIBC
			,SUM(mc.scomm * mc.actualrate) AS CommissionS
			,SUM((CASE WHEN mc.tpositiontaking = 1 THEN 0
					WHEN bg.BettypeGroupID = 6 THEN 0
					WHEN bg.BettypeGroupID = 10 THEN mc.ContributionStake3rd * CAST(mc.epositiontaking AS DECIMAL(10, 8))
					ELSE (mc.winlost - mc.actual_stake) * CAST(mc.epositiontaking AS DECIMAL(10, 8)) END
				) * mc.actualrate) AS ExtraWL
			,CAST(SUM((CASE WHEN mc.tpositiontaking = 1 THEN 0
					ELSE mc.scomm * CAST(mc.epositiontaking AS DECIMAL(10, 8)) / (1 - mc.tpositiontaking)
					END) * mc.actualrate) AS DECIMAL(19, 8)) ExtraComm
			,SUM(CASE WHEN pb.ProductID = 1 THEN ABS(mc.stake) ELSE mc.stake END
					* (1 - mc.tpositiontaking)
					* mc.actualrate
				) AS TurnoverIBC
			,SUM((CASE WHEN mc.tpositiontaking = 1 THEN 0 
					ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(mc.epositiontaking AS DECIMAL(10, 8))
				END) * mc.actualrate) AS ExtraTO
		FROM bodb_ODS.dbo.ODS_bettrans AS mc WITH (NOLOCK)
			INNER JOIN #tmpProductBettype AS pb (NOLOCK) ON mc.bettype = pb.Bettype
			LEFT JOIN bodb_account.dbo.BettypeGroup AS bg WITH (NOLOCK) ON mc.bettype = bg.Bettype AND bg.BettypeGroupID IN (6 ,10)
		WHERE mc.winlostdate = @WLDate
			AND mc.Status IN ('WON', 'LOSE', 'HALF WON', 'HALF LOSE')
			AND mc.currency <> 20
		GROUP BY pb.ProductID
			,CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6))
	)
	INSERT INTO #tmpMarginNonSport (
		ProductID
		,WinlossIBC
		,TurnoverIBC
	)
	SELECT ProductID
		,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
		,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
			* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END) ) AS TurnoverIBC
	FROM CTE_HWL AS h
	GROUP BY ProductID
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX CIX_tmpMarginNonSport ON #tmpMarginNonSport ( ProductID )

	/*
		Group by ProductGroup, Order and Return result
		=================Order=====================
		GroupID GroupName
		-----------------
		1		GRAND TOTAL
		2		T LC
		3		T RNG 
		4		T LOT/KENO
		5		T OTHERS
		
		6		NS TO & M 			--title
		
		7		LC 					--title
		8		LC Products
		..		...
		
		9		RNG					--title
		10		RNG Products
		..		...
		
		11		LOT/KENO			--title
		12		LOT/KENO Products
		..		...
		
		13		OTHERS				--title
		14		the rest Products
		..		...
		
	*/
	;WITH CTE_SubTotal AS (
		SELECT (CASE WHEN h.ProductGroup = 'LC' THEN 2
				WHEN h.ProductGroup = 'RNG' THEN 3
				WHEN h.ProductGroup = 'LOT/KENO' THEN 4
				ELSE 5
				END
			) AS GroupID
			,'T ' + ISNULL(h.ProductGroup,'OTHERS') AS GroupName
			,SUM(TurnoverIBC) AS TurnoverIBC
			,SUM(WinlossIBC) AS WinlossIBC
			,(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END) AS Margin
		FROM #tmpMarginNonSport AS m WITH (NOLOCK)
			LEFT JOIN #tmpHNISetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY h.ProductGroup
			,ISNULL(h.ProductGroup,'OTHERS')
	)
	,CTE_Total AS (
		SELECT 1 AS GroupID
			,'GRAND TOTAL' AS GroupName
			,SUM(TurnoverIBC) AS TurnoverIBC
			,(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END) AS Margin
		FROM CTE_SubTotal
	)
	,CTE_Product AS (
		SELECT (CASE WHEN h.ProductGroup = 'LC' THEN 8
				WHEN h.ProductGroup = 'RNG' THEN 10
				WHEN h.ProductGroup = 'LOT/KENO' THEN 12
				ELSE 14
				END
			) AS GroupID
			,ISNULL(h.ProductShortName,ISNULL(h.ProductName,'Others')) AS GroupName
			,SUM(TurnoverIBC) AS TurnoverIBC
			,(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END) AS Margin
		FROM #tmpMarginNonSport AS m WITH (NOLOCK)
			LEFT JOIN #tmpHNISetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY h.ProductGroup
			,ISNULL(h.ProductShortName,ISNULL(h.ProductName,'Others'))
	)
	----return title----
	SELECT 6 AS GroupID
		,'NS TO & M' AS GroupName
		,NULL AS TurnoverIBC
		,NULL AS Margin
	
	UNION ALL
	
	SELECT 7 AS GroupID
		,'LC' AS GroupName
		,NULL AS TurnoverIBC
		,NULL AS Margin
	
	UNION ALL
	
	SELECT 9 AS GroupID
		,'RNG' AS GroupName
		,NULL AS TurnoverIBC
		,NULL AS Margin
		
	UNION ALL
	
	SELECT 11 AS GroupID
		,'LOT/KENO' AS GroupName
		,NULL AS TurnoverIBC
		,NULL AS Margin
		
	UNION ALL
	
	SELECT 13 AS GroupID
		,'OTHERS' AS GroupName
		,NULL AS TurnoverIBC
		,NULL AS Margin
	----return total----
	UNION ALL
	SELECT GroupID
		,GroupName
		,TurnoverIBC
		,Margin
	FROM CTE_Total
	
	UNION ALL
	
	SELECT GroupID
		,GroupName
		,TurnoverIBC
		,Margin
	FROM CTE_SubTotal
	----return products----
	UNION ALL
	
	SELECT GroupID
		,GroupName
		,TurnoverIBC
		,Margin
	FROM CTE_Product
	ORDER BY GroupID
		,TurnoverIBC DESC
	
	SELECT @Title AS Title
		,@Footer AS Footer
	
	DROP TABLE #tmpHNISetting
	DROP TABLE #tmpProductBettype
	DROP TABLE #tmpMarginNonSport
END

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
		,@Footer VARCHAR(20) = 'ID #34'

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
	
	DECLARE @MaxBettype SMALLINT
		,@isTest BIT = 0
		,@SQLStr VARCHAR(MAX) = ''
		,@MinTransID_RNG BIGINT
		,@MinTransID_LC BIGINT
		,@MaxTransID_RNG BIGINT
		,@MaxTransID_LC BIGINT
	
	CREATE TABLE #tmpProductSetting (
		ProductID INT
		,ProductGroup VARCHAR(20)
		,ProductShortName VARCHAR(50)
	)
	
	CREATE TABLE #tmpProductBettype (
		ProductID INT
		,Bettype SMALLINT
		,RefTable TINYINT
	)
	
	CREATE TABLE #tmpMarginNonSport (
		ProductID INT
		,WinlossIBC DECIMAL(19,4)
		,TurnoverIBC DECIMAL(19,4)
	)
	
	CREATE TABLE #tmpBettypeGroup (
		Bettype INT
		,BettypeGroupID SMALLINT
	)
	
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	/*
		insert Dim for non-sport product
			#tmpProductBettype
			#tmpProductSetting
	*/
	;WITH CTE_Product_Bettype AS (
		SELECT DISTINCT pb.ProductID
			,pb.Bettype
		FROM DBWH.bodb_account.dbo.Product_Bettype AS pb WITH (NOLOCK)
	)
	,CTE_Bettype AS (
		SELECT DISTINCT typeid AS Bettype
			,CASE WHEN SourceTable = 'bettransRNG' THEN 1
				WHEN SourceTable = 'bettransLC' THEN 2
				ELSE 3
				END AS RefTable
		FROM DBWH.bodb_account.dbo.Bettype WITH (NOLOCK)
	)
	INSERT INTO #tmpProductBettype (
		ProductID
		,Bettype
		,RefTable
	)
	SELECT DISTINCT pb.ProductID
		,pb.Bettype
		,b.RefTable
	FROM CTE_Product_Bettype AS pb
		INNER JOIN CTE_Bettype AS b ON pb.Bettype = b.Bettype
	WHERE pb.Bettype IN (
			SELECT DISTINCT Bettype
			FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
			WHERE isTest IN (0,@isTest)
				AND (ProductID NOT IN (1,37) --exclude Sportsbook and Saba Promotion
					OR SubProduct IN ('Bet Builder')
				)
		)
	
	/*Special non-sport product*/
	;WITH CTE_Special AS (
		SELECT DISTINCT pb.ProductID
			,CONVERT(VARCHAR(20),'OTHERS') AS ProductGroup
			,CONVERT(VARCHAR(20),'BetB') AS ProductShortName --Include Bet Builder into [OTHERS] group; show 'BetB'
		FROM #tmpProductBettype AS pb WITH (NOLOCK)
			INNER JOIN bodb02.dbo.SportBettypeMatrix AS sb WITH (NOLOCK) ON pb.Bettype = sb.Bettype
		WHERE sb.SubProduct IN ('Bet Builder')
			AND sb.isTest IN (0,@isTest)
	)
	,CTE_Hardcode AS (
		SELECT ProductID
			,ProductGroup
			,ProductShortName
		FROM ( VALUES
			----------LC----------
			(21,'LC','AB') --Allbet
			,(45,'LC','AE') --AE Sexy
			,(12,'LC','GoldD') --Gold Deluxe
			,(39,'LC','SA') --SA Gaming
			,(52,'LC','ION') --ION
			,(46,'LC','IBC') --IBCBet Live Casino
			,(47,'LC','BBIN') --BBIN
			,(11,'LC','AG') --AG Casino
			,(51,'LC','WM') --WM
			,(59,'LC','GDG') --GDG
			,(57,'LC','BG') --BG
			,(65,'LC','PPLC') --PP Live Casino
			,(70,'LC','FGG') --FGG
			----------RNG----------
			,(42,'RNG','SABAG') --SABA.games
			,(6,'RNG','SabaC') --Saba Casino
			,(34,'RNG','Arca') --Arcadia Gaming
			,(32,'RNG','PP') --PP
			,(40,'RNG','TabG') --Table Game
			,(38,'RNG','VirtG') --Virtual Games
			,(22,'RNG','Macau') --Macau Games
			,(36,'RNG','SG') --SG
			,(50,'RNG','FunkyG') --Funky Games
			,(24,'RNG','FW') --Fishing World
			,(55,'RNG','PGSoft') --PG Soft
			,(56,'RNG','Joker') --Joker
			,(60,'RNG','MaxG') --MaxGame
			,(61,'RNG','HB') --Habanero
			,(62,'RNG','CG') --CG
			,(66,'RNG','SABAG')--Vgaming - Combine in SABA.games
			,(67,'RNG','AP') --AdvantPlay
			,(68,'RNG','APMini') --AdvantPlay Mini
			,(72,'RNG','SEAL') --Seal Entertainment
			,(73,'RNG','MG') --MG-RNG
			----------LOT/KENO----------
			,(8,'LOT/KENO','Mkeno') --RNG Keno
			,(3,'LOT/KENO','NG') --Number Game -Combine NumG, Happy 5, Happy 5 LG into Number Game
			,(28,'LOT/KENO','MLot') --Lottery
			,(23,'LOT/KENO','NG2') --NG2
			,(43,'LOT/KENO','To4D') --Togel 4D
			,(63,'LOT/KENO','SLot') --Sports Lottery
			----------OTHERS----------
			,(27,'OTHERS','VS2') --Virtual Sports 2
			,(5,'OTHERS','VS') --Virtual Sports
			,(15,'OTHERS','CB') --Colossus Bets
			,(31,'OTHERS','EX') --Exchange
			,(49,'OTHERS','VS3') --Virtual Sports 3
			,(69,'OTHERS','BTC') --Bitcoin
			-- ,('Bet Builder','OTHERS','BetB')
		) h (ProductID, ProductGroup, ProductShortName)
	)
	INSERT INTO #tmpProductSetting (
		ProductID
		,ProductGroup
		,ProductShortName
	)
	SELECT DISTINCT pb.ProductID
		,ISNULL(s.ProductGroup,ISNULL(h.ProductGroup,'OTHERS')) AS ProductGroup
		,ISNULL(s.ProductShortName,ISNULL(h.ProductShortName,ISNULL(p.ProductPrefix,'Others'))) AS ProductShortName
	FROM #tmpProductBettype AS pb WITH (NOLOCK)
		LEFT JOIN CTE_Special AS s ON pb.ProductID = s.ProductID
		LEFT JOIN CTE_Hardcode AS h ON pb.ProductID = h.ProductID
		LEFT JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON pb.ProductID = p.ProductID
	
	--make sure no dup ProductID--
	;WITH CTE_Dup AS (
		SELECT ProductID
			,ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY ProductID) AS rn
		FROM #tmpProductSetting
	)
	DELETE
	FROM CTE_Dup
	WHERE rn > 1
		OR ProductID NOT IN (
			SELECT DISTINCT ProductID
			FROM #tmpProductBettype
		)
	
	CREATE CLUSTERED INDEX CIX_tmpProductBettype ON #tmpProductBettype ( Bettype )
	CREATE CLUSTERED INDEX CIX_tmpProductSettings ON #tmpProductSetting ( ProductID )
	
	INSERT INTO #tmpBettypeGroup (
		Bettype
		,BettypeGroupID
	)
	SELECT Bettype
		,BettypeGroupID
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID in ( 6, 10 ) --Prize Tickets & Contribution Tickets
	GROUP BY Bettype
		,BettypeGroupID
	
	CREATE CLUSTERED INDEX CIX_tmpBettypeGroup ON #tmpBettypeGroup ( Bettype, BettypeGroupID )
	
	/*===================================================*/
	SELECT @MaxBettype = MAX(Bettype)
	FROM #tmpProductBettype
	WHERE RefTable = 3
	
	SELECT @MinTransID_RNG = MIN(TransID)
		,@MaxTransID_RNG = MAX(TransID)
	FROM bodb02.dbo.BettransRNG WITH (NOLOCK)
	WHERE winlostdate = @WLDate

	SELECT @MinTransID_LC = MIN(TransID)
		,@MaxTransID_LC = MAX(TransID)
	FROM bodb02.dbo.BettransLC WITH (NOLOCK)
	WHERE winlostdate = @WLDate
	
	;WITH CTE_HWL AS (
		SELECT pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR
			--------------------------------------------------------------------------
			,SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				  WHEN bg.BettypeGroupID = 10 THEN b.swinlost + b.mwinlost + b.awinlost --Contribution Tickets
				  ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END)  * b.actualrate) AS WinlossIBC
			,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL 
			,SUM(b.scomm * b.actualrate) AS CommissionS
			,CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm
			--------------------------------------------------------------------------
			,SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC
		,SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
				ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
			END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettrans AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb (NOLOCK) ON b.bettype = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.Bettype = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113) --Won, Lose
			AND b.currency <> 20
			AND pb.RefTable = 3
			AND b.bettype <= @MaxBettype
			AND b.MatchID >= 0
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9, 6))
			
		UNION ALL
		
		SELECT pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR
			------------------------------------------------------------------------
			,SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				  WHEN bg.BettypeGroupID = 10 THEN b.swinlost + b.mwinlost + b.awinlost --Contribution Tickets
				  ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END) * b.actualrate) AS WinlossIBC
			,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL 
			,SUM(b.scomm * b.actualrate) AS CommissionS
			,CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm
			----------------------------------------------------------------------
			,SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC
			,SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
					ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
				END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettransLC AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113) --Won, Lose
			AND b.currency <> 20
			AND pb.RefTable = 2
			AND b.transID BETWEEN @MinTransID_LC AND @MaxTransID_LC
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
			
		UNION ALL
		
		SELECT pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR
			----------------------------------------------------------------------
			,SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + b.swinlost + b.mwinlost + b.awinlost --Contribution Tickets
				  ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END) * b.actualrate) AS WinlossIBC
			,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL 
			,SUM(b.scomm * b.actualrate) AS CommissionS
			,CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm
			----------------------------------------------------------------------
			,SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC
			,SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
					ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
				END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettransRNG AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113) --Won, Lose
			AND b.currency <> 20
			AND pb.RefTable = 1
			AND b.transID BETWEEN @MinTransID_RNG AND @MaxTransID_RNG
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
	)
	INSERT INTO #tmpMarginNonSport (
		ProductID
		,WinlossIBC
		,TurnoverIBC
	)
	SELECT ProductID
		,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
		,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
			* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
			) AS TurnoverIBC
	FROM CTE_HWL AS h
	GROUP BY ProductID
	
	CREATE CLUSTERED INDEX CIX_tmpMarginNonSport ON #tmpMarginNonSport ( ProductID )

	/*
		Group by [ProductGroup], Order and Return result
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
			LEFT JOIN #tmpProductSetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY CASE WHEN h.ProductGroup = 'LC' THEN 2
				WHEN h.ProductGroup = 'RNG' THEN 3
				WHEN h.ProductGroup = 'LOT/KENO' THEN 4
				ELSE 5
				END
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
			,ISNULL(h.ProductShortName,'Others') AS GroupName
			,SUM(TurnoverIBC) AS TurnoverIBC
			,(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END) AS Margin
		FROM #tmpMarginNonSport AS m WITH (NOLOCK)
			LEFT JOIN #tmpProductSetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY CASE WHEN h.ProductGroup = 'LC' THEN 8
				WHEN h.ProductGroup = 'RNG' THEN 10
				WHEN h.ProductGroup = 'LOT/KENO' THEN 12
				ELSE 14
				END
			,ISNULL(h.ProductShortName,'Others')
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
	
	DROP TABLE #tmpProductSetting
	DROP TABLE #tmpProductBettype
	DROP TABLE #tmpMarginNonSport
	DROP TABLE #tmpBettypeGroup
END

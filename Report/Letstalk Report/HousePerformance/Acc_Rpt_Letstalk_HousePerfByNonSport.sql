/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
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
		20221010@Ned.Le: Email/Letstalk reports - Incorporate Player Tips product (#180653)
		20230222@Roy: Email/Letstalk Reports - Move Table Games from RNG section to LOT/KENO area (#184192)
		20230518@Roy: Email/Letstalk - Jili - Incorporate new product (#182863)
		20230518@Roy: Letstalk/Email - YeeBet - Incorporate new product (#186481)
		20230719@Roy: Email/Letstalk - LG Virtual Sports - Incorporate new product (#189204)
		20230824@Roy: Letstalk Report ID 34 - Change the rule to show Exchange product (#193132)
		20230829@Roy: Letstalk Reports - Support to show Exchange Product statistics every 2 hours for today (#181348)
		20231116@Roy: Email/Letstalk - WE Live Casino - Integrate new product (#195889)
		20240223@Roy: Email/Letstalk Reports - Incorporate Live22 product (#198035)
		20240223@Roy: Email/Letstalk - Virtual Sports 4 - Edge Gaming (#198628)
		20240229@Roy: AG Casino - Email/Letstalk Reports - Add promotion & Jackpot bet type (#200523)
		20240308@Cherry: Integrate UU Slots (#192594)
		20240308@Cherry: Integrate Yolo Play (#201590)
		20240417@Cherry: Integrate Saba xD (#202707)
		20240417@Cherry: Integrate Saba Coins (#203365)
		20240628@Cherry: Integrate FA CHAI (#206635)
		20240628@Cherry: Integrate Fast Spin (#206142)
		20240722@Cherry: Integrate Virtual Sports 5 (#206922), Nextspin (#199988)
		20240916@Cherry: Integrate ON Casino (#210031)
		20241020@Cherry: Integrate GPI (#207012), Playtech(#210555)
		20241104@Cherry: Exclude VS6 (#212749)
		20241122@Cherry: Categorize products (#213102)
		20241122@Cherry: Remove Exchange and Bet Builder (#212829)
		20241202@Cherry: Integrate GPI Live Casino (#213493)
		20241219@Cherry: hotfix (#215548)
		20241224@Cherry: Integrate Saba Keno (#214759)
		20240102@Cherry: Integrate PLAYSTAR (#208029)
		20240206@Cherry: Add VS6 (#217593)
		20250218@Cherry: Integrate ASKMESLOT (#216979)
		20250318@Cherry: Integrate Funky Games (#220052) 
		20250327@Cherry: Integrate HOTDOG (#219713)
		20250404@Cherry: Integrate Microgaming Live (#222626)
		20250411@Cherry: Integrate VS7 (#219279)
		20250424@Cherry: Integrate Playtech Live (#224580)
		20250424@Cherry: Integrate RichGaming (#224308)
		20250512@Cherry: Integrate W Casino (#225846)
		20250602@Cherry: Integrate AI Gaming (#229205)
		20250602@Cherry: Integrate ClotPlay (#229206)
		20250616@Cherry: Offer Jackpot contribution for bettransLC (#225847)
		20250701@Cherry: Integrate GPI Lottery (#231786)
		20250722@Cherry: Integrate ODINGAMING (#219228)
		20250814@Cherry: Integrate Smartsoft (#236071)
		20250825@Cherry: Integrate OFA Live (#236741)
		20250905@Cherry: Integrate Bgaming (#237204)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfByNonSport
			@ExecTime4GMT = '2022-06-29 03:00:00'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Title VARCHAR(50),
		@Footer VARCHAR(20) = 'ID #34',
		@DayOffset INT,
		@WLDate SMALLDATETIME		

	SET @WLDate = DATEADD(dd, DATEDIFF(dd, 0, @ExecTime4GMT), @DayOffset)
	SET @DayOffset = (
			CASE 
				WHEN DATEPART(HOUR, @ExecTime4GMT) >= 2
					THEN 0
				ELSE - 1
				END
			)	

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
	
	CREATE TABLE #tmpProductBettype (
		ProductID INT,
		Bettype SMALLINT,
		RefTable TINYINT,
	)
	
	CREATE TABLE #tmpProductSetting (
		ProductID INT,
		ProductGroup VARCHAR(20),
		GroupOrder INT,
		ProductShortName VARCHAR(50)
	)		

	CREATE TABLE #tmpBettypeGroup (
		Bettype INT,
		BettypeGroupID SMALLINT
	)
	
	CREATE TABLE #tmpMarginNonSport (
		ProductID INT,
		WinlossIBC DECIMAL(19,4),
		TurnoverIBC DECIMAL(19,4)
	)		
	
	DECLARE @MaxBettype SMALLINT
	DECLARE	@isTest BIT = 0
	DECLARE	@SQLStr VARCHAR(MAX) = ''
	DECLARE	@MinTransID_RNG BIGINT
	DECLARE	@MinTransID_LC BIGINT
	DECLARE	@MaxTransID_RNG BIGINT
	DECLARE	@MaxTransID_LC BIGINT
	
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
				AND ProductID NOT IN (1,37,74,81,31) --exclude Sportsbook and Saba Promotion and Player Tips, Saba Coins
				AND SubProduct NOT IN ('Bet Builder')
		)
	
	/*Special non-sport product*/
	;WITH CTE_Hardcode AS (
		SELECT ProductID
			,ProductShortName
		FROM ( VALUES
			(21,'AB') --Allbet
			,(45,'AE') --AE Sexy
			,(12,'GoldD') --Gold Deluxe
			,(39,'SA') --SA Gaming
			,(52,'ION') --ION
			,(46,'IBC') --IBCBet Live Casino
			,(47,'BBIN') --BBIN
			,(11,'AG') --AG Casino
			,(51,'WM') --WM
			,(59,'GDG') --GDG
			,(57,'BG') --BG
			,(65,'PPLC') --PP Live Casino
			,(70,'FGG') --FGG
			,(76,'YeeBet')
			,(80,'WE LC')
			,(96,'ONCasino')
			,(42,'SABAG') --SABA.games
			,(6,'SabaC') --Saba Casino
			,(34,'Arca') --Arcadia Gaming
			,(32,'PP') --PP
			,(38,'VirtG') --Virtual Games
			,(22,'Macau') --Macau Games
			,(36,'SG') --SG
			,(50,'FunkyG') --Funky Games
			,(24,'FW') --Fishing World
			,(55,'PGSoft') --PG Soft
			,(56,'Joker') --Joker
			,(60,'MaxG') --MaxGame
			,(61,'HB') --Habanero
			,(62,'CG') --CG
			,(66,'SABAG')--Vgaming - Combine in SABA.games
			,(67,'AP') --AdvantPlay
			,(68,'APMini') --AdvantPlay Mini
			,(72,'SEAL') --Seal Entertainment
			,(73,'MG') --MG-RNG
			,(75,'Jili')
			,(79,'Live22')
			,(78,'UUS') -- UU Slots
			,(84,'YoloP') 
			,(86,'SABAxD') 
			,(87,'FastSpin')
			,(89,'FACHAI')
			,(85,'Nextspin')
			,(48,'GPI')
			,(100,'Playtech')
			,(40,'TabG') 
			,(8,'Mkeno')
			,(3,'NG') 
			,(28,'MLot') 
			,(23,'NG2') 
			,(43,'To4D') 
			,(63,'SLot')
			,(27,'VS2')
			,(5,'VS') 
			,(15,'CB') 
			,(49,'VS3(Old)')
			,(69,'BTC') 
			,(77,'VS3') 
			,(83,'VS4') 
			,(88,'VS5') 
			,(71,'VS6') 
			,(106,'VS7') 
			,(90,'GPI LC')
			,(102,'SABAG')
			,(91,'PLAYS')
			,(103,'ASKME')
			,(104,'FunkyG') 
			,(95,'HOTDOG')
			,(107,'MG LC')
			,(101,'PlayT LC')
			,(108,'RichG')
			,(98,'W LC')
			,(109,'ClotP')
			,(110,'AIG')
			,(84,'GPILotte')
			,(105,'ODIN')
			,(99,'SmartS')
			,(113,'OFA LC')
			,(114,'BGame')
		) h (ProductID, ProductShortName)
	)
	,CTE_ProductGroup AS (
		SELECT DISTINCT ProductID AS ProductID
			,ProductCategory AS ProductCategory
			,CategoryOrder AS CategoryOrder
		FROM DBWH.bodb_Account.dbo.vw_NonSportSetting WITH(NOLOCK)
		WHERE ProductCategory <> 'Closed'
	)
	INSERT INTO #tmpProductSetting (
		ProductID
		,ProductGroup
		,GroupOrder
		,ProductShortName
	)
	SELECT DISTINCT pb.ProductID
		,pg.ProductCategory AS ProductGroup
		,pg.CategoryOrder AS GroupOrder
		,ISNULL(h.ProductShortName,p.ProductPrefix) AS ProductShortName
	FROM #tmpProductBettype AS pb WITH (NOLOCK)
		LEFT JOIN CTE_Hardcode AS h ON pb.ProductID = h.ProductID
		LEFT JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON pb.ProductID = p.ProductID
		INNER JOIN CTE_ProductGroup AS pg ON pb.ProductID = pg.ProductID
	--make sure no dup ProductID--
	;WITH CTE_Dup AS (
		SELECT ProductID
			,ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY ProductID) AS rn
		FROM #tmpProductSetting
	)
	DELETE d
	FROM CTE_Dup d
	WHERE rn > 1
		OR NOT EXISTS (SELECT 1 FROM #tmpProductBettype p
					WHERE d.ProductID = p.ProductID)
	
	CREATE CLUSTERED INDEX CIX_tmpProductBettype ON #tmpProductBettype ( Bettype )
	CREATE CLUSTERED INDEX CIX_tmpProductSettings ON #tmpProductSetting ( ProductID )

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
	
	INSERT INTO #tmpBettypeGroup (
		Bettype
		,BettypeGroupID
	)
	SELECT Bettype
		,BettypeGroupID
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID in (6, 10) --Prize Tickets & Contribution Tickets
	GROUP BY Bettype
		,BettypeGroupID
	
	CREATE CLUSTERED INDEX CIX_tmpBettypeGroup ON #tmpBettypeGroup ( Bettype, BettypeGroupID )			
	
	;WITH CTE_HWL AS (
		SELECT pb.ProductID,
			CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR,
			SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				--Contribution Tickets: normal in [bettransRnG] - except(1802) - special in [bettrans] (ContributionStake3rd = ISNULL(betid, 0)/100000000)
					WHEN bg.BettypeGroupID = 10 THEN (ISNULL(b.betid, 0)/100000000.0) + b.swinlost + b.mwinlost + b.awinlost
					ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END) * b.actualrate) AS WinlossIBC,
			SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL,
			SUM(b.scomm * b.actualrate) AS CommissionS,
			CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm,
			SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC,
		SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
				ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
			END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettrans AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb (NOLOCK) ON b.bettype = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.Bettype = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113) 
			AND b.currency <> 20
			AND pb.RefTable = 3
			AND b.bettype <= @MaxBettype
			AND b.MatchID >= 0
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9, 6))
			
		UNION ALL
		
		SELECT pb.ProductID,
			CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR,
			SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + b.swinlost + b.mwinlost + b.awinlost --Contribution Tickets
				  ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END) * b.actualrate) AS WinlossIBC,
			SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL, 
			SUM(b.scomm * b.actualrate) AS CommissionS,
			CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm,
			SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
					ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
				END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettransLC AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113) 
			AND b.currency <> 20
			AND pb.RefTable = 2
			AND b.transID BETWEEN @MinTransID_LC AND @MaxTransID_LC
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
			
		UNION ALL
		
		SELECT pb.ProductID,
			CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR,
			SUM((CASE WHEN bg.BettypeGroupID = 6 THEN 0 --Prize Tickets
				  WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + b.swinlost + b.mwinlost + b.awinlost --Contribution Tickets
				  ELSE (b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost
				END) * b.actualrate) AS WinlossIBC,
			SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * CAST(b.epositiontaking AS DECIMAL(10, 8)) * b.actualrate
				END) AS ExtraWL, 
			SUM(b.scomm * b.actualrate) AS CommissionS,
			CAST(SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * CAST(b.epositiontaking AS DECIMAL(10, 8)) / (1 - b.tpositiontaking)
				END) * b.actualrate) AS DECIMAL(19, 8))AS ExtraComm,
			SUM( (CASE WHEN pb.ProductID = 1 THEN ABS(b.stake) ELSE b.stake END)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
					ELSE (CASE WHEN pb.ProductID = 1 THEN ABS(stake) ELSE stake END) * CAST(b.epositiontaking AS DECIMAL(10, 8))
				END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettransRNG AS b WITH (NOLOCK)
			LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
			LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (112, 113)
			AND b.currency <> 20
			AND pb.RefTable = 1
			AND b.transID BETWEEN @MinTransID_RNG AND @MaxTransID_RNG
		GROUP BY pb.ProductID
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
	)
	INSERT INTO #tmpMarginNonSport (
		ProductID,
		WinlossIBC,
		TurnoverIBC
	)
	SELECT ProductID,
		SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC,
		SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
			* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
			) AS TurnoverIBC
	FROM CTE_HWL AS h
	GROUP BY ProductID
	
	CREATE CLUSTERED INDEX CIX_tmpMarginNonSport ON #tmpMarginNonSport ( ProductID )
	
	;WITH CTE_SubTotal AS (
		SELECT h.GroupOrder AS GroupID,
			'T ' + h.ProductGroup AS GroupName,
			SUM(TurnoverIBC) AS TurnoverIBC,
			SUM(WinlossIBC) AS WinlossIBC,
			CONVERT(DECIMAL(10,6),(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END)) AS Margin
		FROM #tmpMarginNonSport AS m WITH (NOLOCK)
			INNER JOIN #tmpProductSetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY h.GroupOrder,
			'T ' + h.ProductGroup
	)
	,CTE_Total AS (
		SELECT 0 AS GroupID,
			'GRAND TOTAL' AS GroupName,
			SUM(TurnoverIBC) AS TurnoverIBC,
			CONVERT(DECIMAL(10,6),(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END)) AS Margin
		FROM CTE_SubTotal
	)
	,CTE_Product AS (
		SELECT h.GroupOrder*1000+1 AS GroupID,
			h.ProductShortName AS GroupName,
			SUM(TurnoverIBC) AS TurnoverIBC,
			CONVERT(DECIMAL(10,6),(CASE WHEN SUM(ISNULL(TurnoverIBC,0)) = 0 THEN 0
				ELSE SUM(ISNULL(WinlossIBC,0)) / SUM(ISNULL(TurnoverIBC,0))
			END)) AS Margin
		FROM #tmpMarginNonSport AS m WITH (NOLOCK)
			INNER JOIN #tmpProductSetting AS h WITH (NOLOCK) ON m.ProductID = h.ProductID
		GROUP BY h.GroupOrder*1000+1,
			h.ProductShortName
	)
	
	SELECT DISTINCT GroupOrder * 1000 AS GroupID,
		ProductGroup AS GroupName,
		NULL AS TurnoverIBC,
		NULL AS Margin,
		'' AS ExtraInfo
	FROM #tmpProductSetting		

	UNION ALL
	SELECT GroupID,
		GroupName,
		TurnoverIBC,
		Margin,
		'' AS ExtraInfo
	FROM CTE_Total
	
	UNION ALL
	
	SELECT GroupID,
		GroupName,
		TurnoverIBC,
		Margin,
		'' AS ExtraInfo
	FROM CTE_SubTotal

	UNION ALL
	
	SELECT GroupID,
		GroupName,
		TurnoverIBC,
		Margin,
		'' ExtraInfo
	FROM CTE_Product
	ORDER BY GroupID ASC,
		TurnoverIBC DESC
	
	SELECT @Title AS Title,
		@Footer AS Footer
	
	DROP TABLE #tmpProductSetting
	DROP TABLE #tmpProductBettype
	DROP TABLE #tmpBettypeGroup
	DROP TABLE #tmpMarginNonSport

END

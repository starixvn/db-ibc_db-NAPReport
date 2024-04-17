/*<info serverAlias="DBWH-bodb_dwrs" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfBySportLic
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220629
	Task: Get House Performance By Sport Lic At Exec Time (Letstalk #36)
	DB: DBACC.bodb02

	Revisions:
		20220629@Roy: Letstalk Reports - Implement Non-Sports TO & Margin and Licensee Turnover Margin (#174679)
		20221206@Roy: Email/Letstalk Reports - Incorporate Saba E-Sports PinGoal (#181261)
		20221219@Roy: Letstalk Report ID #36 - Refactor sp code (#181303)
		20230705@Roy: Email/Letstalk Reports - Incorporate Saba Tennis (#190458)
		20230824@Roy: Letstalk Report ID 34 - Change the rule to show Exchange product (#193132)
		20230829@Roy: Letstalk Reports - Support to show Exchange Product statistics every 2 hours for today (#181348)
		20231114@Roy: NAP Reports - Move SEAL8888 into Credit Group (#195730)
		20231116@Roy: Email/Letstalk - WE Live Casino - Integrate new product (#195889)
		20240223@Roy: Email/Letstalk Reports - Incorporate Live22 product (#198035)
		20240223@Roy: Email/Letstalk - Virtual Sports 4 - Edge Gaming (#198628)
		20240227@Roy: Email/Letstalk Reports - Merge the settings of VS1 VS2 VS3 into Virtual Sports for Deposit (#199544)
		20240308@Cherry: Integrate UU Slots (#192594)
		20240308@Cherry: Integrate Yolo Play (#201590)
		20240417@Cherry: Integrate Saba xD (#202707)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
		For Exchange (https://nexdev.net/projects/owa/wiki/Exchange_Impact_On_LA)
			- Formular based on billing term (Letstalk #36): Licensing Fee = (Licensee WL - Member Charge Comm) * 12.5%
			- Real formula (Acc_Rpt_HouseNetIncome_Deposit): Licensing Fee = (Licensee WL * 12.5%) - (Licensee Charge Comm + Member Charge Comm)
				+ With Licensee Charge Comm = - Member Charge Comm * (1-12.5%)
	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_Letstalk_HousePerfBySportLic
			@ExecTime4GMT = '2022-06-29 03:00:00'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @DayOffset INT
		,@WLDate DATE
		,@Title VARCHAR(50)
		,@EX3rdName VARCHAR(50)
		,@VSMergeCutOffDate DATE = '2024-03-01'

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

		RETURN
	END
	
	DECLARE @SQLStr NVARCHAR(MAX)
		,@PartyIDs VARCHAR(MAX)
		,@ProductCodes VARCHAR(MAX)
	
	/*
		Create tmp tables
	*/
	CREATE TABLE #tmpProduct3rd (
		Product3rdID INT
		,ProductName VARCHAR(50)
		,ProductPrefix VARCHAR(10)
		,Enabled BIT
	)
	CREATE TABLE #tmpBetType (
		BetType INT
		,IsSB BIT
	)
	CREATE TABLE #tmpSBSports (
		SportGroup INT
	)
	CREATE TABLE #tmpOANDARate (
		ExchangeID INT
		,BaseCurrencyRate FLOAT
	)
	CREATE TABLE #tmpLicParty (
		LicenseeName VARCHAR(50)
		,PartyID INT
	)
	CREATE TABLE #tmpDepSuper (
		CustID INT
		,PartyID INT
	)
	CREATE TABLE #tmpChargeInfo (
		ChargeID INT
		,PartyID INT
		,Product3rdID INT
		,Rate FLOAT
		,BetType INT
		,ChargeType INT
	)
	CREATE TABLE #tmpChargeByCurr (
		ChargeID INT
		,CurrencyID INT
		,Rate FLOAT
	)
	CREATE TABLE #tmpSabaLG (
		LeagueGroupID INT
		,SabaType TINYINT
	)
	CREATE TABLE #tmpRawData (
		IsSB BIT
		,PartyID INT
		,Currency INT
		,Product3rdID INT
		,SportGroup SMALLINT
		,ProductGroup TINYINT
		,LiveIndicator BIT
		,SabaType TINYINT
		,TurnOver DECIMAL(19,4)
		,MemberWL DECIMAL(19,4)
		,OddsSpreadAdj DECIMAL(19,4)
		,BAComm DECIMAL(19,4)
		,FullContribution DECIMAL(19,4)
		,HouseContribution DECIMAL(19,4)
		,FreeBet DECIMAL(19,4)
	)
	CREATE TABLE #tmpFinal (
		GroupID INT
		,GroupName VARCHAR(50)
		,HouseTO DECIMAL(19,4)
		,HouseWL DECIMAL(19,4)
		,OrdNo FLOAT
	)
	CREATE TABLE #tmpEXBettrans (
		WLDate SMALLDATETIME
		,LiveIndicator BIT
		,IsBA BIT
		,ProductID INT
		,SportType INT
		,BetType INT
		,Status NVARCHAR(10)
		,SRecommend INT
		,CurrencyID INT
		,Stake DECIMAL(19,4)
		,Actual_Stake DECIMAL(19,4)
		,Winlost DECIMAL(19,4)
		,AWinlost DECIMAL(19,4)
		,MWinlost DECIMAL(19,4)
		,SWinlost DECIMAL(19,4)
		,PlayerComm DECIMAL(19,4)
		,Comm DECIMAL(19,4)
	)
	/*
		Get Dim data
	*/
	--3rd Product--
	SELECT @SQLStr = '
		SELECT ProductID
			,ProductName
			,ProductPrefix
			,Enabled
		FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK)
	'
	INSERT INTO #tmpProduct3rd (
		Product3rdID
		,ProductName
		,ProductPrefix
		,Enabled
	)
	EXEC (@SQLStr) AT DBEXT
	CREATE CLUSTERED INDEX tmpProduct3rd ON #tmpProduct3rd (Product3rdID)
	
	-------------------Format ProductName----------------
	UPDATE #tmpProduct3rd
	SET ProductName = (
		CASE WHEN ProductName = 'Number Game' THEN 'NumG'
			WHEN ProductName = 'Virtual Sports' THEN 'VirtSpo'
			WHEN ProductName = 'RNG Casino' THEN '1RNG'
			WHEN ProductName = 'RNG Keno' THEN 'MKeno'
			-- WHEN ProductName = 'Colossus Bets' THEN 'CB'
			WHEN ProductName = 'Allbet' THEN 'AllB'
			WHEN ProductName = 'Macau Games' THEN 'MacauG'
			-- WHEN ProductName = 'Fishing World' THEN 'FishW'
			-- WHEN ProductName = 'Cash Out' THEN 'CashO'
			WHEN ProductName = 'Virtual Sports 2' THEN 'VirtSpo2'
			WHEN ProductName = 'Lottery' THEN 'MLotte'
			WHEN ProductName = 'Arcadia Gaming' THEN 'ArcaGam'
			WHEN ProductName = 'PG Soft' THEN 'PGSoft'
			WHEN ProductName = 'Virtual Games' THEN 'VirtG'
			WHEN ProductName = 'Table Game' THEN 'TableG'
			WHEN ProductName = 'Saba.games' THEN 'SabaG'
			WHEN ProductName = 'Togel 4D' THEN 'I4D'
			WHEN ProductName = 'PP' THEN 'PragP'
			WHEN ProductName = 'SG' THEN 'SpadeG'
			WHEN ProductName = 'IBCBet Live Casino' THEN 'IBCLC'
			WHEN ProductName = 'SA Gaming' THEN 'SAG'
			WHEN ProductName = 'RNG War' THEN 'RNGWar'
			-- WHEN ProductName = 'Gold Deluxe' THEN 'GoldD'
			WHEN ProductName = 'AG Casino' THEN 'AG'
			WHEN ProductName = 'Sports Lottery' THEN 'SportsLott'
			WHEN ProductName = 'PP Live Casino' THEN 'PP LC'
			WHEN ProductName = 'AE Sexy' THEN 'AESexy'
			WHEN ProductName = 'Habanero' THEN 'Haban'
			WHEN ProductName = 'AdvantPlay' THEN 'AdPlay'
			WHEN ProductName = 'AdvantPlay Mini' THEN 'AdPlayMini'
			WHEN ProductName = 'Virtual Sports 3' THEN 'VirtSpo3'
			WHEN ProductName = 'Funky Games' THEN 'FunkyG'
			WHEN ProductName = 'Saba Casino' THEN 'SabaCas'
			WHEN ProductName = 'WE Live Casino' THEN 'WE LC'
			-- WHEN ProductName = 'Live22' THEN 'Live22' --the same - no need
			WHEN ProductName = 'Virtual Sports 4' THEN 'VirtSpo4'
			WHEN ProductName = 'SEAL Entertainment' THEN 'SealE'
			WHEN ProductName = 'UU Slots' THEN 'UUS'
			WHEN ProductName = 'Yolo Play' THEN 'YoloP'
			WHEN ProductName = 'SABA xD' THEN 'SABAxD'
			ELSE ProductName END)
	
	SELECT @EX3rdName = rd.ProductName
	FROM #tmpProduct3rd AS rd WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON p.ProductPrefix = rd.ProductPrefix
	WHERE p.ProductID = 31
	
	--OANDA Rate--
	SELECT @SQLStr = '
		SELECT ExchangeID
			,BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(''' + CONVERT(VARCHAR, @WLDate, 23) + ''', ''' + CONVERT(VARCHAR, @WLDate, 23) + ''', ''CNY'')
	'
	INSERT INTO #tmpOANDARate (
		ExchangeID
		,BaseCurrencyRate
	)
	EXEC (@SQLStr) AT DBEXT
	
	--Get BetTypes of SB + NS--
	INSERT INTO #tmpBetType (
		BetType
		,IsSB
	)
	SELECT DISTINCT BetType
		,1 AS IsSB
	FROM bodb02.dbo.SportBetTypeMatrix WITH (NOLOCK)
	WHERE ProductID = 1
		AND BetType NOT BETWEEN 801 AND 806
		AND BetType NOT BETWEEN 901 AND 904
		AND BetType <> 38
	
	UNION ALL
	
	SELECT DISTINCT s.BetType
		,0 AS IsSB
	FROM bodb02.dbo.SportBetTypeMatrix AS s WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON p.ProductID = s.ProductID
		LEFT JOIN #tmpProduct3rd AS d WITH (NOLOCK) ON p.ProductPrefix = d.ProductPrefix
	WHERE (p.Enabled = 1 OR d.Enabled = 1 )
		AND (s.ProductID NOT IN (1,12,15,24,25,37,59,74) ---exclude SB(1),Gold Deluxe(12),Colossus Bets(15),Fishing World(24),CO Old Model(25),Saba Promotion(37),GDG(59),Player Tips(74)
			OR (s.ProductID = 1 AND s.SubProduct IN ('Bet Builder','MG-SuperLive'))
		)
	CREATE CLUSTERED INDEX tmpBetType ON #tmpBetType (BetType)
	
	--LicParty--
	SELECT @SQLStr = '
		SELECT l.LicenseeName
			,ISNULL(p.PartyID,0) AS PartyID
		FROM bodb_Licensee.dbo.Licensees AS l WITH (NOLOCK)
			LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.OldRefID = l.LicenseeID AND p.PartyType = 1
	'
	INSERT INTO #tmpLicParty (
		LicenseeName
		,PartyID
		)
	EXEC (@SQLStr) AT DBEXT
	
	--Deposit super--
	INSERT INTO #tmpDepSuper (
		CustID
		,PartyID
	)
	SELECT c.CustID
		,ISNULL(p.PartyID, 0) AS PartyID
	FROM bodb_account.dbo.vw_Dep_CustSuper c WITH (NOLOCK) --use view to exclude some special site
		INNER JOIN #tmpLicParty p WITH (NOLOCK) ON p.LicenseeName = c.site
	WHERE c.currency <> 20
	CREATE CLUSTERED INDEX tmpDepSuper ON #tmpDepSuper (CustID)
	
	-- Get party list--
	SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR, PartyID)
	FROM #tmpDepSuper
	WHERE PartyID IS NOT NULL
	GROUP BY PartyID

	--Get product list of SB
	SELECT @ProductCodes = 'SB,BA'
	--Get product list of NS
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + p.ProductPrefix
	FROM #tmpBetType AS bt
		INNER JOIN bodb02.dbo.SportBetTypeMatrix AS s WITH (NOLOCK) ON bt.BetType = s.BetType
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON p.ProductID = s.ProductID
	WHERE bt.IsSB = 0
	GROUP BY p.ProductPrefix
	
	/*
		Hard code for merge Virtual Sports
		- Old: Have Rate foreach [Virtual Sports] - 1,2,3,4
		- New: Only get Rate of [Virtual Sports] - the rest (2,3,4..) will base on 1
		
		
		IF EXISTS any [Virtual Sports]
			=> Add 'VS' to @ProductCodes to get charge rate
	*/
	DECLARE @VS3rd_FromID INT
		,@VS3rd_FromCode NVARCHAR(50)
	DECLARE @VS3rd_To TABLE (Product3rdID INT)
	
	SELECT @VS3rd_FromID = rd.Product3rdID
		,@VS3rd_FromCode = p.ProductPrefix
	FROM #tmpProduct3rd AS rd WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON p.ProductPrefix = rd.ProductPrefix
	WHERE p.ProductID = 5 --VS
	
	INSERT INTO @VS3rd_To (Product3rdID)
	SELECT DISTINCT rd.Product3rdID
	FROM #tmpProduct3rd AS rd WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON p.ProductPrefix = rd.ProductPrefix
		INNER JOIN bodb02.dbo.SportBetTypeMatrix AS s WITH (NOLOCK) ON p.ProductID = s.ProductID
		INNER JOIN #tmpBetType AS bt ON bt.BetType = s.BetType AND bt.IsSB = 0
	WHERE p.ProductID IN (27, 49, 77, 83)--VS2 (27) / VS3 Old (49) / VS3 (77) / VS4 (83)
		
	IF @WLDate >= @VSMergeCutOffDate --over Cut Off Date
		AND EXISTS (
			SELECT 1
			FROM @VS3rd_To
		)
	BEGIN
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + @VS3rd_FromCode
	END

	-- Get charge rate of 3rd Products--
	SELECT @SQLStr = '
		SELECT DISTINCT ci.ChargeID
			,ci.PartyID
			,ci.ProductID AS Product3rdID
			,ci.DI_Rate AS Rate
			,ci.BetType
			,ci.ChargeType
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(''' + @PartyIDs + ''', ''' + CONVERT(VARCHAR, @WLDate, 23) + ''', ''' + CONVERT(VARCHAR, @WLDate, 23) + ''', ''' + @ProductCodes + ''', ''OA'', 1) AS ci
		WHERE ci.DI_Rate > 0
			AND (ci.ChargeType = 1
				OR (ci.ChargeType = 12 AND ci.ProductID = 39)
			)
	'
	INSERT INTO #tmpChargeInfo (
		ChargeID
		,PartyID
		,Product3rdID
		,Rate
		,BetType
		,ChargeType
		)
	EXEC (@SQLStr) AT DBEXT
	
	-- Get charge rate by Currency--
	;WITH CTE_Charge AS (
		SELECT ChargeID
		FROM #tmpChargeInfo
		GROUP BY ChargeID
	)
	,CTE_IDs AS (
		SELECT (
				STUFF((
						SELECT ',' + CONVERT(VARCHAR, ChargeID)
						FROM CTE_Charge
						FOR XML PATH('')
						), 1, 2, '')
				) AS ChargeIDs
		)
	SELECT @SQLStr = '
		SELECT DISTINCT pc.ChargeID
			,pc.CurrencyID
			,pc.Rate
		FROM bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK)
		WHERE ChargeID IN (' + ChargeIDs + ')'
	FROM CTE_IDs

	INSERT INTO #tmpChargeByCurr (
		ChargeID
		,CurrencyID
		,Rate
	)
	EXEC (@SQLStr) AT DBEXT
	
	/*
		Hard code for merge [Virtual Sports]
			Case #1: IF EXISTS ChargeInfo of ANY VS2,3,4
						THEN
							1. UPDATE #tmpChargeInfo 	- update charge rate by PartyID (from VS to VS 2,3,4)
							2. UPDATE #tmpChargeByCurr 	- update charge rate by ChargeID (of PartyID) / CurrencyID (from VS to VS 2,3,4)
			Case #2: IF NOT EXISTS ChargeInfo of ALL VS2,3,4
						THEN
							1. CLONE #tmpChargeInfo - charge rate by PartyID (from VS to VS 2,3,4)
							2. NO action #tmpChargeByCurr - EXISTED of VS
	*/
	-----------------Case #1 - EXISTS ChargeInfo of VS2,3,4----------------
	IF @WLDate >= @VSMergeCutOffDate --over Cut Off Date
		AND EXISTS (
			SELECT 1
			FROM #tmpChargeInfo AS c
				INNER JOIN @VS3rd_To AS rd ON rd.Product3rdID = c.Product3rdID
		)
	BEGIN
		--update charge by ProductID / PartyID
		;WITH CTE_VSRate AS (
			SELECT c.PartyID
				,c.Rate AS VS_Rate
			FROM #tmpChargeInfo AS c WITH (NOLOCK)
			WHERE Product3rdID = @VS3rd_FromID
		)
		UPDATE c
		SET c.Rate = vsr.VS_Rate
		FROM #tmpChargeInfo AS c
			INNER JOIN CTE_VSRate AS vsr ON c.PartyID = vsr.PartyID
			INNER JOIN @VS3rd_To AS rd ON rd.Product3rdID = c.Product3rdID
		
		--update charge by CurrencyID
		;WITH CTE_VSRate AS (
			SELECT c.PartyID
				,cc.CurrencyID
				,cc.Rate AS VS_Rate
			FROM #tmpChargeInfo AS c WITH (NOLOCK)
				INNER JOIN #tmpChargeByCurr AS cc WITH (NOLOCK) ON c.ChargeID = cc.ChargeID
			WHERE c.Product3rdID = @VS3rd_FromID
		)
		UPDATE cc
		SET cc.Rate = vsr.VS_Rate
		FROM #tmpChargeByCurr AS cc
			INNER JOIN #tmpChargeInfo AS c WITH (NOLOCK) ON cc.ChargeID = c.ChargeID
			INNER JOIN CTE_VSRate AS vsr ON cc.CurrencyID = vsr.CurrencyID AND c.PartyID = vsr.PartyID
			INNER JOIN @VS3rd_To AS rd ON rd.Product3rdID = c.Product3rdID
	END
	-----------------Case #2 - NOT EXISTS-----------------
	ELSE IF @WLDate >= @VSMergeCutOffDate --over Cut Off Date
		AND NOT EXISTS (
			SELECT 1
			FROM #tmpChargeInfo AS c
				INNER JOIN @VS3rd_To AS rd ON rd.Product3rdID = c.Product3rdID
		)
	BEGIN
		--CLONE charge rate by PartyID (from VS to VS 2,3,4)
		INSERT INTO #tmpChargeInfo (
			ChargeID
			,PartyID
			,Product3rdID
			,Rate
			,BetType
			,ChargeType
		)
		SELECT c.ChargeID
			,c.PartyID
			,rd.Product3rdID
			,c.Rate
			,c.BetType
			,c.ChargeType
		FROM #tmpChargeInfo AS c WITH (NOLOCK)
			,@VS3rd_To AS rd
		WHERE c.Product3rdID = @VS3rd_FromID
	END
	
	--specific sport, the rest will be group into [Other Sports]
	INSERT INTO #tmpSBSports (SportGroup)
	SELECT SportType
	FROM bodb02.dbo.Sports WITH (NOLOCK)
	WHERE SportType IN (1,2,5,43,50)
	/*
	UNION ALL
	
	SELECT 0 AS SportGroup --'Other Sports'
	
	UNION ALL
	
	SELECT - 29 AS SportGroup --Parlay
	*/
	
	/*
		Get Saba LeagueGroupID
		1-Saba Virtual Sports
		2-Saba PinGoal
	*/
	;WITH CTE_All_Saba AS (
		SELECT CONVERT(INT,value) AS LeagueGroupID
		FROM STRING_SPLIT((SELECT VValue FROM bodb_account.dbo.SystemSettings WITH (NOLOCK) WHERE VID = 5), ',')
	)
	,CTE_Saba AS (
		SELECT CONVERT(INT,value) AS LeagueGroupID
		FROM STRING_SPLIT((SELECT VValue FROM bodb_account.dbo.SystemSettings WITH (NOLOCK) WHERE VID = 11), ',')
	)
	INSERT INTO #tmpSabaLG (
		LeagueGroupID
		,SabaType
	)
	SELECT DISTINCT a.LeagueGroupID
		,CASE WHEN s.LeagueGroupID IS NOT NULL THEN 1 ELSE 2 END AS SabaType
	FROM CTE_All_Saba AS a
		LEFT JOIN CTE_Saba AS s on a.LeagueGroupID = s.LeagueGroupID
	
	/*
		Get Exchange Data
			- Exchange in bettrans (Betting & Adjustment) only for Yesterday => exclude
			- Manual calculation Exchange by Acc_Rpt_SeparatedWalletProductWL
	*/
	INSERT INTO #tmpEXBettrans (
		WLDate
		,LiveIndicator
		,IsBA
		,ProductID
		,SportType
		,BetType
		,Status
		,SRecommend
		,CurrencyID
		,Stake
		,Actual_Stake
		,Winlost
		,AWinlost
		,MWinlost
		,SWinlost
		,PlayerComm
		,Comm
	)
	EXEC DBLIC.bodb_3rdProduct.dbo.Acc_Rpt_SeparatedWalletProductWL
		@WinlostDate = @WLDate
		,@ProductID = 31
		,@DataMode = 'Letstalk36'
	
	INSERT INTO #tmpRawData WITH (TABLOCK)(
		IsSB
		,PartyID
		,Currency
		,Product3rdID
		,SportGroup
		,ProductGroup
		,LiveIndicator
		,SabaType
		,TurnOver
		,MemberWL
		,OddsSpreadAdj
		,BAComm
		,FullContribution
		,HouseContribution
		,FreeBet
	)
	SELECT bt.IsSB
		,s.PartyID
		,b.CurrencyID
		,ISNULL(prd.Product3rdID,0) AS Product3rdID
		,ISNULL(sp.SportGroup,0) AS SportGroup
		,0 AS ProductGroup
		,b.LiveIndicator
		,0 AS SabaType
		--MEASURE--
		,SUM(CASE WHEN b.Status = 'DRAW' THEN 0 ELSE ABS(Stake) END) AS TurnOver
		,SUM(ISNULL(winlost, 0) - ISNULL(actual_stake, 0)) AS MemberWL
		,0 AS OddsSpreadAdj
		,SUM(b.playercomm) AS BAComm --Exchange BAComm = [Member Charge Comm]
		--Contribution,FreeBet--
		,0 AS FullContribution
		,0 AS HouseContribution
		,0 AS FreeBet
	FROM #tmpEXBettrans AS b
		INNER JOIN #tmpDepSuper s ON s.CustID = b.srecommend
		INNER JOIN #tmpBetType bt ON b.BetType = bt.BetType
		LEFT JOIN #tmpSBSports AS sp ON b.Sporttype = sp.SportGroup
		LEFT JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON b.ProductID = p.ProductID
		LEFT JOIN #tmpProduct3rd AS prd WITH (NOLOCK) ON p.ProductPrefix = prd.ProductPrefix
	GROUP BY bt.IsSB
		,s.PartyID
		,b.CurrencyID
		,ISNULL(prd.Product3rdID,0)
		,ISNULL(sp.SportGroup,0)
		-- ,0 AS ProductGroup
		,b.LiveIndicator
		-- ,0 AS SabaType
	
	/*
		SportGroup: for SB; follow #tmpSBSports
			1,2,5,43,50-SportType
			-29-Parlay
			0-Others
		ProductGroup: for NS; 
			0-Normal or SB BetType
			1-Bet Builder
			2-MG-SuperLive
			3-FreeBet
			4-SA Gaming (Tip) - use to JOIN PartyChargeInfo
			6-Prize
			10-Contribution
		SabaType:
			0-Normal
			1-Saba Virtual Sports
			2-Saba PinGoal
	*/
	INSERT INTO #tmpRawData WITH (TABLOCK)(
		IsSB
		,PartyID
		,Currency
		,Product3rdID
		,SportGroup
		,ProductGroup
		,LiveIndicator
		,SabaType
		,TurnOver
		,MemberWL
		,OddsSpreadAdj
		,BAComm
		,FullContribution
		,HouseContribution
		,FreeBet
	)
	SELECT bt.IsSB
		,s.PartyID
		,b.Currency
		,CASE WHEN b.ProductID = 1 THEN (CASE WHEN b.IsBA = 1 THEN 3 ELSE 0 END)
			ELSE ISNULL(prd.Product3rdID,0) END AS Product3rdID
		,CASE WHEN b.BetType IN (9,29) THEN -29 ELSE ISNULL(sp.SportGroup,0) END AS SportGroup
		,CASE WHEN bt.IsSB = 1 THEN 0								--SB - ignore
			WHEN b.BetType = 38 THEN 1								--Bet Builder
			WHEN b.BetType BETWEEN 801 AND 806 THEN 2				--MG-SuperLive
			WHEN b.ProductID IN (150,173) THEN 3					--FreeBet
			WHEN p.ProductID = 39 AND b.BetType = 3007 THEN 4		--SA Gaming (Tip) - use to JOIN PartyChargeInfo
			ELSE ISNULL(tg.BetTypeGroupID,0) END AS ProductGroup	--Prize & Contribution
		,b.LiveIndicator
		,ISNULL(slg.SabaType,0) AS SabaType
		--MEASURE--
		,SUM(CASE WHEN b.TicketStatusID = 3 THEN 0
				-- ELSE (CASE WHEN (b.TicketStatusID IN ( 12,13 ) OR ABS(modds) = 0.25) THEN ABS(Stake) / 2 ELSE ABS(Stake) END)
				ELSE (CASE WHEN b.TicketStatusID IN (12,13) THEN ABS(Stake) / 2 ELSE ABS(Stake) END)
				END) AS TurnOver
		,SUM(CASE WHEN tg.BetTypeGroupID IS NOT NULL OR b.SportType IN (150,173) THEN 0 --Prize,Contribution,FreeBet(Saba.Cub & VGaming) => 0
			ELSE ISNULL(winlost, 0) - ISNULL(actual_stake, 0) END) AS MemberWL
		,SUM(CASE WHEN b.BetType = 999 THEN awinlost ELSE 0 END) AS OddsSpreadAdj
		,SUM(CASE WHEN b.ProductID = 1 AND b.IsBA = 1 THEN b.Comm ELSE 0 END) AS BAComm --BA Commision
		--Contribution,FreeBet--
		,SUM(CASE WHEN tg.BetTypeGroupID = 10 THEN b.ContributionStake3rd ELSE 0 END) AS FullContribution
		,SUM(CASE WHEN tg.BetTypeGroupID = 10 THEN b.ContributionStake3rd + b.swinlost + b.mwinlost + b.awinlost ELSE 0 END) AS HouseContribution
		,SUM(CASE WHEN b.SportType IN (150,173) THEN b.winlost - b.actual_stake ELSE 0 END) AS FreeBet
	FROM bodb_ODS.dbo.ODS_bettrans AS b WITH (NOLOCK)
		INNER JOIN #tmpDepSuper s ON s.CustID = b.srecommend
		INNER JOIN #tmpBetType bt ON b.BetType = bt.BetType
		LEFT JOIN #tmpSBSports AS sp ON b.Sporttype = sp.SportGroup
		LEFT JOIN bodb02.dbo.League AS l WITH (NOLOCK) ON b.LeagueID = l.LeagueID AND b.BetType NOT IN (9,29)
		LEFT JOIN #tmpSabaLG AS slg ON l.LeagueGroupID = slg.LeagueGroupID
		LEFT JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON b.ProductID = p.ProductID
		LEFT JOIN #tmpProduct3rd AS prd WITH (NOLOCK) ON p.ProductPrefix = prd.ProductPrefix
		LEFT JOIN bodb_Account.dbo.BetTypeGroup AS tg WITH (NOLOCK) ON b.BetType = tg.BetType AND tg.BetTypeGroupID IN (6,10) --Prize & Contribution
	WHERE b.Winlostdate = @WLDate
		AND b.TicketStatusID IN (3,4,8,12,13) --LOSE, WON, HALF LOSE, HALF WON
		AND b.Recommend NOT IN (52466,5707545)  -- Exclude 8RM, BARM
		AND b.ProductID <> 31 --handle Exchange above
	GROUP BY bt.IsSB
		,s.PartyID
		,b.Currency
		,CASE WHEN b.ProductID = 1 THEN (CASE WHEN b.IsBA = 1 THEN 3 ELSE 0 END)
			ELSE ISNULL(prd.Product3rdID,0) END
		,CASE WHEN b.BetType IN (9,29) THEN -29 ELSE ISNULL(sp.SportGroup,0) END
		,CASE WHEN bt.IsSB = 1 THEN 0								--SB - ignore
			WHEN b.BetType = 38 THEN 1								--Bet Builder
			WHEN b.BetType BETWEEN 801 AND 806 THEN 2				--MG-SuperLive
			WHEN b.ProductID IN (150,173) THEN 3					--FreeBet
			WHEN p.ProductID = 39 AND b.BetType = 3007 THEN 4		--SA Gaming (Tip) - use to JOIN PartyChargeInfo
			ELSE ISNULL(tg.BetTypeGroupID,0) END					--Prize & Contribution
		,b.LiveIndicator
		,ISNULL(slg.SabaType,0)

	CREATE CLUSTERED INDEX tmpRawData ON #tmpRawData (IsSB, PartyID, Product3rdID, Currency)
	
	--Get SB by Sport - [GroupID = 2] - fixed order--
	;WITH CTE_SB_BySport AS (
		SELECT CASE WHEN d.SportGroup = 1 AND d.LiveIndicator = 1 AND d.SabaType = 0 THEN 3 --'R.Soc(L)'
				WHEN d.SportGroup = 1 AND d.LiveIndicator = 0 AND d.SabaType = 0 THEN 4 --'R.Soc(NL)'
				WHEN d.SportGroup = 1 AND d.SabaType = 1 THEN 5 --'Saba.Soc'
				WHEN d.SportGroup = 1 AND d.SabaType = 2 THEN 6 --'Soccer PG'
				WHEN d.SportGroup = 2 AND d.SabaType = 2 THEN 7 --'Basket PG'
				WHEN d.SportGroup = 2 AND d.SabaType = 0 THEN 8 --'Real.Bas'
				WHEN d.SportGroup = 2 AND d.SabaType = 1 THEN 9 --'Saba.Bas'
				WHEN d.SportGroup = 5 AND d.SabaType = 0 THEN 10 --'Real.Ten'
				WHEN d.SportGroup = 5 THEN 10.1 --'Saba.Ten'
				WHEN d.SportGroup = 43 THEN 11 --'E-Spo'
				WHEN d.SportGroup = 50 THEN 12 --'Cricket'
				WHEN d.SportGroup = -29 THEN 14 --'Parl'
				ELSE 13 END AS OrdNo --Others
			,SUM(d.TurnOver * ISNULL(lc.Rate, p.Rate) * e.BaseCurrencyRate) AS HouseTO
			,SUM((-d.MemberWL * ISNULL(lc.Rate, p.Rate) - d.OddsSpreadAdj - d.BAComm) * e.BaseCurrencyRate) AS HouseWL
		FROM #tmpRawData AS d
			LEFT JOIN #tmpChargeInfo p ON p.PartyID = d.PartyID AND p.Product3rdID = d.Product3rdID
			LEFT JOIN #tmpChargeByCurr lc ON p.ChargeID = lc.ChargeID AND d.Currency = lc.CurrencyID
			LEFT JOIN #tmpOANDARate e ON e.ExchangeID = d.Currency
		WHERE d.IsSB = 1
		GROUP BY CASE WHEN d.SportGroup = 1 AND d.LiveIndicator = 1 AND d.SabaType = 0 THEN 3 --'R.Soc(L)'
				WHEN d.SportGroup = 1 AND d.LiveIndicator = 0 AND d.SabaType = 0 THEN 4 --'R.Soc(NL)'
				WHEN d.SportGroup = 1 AND d.SabaType = 1 THEN 5 --'Saba.Soc'
				WHEN d.SportGroup = 1 AND d.SabaType = 2 THEN 6 --'Soccer PG'
				WHEN d.SportGroup = 2 AND d.SabaType = 2 THEN 7 --'Basket PG'
				WHEN d.SportGroup = 2 AND d.SabaType = 0 THEN 8 --'Real.Bas'
				WHEN d.SportGroup = 2 AND d.SabaType = 1 THEN 9 --'Saba.Bas'
				WHEN d.SportGroup = 5 AND d.SabaType = 0 THEN 10 --'Real.Ten'
				WHEN d.SportGroup = 5 THEN 10.1 --'Saba.Ten'
				WHEN d.SportGroup = 43 THEN 11 --'E-Spo'
				WHEN d.SportGroup = 50 THEN 12 --'Cricket'
				WHEN d.SportGroup = -29 THEN 14 --'Parl'
				ELSE 13 END
	)
	,CTE_SB_RSoc AS (
		SELECT 2 AS OrdNo --Real.Soc
			,SUM(HouseTO) AS HouseTO
			,SUM(HouseWL) AS HouseWL
		FROM CTE_SB_BySport
		WHERE OrdNo IN (3,4)
	)
	,CTE_SB AS (
		SELECT 1 AS OrdNo --ALL
			,SUM(HouseTO) AS HouseTO
			,SUM(HouseWL) AS HouseWL
		FROM CTE_SB_BySport
	)
	INSERT INTO #tmpFinal (
		GroupID
		,GroupName
		,HouseTO
		,HouseWL
		,OrdNo
	)
	SELECT 2 AS GroupID
		,'ALL' AS GroupName
		,HouseTO
		,HouseWL
		,OrdNo
	FROM CTE_SB
	
	UNION ALL
	
	SELECT 2 AS GroupID
		,'Real.Soc' AS GroupName
		,HouseTO
		,HouseWL
		,OrdNo
	FROM CTE_SB_RSoc
	
	UNION ALL
	
	SELECT 2 AS GroupID
		,CASE WHEN OrdNo = 3 THEN 'R.Soc(L)'
				WHEN OrdNo = 4 THEN 'R.Soc(NL)'
				WHEN OrdNo = 5 THEN 'Saba.Soc'
				WHEN OrdNo = 6 THEN 'Soccer PG'
				WHEN OrdNo = 7 THEN 'Basket PG'
				WHEN OrdNo = 8 THEN 'Real.Bas'
				WHEN OrdNo = 9 THEN 'Saba.Bas'
				WHEN OrdNo = 10 THEN 'Real.Ten'
				WHEN OrdNo = 10.1 THEN 'Saba.Ten'
				WHEN OrdNo = 11 THEN 'E-Spo'
				WHEN OrdNo = 12 THEN 'Cricket'
				WHEN OrdNo = 14 THEN 'Parl'
				ELSE 'Others' END AS GroupName
		,HouseTO
		,HouseWL
		,OrdNo
	FROM CTE_SB_BySport
	
	--Get NS by Product - [GroupID = 3] - order by TurnOver--
	;WITH CTE_NS_ByProd AS (
		SELECT CASE WHEN d.ProductGroup = 1 THEN 'BetB'
				WHEN d.ProductGroup = 2 THEN 'MetricG'
				ELSE rd.ProductName END AS GroupName
			,SUM(ISNULL(d.TurnOver,0) * ISNULL(lc.Rate, p.Rate) * e.BaseCurrencyRate) AS HouseTO
			,SUM(((-d.MemberWL - (d.FullContribution - d.HouseContribution)) * ISNULL(lc.Rate, p.Rate)
					- d.HouseContribution
					- d.FreeBet
					- (CASE WHEN d.Product3rdID IN (3) THEN d.BAComm -- BA Comm of bet builder
						WHEN d.Product3rdID IN (31) THEN d.BAComm * ISNULL(lc.Rate, p.Rate) --- exchange use [Formular based on billing term] (Licensee WL - Member Charge Comm) * 12.5%
						ELSE 0
						END
					) -- exchange product & BAComm
				) * e.BaseCurrencyRate) AS HouseWL
		FROM #tmpRawData AS d
			LEFT JOIN #tmpProduct3rd AS rd WITH (NOLOCK) ON rd.Product3rdID = d.Product3rdID
			LEFT JOIN #tmpChargeInfo p ON p.PartyID = d.PartyID
											AND p.Product3rdID = d.Product3rdID
											AND p.BetType = - 1
											AND ( (d.Product3rdID IN (39) AND p.ChargeType = 12 AND d.ProductGroup = 4)
												OR (d.Product3rdID IN (39) AND p.ChargeType = 1 AND d.ProductGroup <> 4)
												OR (d.Product3rdID NOT IN (39))
											)
			LEFT JOIN #tmpChargeByCurr lc ON p.ChargeID = lc.ChargeID AND d.Currency = lc.CurrencyID
			LEFT JOIN #tmpOANDARate e ON e.ExchangeID = d.Currency
		WHERE d.IsSB = 0
		GROUP BY CASE WHEN d.ProductGroup = 1 THEN 'BetB'
				WHEN d.ProductGroup = 2 THEN 'MetricG'
				ELSE rd.ProductName END
	)
	,CTE_NS AS (
		SELECT 'ALL' AS GroupName
			,SUM(HouseTO) AS HouseTO
			,SUM(HouseWL) AS HouseWL
		FROM CTE_NS_ByProd
		
		UNION ALL
		
		SELECT GroupName
			,HouseTO
			,HouseWL
		FROM CTE_NS_ByProd
	)
	INSERT INTO #tmpFinal (
		GroupID
		,GroupName
		,HouseTO
		,HouseWL
		,OrdNo
	)
	SELECT 3 AS GroupID
		,GroupName
		,HouseTO
		,HouseWL
		,ROW_NUMBER() OVER ( ORDER BY HouseTO DESC) AS OrdNo
	FROM CTE_NS

	/*
		Return Result Set
		GroupID = 1 - WL & M By SB/NS
		GroupID = 2 - TO & M By SB
		GroupID = 3 - TO & M By NS
	*/
	;WITH CTE_Grp1 AS (
		SELECT 1 AS GroupID
			,CASE WHEN GroupID = 2 THEN 'SB' ELSE 'NS' END AS GroupName
			,ISNULL(HouseWL,0) AS Amt
			,(CASE WHEN ISNULL(HouseTO,0) = 0 THEN 0
				ELSE ISNULL(HouseWL,0) / HouseTO
			END) AS Margin
			,CASE WHEN GroupID = 2 THEN 1 ELSE 2 END AS OrdNo
		FROM #tmpFinal
		WHERE OrdNo = 1 --Sum all SB & NS
	)
	,CTE_Grp AS (
		SELECT GroupID
			,GroupName
			,ISNULL(HouseTO,0) AS Amt
			,(CASE WHEN ISNULL(HouseTO,0) = 0 THEN 0
				ELSE ISNULL(HouseWL,0) / HouseTO
			END) AS Margin
			,OrdNo
		FROM #tmpFinal
		WHERE HouseTO IS NOT NULL

		UNION ALL

		SELECT GroupID
			,GroupName
			,Amt
			,Margin
			,OrdNo
		FROM CTE_Grp1
	)
	SELECT GroupID
		,GroupName
		,Amt
		,CONVERT(DECIMAL(10,6),Margin) AS Margin
		,CASE WHEN GroupName = @EX3rdName AND @DayOffset = 0 THEN '[1h delay]' ELSE '' END AS ExtraInfo
	FROM CTE_Grp
	ORDER BY GroupID
		,OrdNo
	
	SELECT @Title AS Title
	
	DROP TABLE #tmpBetType
	DROP TABLE #tmpSBSports
	DROP TABLE #tmpRawData
	DROP TABLE #tmpDepSuper
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpChargeByCurr
	DROP TABLE #tmpOANDARate
	DROP TABLE #tmpLicParty
	DROP TABLE #tmpSabaLG
	DROP TABLE #tmpProduct3rd
	DROP TABLE #tmpFinal
	DROP TABLE #tmpEXBettrans
END

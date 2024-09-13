/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSports_PayoutAlert]
	@FromGMT8Time DATETIME
	,@TimeInterval TINYINT = 1 --hour
AS
/*
	Created: 20210519@Roy
	Task :	Detect the payout of 3rd products which reaches limit
	DB:		DBACC@bodb02
	Revisions:
		20210519@Roy: CWL - New Request to monitor game payout levels (#154598)
		20221128@Roy: Payout Limit Notification - Set Bitcoin payout limit to 115% (#180940)
		20230203@Roy: Game Payout Notification Letstalk - Support different notification level setting for specific group of products (#182931)
		20230424@Roy: Game Payout Letstalk - Support to remove in-active products and un-used reports (#187325)
		20230522@Roy: Risk and Control - YeeBet - Integrate new Live Casino product (#186474)
		20230720@Roy: Risk and Control - LG Virtual Sports - Incorporate new product (#189202)
		20231114@Roy: CWL - Risk and Control - WE Live Casino - Integrate new product (#195888)
		20231206@Roy: CWL - Non Sports Report - Live22 - Integrate New Product (#195092)
		20240223@Roy: Email/Letstalk - Virtual Sports 4 - Edge Gaming (#198628)
		20240417@Cherry: Integrate Saba xD (#202670)
		20240722@Cherry: Integrate FA CHAI (#206634), FastSpin (#205746), VS5 (#207590), Nextspin (#199987)
		20240916@Cherry: Integrate ON Casino (#210027)

	Param's Explanation:
		@FromGMT8Time: start of time range in GMT+8 with format 2021-05-20 19:00:00
		@TimeInterval: time interval in hour
			
	Script:
		EXEC Acc_Rpt_NonSports_PayoutAlert @FromGMT8Time = '2021-05-20 19:00:00'
*/

BEGIN
	SET NOCOUNT ON
	
	/*
		Exclude Products
		4	- SLI Live Casino
		12	- Gold Deluxe
		11	- AG Casino
		13	- Microgaming- Live Casino
		17	- Microgaming- RNG Casino
		14	- Macau
		24	- Fishing World
		26	- Lucky 3
		30	- Bullfighting
		33	- Poker Games
		15	- Colossus Bet
		23	- NG2
		47	- BBIN
		43	- Togel 4D
		59	- GDG
		69	- Bitcoin
	*/
	DECLARE @ExcludeProduct VARCHAR(MAX) = '4,12,11,13,17,14,24,26,30,33,15,23,47,43,59,69'
	
	/*
		Hard code Payout Limit by product
		- ThresholdPCT: threshold percent, the notification will send email to NSD if Game Payout reaches it
		- MinWin: total wins must be equal or greater this value
	*/
	CREATE TABLE #tmpProductLimit (
		ProductID INT
		,ProductName VARCHAR(50)
		,ThresholdPCT DECIMAL(19,4)
		,MinWin DECIMAL(19,4)
	)
	INSERT INTO #tmpProductLimit (
		ProductID
		,ProductName
		,ThresholdPCT
		,MinWin
	)
	SELECT ProductID
		,ProductName
		,ThresholdPCT
		,MinWin
	FROM (
		VALUES
			-------------Live Casino-------------
			(45, 'AE Sexy', 111, 5000) --ProductID, ProductName, ThresholdPCT, MinWin
			,(21, 'Allbet', 111, 5000)
			,(57, 'BG', 111, 5000)
			,(46, 'IBCBet Live Casino', 111, 5000)
			,(52, 'ION', 111, 5000)
			,(65, 'PP Live Casino', 111, 5000)
			,(39, 'SA Gaming', 111, 5000)
			,(51, 'WM', 111, 5000)
			,(76, 'YeeBet', 111, 5000)
			,(80, 'WE Live Casino', 111, 5000)
			,(96, 'ON Casino', 111, 5000)
			
			-------------RNG Game-------------
			,(34, 'Arcadia Gaming', 120, 5000) --ProductID, ProductName, ThresholdPCT, MinWin
			,(70, 'FGG', 120, 5000)
			,(50, 'Funky Games', 120, 5000)
			,(28, 'Lottery', 120, 5000)
			,(60, 'MaxGame', 120, 5000)
			,(3, 'Number Game', 120, 5000)
			,(8, 'RNG Keno', 120, 5000)
			,(42, 'SABA.games', 120, 5000)
			,(63, 'Sports Lottery', 120, 5000)
			,(40, 'Table Game', 120, 5000)
			,(66, 'Vgaming', 120, 5000)
			,(38, 'Virtual Games', 120, 5000)
			,(86, 'SABA xD', 120, 5000)
			
			-------------Sport-------------
			,(5, 'Virtual Sports', 108, 5000)
			,(27, 'Virtual Sports 2', 108, 5000)
			,(49, 'Virtual Sports 3 (Old)', 108, 5000)
			,(77, 'Virtual Sports 3', 108, 5000)
			,(83, 'Virtual Sports 4', 108, 5000)
			,(88, 'Virtual Sports 5', 108, 5000)
			,(69, 'Bitcoin', 108, 5000)
			
			-------------Slot-------------
			,(67, 'AdvantPlay', 300, 5000)
			,(68, 'AdvantPlay Mini', 300, 5000)
			,(62, 'CG', 300, 5000)
			,(61, 'Habanero', 300, 5000)
			,(56, 'Joker', 300, 5000)
			,(22, 'Macau Games', 300, 5000)
			,(6, 'Saba Casino', 300, 5000)
			,(73, 'MG-RNG', 300, 5000)
			,(55, 'PG Soft', 300, 5000)
			,(32, 'PP', 300, 5000)
			,(72, 'SEAL Entertainment', 300, 5000)
			,(36, 'SG', 300, 5000)
			,(75, 'Jili', 300, 5000)
			,(79, 'Live22', 300, 5000)
			,(85, 'Nextspin', 300, 5000)
			,(87, 'FastSpin', 300, 5000)
			,(89, 'FA CHAI', 300, 5000)
		) AS tmp (ProductID, ProductName, ThresholdPCT, MinWin)

	DECLARE @isTest BIT = 0
		,@From4GMTTime DATETIME
		,@To4GMTTime DATETIME
		,@FromWLDate SMALLDATETIME
		,@ToWLDate SMALLDATETIME
	
	---create tmp tables---
	CREATE TABLE #tmpDrawData (
		BetType INT
		,BetCount INT
		,TotalBetsRM DECIMAL(19, 4)
		,TotalWinsRM DECIMAL(19, 4)
	)
	
	CREATE TABLE #tmpResult (
		ProductID INT
		,BetType INT
		,BetCount INT
		,TotalBetsRM DECIMAL(19, 4)
		,TotalWinsRM DECIMAL(19, 4)
		,GamePayout DECIMAL(19, 4)
	)
	
	CREATE TABLE #tmpProductBetType (
		ProductID INT
		,BetType INT
		,RefTable SMALLINT
	)
	
	CREATE TABLE #tmpNonSportSetting (
		ProductID INT
		,BetType INT
	)
	
	CREATE TABLE #tmpMatch ( MatchID INT NOT NULL PRIMARY KEY )
	
	/*
		special BetTypes, special handling
			GroupID = 6: Prize
			GroupID = 10: Contribution
			GroupID = 12: No BetCount
	*/
	CREATE TABLE #tmpSpecialBetType (
		GroupID INT
		,BetType INT
	)
	
	/*
		Convert GMT+8 to GMT-4
		Ex: @FromGMT8Time = 2021-05-20 19:59:59
			=> @From4GMTTime = 2021-05-20 07:00:00
	*/
	SET @From4GMTTime = DATEADD(hh, DATEDIFF(hh, 0, DATEADD(hh, - 12, @FromGMT8Time)), 0) --Remove minute and second
	SET @To4GMTTime = DATEADD(hh, @TimeInterval, @From4GMTTime)
	
	/*
		Define WinlostDate
			- Only >>>1<<< day based on @From4GMTTime
	*/
	SET @FromWLDate = CAST(@From4GMTTime AS DATE)
	SET @ToWLDate = DATEADD(dd, 1, @FromWLDate) --to compare < @ToWLDate--
	
	---Define BetType---
	/*
		All Non-sport BetType
	*/
	INSERT INTO #tmpNonSportSetting (
		ProductID
		,BetType
		)
	SELECT ProductID
		,BetType
	FROM DBDW.bodb_Account.dbo.NonSportSetting WITH (NOLOCK)
	WHERE [Enable] = 1
		AND WalletType = 'SingleWallet' --only SingleWallet
	
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	;WITH CTE_ExcludeProduct AS (
		SELECT CONVERT(INT, val) AS ProductID
		FROM dbo.strSplit(REPLACE(@ExcludeProduct, ' ', ''), ',')
		WHERE ISNUMERIC(val + '.0e0') = 1
		GROUP BY val
	)
	INSERT INTO #tmpProductBetType (
		ProductID
		,BetType
		,RefTable
		)
	SELECT s.ProductID
		,s.BetType
		,MAX(s.RefTable) RefTable
	FROM dbo.f_SportBetTypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) AS s
		INNER JOIN #tmpNonSportSetting AS ns WITH (NOLOCK) ON s.ProductID = ns.ProductID AND s.BetType = ns.BetType
	WHERE s.ProductID NOT IN ( SELECT ProductID FROM CTE_ExcludeProduct )
	GROUP BY s.ProductID
		,s.BetType
	
	CREATE CLUSTERED INDEX CIX_tmpProductBetType ON #tmpProductBetType (BetType, ProductID, RefTable)
	
	/*
		Special BetType
			1.Treat Contribution tickets as normal tickets
				=> NO action - exists in #tmpProductBetType
			2.For internal products like Saba.club/Vgaming, the data includes 'Free Bets' and normal bet
				=> NO action - exists in #tmpProductBetType (just group Product/BetType - NOT divided SportType/BetType)
			3.Prize BetTypes
				=> exclude
			4.Prize/Contribution/Odds Spread Adjustment/etc. BetTypes
				=> empty betcount
	*/
	INSERT INTO #tmpSpecialBetType (
		GroupID
		,BetType
	)
	SELECT BetTypeGroupID
		,BetType
	FROM DBWH.bodb_Account.dbo.BetTypeGroup WITH (NOLOCK)
	WHERE BetTypeGroupID in (6, 12) --Prize, No BetCount
	
	CREATE CLUSTERED INDEX CIX_tmpSpecialBetType ON #tmpSpecialBetType (GroupID, BetType)
		
	--Exclude Prize BetTypes--
	DELETE #tmpProductBetType
	WHERE BetType IN ( SELECT BetType FROM #tmpSpecialBetType WHERE GroupID = 6 )
	
	----------------------------------------------
	/*
		Get MatchID to reduce memory usage when select data from Bettrans
	*/
	INSERT INTO #tmpMatch ( MatchID )
	SELECT MatchID
	FROM dbo.Bettrans WITH (NOLOCK)
	WHERE WinlostDate >= @FromWLDate
		AND WinlostDate < @ToWLDate
		AND BetType IN (SELECT BetType FROM #tmpProductBetType WHERE RefTable IN (0,3) GROUP BY BetType)
		AND StatusID IN (111, 112, 113) -- won/lose/draw tickets
		AND Currency <> 20
		AND MatchID IS NOT NULL
	GROUP BY MatchID
	/*
		Get all data of Non-Sports
	*/
	---Get from Bettrans - RefTable IN (0,3)---
	INSERT INTO #tmpDrawData (
		BetType
		,BetCount
		,TotalBetsRM
		,TotalWinsRM
	)
	SELECT b.BetType
		,COUNT(b.TransId) AS BetCount
		,SUM(b.actual_stake * b.actualrate) AS TotalBetsRM
		,SUM(b.winlost * b.actualrate) AS TotalWinsRM
	FROM dbo.Bettrans b WITH (NOLOCK)
	WHERE b.WinlostDate >= @FromWLDate
		AND b.WinlostDate < @ToWLDate
		AND b.transdate >= @From4GMTTime
		AND b.transdate < @To4GMTTime
		AND b.BetType IN (SELECT BetType FROM #tmpProductBetType WHERE RefTable IN (0,3) GROUP BY BetType)
		-- AND b.ruben = 1
		AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
		AND b.Currency <> 20
		AND b.MatchID IN (SELECT MatchID FROM #tmpMatch)
	GROUP BY b.BetType
	OPTION (RECOMPILE)

	---Get from BettransRNG - RefTable = 1---
	INSERT INTO #tmpDrawData (
		BetType
		,BetCount
		,TotalBetsRM
		,TotalWinsRM
	)
	SELECT b.GameID AS BetType
		,COUNT(b.TransId) AS BetCount
		,SUM(b.actual_stake * b.actualrate) AS TotalBetsRM
		,SUM(b.winlost * b.actualrate) AS TotalWinsRM
	FROM dbo.BettransRNG b WITH (NOLOCK)
	WHERE b.WinlostDate >= @FromWLDate
		AND b.WinlostDate < @ToWLDate
		AND b.transdate >= @From4GMTTime
		AND b.transdate < @To4GMTTime
		AND b.GameID IN (SELECT BetType FROM #tmpProductBetType WHERE RefTable = 1 GROUP BY BetType)
		AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
		AND b.Currency <> 20
	GROUP BY b.GameID
	OPTION (RECOMPILE)
	
	---Get from BettransLC - RefTable = 2---
	INSERT INTO #tmpDrawData (
		BetType
		,BetCount
		,TotalBetsRM
		,TotalWinsRM
	)
	SELECT b.GameID AS BetType
		,COUNT(b.TransId) AS BetCount
		,SUM(b.actual_stake * b.actualrate) AS TotalBetsRM
		,SUM(b.winlost * b.actualrate) AS TotalWinsRM
	FROM dbo.BettransLC b WITH (NOLOCK)
	WHERE b.WinlostDate >= @FromWLDate
		AND b.WinlostDate < @ToWLDate
		AND b.transdate >= @From4GMTTime
		AND b.transdate < @To4GMTTime
		AND b.GameID IN (SELECT BetType FROM #tmpProductBetType WHERE RefTable = 2 GROUP BY BetType)
		AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
		AND b.Currency <> 20
	GROUP BY b.GameID
	OPTION (RECOMPILE)

	CREATE CLUSTERED INDEX CIX_tmpDrawData ON #tmpDrawData (BetType)
	
	/*
		Filter Payout limit value
	*/
	;WITH CTE_Payout AS (
		SELECT d.BetType
			,SUM(CASE WHEN nbc.BetType IS NOT NULL THEN 0 ELSE d.BetCount END) BetCount
			,SUM(TotalBetsRM) TotalBetsRM
			,SUM(TotalWinsRM) TotalWinsRM
			,CASE WHEN SUM(ISNULL(TotalBetsRM,0)) = 0 THEN 0 ELSE (SUM(TotalWinsRM)/SUM(TotalBetsRM)) END AS GamePayout
		FROM #tmpDrawData AS d
			LEFT JOIN #tmpSpecialBetType AS nbc ON nbc.GroupID = 12 AND d.BetType = nbc.BetType
		GROUP BY d.BetType
	)
	INSERT INTO #tmpResult (
		ProductID
		,BetType
		,BetCount
		,TotalBetsRM
		,TotalWinsRM
		,GamePayout
	)
	SELECT pb.ProductID
		,po.BetType
		,po.BetCount
		,po.TotalBetsRM
		,po.TotalWinsRM
		,po.GamePayout
	FROM CTE_Payout AS po
		LEFT JOIN #tmpProductBetType AS pb ON po.BetType = pb.BetType
		LEFT JOIN #tmpProductLimit AS pl ON pl.ProductID = pb.ProductID
	WHERE po.GamePayout >= (ISNULL(pl.ThresholdPCT,200) / 100) --default 200%
		AND po.TotalWinsRM >= ISNULL(pl.MinWin,5000) --default 5k
	OPTION (RECOMPILE)
	
	---Return Result---
	SELECT p.ProductName AS Product
		,b.typenamee AS GameType
		,r.BetCount
		,r.TotalBetsRM
		,r.TotalWinsRM
		,r.GamePayout
	FROM #tmpResult AS r
		LEFT JOIN dbo.Products AS p ON r.ProductID = p.ProductID
		LEFT JOIN dbo.BetType AS b ON r.BetType = b.TypeID
	ORDER BY GamePayout DESC
		,b.typenamee
	
	DROP TABLE #tmpDrawData
	DROP TABLE #tmpResult
	DROP TABLE #tmpProductBetType
	DROP TABLE #tmpNonSportSetting
	DROP TABLE #tmpSpecialBetType
	DROP TABLE #tmpMatch
	DROP TABLE #tmpProductLimit
END

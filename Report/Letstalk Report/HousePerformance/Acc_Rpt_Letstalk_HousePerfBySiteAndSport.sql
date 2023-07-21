/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_HousePerfBySiteAndSport
	@ExecTime4GMT SMALLDATETIME
AS
/*
	Created: Roy@20220531
	Task: Get House WL At Exec Time  (Letstalk #32)
	DB: DBACC.bodb02

	Revisions:
		20220531@Roy: Letstalk Report - House Performance by Site & Sport (#173219)
		20220714@Roy: Fix the way to determine HALF-WON|HALF_LOSE ticket (#175382)
		20220916@Roy: Letstalk report ID #32, #34 - Add 8RM info & enhance the UI (#177825)
		20221010@Roy: Letstalk reports - Enhance UI/UX for smartwatch devices (#178950)
		20221206@Roy: Email/Letstalk Reports - Incorporate Saba E-Sports PinGoal (#181261)
		20230117@Roy: Email/Letstalk Reports - Split 789Y site into smaller sites (#182388)
		20230705@Roy: Email/Letstalk Reports - Incorporate Saba Tennis (#190458)
		20230720@Roy: Email/Letstalk Reports - Apply Bot API and change HTML UI (#191481)

	Param's Explanation:
		@ExecTime4GMT: The exec time (GMT-4)
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_HousePerfBySiteAndSport
			@ExecTime4GMT = '2022-06-03 03:00:00'
*/
BEGIN

	SET NOCOUNT ON
	
	DECLARE @DayOffset INT
		,@WLDate SMALLDATETIME
		,@Title VARCHAR(20)
	
	SET @DayOffset = (CASE WHEN DATEPART(HOUR, @ExecTime4GMT) >= 2
								THEN 0
							ELSE - 1
							END)
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
	SET @Title = @Title + ' (ID #32)'
	
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
	
	--CREATE temp tables--
	CREATE TABLE #tmpDWSite (
		[Site] VARCHAR(20)
		,IsDeposit BIT
		,SiteLabel VARCHAR(50)
	)
	
	CREATE TABLE #tmpMatch (
		MatchID INT
	)
	
	CREATE TABLE #tmpTestLeague (
		LeagueID INT
	)
	
	CREATE TABLE #tmpRecommend (
		Recommend INT
	)
	
	CREATE TABLE #tmpCustomer (
		CustID INT
		,Site VARCHAR(20)
		,IsDeposit BIT
	)
	
	CREATE TABLE #tmpProductBettype (
		ProductID INT
		,Bettype INT
		,RefTable TINYINT
		,HalfBettype BIT
	)
	
	CREATE TABLE #tmpDWBettypeSource (
		Bettype INT
		,SourceTable VARCHAR(50)
	)
	
	CREATE TABLE #tmpBettypeGroup (
		Bettype INT
		,BettypeGroupID SMALLINT
	)
	
	CREATE TABLE #tmpRawData (
		Site VARCHAR(20)
		,IsDeposit BIT
		,LeagueID INT
		,Bettype INT
		,IsHalf BIT
		,LiveStatus TINYINT
		,VarianceVR DECIMAL(9,6)
		,WinlossIBC DECIMAL(19,4)
		,ExtraWL DECIMAL(19,6)
		,CommissionS DECIMAL(19,4)
		,ExtraComm DECIMAL(19,8)
		,TurnoverIBC DECIMAL(19,4)
		,ExtraTO DECIMAL(19,6)
	)
	
	CREATE TABLE #tmpSportBettypeGroup (
		Sporttype INT
		,Bettype INT
	)
	
	CREATE TABLE #tmpOrderByGroupName (
		GroupID TINYINT
		,OrderNo TINYINT IDENTITY(1,1)
		,IsTitle BIT
		,GroupName VARCHAR(50) UNIQUE
	)
	
	CREATE TABLE #tmpResult (
		GroupName VARCHAR(50)
		,WinlossIBC DECIMAL(19,4)
		,TurnoverIBC DECIMAL(19,4)
	)	
	
	---------Insert Dimension tables---
	/*
		hard code the order of group
		GroupID IN (1,2) => return WL
			Otherwise => return TO
	*/
	INSERT INTO #tmpOrderByGroupName (
		GroupID, IsTitle, GroupName
	)
	VALUES 
		(1, 0, 'GRAND TOTAL')
		,(1, 0, 'T SB')
		,(1, 0, 'T NS')
		,(1, 0, 'BySite_8RM')
		
		,(2, 1, 'WL & M')
		,(2, 0, 'XYZ & BO')
		,(2, 0, '611 (Chi)')
		,(2, 0, '733 (Mala)')
		,(2, 0, '755 (Thai)')
		,(2, 0, 'Indo')
		,(2, 0, 'IbcIndo')
		,(2, 0, 'Myanmar')
		,(2, 0, 'Y SB')
		,(2, 0, 'Y NS')
		,(2, 0, 'Other Credit')
		,(2, 0, 'C SB')
		,(2, 0, 'C NS')
		,(2, 0, 'CV SB')
		,(2, 0, 'CV NS')
		
		,(3, 1, 'SB TO & M')
		,(3, 0, 'Real.Soc')
		,(3, 0, 'Real.Soc(L)')
		,(3, 0, 'Real.Soc(NL)')
		,(3, 0, 'Saba.Soc')
		,(3, 0, 'Soccer PG')
		,(3, 0, 'Basket PG')
		,(3, 0, 'Real.Bas')
		,(3, 0, 'Saba.Bas')
		,(3, 0, 'Real.Ten')
		,(3, 0, 'Saba.Ten')
		,(3, 0, 'E-Spo')
		,(3, 0, 'S.E-SPG')
		,(3, 0, 'Cricket')
		,(3, 0, 'Others')
		,(3, 0, 'Parl')
		
		,(4, 0, 'TOTAL SB')
		,(4, 0, 'BySport_8RM')
		
		,(5, 1, 'PH TO & M')
		,(5, 0, 'PHAIO')
		
		,(6, 1, 'TimeM TO & M')
		,(6, 0, 'TimeM_HDP')
		,(6, 0, 'TimeM_OU')
	
	INSERT INTO #tmpDWBettypeSource (
		Bettype
		,SourceTable
	)
	SELECT typeid AS Bettype
		,SourceTable
	FROM DBWH.bodb_Account.dbo.Bettype WITH (NOLOCK)
	
	--Make sure SourceTable the same with DW
	INSERT INTO #tmpProductBettype (
		ProductID
		,Bettype
		,RefTable
		,HalfBettype
	)
	SELECT DISTINCT pb.ProductID
		,pb.Bettype
		,CASE WHEN bs.SourceTable = 'bettransRNG' THEN 1
			WHEN bs.SourceTable = 'bettransLC' THEN 2
			ELSE 3
		END AS RefTable
		,CASE WHEN pb.ProductID = 1 AND pb.Bettype NOT IN (29, 38, 901, 902 ,903, 904, 999, 18999) THEN 1
			ELSE 0
		END AS HalfBettype
	FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', 0) AS pb
		LEFT JOIN #tmpDWBettypeSource AS bs ON pb.Bettype = bs.Bettype
	
	CREATE CLUSTERED INDEX CIX_tmpProductBettype ON #tmpProductBettype ( Bettype, RefTable, ProductID )
	
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
	
	INSERT INTO #tmpDWSite (
		Site
		,IsDeposit
		,SiteLabel
		)
	SELECT DISTINCT Site
		,IsDeposit
		,CASE WHEN SiteLabel = '789y' THEN SiteLabel ELSE Site END AS SiteLabel --only for 789y (divided 789y site into YUT, Y789, Y889, YOther)
	FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK)
	
	INSERT INTO #tmpTestLeague ( LeagueID )
	SELECT DISTINCT LeagueID
	FROM dbo.league WITH (NOLOCK)
	WHERE isTest = 1
	CREATE CLUSTERED INDEX CIX_tmpTestLeague ON #tmpTestLeague ( LeagueID )
	--------------------------------Get Raw data------------------------------
	DECLARE @Parl_LeagueID INT --dummy Parlay LeagueID
		,@NS_LeagueID INT --dummy Non-Sports LeagueID
	
	--make sure dummy LeagueID NOT exists IN [League] table
	SELECT @Parl_LeagueID = (MIN(LeagueID) - 1)
		,@NS_LeagueID = (MIN(LeagueID) - 2)
	FROM dbo.League WITH (NOLOCK)
	
	--------------------------------bettrans----------------------------------
	INSERT INTO #tmpMatch ( MatchID )
	SELECT MatchID
	FROM dbo.bettrans AS b WITH (NOLOCK)
	WHERE winlostdate = @WLDate
	GROUP BY MatchID
	
	--remove match of test league--
	DELETE m
	FROM #tmpMatch AS m
		INNER JOIN dbo.match AS m1 WITH (NOLOCK) ON m.MatchID = m1.MatchID
		INNER JOIN #tmpTestLeague AS l WITH (NOLOCK) ON m1.LeagueID = l.LeagueID
	
	CREATE UNIQUE CLUSTERED INDEX CIX_tmpMatch ON #tmpMatch ( MatchID )
	
	INSERT INTO #tmpRecommend ( Recommend )
	SELECT Recommend
	FROM dbo.bettrans AS b WITH (NOLOCK)
	WHERE winlostdate = @WLDate
	GROUP BY Recommend

	INSERT INTO #tmpCustomer (
		CustID
		,Site
		,IsDeposit
	)
	SELECT DISTINCT c.CustID
		,(CASE WHEN c.CustID = 52466 THEN '8RM'
		ELSE s.SiteLabel
		END) AS Site
		,s.IsDeposit
	FROM dbo.vw_Customer AS c WITH (NOLOCK)
		INNER JOIN #tmpDWSite AS s WITH (NOLOCK) ON c.Site = s.Site
	WHERE c.CustID IN (
			SELECT Recommend
			FROM #tmprecommend
			)
	OPTION (RECOMPILE)
	CREATE UNIQUE CLUSTERED INDEX CIX_tmpCustomer ON #tmpCustomer ( CustID )
	
	INSERT INTO #tmpRawData (
		Site
		,IsDeposit
		,LeagueID
		,Bettype
		,IsHalf
		,LiveStatus
		,VarianceVR
		,WinlossIBC
		,ExtraWL
		,CommissionS
		,ExtraComm
		,TurnoverIBC
		,ExtraTO
	)
	SELECT c.Site
		,c.IsDeposit
		,CASE WHEN b.bettype = 29 THEN @Parl_LeagueID
			WHEN pb.ProductID <> 1 THEN @NS_LeagueID
			WHEN m.matchid IS NOT NULL THEN m.leagueid
			WHEN o.orid IS NOT NULL THEN o.leagueid
			ELSE @NS_LeagueID
		END AS LeagueID
		,b.Bettype
		,(CASE WHEN ( ABS(b.modds) = 0.25 AND pb.HalfBettype = 1 ) THEN 1 ELSE 0 END) AS IsHalf
		,(CASE WHEN b.bettype = 29 THEN b.livehomescore
		ELSE CAST(b.liveindicator AS TINYINT)
		END) AS LiveStatus --0: Nonlive | 1:Live | 2: Mixed
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
	FROM dbo.bettrans AS b WITH (NOLOCK)--, INDEX = CIX_matchid_bettype) -- faster but dirty read
		LEFT JOIN #tmpCustomer AS c WITH (NOLOCK) ON b.Recommend = c.CustID
		LEFT JOIN match AS m WITH (NOLOCK) ON b.matchid = m.matchid AND b.bettype NOT IN ( 10, 29)
		LEFT JOIN outright AS o WITH (NOLOCK) ON b.matchid = o.orid AND b.bettype = 10
		LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.Bettype = pb.Bettype
		LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.Bettype = bg.Bettype
	WHERE b.winlostdate = @WLDate
		AND b.matchid IN (SELECT MatchID FROM #tmpMatch WITH (NOLOCK))
		AND b.statusID IN (112, 113) --Won, Lose
		AND b.currency <> 20
		AND pb.RefTable = 3
	GROUP BY c.Site
		,c.IsDeposit
		,CASE WHEN b.bettype = 29 THEN @Parl_LeagueID
			WHEN pb.ProductID <> 1 THEN @NS_LeagueID
			WHEN m.matchid IS NOT NULL THEN m.leagueid
			WHEN o.orid IS NOT NULL THEN o.leagueid
			ELSE @NS_LeagueID
		END
		,b.Bettype
		,(CASE WHEN ( ABS(b.modds) = 0.25 AND pb.HalfBettype = 1 ) THEN 1 ELSE 0 END)
		,(CASE WHEN b.bettype = 29 THEN b.livehomescore
		ELSE CAST(b.liveindicator AS TINYINT)
		END)
		,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
	
	--------------------------------bettransLC--------------------------------
	TRUNCATE TABLE #tmpRecommend
	INSERT INTO #tmpRecommend ( Recommend )
	SELECT Recommend
	FROM dbo.bettransLC AS b WITH (NOLOCK)
	WHERE winlostdate = @WLDate
	GROUP BY Recommend
	
	UPDATE STATISTICS #tmpRecommend

	TRUNCATE TABLE #tmpCustomer
	INSERT INTO #tmpCustomer (
		CustID
		,Site
		,IsDeposit
	)
	SELECT DISTINCT c.CustID
		,(CASE WHEN c.CustID = 52466 THEN '8RM'
		ELSE s.SiteLabel
		END) AS Site
		,s.IsDeposit
	FROM dbo.vw_Customer AS c WITH (NOLOCK)
		INNER JOIN #tmpDWSite AS s WITH (NOLOCK) ON c.Site = s.Site
	WHERE c.CustID IN (
			SELECT Recommend
			FROM #tmprecommend
			)
	OPTION (RECOMPILE)
	
	UPDATE STATISTICS #tmpCustomer
	
	INSERT INTO #tmpRawData (
		Site
		,IsDeposit
		,LeagueID
		,Bettype
		,IsHalf
		,LiveStatus
		,VarianceVR
		,WinlossIBC
		,ExtraWL
		,CommissionS
		,ExtraComm
		,TurnoverIBC
		,ExtraTO
	)
	SELECT c.Site
		,c.IsDeposit
		,@NS_LeagueID AS LeagueID
		,b.gameID
		,0 AS IsHalf
		,0 AS LiveStatus
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
	FROM dbo.bettransLC AS b WITH (NOLOCK)
		LEFT JOIN #tmpCustomer AS c WITH (NOLOCK) ON b.Recommend = c.CustID
		LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
		LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
	WHERE b.winlostdate = @WLDate
		AND b.statusID IN (112, 113) --Won, Lose
		AND b.currency <> 20
		AND pb.RefTable = 2
	GROUP BY c.Site
		,c.IsDeposit
		,b.gameID
		,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
	
	--------------------------------bettransRNG-------------------------------
	TRUNCATE TABLE #tmpRecommend
	INSERT INTO #tmpRecommend ( Recommend )
	SELECT Recommend
	FROM dbo.bettransRNG AS b WITH (NOLOCK)
	WHERE winlostdate = @WLDate
	GROUP BY Recommend
	
	UPDATE STATISTICS #tmpRecommend

	TRUNCATE TABLE #tmpCustomer
	INSERT INTO #tmpCustomer (
		CustID
		,Site
		,IsDeposit
	)
	SELECT DISTINCT c.CustID
		,(CASE WHEN c.CustID = 52466 THEN '8RM'
		ELSE s.SiteLabel
		END) AS Site
		,s.IsDeposit
	FROM dbo.vw_Customer AS c WITH (NOLOCK)
		INNER JOIN #tmpDWSite AS s WITH (NOLOCK) ON c.Site = s.Site
	WHERE c.CustID IN (
			SELECT Recommend
			FROM #tmprecommend
			)
	OPTION (RECOMPILE)
	
	UPDATE STATISTICS #tmpCustomer
	
	INSERT INTO #tmpRawData (
		Site
		,IsDeposit
		,LeagueID
		,Bettype
		,IsHalf
		,LiveStatus
		,VarianceVR
		,WinlossIBC
		,ExtraWL
		,CommissionS
		,ExtraComm
		,TurnoverIBC
		,ExtraTO
	)
	SELECT c.Site
		,c.IsDeposit
		,@NS_LeagueID AS LeagueID
		,b.gameID
		,0 AS IsHalf
		,0 AS LiveStatus --0: Nonlive | 1:Live | 2: Mixed
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
	FROM dbo.bettransRNG AS b WITH (NOLOCK)
		LEFT JOIN #tmpCustomer AS c WITH (NOLOCK) ON b.Recommend = c.CustID
		LEFT JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON b.gameID = pb.Bettype
		LEFT JOIN #tmpBettypeGroup AS bg WITH (NOLOCK) ON b.gameID = bg.Bettype
	WHERE b.winlostdate = @WLDate
		AND b.statusID IN (112, 113) --Won, Lose
		AND b.currency <> 20
		AND pb.RefTable = 1
	GROUP BY c.Site
		,c.IsDeposit
		,b.gameID
		,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
	
	CREATE CLUSTERED INDEX CIX_tmpRawData ON #tmpRawData ( Bettype, LeagueID, Site )
	
	------------------------Group Data follow spec------------------------
	--Hardcode to move [Bet Builder] from SB to Non-Sport
	UPDATE pb
	SET ProductID = -1
	FROM #tmpProductBettype AS pb
		INNER JOIN (
				SELECT DISTINCT Bettype
				FROM dbo.SportBettypeMatrix WITH (NOLOCK)
				WHERE SubProduct IN ('Bet Builder')
			) AS bb ON pb.Bettype = bb.Bettype
	--------------------------------GroupBySite---------------------------
	;WITH CTE_ProductSite AS (
		SELECT CASE WHEN d.Site IN ('BEST-ODDS', 'XYZBET', '8RM') THEN 'XYZ & BO'
				WHEN d.Site IN ('611111') THEN '611 (Chi)'
				WHEN d.Site IN ('733333') THEN '733 (Mala)'
				WHEN d.Site IN ('755555') THEN '755 (Thai)'
				WHEN d.Site IN ('INDO') THEN 'Indo'
				WHEN d.Site IN ('IBCIndo') THEN 'IbcIndo'
				WHEN d.Site IN ('76666B') THEN 'Myanmar'
				WHEN pb.ProductID = 1 AND d.Site IN ('789y', 'y987') THEN 'Y SB'
				WHEN pb.ProductID <> 1 AND d.Site IN ('789y', 'y987') THEN 'Y NS'
				WHEN (d.IsDeposit = 0 OR d.Site IN ('Saba789')) THEN 'Other Credit'
				WHEN d.IsDeposit = 1 AND d.Site LIKE '%CV' AND pb.ProductID = 1 THEN 'CV SB'
				WHEN d.IsDeposit = 1 AND d.Site LIKE '%CV' AND pb.ProductID <> 1 THEN 'CV NS'
				WHEN d.IsDeposit = 1 AND pb.ProductID = 1 THEN 'C SB'
				WHEN d.IsDeposit = 1 AND pb.ProductID <> 1 THEN 'C NS'
			END AS SiteName
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
			INNER JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON d.Bettype = pb.Bettype
		-- WHERE pb.ProductID NOT IN ( 25, 31, 37 ) --Old Cash Out, Exchange, Saba Promotion
		GROUP BY CASE WHEN d.Site IN ('BEST-ODDS', 'XYZBET', '8RM') THEN 'XYZ & BO'
				WHEN d.Site IN ('611111') THEN '611 (Chi)'
				WHEN d.Site IN ('733333') THEN '733 (Mala)'
				WHEN d.Site IN ('755555') THEN '755 (Thai)'
				WHEN d.Site IN ('INDO') THEN 'Indo'
				WHEN d.Site IN ('IBCIndo') THEN 'IbcIndo'
				WHEN d.Site IN ('76666B') THEN 'Myanmar'
				WHEN pb.ProductID = 1 AND d.Site IN ('789y', 'y987') THEN 'Y SB'
				WHEN pb.ProductID <> 1 AND d.Site IN ('789y', 'y987') THEN 'Y NS'
				WHEN (d.IsDeposit = 0 OR d.Site IN ('Saba789')) THEN 'Other Credit'
				WHEN d.IsDeposit = 1 AND d.Site LIKE '%CV' AND pb.ProductID = 1 THEN 'CV SB'
				WHEN d.IsDeposit = 1 AND d.Site LIKE '%CV' AND pb.ProductID <> 1 THEN 'CV NS'
				WHEN d.IsDeposit = 1 AND pb.ProductID = 1 THEN 'C SB'
				WHEN d.IsDeposit = 1 AND pb.ProductID <> 1 THEN 'C NS'
			END
	)
	,CTE_SubTotalSite AS (
		SELECT CASE WHEN pb.ProductID = 1 THEN 'T SB'
				WHEN pb.ProductID <> 1 THEN 'T NS'
			END AS SiteName
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
			INNER JOIN #tmpProductBettype AS pb WITH (NOLOCK) ON d.Bettype = pb.Bettype
		-- WHERE pb.ProductID NOT IN ( 25, 31, 37 ) --Old Cash Out, Exchange, Saba Promotion
		GROUP BY CASE WHEN pb.ProductID = 1 THEN 'T SB'
				WHEN pb.ProductID <> 1 THEN 'T NS'
			END
	)
	,CTE_8RM AS (
		SELECT 'BySite_8RM' AS SiteName
			,SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossMem --Member view - opposite of above WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
		WHERE d.Site = '8RM'
		GROUP BY d.Site
	)
	,CTE_TotalSite AS (
		SELECT 'GRAND TOTAL' AS SiteName
			,SUM(ISNULL(WinlossIBC,0)) AS WinlossIBC 
			,SUM(ISNULL(TurnoverIBC,0)) AS TurnoverIBC
		FROM (
			SELECT WinlossIBC
				,TurnoverIBC
			FROM CTE_SubTotalSite
			
			UNION ALL
			
			SELECT WinlossMem AS WinlossIBC
				,TurnoverIBC
			FROM CTE_8RM
		) AS t
	)
	INSERT INTO #tmpResult (
		GroupName
		,WinlossIBC
		,TurnoverIBC
	)
	SELECT SiteName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_ProductSite
	
	UNION ALL
	
	SELECT SiteName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_SubTotalSite

	UNION ALL

	SELECT SiteName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_TotalSite
	
	UNION ALL

	SELECT SiteName
		,WinlossMem
		,TurnoverIBC
	FROM CTE_8RM
	
	------------------------------GroupBySB-------------------------------
	DECLARE @SabaLeagueGroupID VARCHAR(500)
	SELECT @SabaLeagueGroupID = VValue
	FROM DBWH.bodb_account.dbo.SystemSettings WITH (NOLOCK)
	WHERE VID = 5
	
	;WITH CTE_SabaLG AS (
		SELECT CONVERT(SMALLINT, val) AS LeagueGroupID
		FROM dbo.strSplit(@SabaLeagueGroupID, ',')
	)
	,CTE_Sport AS (
		SELECT CASE WHEN l.SportType = 1 AND sl.LeagueGroupID IS NULL AND d.LiveStatus = 1 THEN 'Real.Soc(L)'
				WHEN l.SportType = 1 AND sl.LeagueGroupID IS NULL AND d.LiveStatus = 0 THEN 'Real.Soc(NL)'
				WHEN l.SportType = 1 AND l.LeagueGroupId = 113 THEN 'Soccer PG'
				WHEN l.SportType = 1 AND sl.LeagueGroupID IS NOT NULL THEN 'Saba.Soc'
				
				WHEN l.SportType = 2 AND sl.LeagueGroupID IS NULL THEN 'Real.Bas'
				WHEN l.SportType = 2 AND l.LeagueGroupId = 122 THEN 'Basket PG'
				WHEN l.SportType = 2 AND sl.LeagueGroupID IS NOT NULL THEN 'Saba.Bas'
				
				WHEN l.SportType = 43 AND sl.LeagueGroupID = 151 THEN 'S.E-SPG'
				WHEN l.SportType = 43 THEN 'E-Spo'
				
				WHEN l.SportType = 5 AND sl.LeagueGroupID IS NULL THEN 'Real.Ten'
				WHEN l.SportType = 5 THEN 'Saba.Ten'
				
				WHEN l.SportType = 50 THEN 'Cricket'
				WHEN d.LeagueID = @Parl_LeagueID THEN 'Parl'
				ELSE 'Others'
			END AS SportName
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
			LEFT JOIN dbo.League AS l WITH (NOLOCK) ON d.LeagueID = l.LeagueID
			LEFT JOIN CTE_SabaLG AS sl ON l.LeagueGroupID = sl.LeagueGroupID
		WHERE ( d.LeagueID <> @NS_LeagueID OR d.Site = '8RM')
			AND d.Bettype NOT IN (
				SELECT DISTINCT Bettype
				FROM dbo.SportBettypeMatrix WITH (NOLOCK)
				WHERE SubProduct IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			)
		GROUP BY CASE WHEN l.SportType = 1 AND sl.LeagueGroupID IS NULL AND d.LiveStatus = 1 THEN 'Real.Soc(L)'
				WHEN l.SportType = 1 AND sl.LeagueGroupID IS NULL AND d.LiveStatus = 0 THEN 'Real.Soc(NL)'
				WHEN l.SportType = 1 AND l.LeagueGroupId = 113 THEN 'Soccer PG'
				WHEN l.SportType = 1 AND sl.LeagueGroupID IS NOT NULL THEN 'Saba.Soc'
				
				WHEN l.SportType = 2 AND sl.LeagueGroupID IS NULL THEN 'Real.Bas'
				WHEN l.SportType = 2 AND l.LeagueGroupId = 122 THEN 'Basket PG'
				WHEN l.SportType = 2 AND sl.LeagueGroupID IS NOT NULL THEN 'Saba.Bas'
				
				WHEN l.SportType = 43 AND sl.LeagueGroupID = 151 THEN 'S.E-SPG'
				WHEN l.SportType = 43 THEN 'E-Spo'
				
				WHEN l.SportType = 5 AND sl.LeagueGroupID IS NULL THEN 'Real.Ten'
				WHEN l.SportType = 5 THEN 'Saba.Ten'
				
				WHEN l.SportType = 50 THEN 'Cricket'
				WHEN d.LeagueID = @Parl_LeagueID THEN 'Parl'
				ELSE 'Others'
			END
	)
	,CTE_RealSoc AS (
		SELECT 'Real.Soc' AS SportName
			,SUM(ISNULL(WinlossIBC,0)) AS WinlossIBC
			,SUM(ISNULL(TurnoverIBC,0)) AS TurnoverIBC
		FROM CTE_Sport
		WHERE SportName IN ('Real.Soc(L)', 'Real.Soc(NL)')
	)
	,CTE_Total AS (
		SELECT 'TOTAL SB' AS SportName
			,SUM(ISNULL(WinlossIBC,0)) AS WinlossIBC
			,SUM(ISNULL(TurnoverIBC,0)) AS TurnoverIBC
		FROM CTE_Sport
	)
	,CTE_8RM AS (
		SELECT 'BySport_8RM' AS SportName
			,SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossMem --Member view - opposite of above WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
		WHERE d.Site = '8RM'
			AND d.Bettype NOT IN (
				SELECT DISTINCT Bettype
				FROM dbo.SportBettypeMatrix WITH (NOLOCK)
				WHERE SubProduct IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			)
	)
	INSERT INTO #tmpResult (
		GroupName
		,WinlossIBC
		,TurnoverIBC
	)
	SELECT SportName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_Sport
	
	UNION ALL
	
	SELECT SportName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_RealSoc
	
	UNION ALL
	
	SELECT SportName
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_Total
	
	UNION ALL
	
	SELECT SportName
		,WinlossMem
		,TurnoverIBC
	FROM CTE_8RM
	
	--------------------------Group By Pool House-------------------------
	INSERT INTO #tmpSportBettypeGroup (
		SportType
		,BetType
	)
	SELECT SportType
		,BetType
	FROM DBWH.bodb_account.dbo.SportBettypeGroup WITH (NOLOCK)
	WHERE GroupID = 1 --PHAIO
	GROUP BY SportType
		,BetType
	CREATE CLUSTERED INDEX CIX_tmpSportBettypeGroup ON #tmpSportBettypeGroup (BetType, SportType)
	
	;WITH CTE_PH_Normal AS (
		SELECT 'PHAIO' AS Market
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
			INNER JOIN dbo.League AS l WITH (NOLOCK) ON d.LeagueID = l.LeagueID
			INNER JOIN #tmpSportBettypeGroup AS sbg WITH (NOLOCK) ON l.SportType = sbg.SportType AND d.BetType = sbg.BetType
		WHERE d.BetType NOT IN (9, 29)
	)
	,CTE_PH_Parlay AS (
		SELECT 'PHAIO' AS Market
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
		WHERE d.BetType IN (SELECT DISTINCT BetType FROM #tmpSportBettypeGroup WITH (NOLOCK) WHERE BetType IN (9, 29))
	)
	,CTE_TimeM AS (
		SELECT CASE WHEN sbg.BetType = 229 THEN 'TimeM_HDP'
			ELSE 'TimeM_OU'
			END AS Market
			,SUM(-(WinlossIBC - ExtraWL + CommissionS - ExtraComm)) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData AS d WITH (NOLOCK)
			INNER JOIN dbo.League AS l WITH (NOLOCK) ON d.LeagueID = l.LeagueID
			INNER JOIN #tmpSportBettypeGroup AS sbg WITH (NOLOCK) ON l.SportType = sbg.SportType AND d.BetType = sbg.BetType
		WHERE d.BetType IN (228, 229)
		GROUP BY CASE WHEN sbg.BetType = 229 THEN 'TimeM_HDP'
			ELSE 'TimeM_OU'
			END
	)
	INSERT INTO #tmpResult (
		GroupName
		,WinlossIBC
		,TurnoverIBC
	)
	SELECT Market
		,SUM(WinlossIBC) AS WinlossIBC
		,SUM(TurnoverIBC) AS TurnoverIBC
	FROM (
		SELECT Market
			,WinlossIBC
			,TurnoverIBC
		FROM CTE_PH_Normal
		
		UNION ALL
		
		SELECT Market
			,WinlossIBC
			,TurnoverIBC
		FROM CTE_PH_Parlay
		
		UNION ALL
		
		SELECT Market
			,WinlossIBC
			,TurnoverIBC
		FROM CTE_TimeM
	) AS ph
	GROUP BY Market
	
	--Remove redundant data--
	DELETE #tmpResult
	WHERE GroupName IS NULL
		OR (ISNULL(TurnoverIBC,0) = 0 AND ISNULL(WinlossIBC,0) = 0)
	
	DELETE o
	FROM #tmpOrderByGroupName AS o
		LEFT JOIN #tmpResult AS r ON r.GroupName = o.GroupName
	WHERE o.IsTitle <> 1
		AND r.GroupName IS NULL
	
	--Return Result Set--
	SELECT o.GroupID
		,(CASE WHEN o.GroupName IN ('BySite_8RM','BySport_8RM') THEN '8RM' ELSE o.GroupName END) AS GroupName
		,(CASE WHEN o.GroupID IN (1, 2) THEN WinlossIBC ELSE TurnoverIBC END) AS HWL_TO --GroupID IN (1,2) => return WL
		,(CASE WHEN o.IsTitle = 1 THEN NULL
			WHEN ISNULL(TurnoverIBC,0) = 0 THEN 0
		ELSE ISNULL(WinlossIBC,0)/TurnoverIBC
		END) AS Margin
	FROM #tmpOrderByGroupName AS o
		LEFT JOIN #tmpResult AS r ON r.GroupName = o.GroupName
	ORDER BY o.GroupID
		,o.OrderNo
	
	SELECT @Title AS Title
	
	DROP TABLE #tmpDWSite
	DROP TABLE #tmpMatch
	DROP TABLE #tmpTestLeague
	DROP TABLE #tmpRecommend
	DROP TABLE #tmpCustomer
	DROP TABLE #tmpProductBettype
	DROP TABLE #tmpDWBettypeSource
	DROP TABLE #tmpBettypeGroup
	DROP TABLE #tmpRawData
	DROP TABLE #tmpResult
	DROP TABLE #tmpSportBettypeGroup
	DROP TABLE #tmpOrderByGroupName
END

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel
	@WinlostDate SMALLDATETIME
	,@Divisions VARCHAR(MAX) = 'ALL'
	,@DangerLevels VARCHAR(10) = '50'
	,@SportBettypes VARCHAR(MAX) = 'ALL'
	,@LeagueName NVARCHAR(500) = 'ALL'
	,@LeagueGroupIDs VARCHAR(MAX) = 'ALL'
	,@LiveStat VARCHAR(10) = 'ALL'
	,@TopUsers INT = 10
AS
/*
	Created: 20210105@Roy
	Task : Get SB Customer Performance filtered by ABI danger level
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		
	Param's Explanation:
		@Divisions: List of site names
		@DangerLevels: danger level - blank for all
		@SportBettypes: List of Sporttypes and Bettypes with format: Sport_Bettype (ex: 43_2,29_9)
		@LeagueName: exactly league name - 'All Leagues' for all
		@LeagueGroupIDs: List of LeagueGroups by IDs
		@LiveStat: ALL, Non-Live, Live
		@TopUsers: No. of user order by member winlost
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel
											@WinlostDate SMALLDATETIME = '2020-12-06'
											,@Divisions VARCHAR(MAX) = 'ALL'
											,@DangerLevels VARCHAR(10) = ''
											,@SportBettypes VARCHAR(MAX)= 'ALL'
											,@LeagueName NVARCHAR(500)= 'All Leagues'
											,@LeagueGroupIDs VARCHAR(MAX) = 'ALL'
											,@LiveStat VARCHAR(10) = 'All'
											,@TopUsers INT = 1000
*/
BEGIN

	SET NOCOUNT ON
	
	DECLARE @StartDate SMALLDATETIME
		,@EndDate SMALLDATETIME
		,@IsLive BIT
		,@AssoSQLStr NVARCHAR(MAX)
		,@AssoParmDefStr NVARCHAR(MAX)
		,@UserIDs VARCHAR(MAX) = ''

	---Create temp tables---
	CREATE TABLE #tmpSportBettypes (
		SportType SMALLINT
		,Bettype SMALLINT
	)
	CREATE TABLE #tmpMatch (
		MatchID INT		
		,MatchType TINYINT
		,SportType SMALLINT
	)
	CREATE TABLE #tmpAgentBySite (
		AgentID INT
	)
	CREATE TABLE #tmpDangerLevel (
		DangerLevel INT
	)
	CREATE TABLE #tmpRawData (
		CustID INT
		,UserName NVARCHAR(50)
		,DangerLevel INT
		,AgentID INT
		,MasterID INT
		,SuperID INT
		,MatchID INT
		,MatchType TINYINT
		,Bettype SMALLINT
		,Currency TINYINT
		,BetCount INT
		,MemberTO DECIMAL(25, 8)
		,MemberWL DECIMAL(25, 8)
		,RealIncome DECIMAL(25, 8)
		,RealTurnover DECIMAL(25, 8)
	)
	CREATE TABLE #tmpFiltered (
		CustID INT
		,UserName NVARCHAR(50)
		,DangerLevel INT
		,AgentID INT
		,MasterID INT
		,SuperID INT
		,Currency NVARCHAR(50)
		,BetCount INT
		,MemberTO DECIMAL(19, 2)
		,MemberWL DECIMAL(19, 2)
		,RealIncome DECIMAL(19, 2)
		,RealTurnover DECIMAL(19, 2)
	)
	CREATE TABLE #tmpNoAssocByCust (
		CustID INT
		,NoAssoc INT
	)
	/*
		parse and clean up parameters
	*/
	SET @StartDate = CAST(@WinlostDate AS date)--remove time part
	SET @EndDate = DATEADD(dd, 1, @StartDate)
	
	---TopUsers---
	IF @TopUsers < 0
		SET @TopUsers = 0

	---Live Status---
	IF @LiveStat = 'Live'
		SET @IsLive = 1
	ELSE IF @LiveStat = 'Non-Live'
		SET @IsLive = 0

	/*
		Define Agent by site name
		From: @Divisions
		To: #tmpAgentBySite ( AgentID )
	*/
	IF @Divisions <> 'ALL'
	BEGIN
		;WITH CTE_Sites AS (
			SELECT val SiteName
			FROM dbo.strSplit(@Divisions, ',')
			WHERE LEN(val) > 0
		)
		INSERT INTO #tmpAgentBySite
		SELECT c.custid
		FROM dbo.CustAgent AS c WITH (NOLOCK)
			INNER JOIN CTE_Sites cte ON c.site = cte.SiteName
		GROUP BY c.custid
		
		CREATE CLUSTERED INDEX [CIX_tmpAgentBySite] ON #tmpAgentBySite( AgentID )
	END

	/*
		Define DangerLevel
		From: @DangerLevels
		To: #tmpDangerLevel ( DangerLevel )
	*/
	SET @DangerLevels = REPLACE(@DangerLevels, ' ', '')
	IF LEN(@DangerLevels) > 0
	BEGIN
		INSERT INTO #tmpDangerLevel
		SELECT CONVERT(INT, val)
		FROM dbo.strSplit(@DangerLevels, ',')
		WHERE LEN(val) > 0
			AND ISNUMERIC(val + '.0e0') = 1
	END
	ELSE
	BEGIN
		SET @DangerLevels = 'ALL'
	END

	/*
		Define SportBettypes
		From: @SportBettypes
		To: #tmpSportBettypes ( SportType, BetType )
		Desc: if @SportBettypes = 'ALL', this table is SportBettypeMatrix
	*/
	SET @SportBettypes = REPLACE(@SportBettypes, ' ', '')
	;WITH CTE_SportBettype AS (
		SELECT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS SportType
			,CAST(SUBSTRING(val, CHARINDEX('_', val) + 1, LEN(val)) AS SMALLINT) AS BetType
		FROM dbo.strSplit(REPLACE(@SportBettypes, ' ', ''), ',')
		WHERE val <> 'ALL'
			AND LEN(val) > 0
	)
	INSERT INTO #tmpSportBettypes (
		SportType
		,BetType
	)
	SELECT DISTINCT sbm.SportType
		,sbm.BetType
	FROM dbo.SportBettypeMatrix sbm(NOLOCK)
		INNER JOIN dbo.bettype b(NOLOCK) ON sbm.BetType = b.typeid
	WHERE sbm.ProductID = 1
		AND sbm.SportType <> 27 --Cricket (use 50)
		AND sbm.SubProduct NOT IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
		AND sbm.BetType NOT IN (9, 29, 999) --Parlay & Odds Spread Adjustment
		AND (
			@SportBettypes = 'ALL'
			OR EXISTS (
				SELECT 1
				FROM CTE_SportBettype psb
				WHERE sbm.SportType = psb.SportType
					AND sbm.BetType = psb.BetType
				)
			)
	CREATE CLUSTERED INDEX [CIX_tmpsb] ON #tmpSportBettypes( SportType, BetType )

	/*
		Define Match
		From: @LeagueGroupIDs, @LeagueName, #tmpSportBettypes
		To: #tmpMatch ( MatchID, MatchType, SportType )
		Desc: get all matches filtered by sport and league (use MatchType to determine *match* and *outright*)
	*/
	SET @LeagueGroupIDs = REPLACE(@LeagueGroupIDs, ' ', '')
	;WITH CTE_League AS (
		SELECT l.leagueid
			,ISNULL(lg.GroupID, - 1) AS GroupID
			,l.SportType
		FROM dbo.League l(NOLOCK)
			LEFT JOIN dbo.LeagueGroup lg(NOLOCK) ON l.LeagueGroupID = lg.GroupID
		WHERE l.isTest = 0
			AND l.leagueid >= 0
			AND (
				@LeagueName = 'All Leagues'
				OR l.leaguename = @LeagueName
				)
			AND lg.IsActive = 1
		GROUP BY l.leagueid
			,lg.GroupID
			,l.SportType
	)
	,CTE_LeagueGroup AS (
		SELECT CAST(val AS SMALLINT) GroupID
		FROM dbo.strSplit(@LeagueGroupIDs, ',')
		WHERE ISNUMERIC(val + '.0e0') = 1
		GROUP BY val
	)
	,CTE_Matches AS (
		SELECT MatchID
			,0 MatchType
			,LeagueID
		FROM dbo.match WITH (NOLOCK)
		WHERE eventdate = @StartDate
		
		UNION ALL
		
		SELECT orid MatchID
			,1 MatchType
			,LeagueID
		FROM dbo.outright WITH (NOLOCK)
		WHERE eventdate = @StartDate
	)
	INSERT INTO #tmpMatch (
		MatchID
		,MatchType
		,SportType
	)
	SELECT m.MatchID
		,m.MatchType
		,l.SportType
	FROM CTE_Matches m
		INNER JOIN CTE_League l ON m.LeagueID = l.LeagueID
	WHERE (
			@LeagueGroupIDs = 'ALL'
			OR EXISTS ( SELECT 1 FROM CTE_LeagueGroup lg WHERE l.GroupID = lg.GroupID )
		)
		AND (
			@SportBettypes = 'ALL'
			OR EXISTS (
				SELECT 1
				FROM #tmpSportBettypes sb
				WHERE l.SportType = sb.SportType
				)
		)
	GROUP BY m.MatchID
		,m.MatchType
		,l.SportType
	CREATE CLUSTERED INDEX [CIX_tmpMatch] ON #tmpMatch( MatchType, MatchID )

	/*
		Get raw data
		From: bettrans, #tmpSportBettypes, @LiveStat, @Divisions, @DangerLevels
		To: #tmpData
		Desc: get raw data filtered by WLdate, bettype, Liveindicator, SiteNames, DangerLevel
	*/
	INSERT INTO #tmpRawData (
		CustID
		,UserName
		,DangerLevel
		,AgentID
		,MasterID
		,SuperID
		,MatchID
		,MatchType
		,Bettype
		,Currency
		,BetCount
		,MemberTO
		,MemberWL
		,RealIncome
		,RealTurnover
	)
	SELECT b.CustID
		,c.UserName
		,ISNULL(CONVERT(INT, c.danger2), -1) DangerLevel
		,b.Recommend
		,b.mRecommend
		,b.sRecommend
		,b.Matchid
		,(CASE WHEN b.Bettype = 10 THEN 1 ELSE 0 END) AS MatchType
		,b.Bettype
		,b.Currency
		,SUM(CASE WHEN co.VendorID = 14 THEN 0 ELSE 1 END) AS BetCount -- Exclude Dummy Cashout accounts
		,SUM(abs(b.stake)) AS MemberTO
		,SUM(b.winlost - b.actual_stake) MemberWL
		,-SUM((b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm - (CASE WHEN b.tpositiontaking = 1 THEN 0
																								ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)
																							END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.actualrate) AS RealIncome
		,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
				ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0))
						* ABS(stake)
						* (CASE WHEN b.virtualrate > b.actualrate THEN b.virtualrate
							ELSE b.actualrate END)
			END) AS RealTurnover
	FROM dbo.bettrans AS b WITH (NOLOCK)
		LEFT JOIN dbo.custInfo AS c WITH (NOLOCK) ON (c.roleid = 1 AND b.CustID = c.CustID)
		LEFT JOIN dbo.TradeCust AS co WITH (NOLOCK) ON b.CustID = co.CustID
	WHERE Winlostdate >= @StartDate AND Winlostdate < @EndDate
		AND b.Ruben = 1
		AND b.StatusID IN (111, 112, 113)
		AND b.Currency NOT IN (20, 27, 28)
		AND b.Bettype IN ( SELECT DISTINCT BetType FROM #tmpSportBettypes )
		AND b.Liveindicator = ISNULL(@IsLive, b.Liveindicator)
		AND ('ALL' = @Divisions OR b.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
		AND ('ALL' = @DangerLevels OR c.danger2 IN (SELECT DangerLevel FROM #tmpDangerLevel))
		AND @TopUsers > 0
	GROUP BY b.CustID
		,c.UserName
		,ISNULL(CONVERT(INT, c.danger2), -1)
		,b.Recommend
		,b.mRecommend
		,b.sRecommend
		,b.Matchid
		,(CASE WHEN b.Bettype = 10 THEN 1 ELSE 0 END)
		,b.Bettype
		,b.Currency
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_tmpRawData] ON #tmpRawData(
		Bettype
		,MatchType
		,MatchID
		,CustID
		,UserName
		,DangerLevel
		,AgentID
		,MasterID
		,SuperID
		,Currency
	)
	
	/*
		Get TOP (@TopUsers) data by SportBettypes
		From: #tmpRawData, #tmpSportBettypes, #tmpMatch
		To: #tmpFiltered
	*/
	INSERT INTO #tmpFiltered (
		CustID
		,UserName
		,DangerLevel
		,AgentID
		,MasterID
		,SuperID
		,Currency
		,BetCount
		,MemberTO
		,MemberWL
		,RealIncome
		,RealTurnover
	)
	SELECT TOP (@TopUsers) CustID
		,UserName
		,DangerLevel
		,AgentID
		,MasterID
		,SuperID
		,Currency
		,BetCount
		,MemberTO
		,MemberWL
		,RealIncome
		,RealTurnover
	FROM (
		SELECT d.CustID
			,d.UserName
			,d.DangerLevel
			,d.AgentID
			,d.MasterID
			,d.SuperID
			,e.Currency
			,SUM(d.BetCount) BetCount
			,SUM(d.MemberTO) MemberTO
			,SUM(d.MemberWL) MemberWL
			,SUM(d.RealIncome) RealIncome
			,SUM(d.RealTurnover) RealTurnover
		FROM #tmpRawData d
			INNER JOIN #tmpSportBettypes sb ON d.Bettype = sb.Bettype
			INNER JOIN #tmpMatch m ON d.MatchType = m.MatchType AND d.Matchid = m.Matchid AND sb.SportType = m.SportType
			INNER JOIN dbo.Exchange AS e WITH (NOLOCK) ON d.Currency = e.ExchangeId
		GROUP BY d.CustID
			,d.UserName
			,d.DangerLevel
			,d.AgentID
			,d.MasterID
			,d.SuperID
			,e.Currency
	) tmp
	ORDER BY MemberWL DESC
		,UserName

	CREATE CLUSTERED INDEX [CIX_tmpFiltered] ON #tmpFiltered (
		SuperID
		,MasterID
		,AgentID
		,CustID
	)

	/*
		Get "No. Associated Accounts"
		From: #tmpFiltered
		To: #tmpNoAssocByCust
	*/
	SET @AssoSQLStr = N'EXEC bodb_dwrs.dbo.Acc_Rpt_SBCustPerfByDangerLevel_CTSAssociation @CustIDs'
	SET @AssoParmDefStr = N'@CustIDs VARCHAR(MAX)'
	
	---Parse all member Ids to string---
	SELECT @UserIDs = @UserIDs + CONVERT(VARCHAR, CustID) + ',' from #tmpFiltered
	SET @UserIDs = SUBSTRING(@UserIDs, 0, LEN(@UserIDs))

	INSERT INTO #tmpNoAssocByCust
	EXECUTE DBWH.master.dbo.sp_executesql @AssoSQLStr
										,@AssoParmDefStr
											,@UserIDs
	
	CREATE CLUSTERED INDEX [CIX_tmpNoAssocByCust] ON #tmpNoAssocByCust ( CustID	)

	---Return result---
	SELECT d.UserName
		,a.UserName AgentName
		,m.UserName MasterName
		,s.UserName SuperName
		,a.Site Division
		,d.Currency
		,CASE WHEN d.DangerLevel <= 0 THEN 'None' ELSE CONVERT(CHAR, d.DangerLevel) END DangerLevel
		,SUM(d.BetCount) BetCount
		,SUM(d.MemberTO) MemberTO
		,SUM(d.MemberWL) MemberWL
		,SUM(d.RealTurnover) HouseTO
		,SUM(d.RealIncome) 	HouseIncome		
		,SUM(ISNULL(assoc.NoAssoc, 0)) NoAssoc
	FROM #tmpFiltered d
		LEFT JOIN dbo.Customer AS s WITH (NOLOCK) ON ( s.roleid = 4 AND d.SuperID = s.CustID )
		LEFT JOIN dbo.Customer AS m WITH (NOLOCK) ON ( m.roleid = 3 AND d.MasterID = m.CustID )
		LEFT JOIN dbo.Customer AS a WITH (NOLOCK) ON ( a.roleid = 2 AND d.AgentID = a.CustID )
		LEFT JOIN #tmpNoAssocByCust AS assoc ON d.CustID = assoc.CustID
	GROUP BY d.UserName
		,a.UserName
		,m.UserName
		,s.UserName
		,a.Site
		,d.Currency
		,(CASE WHEN d.DangerLevel <= 0 THEN 'None' ELSE CONVERT(CHAR, d.DangerLevel) END)
	ORDER BY SUM(d.MemberWL) DESC
		,d.UserName

	DROP TABLE #tmpSportBettypes
	DROP TABLE #tmpMatch
	DROP TABLE #tmpAgentBySite
	DROP TABLE #tmpDangerLevel
	DROP TABLE #tmpRawData
	DROP TABLE #tmpFiltered
	DROP TABLE #tmpNoAssocByCust
END

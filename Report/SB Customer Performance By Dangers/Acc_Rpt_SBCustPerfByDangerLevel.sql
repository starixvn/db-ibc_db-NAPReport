/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel
	@WinlostDate SMALLDATETIME
	,@Divisions VARCHAR(MAX) = 'ALL'
	,@DangerLevels VARCHAR(10) = '50'
	,@SportBettypes VARCHAR(MAX) = 'ALL'
	,@LeagueName NVARCHAR(500) = 'All Leagues'
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
											@WinlostDate = '2020-12-06'
											,@Divisions = 'ALL'
											,@DangerLevels = ''
											,@SportBettypes = 'ALL'
											,@LeagueName = 'All Leagues'
											,@LeagueGroupIDs = 'ALL'
											,@LiveStat = 'All'
											,@TopUsers = 1000
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
		,SiteName VARCHAR(10)
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
		,SportType SMALLINT
		,Bettype SMALLINT
		,Currency INT
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
		To: #tmpAgentBySite ( AgentID, SiteName )
		Desc: result data will get this SiteName instead of Customer.Site (exec plan)
	*/
	;WITH CTE_Sites AS (
		SELECT val SiteName
		FROM dbo.strSplit(@Divisions, ',')
		WHERE LEN(val) > 0
		GROUP BY val
	)
	INSERT INTO #tmpAgentBySite (
		AgentID
		,SiteName
	)
	SELECT c.custid
		,c.site
	FROM dbo.CustAgent AS c WITH (NOLOCK)
	WHERE (
		@Divisions <> 'ALL'
		OR c.site IN ( SELECT SiteName FROM CTE_Sites )
	)
	GROUP BY c.custid
		,c.site
	
	CREATE CLUSTERED INDEX [CIX_tmpAgentBySite] ON #tmpAgentBySite( AgentID, SiteName )

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
			,ISNULL(lg.IsActive, 1) IsActive
		FROM dbo.League l(NOLOCK)
			LEFT JOIN dbo.LeagueGroup lg(NOLOCK) ON l.LeagueGroupID = lg.GroupID
		WHERE l.isTest = 0
			AND l.leagueid >= 0
			AND (
				@LeagueName = 'All Leagues'
				OR l.leaguename = @LeagueName
			)
			AND (
				@SportBettypes = 'ALL'
				OR l.SportType IN (
					SELECT DISTINCT sb.SportType
					FROM #tmpSportBettypes sb
					)
			)
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
			OR l.GroupID IN ( SELECT lg.GroupID FROM CTE_LeagueGroup lg )
		)
		AND l.IsActive = 1
	GROUP BY m.MatchID
		,m.MatchType
		,l.SportType
	OPTION (RECOMPILE)

	CREATE CLUSTERED INDEX [CIX_tmpMatch] ON #tmpMatch( MatchID, MatchType, SportType )

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
		,SportType
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
		,ISNULL(CONVERT(INT, c.danger2), -1) AS DangerLevel
		,b.Recommend
		,b.mRecommend
		,b.sRecommend
		,m.SportType
		,b.Bettype
		,b.Currency
		,SUM(CASE WHEN co.VendorID = 14 THEN 0 ELSE 1 END) AS BetCount -- Exclude Dummy Cashout accounts
		,SUM(ABS(b.stake) * b.actualrate ) AS MemberTO
		,SUM((b.winlost - b.actual_stake) * b.actualrate ) AS MemberWL
		,-SUM((b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm - (CASE WHEN b.tpositiontaking = 1 THEN 0
																								ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)
																							END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(10, 8)), 0)) * b.actualrate) AS RealIncome
		,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
				ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(10, 8)), 0))
						* ABS(stake)
						* (CASE WHEN b.virtualrate > b.actualrate THEN b.virtualrate
							ELSE b.actualrate END)
			END) AS RealTurnover
	FROM dbo.bettrans AS b WITH (NOLOCK)
		INNER JOIN #tmpMatch AS m ON (b.Matchid = m.Matchid AND (CASE WHEN b.Bettype = 10 THEN 1 ELSE 0 END) = m.MatchType)
		LEFT JOIN dbo.custInfo AS c WITH (NOLOCK) ON (c.roleid = 1 AND b.CustID = c.CustID)
		LEFT JOIN dbo.TradeCust AS co WITH (NOLOCK) ON b.CustID = co.CustID
	WHERE b.Winlostdate >= @StartDate AND b.Winlostdate < @EndDate
		AND b.Ruben = 1
		AND b.StatusID IN (111, 112, 113)
		AND b.Currency NOT IN (20, 27, 28)
		AND b.Bettype IN ( SELECT DISTINCT BetType FROM #tmpSportBettypes )
		AND ISNULL(b.Liveindicator, 0) = COALESCE(@IsLive, b.Liveindicator, 0)
		AND ('ALL' = @Divisions OR b.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
		AND ('ALL' = @DangerLevels OR c.danger2 IN (SELECT DangerLevel FROM #tmpDangerLevel))
		AND @TopUsers > 0
	GROUP BY b.CustID
		,c.UserName
		,ISNULL(CONVERT(INT, c.danger2), -1)
		,b.Recommend
		,b.mRecommend
		,b.sRecommend
		,m.SportType
		,b.Bettype
		,b.Currency
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_tmpRawData] ON #tmpRawData(
		Bettype
		,SportType
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
		FROM #tmpRawData AS d
			INNER JOIN #tmpSportBettypes AS sb ON d.Bettype = sb.Bettype AND sb.SportType = d.SportType
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
		,DangerLevel DESC
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
	
	---Parse all member Ids to string---
	SELECT @UserIDs = @UserIDs + CONVERT(VARCHAR, CustID) + ','
	FROM #tmpFiltered
	GROUP BY CustID
	SET @UserIDs = SUBSTRING(@UserIDs, 0, LEN(@UserIDs))

	IF LEN(@UserIDs) > 0
	BEGIN
		SET @AssoSQLStr = N'EXEC bodb_dwrs.dbo.Acc_Rpt_SBCustPerfByDangerLevel_CTSAssociation @CustIDs'
		SET @AssoParmDefStr = N'@CustIDs VARCHAR(MAX)'
		
		INSERT INTO #tmpNoAssocByCust ( CustID, NoAssoc )
		EXECUTE DBWH.master.dbo.sp_executesql @AssoSQLStr
											,@AssoParmDefStr
												,@UserIDs
		
		CREATE CLUSTERED INDEX [CIX_tmpNoAssocByCust] ON #tmpNoAssocByCust ( CustID	)
	END

	---Return result---
	SELECT d.UserName
		,a.UserName AgentName
		,m.UserName MasterName
		,s.UserName SuperName
		,a2.SiteName Division
		,d.Currency
		,CASE WHEN d.DangerLevel <= 0 THEN 'None' ELSE CONVERT(VARCHAR, d.DangerLevel) END DangerLevel
		,SUM(d.BetCount) BetCount
		,SUM(d.MemberTO) MemberTO
		,SUM(d.MemberWL) MemberWL
		,SUM(d.RealTurnover) HouseTO
		,SUM(d.RealIncome) 	HouseIncome		
		,SUM(ISNULL(assoc.NoAssoc, 0)) NoAssoc
	FROM #tmpFiltered AS d
		LEFT JOIN dbo.Customer AS s WITH (NOLOCK) ON ( s.roleid = 4 AND d.SuperID = s.CustID )
		LEFT JOIN dbo.Customer AS m WITH (NOLOCK) ON ( m.roleid = 3 AND d.MasterID = m.CustID )
		LEFT JOIN dbo.Customer AS a WITH (NOLOCK) ON ( a.roleid = 2 AND d.AgentID = a.CustID )
		LEFT JOIN #tmpNoAssocByCust AS assoc ON d.CustID = assoc.CustID
		LEFT JOIN #tmpAgentBySite AS a2 ON d.AgentID = a2.AgentID
	GROUP BY d.UserName
		,a.UserName
		,m.UserName
		,s.UserName
		,a2.SiteName
		,d.Currency
		,(CASE WHEN d.DangerLevel <= 0 THEN 'None' ELSE CONVERT(VARCHAR, d.DangerLevel) END)
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
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel
	@FromDate SMALLDATETIME
	,@ToDate SMALLDATETIME
	,@Divisions VARCHAR(MAX) = 'ALL'
	,@DangerLevels VARCHAR(MAX) = '1_50'
	,@SportBettypes VARCHAR(MAX) = 'ALL'
	,@LeagueName NVARCHAR(500) = 'All Leagues'
	,@LeagueGroupIDs VARCHAR(MAX) = 'ALL'
	,@LiveStatus VARCHAR(10) = 'ALL'
	,@TopUsers INT = 10
AS
/*
	Created: 20210105@Roy
	Task : Get SB Customer Performance filtered by ABI danger level
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		20210413@Kean: Add More DangerLevel Filter (#153264)
		20210818@Roy: NAP Report - SB Customer Performance By Dangers Report - Support filter multiple days (#160348)
		202109001@Jaden: Add 2 more Dangerous types (#159779)
		
	Param's Explanation:
		@Divisions: List of site names
		@DangerLevels: List of DangerType and DangerLevel with format: DangerType_DangerLevel (ex: 1_0,2_30,3_20)
						DangerType: 1(Original Level), 2(ABI Level), 3(O.Sports Level)
						DangerLevel: From 1 to 50
		@SportBettypes: List of Sporttypes and Bettypes with format: Sport_Bettype (ex: 43_2,29_9)
		@LeagueName: exactly league name - 'All Leagues' for all
		@LeagueGroupIDs: List of LeagueGroups by IDs
		@LiveStatus: ALL, Non-Live, Live
		@TopUsers: No. of user order by member winlost
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel
											@WinlostDate = '2020-12-06'
											,@Divisions = 'ALL'
											,@DangerLevels = ''
											,@SportBettypes = 'ALL'
											,@LeagueName = 'All Leagues'
											,@LeagueGroupIDs = 'ALL'
											,@LiveStatus = 'All'
											,@TopUsers = 9999
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
		DangerType INT
		,DangerLevel INT
	)
	CREATE TABLE #tmpRawData (
		CustID INT
		,UserName NVARCHAR(50)
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
		,danger  INT
		,danger2 INT
		,danger3 INT
		,danger4 INT
		,danger5 INT
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
		parse and clean up parameters (remove time part)
		make sure get data in range bettrans
	*/
	SELECT @StartDate = MAX(FromDate)
		,@EndDate = DATEADD(DAY, 1, CAST(@ToDate AS DATE))
	FROM (
		SELECT DATEADD(DAY, 1, CAST(MoveBetsDay AS DATE)) AS FromDate
		FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.Age_SelBalanceUpDay')

		UNION ALL

		SELECT CAST(@FromDate AS DATE)
	) AS t
	
	---TopUsers---
	IF @TopUsers < 0
		SET @TopUsers = 0

	---Live Status---
	IF @LiveStatus = 'Live'
		SET @IsLive = 1
	ELSE IF @LiveStatus = 'Non-Live'
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
		@Divisions = 'ALL'
		OR c.site IN ( SELECT SiteName FROM CTE_Sites )
	)
	GROUP BY c.custid
		,c.site
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_tmpAgentBySite] ON #tmpAgentBySite( AgentID, SiteName )

	/*
		Define DangerLevel
		From: @DangerLevels
		To: #tmpDangerLevel ( DangerType,DangerLevel )
	*/
	SET @DangerLevels = REPLACE(@DangerLevels, ' ', '')
	IF LEN(@DangerLevels) > 0 AND @DangerLevels <> 'ALL'
	BEGIN
		INSERT INTO #tmpDangerLevel(DangerType,DangerLevel)
		SELECT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS DangerType
			,CAST(SUBSTRING(val, CHARINDEX('_', val) + 1, LEN(val)) AS SMALLINT) AS DangerLevel
		FROM dbo.strSplit(REPLACE(@DangerLevels, ' ', ''), ',')
		WHERE val <> 'ALL'
			AND LEN(val) > 0
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
	OPTION (RECOMPILE)
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
		WHERE eventdate >= @StartDate
			AND eventdate < @EndDate
		
		UNION ALL
		
		SELECT orid MatchID
			,1 MatchType
			,LeagueID
		FROM dbo.outright WITH (NOLOCK)
		WHERE eventdate >= @StartDate
			AND eventdate < @EndDate
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
		From: bettrans, #tmpSportBettypes, @LiveStatus, @Divisions, @DangerLevels
		To: #tmpData
		Desc: get raw data filtered by WLdate, bettype, Liveindicator, SiteNames, DangerLevel
	*/
	INSERT INTO #tmpRawData (
		CustID
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
		LEFT JOIN dbo.TradeCust AS co WITH (NOLOCK) ON b.CustID = co.CustID
	WHERE b.Winlostdate >= @StartDate AND b.Winlostdate < @EndDate
		AND b.Ruben = 1
		AND b.StatusID IN (111, 112, 113)
		AND b.Currency NOT IN (20, 27, 28)
		AND b.Bettype IN ( SELECT DISTINCT BetType FROM #tmpSportBettypes )
		AND ISNULL(b.Liveindicator, 0) = COALESCE(@IsLive, b.Liveindicator, 0)
		AND ('ALL' = @Divisions OR b.recommend IN (SELECT AgentID FROM #tmpAgentBySite))
		AND @TopUsers > 0
	GROUP BY b.CustID
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
		,danger
		,danger2
		,danger3
		,danger4
		,danger5
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
		,DangerLevelOriginal
		,DangerLevelABI
		,DangerLevelOtherSport
		,DangerLevelBasketball
		,DangerLevelESport
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
			,c.UserName
			,ISNULL(CONVERT(INT, c.danger), -1) AS DangerLevelOriginal
			,ISNULL(CONVERT(INT, c.danger2), -1) AS DangerLevelABI
			,ISNULL(CONVERT(INT, c.danger3), -1) AS DangerLevelOtherSport
			,ISNULL(CONVERT(INT, c.danger4), -1) AS DangerLevelBasketball
			,ISNULL(CONVERT(INT, c.danger5), -1) AS DangerLevelESport
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
			LEFT JOIN dbo.custInfo AS c WITH (NOLOCK) ON (c.roleid = 1 AND d.CustID = c.CustID)
		WHERE 'ALL' = @DangerLevels 
			 OR ISNULL(CONVERT(INT, c.danger), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 1)
			 OR ISNULL(CONVERT(INT, c.danger2), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 2)
			 OR ISNULL(CONVERT(INT, c.danger3), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 3)
			 OR ISNULL(CONVERT(INT, c.danger4), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 4)
			 OR ISNULL(CONVERT(INT, c.danger5), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 5)
		GROUP BY d.CustID
			,c.UserName
			,ISNULL(CONVERT(INT, c.danger), -1)
			,ISNULL(CONVERT(INT, c.danger2), -1)
			,ISNULL(CONVERT(INT, c.danger3), -1)
			,ISNULL(CONVERT(INT, c.danger4), -1)
			,ISNULL(CONVERT(INT, c.danger5), -1)
			,d.AgentID
			,d.MasterID
			,d.SuperID
			,e.Currency
	) tmp
	ORDER BY MemberWL DESC
			,DangerLevelOriginal DESC
			,DangerLevelABI DESC
			,DangerLevelOtherSport DESC
			,UserName
	OPTION (RECOMPILE)
	
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
		,REPLACE(LTRIM(RTRIM(
				CASE WHEN d.danger > 0 THEN 'Ori@' + cast(d.danger as varchar(3)) ELSE '' END
				+ CASE WHEN d.danger2 > 0 THEN ' ABI@' + cast(d.danger2 as varchar(3)) ELSE '' END
				+ CASE WHEN d.danger4 > 0 THEN ' Basket@' + cast(d.danger4 as varchar(3)) ELSE '' END 
				+ CASE WHEN d.danger5 > 0 THEN ' E-Sport@' + cast(d.danger5 as varchar(3)) ELSE '' END 
				+ CASE WHEN d.danger3 > 0 THEN ' O.Sport@' + cast(d.danger3 as varchar(3)) ELSE '' END 
			)), ' ', ', ') [DangerLevel]
		,SUM(d.BetCount) BetCount
		,SUM(d.MemberTO) MemberTO
		,SUM(d.MemberWL) MemberWL
		,SUM(d.RealTurnover) HouseTO
		,SUM(d.RealIncome) 	HouseIncome		
		,SUM(ISNULL(assoc.NoAssoc, 0)) NumberOfAssociatedAccount 
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
		,REPLACE(LTRIM(RTRIM(
				CASE WHEN d.danger > 0 THEN 'Ori@' + cast(d.danger as varchar(3)) ELSE '' END
				+ CASE WHEN d.danger2 > 0 THEN ' ABI@' + cast(d.danger2 as varchar(3)) ELSE '' END
				+ CASE WHEN d.danger4 > 0 THEN ' Basket@' + cast(d.danger4 as varchar(3)) ELSE '' END 
				+ CASE WHEN d.danger5 > 0 THEN ' E-Sport@' + cast(d.danger5 as varchar(3)) ELSE '' END 
				+ CASE WHEN d.danger3 > 0 THEN ' O.Sport@' + cast(d.danger3 as varchar(3)) ELSE '' END 
			)), ' ', ', ')
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
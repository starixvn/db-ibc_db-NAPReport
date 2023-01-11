/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_SoccerPerfByKOHour
	@KOStartTime4GMT SMALLDATETIME
	,@KOEndTime4GMT SMALLDATETIME
	,@TopLeagueWL TINYINT = 3
	,@LiveStatus TINYINT = 2
AS
/*
	Created: Roy@20220511
	Task: Get top winlost league By KO Time
	DB: DBACC.bodb02

	Revisions:
		20220511@Roy: Letstalk Reports - Top 3 Winning and Loosing Leagues (#172608)
		20230110@Roy: Letstalk Reports - Implement Live Soccer Performance (#182668)

	Param's Explanation:
		@KOStartTime4GMT: The start KO time (GMT-4)
		@KOEndTime4GMT: The end KO time (GMT-4)
		@LiveStatus: 0: Nonlive | 1:Live | 2: All
	
	Example:
		EXEC bodb02.dbo.Acc_Rpt_Letstalk_SoccerPerfByKOHour
			@KOStartTime4GMT = '2022-05-11 00:00:00'
			,@KOEndTime4GMT = '2022-05-11 02:00:00'
*/

BEGIN

	SET NOCOUNT ON

	DECLARE @SabaLeagueGroupID VARCHAR(500)
		,@FWLDate SMALLDATETIME
		,@TWLDate SMALLDATETIME
		,@MoveBetsDay SMALLDATETIME
		,@KOTimeAsText VARCHAR(100)
		,@KOStartTimeGMT8 SMALLDATETIME
		,@KOEndTimeGMT8 SMALLDATETIME
		,@IsLive BIT
	
	CREATE TABLE #tmpRawData (
		LeagueID INT
		,IsHalf BIT
		,Is8RM BIT
		,WinlossIBC DECIMAL(19,4)
		,ExtraWL DECIMAL(19,6)
		,CommissionS DECIMAL(19,4)
		,ExtraComm DECIMAL(19,6)
		,TurnoverIBC DECIMAL(19,4)
		,ExtraTO DECIMAL(19,6)
		,VarianceVR DECIMAL(9,6)
	)
	
	CREATE TABLE #tmpData (
		GroupName VARCHAR(50)
		,LeagueID INT
		,Turnover DECIMAL(19,4)
		,Winloss DECIMAL(19,4)
	)
	
	CREATE TABLE #tmpMatch (
		EventDate SMALLDATETIME
		,MatchID INT
		,LeagueID INT
	)
	
	--Build KO Time as Text
	SELECT @KOStartTimeGMT8 = DATEADD(HOUR, 12, @KOStartTime4GMT)
		,@KOEndTimeGMT8 = DATEADD(MINUTE, -1, DATEADD(HOUR, 12, @KOEndTime4GMT))

		
	IF CONVERT(DATE, @KOStartTimeGMT8) = CONVERT(DATE, @KOEndTimeGMT8)
	BEGIN
		--20220511 - 22:00-23:59 (GMT +8)
		SELECT @KOTimeAsText = CONVERT(VARCHAR, @KOStartTimeGMT8, 112)
				+ ' - '
				+ CONVERT(VARCHAR(5), @KOStartTimeGMT8, 108)
				+ '-'
				+ CONVERT(VARCHAR(5), @KOEndTimeGMT8, 108)
				+ ' (GMT +8)'
	END
	ELSE
	BEGIN
		--20220511-22:00 - 20220511-23:59 (GMT +8)
		SELECT @KOTimeAsText = CONVERT(VARCHAR, @KOStartTimeGMT8, 112)
				+ '-'
				+ CONVERT(VARCHAR(5), @KOStartTimeGMT8, 108)
				+ ' - '
				+ CONVERT(VARCHAR, @KOEndTimeGMT8, 112)
				+ '-'
				+ CONVERT(VARCHAR(5), @KOEndTimeGMT8, 108)
				+ ' (GMT +8)'
	END
	
	--Get Data by KO Time
	SELECT @SabaLeagueGroupID = VValue
	FROM DBWH.bodb_account.dbo.SystemSettings WITH (NOLOCK)
	WHERE VID = 5
	
	IF @LiveStatus IN (0,1)
		SET @IsLive = @LiveStatus
	
	--Get match by GlobalShowTime
	INSERT INTO #tmpMatch (
		EventDate
		,MatchID
		,LeagueID
	)
	SELECT DISTINCT m.EventDate
		,m.MatchID
		,m.LeagueID 
	FROM bodb02.dbo.match AS m WITH (NOLOCK)
	INNER JOIN bodb02.dbo.league AS l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE l.sporttype = 1
		AND (l.LeagueGroupID IS NULL
			OR
			l.LeagueGroupID NOT IN (
				SELECT CONVERT(SMALLINT, val) AS LeagueGroupID
				FROM bodb02.dbo.strSplit(@SabaLeagueGroupID, ',')
				)
			)--Real Soccer only
		AND l.isTest = 0
		AND m.GlobalShowTime >= @KOStartTime4GMT
		AND m.GlobalShowTime < @KOEndTime4GMT
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX tmpMatch ON #tmpMatch (MatchID, LeagueID)
	
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'exec bodb02.dbo.[Age_SelBalanceUpDay]')
	
	SELECT @FWLDate = MIN(EventDate)
		,@TWLDate = MAX(EventDate)
	FROM #tmpMatch
	
	--Get raw data - loop for each day
	WHILE @FWLDate <= @TWLDate
	BEGIN
		IF ( NOT EXISTS (SELECT 1 FROM #tmpMatch WITH (NOLOCK) WHERE EventDate = @FWLDate) --eventdate must be existed in tmpMatch
			OR @FWLDate <= @MoveBetsDay ) --eventdate must be > @MoveBetsDay
		BEGIN
			SELECT @FWLDate = DATEADD(DAY, 1, @FWLDate)
			CONTINUE
		END
		
		INSERT INTO #tmpRawData (
			LeagueID
			,IsHalf
			,Is8RM
			,VarianceVR
			,WinlossIBC
			,ExtraWL
			,CommissionS
			,ExtraComm
			,TurnoverIBC
			,ExtraTO
		)
		SELECT m.LeagueID
			,(CASE WHEN ABS(b.modds) = 0.25 THEN 1 ELSE 0 END) AS IsHalf
			,(CASE WHEN b.recommend = 52466 THEN 1 ELSE 0 END) AS Is8RM
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6)) AS VarianceVR
			--------------------------------------------------------------------------
			,SUM(((b.winlost - b.actual_stake) + b.swinlost + b.mwinlost + b.awinlost) * b.actualrate) AS WinlossIBC
			,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE (b.winlost - b.actual_stake) * b.epositiontaking * b.actualrate
				END) AS ExtraWL 
			,SUM(b.scomm * b.actualrate) AS CommissionS
			,SUM((CASE WHEN b.tpositiontaking = 1 THEN 0
					ELSE b.scomm * b.epositiontaking / (1 - b.tpositiontaking)
				END) * b.actualrate) AS ExtraComm
			--------------------------------------------------------------------------
			,SUM( ABS(b.stake)
				* (1-b.tpositiontaking)
				* b.actualrate ) AS TurnoverIBC
			,SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 
					ELSE ABS(b.stake) * b.epositiontaking
				END) * b.actualrate) AS ExtraTO
		FROM bodb02.dbo.bettrans AS b WITH (NOLOCK)
			INNER JOIN #tmpMatch AS m WITH (NOLOCK) ON b.MatchID = m.MatchID
		WHERE b.winlostdate = @FWLDate
		AND b.statusID IN (112, 113) --Won, Lose
		AND b.currency <> 20
		AND b.bettype NOT IN (29, 38, 10) --exclude parlay, Bet Builder, outright
		AND (@IsLive IS NULL OR b.liveindicator = @IsLive )
		GROUP BY m.LeagueID
			,(CASE WHEN ABS(b.modds) = 0.25 THEN 1 ELSE 0 END)
			,(CASE WHEN b.recommend = 52466 THEN 1 ELSE 0 END)
			,CAST((b.virtualrate / b.actualrate - 1) AS DECIMAL(9,6))
		
		SELECT @FWLDate = DATEADD(DAY, 1, @FWLDate)
	END
	
	CREATE CLUSTERED INDEX tmpRawData ON #tmpRawData(LeagueID, IsHalf, Is8RM)
	
	--Top Win/lose
	;WITH CTE_League AS (
		SELECT LeagueID
			,SUM(CASE WHEN Is8RM = 1 THEN 0 ELSE -(WinlossIBC - ExtraWL + CommissionS - ExtraComm) END) AS WinlossIBC
			,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
				* (CASE WHEN VarianceVR > 0 THEN VarianceVR + 1 ELSE 1 END)
				* (CASE WHEN IsHalf = 1 THEN 0.5 ELSE 1 END)) AS TurnoverIBC
		FROM #tmpRawData WITH (NOLOCK)
		GROUP BY LeagueID
	)
	--TOTAL
	,CTE_Total AS (
		SELECT 'TOTAL' AS GroupName
			,NULL LeagueID
			,SUM(WinlossIBC) AS WinlossIBC
			,SUM(TurnoverIBC) AS TurnoverIBC
		FROM CTE_League
	)
	--Top Winning Leagues
	,CTE_Win AS (
		SELECT TOP (@TopLeagueWL) 'WIN' AS GroupName
			,LeagueID
			,WinlossIBC
			,TurnoverIBC
		FROM CTE_League
		WHERE WinlossIBC > 0
		ORDER BY WinlossIBC DESC
	)
	--Top Losing Leagues
	,CTE_Lose AS (
		SELECT TOP (@TopLeagueWL) 'LOSE' AS GroupName
			,LeagueID
			,WinlossIBC
			,TurnoverIBC
		FROM CTE_League
		WHERE WinlossIBC < 0
		ORDER BY WinlossIBC ASC
	)
	INSERT INTO #tmpData (
		GroupName
		,LeagueID
		,Winloss
		,Turnover
	)
	SELECT GroupName
		,LeagueID
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_Total

	UNION ALL
	
	SELECT GroupName
		,LeagueID
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_Win

	UNION ALL

	SELECT GroupName
		,LeagueID
		,WinlossIBC
		,TurnoverIBC
	FROM CTE_Lose
	
	--Return data
	SELECT GroupName
		,LeagueName
		,Winloss
		,Turnover
	FROM #tmpData AS d
		LEFT JOIN bodb02.dbo.league AS l WITH (NOLOCK) ON d.LeagueID = l.leagueid
	
	--Return KO Time As Text
	SELECT @KOTimeAsText AS KOTimeAsText
	
	DROP TABLE #tmpData
	DROP TABLE #tmpRawData
	DROP TABLE #tmpMatch
END

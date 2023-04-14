/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetJob]
	@MatchID INT,
	@GroupSports INT = 0
AS

/*
	Created by: Dom
	Date:2014-04-29
	Task: Get Job for Windows service
	DB: DBWH.bodb_dwrs
	
	Revisions:
	   2017.10.02@Tom-Add @GroupSports Parameter Input
		  0: Sportbook-Soccer
		  1: Sportbook-OtherSport
		  2: 3rd Sports
	   20180719@Tom:Enhance_the_flow_get_Virtual_Sport(98520)
	   20210423@Roy: NAP Report - Move Save bet db & service (#153147)
	   20221129@Roy: NAP Report - Save Bet Report out of memory (#180701)
	   20230414@Roy: Support - Generate Automail Report (#186908)
		
*/

BEGIN
    SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

	DECLARE @imsGenerateTime INT=1000*60*60 --60 minutes
		,@SportType INT
		,@Eventdate DATE
	
	;WITH CTE AS (
		SELECT l.SportType
			,m.eventdate
		FROM bodb_archive.dbo.match AS m WITH (NOLOCK)
			INNER JOIN bodb02.dbo.league AS l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE m.MatchID = @MatchID
		
		UNION
		
		SELECT l.SportType
			,m.eventdate
		FROM bodb_Account.dbo.match AS m WITH (NOLOCK)
			INNER JOIN bodb02.dbo.league AS l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE m.MatchID = @MatchID
	)
	SELECT @SportType = SportType
		,@Eventdate = eventdate
	FROM CTE
	
	CREATE TABLE #tmpServiceJob (
		JobID INT
		,LiveIndicator BIT
		,Bettype INT
		,TypeName NVARCHAR(100)
		,MatchID INT
		,JobType VARCHAR(10)
	)
	
	IF EXISTS (SELECT MatchID FROM bodb_Account.dbo.ServiceJob s WITH(NOLOCK) WHERE MatchID = @MatchID)
	BEGIN
		INSERT INTO #tmpServiceJob (
			JobID
			,LiveIndicator
			,Bettype
			,TypeName
			,MatchID
			,JobType
		)
		SELECT JobID
			,LiveIndicator
			,Bettype
			,TypeName
			,MatchID
			,JobType
		FROM bodb_account.dbo.ServiceJob WITH(NOLOCK)
		WHERE MatchID = @MatchID
	END
	ELSE
	BEGIN
		DECLARE @MoveBetsDay DATE
			,@BalanceUpDay DATE
			,@StrSQL NVARCHAR(MAX)
	
		SELECT @MoveBetsDay = MoveBetsDay
			,@BalanceUpDay = BalanceUpDay
		FROM OPENQUERY(DBACC, 'exec bodb02.dbo.[Age_SelBalanceUpDay]')
		
		CREATE TABLE #tmpSJob (
			JobID INT IDENTITY(1,1) NOT NULL
			,LiveIndicator BIT
			,Bettype INT
			,TypeName NVARCHAR(100)
			,MatchID INT
			,JobType VARCHAR(10)
		)
		
		SELECT @StrSQL = '
			SELECT MatchID
				,Bettype
				,LiveIndicator
			FROM '+(CASE WHEN @Eventdate < @BalanceUpDay THEN 'bodb_archive.dbo.bettrans_bk'
					WHEN @Eventdate BETWEEN @BalanceUpDay AND @MoveBetsDay THEN 'bodb02.dbo.bettrans14'
					ELSE 'bodb02.dbo.bettrans' END)+' WITH (NOLOCK)
			WHERE winlostdate = '''+ CONVERT(NVARCHAR, @Eventdate, 23)+ '''
				AND matchid IN ('+ CONVERT(NVARCHAR, @MatchID)+ ')
				AND bettype NOT IN ( SELECT bettype FROM bodb02.dbo.f_VSHorseRacingByBettype() )
				AND bettype NOT IN (901, 902, 903, 904)
				AND bettype NOT IN (911, 912, 913, 914, 38)
			GROUP BY MatchID
				,Bettype
				,LiveIndicator'
		
		CREATE TABLE #MatchBettype (
			MatchID INT
			,Bettype INT
			,LiveIndicator BIT
		)
		INSERT INTO #MatchBettype (
				MatchID
				,Bettype
				,LiveIndicator
			)
		EXECUTE DBACC.master.dbo.sp_executesql @StrSQL
		CREATE CLUSTERED INDEX [CIX_MatchBettype] ON #MatchBettype( MatchID, BetType, LiveIndicator )
		
		INSERT INTO #tmpSJob(MatchID,Bettype,LiveIndicator,JobType,TypeName)
		SELECT DISTINCT @MatchID, 0, 0, 'SUM', ''
		FROM #MatchBettype WHERE MatchID = @MatchID
		UNION ALL
		SELECT @MatchID, Bettype, liveindicator, 'TB', typenamee
		FROM #MatchBettype mb INNER JOIN bodb02.dbo.bettype WITH(NOLOCK) ON typeid = mb.bettype
		WHERE MatchID = @MatchID 
			AND (bettype IN (1,3,7,8,20)
				OR bettype BETWEEN 801 AND 808
				)
			AND liveindicator = 0
		UNION ALL
		SELECT @MatchID, Bettype, liveindicator, 'TB', typenamee
		FROM #MatchBettype  mb INNER JOIN bodb02.dbo.bettype WITH(NOLOCK) ON typeid = mb.bettype
		WHERE MatchID = @MatchID 
			AND (bettype IN (1,3,7,8,20)
				OR bettype BETWEEN 801 AND 808
				)
			AND liveindicator = 1
		UNION ALL
		SELECT @MatchID, Bettype, liveindicator, 'BETS', typenamee
		FROM #MatchBettype mb INNER JOIN bodb02.dbo.bettype WITH(NOLOCK) ON typeid = mb.bettype 
		WHERE MatchID = @MatchID 
		UNION ALL
		SELECT DISTINCT @MatchID, 0, 0, 'END',''
		FROM #MatchBettype 
		WHERE MatchID = @MatchID
		
		INSERT INTO #tmpServiceJob (
			JobID
			,LiveIndicator
			,Bettype
			,TypeName
			,MatchID
			,JobType
		)
		SELECT JobID
			,LiveIndicator
			,Bettype
			,TypeName
			,MatchID
			,JobType
		FROM #tmpSJob
		
		DROP TABLE IF EXISTS #tmpSJob
		DROP TABLE IF EXISTS #MatchBettype
	END
	--seperate IsDeposit/Half only for soccer
	IF @SportType = 1
	BEGIN
		;WITH CTE_Dep AS (
			SELECT 1 IsDeposit
			
			UNION ALL
			
			SELECT 0 IsDeposit
		)
		,CTE_Half AS (
			SELECT 1 Half
			
			UNION ALL
			
			SELECT 2 Half
		)
		SELECT JobID,d.IsDeposit,CASE WHEN s.LiveIndicator = 0 THEN 0 ELSE h.Half END AS Half,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate 
		FROM #tmpServiceJob s WITH(NOLOCK)
			INNER JOIN (
				SELECT TOP 1 * FROM bodb_Account.dbo.MatchList ml WITH(NOLOCK) WHERE ml.MatchID = @MatchID
			) ml ON ml.MatchID = s.MatchID
			,CTE_Dep AS d
			,CTE_Half AS h
		WHERE NOT (s.LiveIndicator = 0 AND h.Half = 2) --ignore 2nd half for non-live tickets
		ORDER BY JobID,d.IsDeposit,h.Half,s.LiveIndicator
	END
	ELSE
	BEGIN
		SELECT JobID,2 IsDeposit, 0 Half,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate 
		FROM #tmpServiceJob s WITH(NOLOCK)
			INNER JOIN (
				SELECT TOP 1 * FROM bodb_Account.dbo.MatchList ml WITH(NOLOCK) WHERE ml.MatchID = @MatchID
			) ml ON ml.MatchID = s.MatchID
		ORDER BY JobID
	END
	
	DROP TABLE IF EXISTS #tmpServiceJob

END

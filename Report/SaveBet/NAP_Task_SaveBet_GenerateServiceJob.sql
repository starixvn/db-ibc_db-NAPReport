/*<info serverAlias="DBWH-bodb_Account" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_GenerateServiceJob]
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Generating Job for service.
	DB: DBWH.bodb_Account
	
	Revisions:
		- 20150529@Jim: add Metric Gaming
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20170612@Percy: check bettype of Cash Out [RedmineID: #78160]
		- 20190308@Robert: #109822 - NAP Report - Integrate Bet Builder
		- 20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay DATETIME
		,@MatchID INT
		,@ID INT
		,@Total INT
		,@StrSQL NVARCHAR(MAX)
	
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'exec bodb02.dbo.[Age_SelBalanceUpDay]')
	
	DELETE ServiceJob
	WHERE MatchID IN (
			SELECT MatchList.MatchID
			FROM MatchList WITH (NOLOCK)
			WHERE EventDate <= @MoveBetsDay
				AND JobFinished = 1
				AND JobGenerated = 1
			)
	OPTION (RECOMPILE)
	
	CREATE TABLE #Match (ID INT IDENTITY(1,1), EventDate DATE, MatchID INT)
	
	INSERT INTO #Match (
		EventDate
		,MatchID
	)
	SELECT DISTINCT EventDate
		,MatchID
	FROM MatchList WITH (NOLOCK) 
	WHERE JobGenerated = 0
	
	CREATE UNIQUE CLUSTERED INDEX CIX_tmpMatch ON #Match(MatchID)

	CREATE TABLE #MatchBettype (
		MatchID INT
		,Bettype INT
		,LiveIndicator BIT
	)
	
	DECLARE @FEventDate DATE
		,@TEventDate DATE
	
	SELECT @FEventDate = MIN(EventDate)
		,@TEventDate = MAX(EventDate)
	FROM #Match
	
	INSERT INTO #MatchBettype (
		MatchID
		,Bettype
		,LiveIndicator
	)
	SELECT MatchID
		,Bettype
		,LiveIndicator
	FROM bodb_ODS.dbo.ODS_bettrans WITH (NOLOCK)
	WHERE winlostdate BETWEEN @FEventDate AND @TEventDate
		AND MatchID IN (SELECT MatchID FROM #Match)
		AND bettype NOT IN ( 1231, 1232, 1233, 1237, 1238 --SELECT bettype FROM bodb02.dbo.f_VSHorseRacingByBettype()
			,901, 902, 903, 904
			,911, 912, 913, 914, 38
		)
	GROUP BY MatchID
		,Bettype
		,LiveIndicator
	OPTION(RECOMPILE, MAXDOP 4,  MAX_GRANT_PERCENT = 25)
	
	CREATE CLUSTERED INDEX [CIX_MatchBettype] ON #MatchBettype( MatchID, BetType, LiveIndicator ) 
	
	SELECT @ID = 1
		,@Total = COUNT(*)
	FROM #Match

	WHILE @ID <= @Total
	BEGIN
		SELECT @MatchID=MatchID FROM #Match WHERE ID = @ID
		
		IF(NOT EXISTS(SELECT * FROM #MatchBettype WHERE MatchID=@MatchID))
		BEGIN
			DELETE MatchList WITH(ROWLOCK,UPDLOCK) WHERE MatchID = @MatchID
		END
		ELSE
		BEGIN
			INSERT INTO ServiceJob(MatchID,Bettype,LiveIndicator,JobType,TypeName)
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

			UPDATE MatchList SET JobGenerated = 1 WHERE MatchID = @MatchID
		END
		
		SET @ID = @ID + 1
	END
	
	DROP TABLE #Match
	DROP TABLE #MatchBettype
END

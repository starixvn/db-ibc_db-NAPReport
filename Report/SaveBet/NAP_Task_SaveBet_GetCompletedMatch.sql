/*<info serverAlias="DBWH-bodb_Account" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_GetCompletedMatch]
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Completed match.
	DB: DBWH.bodb_Account
	
	Revisions:
		- 20170704@Robert: Integrate Betradar Virtual Sports Product [RedmineID: #78495]
		- 20180320@Franklin: VS2  [RedmineID: #91098]
		- 20200325@Ned.Le: NAP Report - Incorporate two new sports of Betradar VS (#131117)
		- 20210423@Roy: NAP Report - Move Save bet db & service (#153147)
		- 20211216@Jaden: Add IsDeleted column check (#164376)
		- 20220624@Roy: Keep MatchList only 6mth data (#174508)
		- 20220801@Kean: Use DISTINCT before insert into MatchList table (#176041)
		- 20220805@Roy: Fix duplicate MatchID when insert into MatchList table (#176340)
		- 20221125@Roy: Defer Gen File After Match Complete (#180910)
		- 20230719@Roy: NAP Report - Integrate product Leap Gaming VS (VS3) (#189510)
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @MoveBetsDay DATETIME,
			@CurentDate  DATETIME,
			@iRowCount INT = 20000
	
	CREATE TABLE #tmpMatchList (
		MatchID INT NOT NULL
		,EventDate DATETIME NOT NULL
		,EventStatus VARCHAR(50) NOT NULL
		,JobFinished BIT NOT NULL
		,JobGenerated BIT NOT NULL
		,SportType INT NOT NULL
		,LeagueID INT NOT NULL
		,MatchCode NVARCHAR(100) NOT NULL
		,HomeID INT NOT NULL
		,AwayID INT NOT NULL
	)

	SELECT @CurentDate = CONVERT( VARCHAR(10), GETDATE(), 120)
	
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'exec bodb02.dbo.[Age_SelBalanceUpDay]')
	
	--keep data in 6 month
	WHILE (1 = 1)
	BEGIN
		DELETE TOP (@iRowCount) dbo.MatchList
		WHERE EventDate < DATEADD(mm,-6,@CurentDate)

		IF @@ROWCOUNT < @iRowCount
			BREAK
	END

	INSERT INTO #tmpMatchList (
		MatchID
		,EventDate
		,EventStatus
		,JobFinished
		,JobGenerated
		,SportType
		,LeagueID
		,MatchCode
		,HomeID
		,AwayID
	)
	SELECT DISTINCT MatchID,
		EventDate,
		EventStatus,
		0,
		0,
		sporttype,
		leagueid,
		MatchCode,
		HomeID,
		AwayID
	FROM bodb02.dbo.match WITH ( NOLOCK )
	WHERE matchid NOT IN ( 
			SELECT MatchID
			FROM MatchList
			WHERE eventdate > DATEADD(DD, -15, @MoveBetsDay)
		)
		AND eventdate BETWEEN DATEADD(DD, -1, @CurentDate) AND @CurentDate
		AND eventstatus = 'completed'
		AND ( sporttype < 99
			OR sporttype IN (SELECT DISTINCT sbm.SportType
				 FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
				 WHERE sbm.ProductID IN (5,27,77)--5(VS), 27(VS2), 77 (VS3 - new)
					   AND sbm.EventType = 1)
		)
		AND IsDeleted = 0
	OPTION (RECOMPILE)
	
	--remove duplication MatchID
	;WITH CTE_Dup AS (
		SELECT ROW_NUMBER() OVER ( PARTITION BY MatchID ORDER BY MatchID ) AS rn
			,MatchID
		FROM #tmpMatchList WITH (NOLOCK)
	)
	DELETE
	FROM #tmpMatchList
	WHERE MatchID IN (
			SELECT MatchID
			FROM CTE_Dup
			WHERE rn > 1
			)
	
	INSERT INTO dbo.MatchList (
		MatchID
		,EventDate
		,EventStatus
		,JobFinished
		,JobGenerated
		,SportType
		,LeagueID
		,MatchCode
		,HomeID
		,AwayID
		,GenerateTime
	)
	SELECT MatchID
		,EventDate
		,EventStatus
		,JobFinished
		,JobGenerated
		,SportType
		,LeagueID
		,MatchCode
		,HomeID
		,AwayID
		,GETDATE()--Defer Gen File, add value for GenerateTime => NAP_SaveBet_GetJob will wait after 60mins
	FROM #tmpMatchList
	
	DROP TABLE #tmpMatchList
END

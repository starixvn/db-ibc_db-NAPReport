/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_ListMatchByLeague]
	@SportType INT,
	@LeagueID INT = -1,
	@Date DATETIME	
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Matches by leagueid
	DB: DB06.bodb_ACC
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/	
BEGIN
	SET NOCOUNT ON
	SELECT ml.MatchID
		,ml.MatchCode
		,home.TeamName Home
		,away.TeamName away
		,ml.EventDate
		,ml.SportType
	FROM bodb_Account.dbo.MatchList ml WITH (NOLOCK)
	INNER JOIN bodb02.dbo.Team home WITH (NOLOCK) ON home.teamid = ml.HomeID
	INNER JOIN bodb02.dbo.Team away WITH (NOLOCK) ON away.teamid = ml.AwayID
	WHERE ml.sporttype = @SportType
		AND ( @LeagueID = - 1 OR (ml.LeagueID = @LeagueID) )
		AND ml.EventDate = @Date
		AND ml.JobFinished = 1
	ORDER BY ml.MatchID ASC
END

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetMatchInfo]
	@matchid int
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get match info for report
	DB: DBACC.bodb_ACC
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @EventDate DATETIME
	,@MoveBetsDay DATETIME

	---Get match info---
	;WITH cte_match
	AS (
		SELECT eventdate
		FROM bodb02.dbo.match WITH (NOLOCK)
		WHERE matchid = @matchid
		
		UNION
		
		SELECT eventdate
		FROM bodb02.dbo.match14 WITH (NOLOCK)
		WHERE matchid = @matchid
	)
	SELECT @EventDate = MAX(eventdate)
	FROM cte_match

	---Get MoveBetsDay---
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
	---Get data from bettrans---
	IF @EventDate > @MoveBetsDay
		SELECT
			s.sportname,
			s.SportType,
			m.eventdate, m.matchid,
			m.matchcode, l.leaguename,
			h.teamname Home, a.teamname Away,
			'FT:' + CAST(finalhomescore as varchar(10)) + '-' + CAST(finalawayscore as varchar(10)) FT,
			'HT:' + CAST(hthomescore as varchar(10)) + '-' + CAST(htawayscore as varchar(10)) HT,
			IsNull(GoalRecord, '') Goal,
			CASE LEFT (IsNull(GoalRecord, ''), 1) WHEN 'H' THEN 'FG:Home' WHEN 'A' THEN 'FG:Away' ELSE 'No Goal' END FG,
			CASE RIGHT(IsNull(GoalRecord, ''), 1) WHEN 'H' THEN 'LG:Home' WHEN 'A' THEN 'LG:Away' ELSE '' END LG,
			IsNull(betstatus, '') betstatus
		FROM
			bodb02.dbo.match m with (nolock)
			INNER JOIN bodb02.dbo.league l with (nolock) ON m.leagueid = l.leagueid
			INNER JOIN bodb02.dbo.sports s with (nolock) ON l.sporttype = s.sporttype
			LEFT JOIN bodb02.dbo.team h with (nolock) ON m.homeid = h.teamid
			LEFT JOIN bodb02.dbo.team a with (nolock) ON m.awayid = a.teamid
		WHERE
			matchid = @matchid
	ELSE ---Get data from bettrans14---
		SELECT
			s.sportname,
			s.SportType,
			m.eventdate, m.matchid,
			m.matchcode, l.leaguename,
			h.teamname Home, a.teamname Away,
			'FT:' + CAST(finalhomescore as varchar(10)) + '-' + CAST(finalawayscore as varchar(10)) FT,
			'HT:' + CAST(hthomescore as varchar(10)) + '-' + CAST(htawayscore as varchar(10)) HT,
			IsNull(GoalRecord, '') Goal,
			CASE LEFT (IsNull(GoalRecord, ''), 1) WHEN 'H' THEN 'FG:Home' WHEN 'A' THEN 'FG:Away' ELSE 'No Goal' END FG,
			CASE RIGHT(IsNull(GoalRecord, ''), 1) WHEN 'H' THEN 'LG:Home' WHEN 'A' THEN 'LG:Away' ELSE '' END LG,
			IsNull(betstatus, '') betstatus
		FROM
			bodb02.dbo.match14 m with (nolock)
			INNER JOIN bodb02.dbo.league l with (nolock) ON m.leagueid = l.leagueid
			INNER JOIN bodb02.dbo.sports s with (nolock) ON l.sporttype = s.sporttype
			INNER JOIN bodb02.dbo.team h with (nolock) ON m.homeid = h.teamid
			INNER JOIN bodb02.dbo.team a with (nolock) ON m.awayid = a.teamid
		WHERE
			matchid = @matchid
END

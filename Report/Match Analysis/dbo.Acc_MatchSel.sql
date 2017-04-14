ALTER PROCEDURE [dbo].[Acc_MatchSel]
	@eventdate datetime,
	@leagueids1 varchar(8000) = null,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME	
AS

/*
	Created: Dan
	Date: 2012/04/05
	Task: Get list of matches for report Special match analysis
	DB: DBACC/BODB02

	Revisions:
		- 20120914@Sophia: Revise condition of sporttype: support sportbook, number games, live casino
		- 20120920@Sophia: Only support sportbook
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20131209@Kathy: Add Hr Fixed Odds (154) [Redmine:#6505]
	Parameters Explanations:			
*/
SET NOCOUNT ON
DECLARE @tmp TABLE (ID INT IDENTITY PRIMARY KEY, val INT)

IF (@leagueids1 IS NOT NULL)
	INSERT INTO @tmp(val) SELECT CONVERT(INT,val) FROM dbo.strSplit(@leagueids1,',')

IF (@eventdate>@MoveBetsDay)
BEGIN
	-- get from match
	SELECT leagueid,	m.matchid, matchcode, homeid, awayid, showtime, sporttype		
	FROM dbo.match m WITH (NOLOCK) 
 	WHERE eventdate = @eventdate
		AND (m.sporttype <=99 OR m.sporttype = 154)  --support sportbook
		AND (@leagueids1 IS NULL OR leagueid IN (SELECT val FROM @tmp))		
		AND m.matchcode not like '%hedge%'	--exclude hedge match
		AND m.eventstatus = 'completed'
		AND m.betstatus <> 'Refund'
	ORDER BY sporttype, leagueid, 	matchcode
END
ELSE IF (@eventdate>=@BalanceUpDay)
BEGIN
	-- get from match14	
	SELECT leagueid,	m.matchid, matchcode, homeid, awayid, showtime, sporttype				
	FROM match14 m WITH (NOLOCK) 
 	WHERE eventdate = @eventdate
		AND (m.sporttype <=99 OR m.sporttype = 154) --support sportbook
		AND (@leagueids1 IS NULL OR leagueid IN (SELECT val FROM @tmp))			
		AND m.matchcode not like '%hedge%'	--exclude hedge match
		AND m.eventstatus = 'completed'
		AND m.betstatus <> 'Refund'
	ORDER BY sporttype, leagueid, 	matchcode
END
ELSE 
BEGIN
	-- get from match_bk	 
	SELECT leagueid,	m.matchid, matchcode, homeid, awayid, showtime, sporttype				
	FROM DBARC.BODB_Archive.dbo.match_bk m WITH (NOLOCK) 
 	WHERE eventdate = @eventdate
		AND (m.sporttype <=99 OR m.sporttype = 154)   --support sportbook
		AND (@leagueids1 IS NULL OR leagueid IN (SELECT val FROM @tmp))				
		AND m.matchcode not like '%hedge%'	--exclude hedge match
		AND m.eventstatus = 'completed'
		AND m.betstatus <> 'Refund'
	ORDER BY sporttype, leagueid, 	matchcode
END



GO
GRANT EXECUTE ON [dbo].[Acc_MatchSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_MatchSel] TO [vnteam]
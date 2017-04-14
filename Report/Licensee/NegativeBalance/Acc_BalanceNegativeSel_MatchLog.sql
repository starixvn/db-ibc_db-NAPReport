ALTER PROCEDURE [dbo].[Acc_BalanceNegativeSel_MatchLog]
	 @MatchID	INT,
	 @GroupID	INT = 1 
AS
/*
	Created by: Jamie
	Date: 2013-06-26
	Task: Retreive Match Info and Settlement Log 
	DB: DBLOG/bodb_CustomerLog 
	
	Revisions:
		- 20140304@Elodie: Retreive settlement log for outright
		- 20150918@Elodie: Get Log Action Name by Chinese langague [Red:#43705]
	Param's Explanation: 
		+ @GroupID: 1: Match Single Bet; 2: Match Parlay Bet ; 3: Outright 

*/
BEGIN 
	SET NOCOUNT ON 

	DECLARE @tmpMatch TABLE (
		 MatchID		INT PRIMARY KEY
		,LeagueID		INT
		,MatchCode		VARCHAR(50)
		,EventDate		DATETIME
		,HomeID			INT
		,AwayID			INT
	)
	
	IF @GroupID BETWEEN 1 AND  2 
	BEGIN 

		IF EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.[match] WITH (NOLOCK) WHERE matchid = @MatchID)
		BEGIN 
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 TOP 1 MatchID
					,LeagueID
					,MatchCode
					,EventDate
					,HomeID
					,AwayID
			FROM	bodb02.dbo.[match]  WITH (NOLOCK)
			WHERE	matchid = @MatchID
		END
		ELSE IF EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.[match14] WITH (NOLOCK) WHERE matchid = @MatchID) 
		BEGIN
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 TOP 1 MatchID
					,LeagueID
					,MatchCode
					,EventDate
					,HomeID
					,AwayID
			FROM	bodb02.dbo.[match14]  WITH (NOLOCK)
			WHERE	matchid = @MatchID
		END
		ELSE 
		BEGIN
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 TOP 1 MatchID
					,LeagueID
					,MatchCode
					,EventDate
					,HomeID
					,AwayID
			FROM	DBACC.bodb_archive.dbo.[match_bk]  WITH (NOLOCK)
			WHERE	matchid = @MatchID
		END
	END 
	ELSE IF @GroupID = 3 
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.[outright] WITH (NOLOCK) WHERE orid = @MatchID)
		BEGIN 		
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 orid
					,leagueid
					,matchcode
					,eventdate
					,teamid
					,0
			FROM	bodb02.dbo.[outright] WITH (NOLOCK)	
			WHERE	orid = @MatchID
		END
		ELSE IF EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.[outright14] WITH (NOLOCK) WHERE orid = @MatchID) 
		BEGIN
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 orid
					,leagueid
					,matchcode
					,eventdate
					,teamid
					,0
			FROM	bodb02.dbo.[outright14] WITH (NOLOCK)	
			WHERE	orid = @MatchID		
		END 
		ELSE 
		BEGIN
			INSERT INTO @tmpMatch(
				 MatchID
				,LeagueID
				,MatchCode
				,EventDate
				,HomeID
				,AwayID
			)
			SELECT	 orid
					,leagueid
					,matchcode
					,eventdate
					,teamid
					,0
			FROM	DBACC.bodb_Archive.dbo.[outright_bk] WITH (NOLOCK)	
			WHERE	orid = @MatchID			
		END
		
	END
	SELECT	 MatchID
			,LeagueID
			,MatchCode
			,EventDate
			,HomeID
			,AwayID
	FROM	@tmpMatch

	IF @GroupID BETWEEN 1 AND  2 
	BEGIN
		SELECT	  l.logid
				, l.logdate
				, la.ActionNameEN
				, la.ActionNameCS
				, l.finalhomescore
				, l.finalawayscore
				, l.hthomescore
				, l.htawayscore
		FROM	bodb_CustomerLog.dbo.UserLog_Settle l WITH(NOLOCK)
				LEFT JOIN bodb_CustomerLog.dbo.LogAction la WITH (NOLOCK) ON l.ActionID = la.ActionID
		WHERE	l.MatchID = @MatchID
		ORDER BY	l.LogID ASC 	
	END
	ELSE IF @GroupID = 3
	BEGIN
		SELECT	  l.logid
				, l.logdate
				, la.ActionNameEN
				, la.ActionNameCS
				, l.Result
				, CASE WHEN l.ActionID = 137 AND cast(l.Remark as INT) > 1 THEN 'DeadHeat(' + l.Remark + ')' ELSE '' END AS Remark
		FROM	bodb_CustomerLog.dbo.UserLog_SettleOutright l WITH(NOLOCK)
				LEFT JOIN bodb_CustomerLog.dbo.LogAction la WITH (NOLOCK) ON l.ActionID = la.ActionID
		WHERE	l.MatchID = @MatchID and l.ActionID IN (137,141,139)
		ORDER BY	l.LogID ASC 	
	END
END 

GO 
GRANT EXECUTE ON [dbo].[Acc_BalanceNegativeSel_MatchLog] TO [bodbAdminNet]

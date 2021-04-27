/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_ListLeagueBySport]
	@Date DATETIME,
	@SportType INT
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Leagues by sportid
	DB: DB06.bodb_ACC
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/	
BEGIN
	SET NOCOUNT ON
	SELECT DISTINCT ml.LeagueID
		,l.LeagueName
	FROM bodb_Account.dbo.MatchList ml WITH (NOLOCK)
	INNER JOIN bodb02.dbo.League l WITH (NOLOCK) ON l.LeagueID = ml.LeagueID
	WHERE ml.EventDate = @Date
		AND ml.sporttype = @SportType
	ORDER BY l.LeagueName
END

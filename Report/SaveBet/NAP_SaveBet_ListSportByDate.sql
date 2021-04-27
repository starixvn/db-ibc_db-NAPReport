/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_ListSportByDate]
	@Date DATETIME
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Get Sports by date
	DB: DB06.bodb_ACC
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/	
BEGIN
	SET NOCOUNT ON

	SELECT DISTINCT ml.SportType
		,s.SportName
	FROM bodb_Account.dbo.MatchList ml WITH (NOLOCK)
	INNER JOIN bodb02.dbo.Sports s WITH (NOLOCK) ON s.sporttype = ml.sporttype
	WHERE EventDate = @Date
	ORDER BY ml.SportType

END

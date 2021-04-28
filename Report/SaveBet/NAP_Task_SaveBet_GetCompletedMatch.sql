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
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @movebetdate DATETIME,
			@CurentDate  DATETIME
	SELECT @CurentDate = CONVERT( VARCHAR(10), GETDATE(), 120)
	
	SELECT @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC, 'exec bodb02.dbo.[Age_SelBalanceUpDay]')

	INSERT INTO dbo.MatchList
		   ( MatchID,
			 EventDate,
			 EventStatus,
			 JobFinished,
			 JobGenerated,
			 SportType,
			 LeagueID,
			 MatchCode,
			 HomeID,
			 AwayID
		   )
		   SELECT MatchID,
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
		   WHERE matchid NOT IN( 
								 SELECT matchlist.MatchID
								 FROM MatchList
								 WHERE match.eventdate BETWEEN @movebetdate AND GETDATE())
			 AND eventdate BETWEEN DATEADD(DD, -1, @CurentDate) AND @CurentDate
			 AND eventstatus = 'completed'
			 AND ( sporttype < 99
				OR sporttype IN (SELECT DISTINCT sbm.SportType
								 FROM bodb02.dbo.SportBettypeMatrix sbm (NOLOCK)
								 WHERE sbm.ProductID IN (5,27)
									   AND sbm.EventType = 1)
				)
			OPTION (RECOMPILE)
END

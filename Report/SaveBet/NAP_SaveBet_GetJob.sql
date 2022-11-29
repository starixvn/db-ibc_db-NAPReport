/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetJob]
	@MatchID INT = 0,
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
		
*/

BEGIN
    SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

	DECLARE @imsGenerateTime INT=1000*60*60 --60 minutes
		,@SportType INT

	IF @matchid =0
		BEGIN
			;WITH CTE_MatchList
			AS (
			SELECT TOP 1  MatchID,GenerateTime
			FROM bodb_Account.dbo.MatchList ml WITH(ROWLOCK) 				  
			WHERE JobGenerated = 1 AND JobFinished = 0 AND (GenerateTime IS NULL OR DATEDIFF(ms,GenerateTime,GETDATE())>@imsGenerateTime)
						AND (
							(@GroupSports = 0 AND (ml.sporttype = 1))
							OR (@GroupSports = 1 AND ml.sporttype > 1 AND ml.SportType <100)
							OR (@GroupSports = 2 AND ml.sporttype > 99)
							) 
			ORDER BY ml.EventDate ASC
			)
			UPDATE CTE_MatchList WITH(ROWLOCK,UPDLOCK)
			SET GenerateTime=GETDATE()
				,@MatchID = MatchID;
		END;
	
	SELECT @SportType = l.SportType
	FROM bodb_Account.dbo.match AS m WITH (NOLOCK)
		INNER JOIN bodb02.dbo.league AS l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE m.MatchID = @MatchID
	
	--seperate IsDeposit/Half only for soccer
	IF @SportType = 1
	BEGIN
		;WITH CTE_Dep AS (
			SELECT 1 IsDeposit
			
			UNION ALL
			
			SELECT 0 IsDeposit
		)
		,CTE_Half AS (
			SELECT 1 Is1H
			
			UNION ALL
			
			SELECT 0 Is1H
		)
		SELECT JobID,d.IsDeposit,h.Is1H,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate 
		FROM bodb_Account.dbo.ServiceJob s WITH(NOLOCK)
			INNER JOIN (
				SELECT TOP 1 * FROM bodb_Account.dbo.MatchList ml WITH(NOLOCK) WHERE ml.MatchID = @MatchID
			) ml ON ml.MatchID = s.MatchID
			,CTE_Dep AS d
			,CTE_Half AS h
		ORDER BY JobID,d.IsDeposit,h.Is1H,s.LiveIndicator
	END
	ELSE
	BEGIN
		SELECT JobID,2 IsDeposit, 2 Is1H,s.LiveIndicator,s.Bettype,s.TypeName,ml.MatchID,s.JobType,ml.EventDate 
		FROM bodb_Account.dbo.ServiceJob s WITH(NOLOCK)
			INNER JOIN (
				SELECT TOP 1 * FROM bodb_Account.dbo.MatchList ml WITH(NOLOCK) WHERE ml.MatchID = @MatchID
			) ml ON ml.MatchID = s.MatchID
		ORDER BY JobID
	END

END

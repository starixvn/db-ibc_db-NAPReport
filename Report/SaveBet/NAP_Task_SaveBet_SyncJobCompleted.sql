/*<info serverAlias="DBWH-bodb_Account" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_SyncJobCompleted]
AS
/*
	Created by: Roy
	Date:2021-05-13
	Task: Sync JobFinished flag between DBDW and DBDW2
	DB: DBWH.bodb_Account
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
		20211112@Roy: NAP Report - Update date range to sync job completed
*/
BEGIN
	SET NOCOUNT ON
	/*
		Sync MatchList.JobFinished from DBDW to DBDW2
			- DBDW is primary database
			- DBDW2 is standby database
			- Just update JobFinished - NOT handle missing MatchID
	*/
	DECLARE @StandbyDB NVARCHAR(128) = 'UNKNOWN'
	CREATE TABLE #tmpMatch ( MatchID INT PRIMARY KEY )
	---Get standby database name---
	BEGIN TRY
		EXEC sp_testlinkedserver N'DBSTAGING'

		DECLARE @Server TABLE (StandbyDB NVARCHAR(128))

		INSERT INTO @Server
		EXEC ('SELECT @@SERVERNAME') AT DBSTAGING

		SELECT @StandbyDB = StandbyDB
		FROM @Server
	END TRY
	BEGIN CATCH
		SELECT @StandbyDB = NULL
	END CATCH

	---linkedserver is NOT OFFLINE and CurrentServer is NOT Standby---
	IF @StandbyDB IS NOT NULL AND @@SERVERNAME <> @StandbyDB
	BEGIN
		DECLARE @EventDate DATETIME
			,@StrSQL NVARCHAR(MAX)
			,@StrMatchID NVARCHAR(MAX) = ''
			
		SELECT @EventDate = DATEADD(DAY,-2,MAX(ExchangeDate))
		FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		
		--Get NOT Finish Match from Standby Server--
		INSERT INTO #tmpMatch
		SELECT MatchID
		FROM DBSTAGING.bodb_Account.dbo.MatchList WITH (NOLOCK)
		WHERE EventDate >= @EventDate
			AND JobFinished = 0
			AND JobGenerated = 1
		
		--Concat multiple MatchID into single string--
		SELECT @StrMatchID = @StrMatchID  + CONVERT(NVARCHAR, MatchID) + ','
		FROM #tmpMatch
		WHERE MatchID IN (
				SELECT MatchID
				FROM bodb_Account.dbo.MatchList WITH (NOLOCK)
				WHERE EventDate >= @EventDate
					AND JobFinished = 1
					AND JobGenerated = 1
				)
		OPTION (RECOMPILE)
		
		--Update JobFinished at Standby Server--
		IF LEN(@StrMatchID) > 0
		BEGIN
			SELECT @StrMatchID  =  SUBSTRING ( @StrMatchID ,1 , LEN(@StrMatchID) - 1 )
			SET @StrSQL = 'UPDATE bodb_Account.dbo.MatchList WITH(ROWLOCK,UPDLOCK) SET JobFinished = 1 WHERE MatchID IN ('+@StrMatchID+')'
			EXECUTE DBSTAGING.master.dbo.sp_executesql @StrSQL
		END
	END
	
	DROP TABLE #tmpMatch
END
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
        20230306@Ned.Le: Enhence the way to update data at two server

    Step by step:
		Sync MatchList.JobFinished between two server
        Just update JobFinished - NOT handle missing MatchID
*/

BEGIN
	SET NOCOUNT ON

    -- Declare variables and create temp tables
    DECLARE @DBWH      VARCHAR(100),
            @DBSTAGING VARCHAR(100),
            @LOCAL     VARCHAR(100)
    SELECT  @DBWH      = Servername FROM OPENQUERY (DBWH,      'SELECT @@SERVERNAME Servername')
    SELECT  @DBSTAGING = Servername FROM OPENQUERY (DBSTAGING, 'SELECT @@SERVERNAME Servername')
    SELECT  @LOCAL     = @@SERVERNAME

    DECLARE @EventDate  DATETIME,
            @StrSQL     NVARCHAR(MAX),
            @StrMatchID NVARCHAR(MAX) = ''
    SELECT @EventDate = DATEADD(DAY,-2,MAX(ExchangeDate)) FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)

    CREATE TABLE #tmpMatch ( MatchID INT PRIMARY KEY )

	-- Execute at DBWH
	IF (@DBWH <> @DBSTAGING AND @LOCAL <> @DBWH)
    BEGIN
		--Get NOT Finish Match from Standby Server--
		INSERT INTO #tmpMatch
		SELECT MatchID
		FROM DBWH.bodb_Account.dbo.MatchList WITH (NOLOCK)
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
			EXECUTE DBWH.master.dbo.sp_executesql @StrSQL
		END
    END
	
	-- Execute at DBSAGING
	IF (@DBWH <> @DBSTAGING AND @LOCAL <> @DBSTAGING)
    BEGIN
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
	
    -- Drop temp tables
	DROP TABLE #tmpMatch
END
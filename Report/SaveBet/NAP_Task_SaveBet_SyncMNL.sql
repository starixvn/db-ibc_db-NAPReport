/*<info serverAlias="DBWH-bodb_Account" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_Task_SaveBet_SyncMNL]
AS
/*
	Created by: Roy
	Date:2021-05-13
	Task: Sync JobFinished flag between DW and MNL
	DB: DBWH.bodb_Account
	
	Revisions:
		20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BeforeYesterday DATETIME
		,@StrSQL NVARCHAR(MAX)
		,@StrMatchID NVARCHAR(MAX) = ''
	
	CREATE TABLE #tmpMatch ( MatchID INT PRIMARY KEY )
	
	SELECT @BeforeYesterday = DATEADD(DAY,-1,MAX(ExchangeDate))
	FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
	
	--Get NOT Finish Match from MNL Server--
	INSERT INTO #tmpMatch
	SELECT MatchID
	FROM DBDW_MNL.bodb_Account.dbo.MatchList WITH (NOLOCK)
	WHERE EventDate >= @BeforeYesterday
		AND JobFinished = 0
		AND JobGenerated = 1
	GROUP BY MatchID
	
	--Concat multiple MatchID into single string--
	SELECT @StrMatchID = @StrMatchID  + CONVERT(NVARCHAR, MatchID) + ','
	FROM #tmpMatch
	WHERE MatchID IN (
			SELECT MatchID
			FROM bodb_Account.dbo.MatchList WITH (NOLOCK)
			WHERE EventDate >= @BeforeYesterday
				AND JobFinished = 1
				AND JobGenerated = 1
			)
	OPTION (RECOMPILE)
	
	--Update JobFinished to MNL Server--
	IF LEN(@StrMatchID) > 0
	BEGIN
		SELECT @StrMatchID  =  SUBSTRING ( @StrMatchID ,1 , LEN(@StrMatchID) - 1 )
		SET @StrSQL = 'UPDATE bodb_Account.dbo.MatchList WITH(ROWLOCK,UPDLOCK) SET JobFinished = 1 WHERE MatchID IN ('+@StrMatchID+')'
		EXECUTE DBDW_MNL.master.dbo.sp_executesql @StrSQL
	END
	
	DROP TABLE #tmpMatch
END
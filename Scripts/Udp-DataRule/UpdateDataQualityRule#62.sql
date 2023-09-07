/*<info serverAlias="DBWH-bodb_Audit" isFunction="0" isNested="0"></info>*/

/*
Created by Roy.Du@20230907
Run at DBDW@bodb_Audit
Task: add more rule to check SaveBet
*/

USE bodb_Audit
GO

DECLARE @sqlStm NVARCHAR(MAX)

SELECT @sqlStm =
'
	/*  
		Created: Roy@20210423
		Description: SaveBet - Check data
			--Check Pending Match >= 500
			--Unfinished MatchID exists in bettrans_bk

		Input Param (Already Input From SSIS Package): 

				--Declaration for Unit Testing
				DECLARE @FDate DATE = ''20210421''
				DECLARE @TDate DATE = ''20210428''
		
		Output Param (Already Input From SSIS Package): 

				--Declaration for Unit Testing
				DECLARE @Passed BIT = 0
				DECLARE @ErrMsg NVARCHAR(max) = ''''

		Revision:
			20210423@Roy: NAP Report - Move Save bet db & service (#153147)
			20230907@Roy: Exclude test match (#193705)
	*/
				
	SELECT @Passed = 1
	SELECT @ErrMsg = ''''

	DECLARE @_Date DATE = @FDate
		,@MatchCnt INT
		,@BalanceUpDay DATETIME

	---Get BalanceUpDay---
	SELECT @BalanceUpDay = BalanceUpDay
	FROM OPENQUERY(DBACC, ''EXEC bodb02.dbo.Age_SelBalanceUpDay'')
	
	WHILE (@_Date <=  @TDate)
	BEGIN 
		---------------Pending MatchIDs <= 500-------------------
		SELECT @MatchCnt = COUNT(MatchID)
		FROM bodb_Account.dbo.MatchList WITH (NOLOCK) 
		WHERE JobFinished = 0
			AND JobGenerated = 1
			AND EventDate BETWEEN CONVERT(DATETIME, DATEADD(D, -1, @_Date)) AND CONVERT(DATETIME, @_Date) --EventDate BETWEEN Yesterday AND Today
			AND (GenerateTime IS NULL OR DATEDIFF(ms,GenerateTime,GETDATE())>(1000*60*60)) --only count Defered MatchIDs
		OPTION (RECOMPILE)

		IF @MatchCnt >= 500
		BEGIN				
			SELECT @ErrMsg = @ErrMsg + N''- More than 500 Pending MatchIDs BETWEEN ''+CONVERT(NVARCHAR, DATEADD(D, -1, @_Date), 23)+'' AND ''+CONVERT(NVARCHAR, @_Date, 23)+''</br>''

			SELECT @Passed = 0
		END
			
		SELECT @_Date = DATEADD(DAY,1,@_Date)
	END
	
	---------------Unfinished MatchID in bettrans_bk-------------------
	IF EXISTS(
		SELECT 1
		FROM bodb_Account.dbo.MatchList WITH (NOLOCK) 
		WHERE EventDate < @BalanceUpDay
			AND EventDate > DATEADD( D, -60, @BalanceUpDay ) --Just get data in 2 months from BalanceUpDay - not scan all table
			AND ( JobFinished = 0 OR JobGenerated = 0 )
	)
	BEGIN				
		SELECT @ErrMsg = @ErrMsg + N''- Exists Unfinished match in bettrans_bk.(''+CONVERT(NVARCHAR, @BalanceUpDay, 23)+'')</br>''

		SELECT @Passed = 0

		SELECT MatchID
		FROM bodb_Account.dbo.MatchList WITH (NOLOCK) 
		WHERE EventDate < @BalanceUpDay
			AND EventDate > DATEADD( D, -60, @BalanceUpDay )
			AND ( JobFinished = 0 OR JobGenerated = 0 )
	END
	
	---------------Inserted MatchList but exists in match-------------------
	IF EXISTS(
		SELECT 1
		FROM bodb_account.dbo.MatchList AS ml WITH (NOLOCK)
			INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON ml.MatchID = m.matchid
		WHERE DATEDIFF(dd, ml.GenerateTime, GETDATE()) >= 15
	)
	BEGIN				
		SELECT @ErrMsg = @ErrMsg + N''- Inserted into [MatchList], but still persists in [Match] for over 15 days.</br>''

		SELECT @Passed = 0
	END
	
	SELECT @Passed ,@ErrMsg
'
------------------Update rule#62----------------
UPDATE bodb_Audit.dbo.DataQualityRule
SET SQLStatement = @sqlStm
WHERE RuleID = 62
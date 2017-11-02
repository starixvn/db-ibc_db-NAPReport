USE [bk]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Task_ClearOldBetTranslog]
AS
/* 
	Created: Dominic@20171027
	Task: Clear old bets in bets_Translog/betsReject_Translog
	DB: DBBET/BK
	Revisions:

	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #BetEventType (Bettype INT,Eventtype TINYINT)

	INSERT INTO #BetEventType(Bettype,Eventtype)
	SELECT DISTINCT Bettype,Eventtype
	FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)

	CREATE UNIQUE CLUSTERED INDEX PK_BetEvent ON #BetEventType(Bettype,Eventtype)

	CREATE TABLE #m (matchid int, EventType TINYINT, IsDeleted BIT)
	CREATE UNIQUE CLUSTERED INDEX PK_Match ON #m(matchid,EventType)

	INSERT INTO #m(matchid,EventType,IsDeleted)
	SELECT DISTINCT eventID,Eventtype,0
	FROM bets_Translog b(nolock)
	INNER JOIN #BetEventType m ON m.Bettype=b.gameID

	/* EventType
		0: Can't join with any table 
		1: Match
		2: Outright
		3: VSOutright/VSRaceInfo
		4: DW
		5: Match3rd
	*/

	DELETE #m FROM bodb02.dbo.Match3rd m WHERE #m.matchid = m.Match3rdId AND #m.EventType=5


	--------------------EventType = 5------------------------
	DECLARE @matchid int
	DECLARE @EventType TINYINT

	UPDATE TOP(1) #m
	SET @matchid= #m.matchid
		,@EventType= #m.EventType
		,IsDeleted=1
	WHERE IsDeleted=0

	IF @@ROWCOUNT = 0 SELECT @matchid = -1

	WHILE(@matchid <> -1)
	BEGIN
		WHILE(1=1)
		BEGIN
			DELETE TOP(20000) main
			FROM bets_Translog main
			INNER JOIN #BetEventType m ON m.Bettype=main.gameID
			WHERE eventID = @matchid AND m.Eventtype=@EventType

			IF @@ROWCOUNT < 20000 BREAK;
		END

		WHILE(1=1)
		BEGIN
			DELETE TOP(20000) main
			FROM betsReject_Translog main
			INNER JOIN #BetEventType m ON m.Bettype=main.gameID
			WHERE eventID = @matchid AND m.Eventtype=@EventType

			IF @@ROWCOUNT < 20000 BREAK;
		END

		UPDATE TOP(1) #m
		SET @matchid= ISNULL(#m.matchid,-1)
			,@EventType= ISNULL(#m.EventType,-1)
			,IsDeleted=1
		WHERE IsDeleted=0

		IF @@ROWCOUNT = 0 SELECT @matchid = -1
	END
END
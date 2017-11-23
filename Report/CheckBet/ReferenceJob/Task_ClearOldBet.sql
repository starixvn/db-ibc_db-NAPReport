USE [bk]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Task_ClearOldBet]
AS
/* 
	DB: DBBET/BK
	Revisions:
		- 20171027@Dominic: Integrate Bullfighting #85382,HotFix #85757
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #BetEventType (Bettype INT,Eventtype TINYINT)

	INSERT INTO #BetEventType(Bettype,Eventtype)
	SELECT DISTINCT Bettype,Eventtype
	FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)

	CREATE UNIQUE CLUSTERED INDEX PK_BetEvent ON #BetEventType(Bettype,Eventtype)

	CREATE TABLE #m (matchid int, EventType TINYINT, oddsid INT)
	CREATE CLUSTERED INDEX PK_Match ON #m(matchid,EventType)

	INSERT INTO #m(matchid,EventType,oddsid)
	SELECT DISTINCT matchid,Eventtype,CASE WHEN EventType=3 THEN oddsid ELSE 1 END
	FROM bets b(nolock)
	INNER JOIN #BetEventType m ON m.Bettype=b.bettype

	/* EventType
		0: Can't join with any table 
		1: Match
		2: Outright
		3: VSOutright/VSRaceInfo
		4: DW
		5: Match3rd
	*/

	
	DELETE #m FROM bodb02.dbo.match m WHERE #m.matchid = m.matchid AND #m.EventType=1
	DELETE #m FROM bodb02.dbo.outright m WHERE #m.matchid = m.orid AND #m.EventType=2
	DELETE #m FROM bodb02.dbo.VSOutright m WHERE #m.oddsid = m.Orid AND #m.EventType=3

	--------------------EventType = 0------------------------
	DECLARE @FDate DATETIME, @TDate DATETIME
	SELECT @FDate=MIN(winlostdate)
	FROM bets (NOLOCK)
	WHERE matchid IN (SELECT matchid FROM #m WHERE Eventtype=0)

	SELECT @TDate=MAX(eventdate)
	FROM bodb02.dbo.match14 (NOLOCK)

	WHILE(@FDate <= @TDate)
	BEGIN
		WHILE(1=1)
		BEGIN
			DELETE TOP(20000) main
			FROM bets main
			WHERE winlostdate=@FDate AND matchid IN (SELECT matchid FROM #m WHERE Eventtype=0)

			IF @@ROWCOUNT < 20000 BREAK;
		END

		WHILE(1=1)
		BEGIN
			DELETE TOP(20000) main
			FROM betsReject main
			WHERE winlostdate=@FDate AND matchid IN (SELECT matchid FROM #m WHERE Eventtype=0)

			IF @@ROWCOUNT < 20000 BREAK;
		END

		SELECT @FDate = DATEADD(DAY,1,@FDate)
	END

	--------------------EventType <> 0------------------------
	DELETE #m WHERE EventType=0

	WHILE(1=1)
	BEGIN
		DELETE TOP(20000) main
		FROM bets main
		WHERE matchid IN (SELECT matchid FROM #m WHERE Eventtype <> 3)

		IF @@ROWCOUNT < 20000 BREAK;
	END

	WHILE(1=1)
	BEGIN
		DELETE TOP(20000) main
		FROM bets main
		WHERE matchid IN (SELECT matchid FROM #m WHERE Eventtype <> 3)
		AND oddsid IN (SELECT oddsid FROM #m WHERE Eventtype = 3)

		IF @@ROWCOUNT < 20000 BREAK;
	END

	WHILE(1=1)
	BEGIN
		DELETE TOP(20000) main
		FROM betsReject main
		WHERE matchid IN (SELECT matchid FROM #m WHERE Eventtype <> 3)

		IF @@ROWCOUNT < 20000 BREAK;
	END

	WHILE(1=1)
	BEGIN
		DELETE TOP(20000) main
		FROM betsReject main
		WHERE matchid IN (SELECT matchid FROM #m WHERE Eventtype <> 3)
		AND oddsid IN (SELECT oddsid FROM #m WHERE Eventtype = 3)

		IF @@ROWCOUNT < 20000 BREAK;
	END
END
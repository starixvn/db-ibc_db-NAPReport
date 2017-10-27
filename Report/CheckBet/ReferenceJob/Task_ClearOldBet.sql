USE [bk]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Task_ClearOldBet]
AS

SET NOCOUNT ON

CREATE TABLE #m (matchid int)
INSERT INTO #m
SELECT DISTINCT matchid FROM bets (nolock)

DELETE #m FROM bodb02.dbo.match m    WHERE #m.matchid = m.matchid
DELETE #m FROM bodb02.dbo.outright r WHERE #m.matchid = r.orid

DECLARE @matchid int

DECLARE CS_matchid
	CURSOR FOR
	SELECT matchid FROM #m

OPEN CS_matchid
FETCH NEXT FROM CS_matchid INTO @matchid

WHILE @@FETCH_STATUS = 0
BEGIN

	DELETE FROM bets
		WHERE matchid = @matchid
	DELETE FROM betsReject
		WHERE matchid = @matchid

	FETCH NEXT FROM CS_matchid INTO @matchid
END

CLOSE CS_matchid
DEALLOCATE CS_matchid

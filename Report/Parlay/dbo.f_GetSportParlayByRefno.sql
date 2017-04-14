USE [bodb02]
GO

ALTER FUNCTION [dbo].[f_GetSportParlayByRefno]
(
	@Refno BIGINT
)
RETURNS SMALLINT
AS
/*
	Creator: Percy
	Date: 2016-08-26
	DB: DBACC.bodb02
	Task: Get Sport of Parlay by Refno
*/
BEGIN
	
	DECLARE @Sporttype SMALLINT
	DECLARE @Sport TABLE (Sporttype TINYINT)
	
	INSERT INTO @Sport (Sporttype)
	SELECT DISTINCT m.sporttype
	FROM dbo.bettransm bm WITH(NOLOCK)
		INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid
	WHERE bm.refno = @Refno
	UNION
	SELECT DISTINCT m.sporttype
	FROM dbo.bettransm14 bm WITH(NOLOCK)
		INNER JOIN dbo.match14 m WITH(NOLOCK) ON bm.matchid = m.matchid
	WHERE bm.refno = @Refno

	IF (SELECT COUNT(1) FROM @Sport) = 1
	BEGIN
		SELECT @Sporttype = sporttype FROM @Sport
	END
	ELSE IF EXISTS (SELECT TOP 1 1 FROM @Sport WHERE Sporttype = 1)
		SELECT @Sporttype = -1
	ELSE
		SELECT @Sporttype = -2

	RETURN @Sporttype
END
/*<info serverAlias="DBACC-bodb02" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/

ALTER FUNCTION dbo.f_BetBuilder_GetSelectionName(
	@MarketId       VARCHAR(20)
   , @WinlostDate    DATETIME)
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBACC.bodb02
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]

	Param's Explanation:
		
*/
RETURNS @Result TABLE(
	Selection    VARCHAR(MAX))
AS
BEGIN
    DECLARE @s                VARCHAR(MAX)
		, @movebetdate      DATETIME
		, @balanceupdate    DATETIME;

    SELECT TOP 1 @balanceupdate = winlostdate
    FROM bodb02.dbo.Bettrans WITH (NOLOCK)
    WHERE bettype = 20000
		AND matchid = 0
		AND custid = 3;

    SELECT @movebetdate = MAX(eventdate)
    FROM bodb02.dbo.match14 WITH (NOLOCK);

    IF @WinlostDate > @movebetdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM SMP_MarketSelection AS s1 WITH (NOLOCK)
			 INNER JOIN SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    IF @WinlostDate <= @movebetdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM SMP_MarketSelection14 AS s1 WITH (NOLOCK)
			 INNER JOIN SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    IF @WinlostDate < @balanceupdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM bodb_Archive.dbo.SMP_MarketSelection_bk AS s1 WITH (NOLOCK)
			 INNER JOIN SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    INSERT INTO @Result(Selection)
		 (
			SELECT @s AS Selection
		 );

    RETURN;
END;
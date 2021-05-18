/*<info serverAlias="DBRPT-bodb_Report" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/
USE bodb_Report
GO

ALTER FUNCTION dbo.f_BetBuilder_GetSelectionName(
	@MarketId       VARCHAR(20)
   , @WinlostDate    DATETIME)
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBRPT.bodb_Report
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]
		- 20210504@Jaden: Use SP to get balanceup & movebets (#154116)

	Param's Explanation:
		
*/
RETURNS @Result TABLE(
	Selection    VARCHAR(MAX))
AS
BEGIN
    DECLARE @s                VARCHAR(MAX)
		, @movebetdate      DATETIME
		, @balanceupdate    DATETIME;

	SELECT @balanceupdate = BalanceUpDay, @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

    IF @WinlostDate > @movebetdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM bodb02.dbo.SMP_MarketSelection AS s1 WITH (NOLOCK)
			 INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    IF @WinlostDate <= @movebetdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM bodb02.dbo.SMP_MarketSelection14 AS s1 WITH (NOLOCK)
			 INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    IF @WinlostDate < @balanceupdate
	   BEGIN
		  SELECT @s = COALESCE(@s+'; ', '')+s2.SelectionName
		  FROM bodb_Archive.dbo.SMP_MarketSelection_bk AS s1 WITH (NOLOCK)
			 INNER JOIN bodb02.dbo.SMP_Selection AS s2 WITH (NOLOCK) ON s1.SelectionType = s2.SelectionType
		  WHERE MarketId = @MarketId
		  ORDER BY s2.SelectionName;
	   END;

    INSERT INTO @Result(Selection)
		 (
			SELECT @s AS Selection
		 );

    RETURN;
END;
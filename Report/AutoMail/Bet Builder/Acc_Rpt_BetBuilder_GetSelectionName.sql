/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" viewers="" isFunction="0" isNested="1"></info>*/
USE bodb_Report
GO

ALTER PROCEDURE dbo.Acc_Rpt_BetBuilder_GetSelectionName
	@WinlostDate    SMALLDATETIME
   , @IsFullRange    BIT           = 0
AS
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

BEGIN
    SET NOCOUNT ON;

    DECLARE @movebetdate      DATETIME
		, @balanceupdate    DATETIME;

    CREATE TABLE #Selection(
	    MarketId         VARCHAR(50)
	  , SelectionName    VARCHAR(MAX));

	SELECT @balanceupdate = BalanceUpDay, @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

    IF @WinlostDate > @movebetdate
	  OR @IsFullRange = 1
	   BEGIN		  
		  INSERT INTO #Selection(MarketId
						   , SelectionName)
			    (
				   SELECT s.MarketId
					   , Selection = STUFF(
						(
						    SELECT '; '+s2.SelectionName
						    FROM bodb02.dbo.SMP_MarketSelection AS s1
							   INNER JOIN bodb02.dbo.SMP_Selection AS s2 ON s1.SelectionType = s2.SelectionType
						    WHERE s1.MarketId = s.MarketId
						    ORDER BY s2.SelectionName FOR XML PATH, TYPE
						).value
						(N'.[1]', N'varchar(max)'), 1, 2, '')
				   FROM bodb02.dbo.SMP_MarketSelection AS s
				   GROUP BY s.MarketId
			    );
	   END;

    IF @WinlostDate BETWEEN @balanceupdate AND @movebetdate --@WinlostDate <= @movebetdate
	  OR @IsFullRange = 1
	   BEGIN		  
		  INSERT INTO #Selection(MarketId
						   , SelectionName)
			    (
				   SELECT s.MarketId
					   , Selection = STUFF(
						(
						    SELECT '; '+s2.SelectionName
						    FROM bodb02.dbo.SMP_MarketSelection14 AS s1
							   INNER JOIN bodb02.dbo.SMP_Selection AS s2 ON s1.SelectionType = s2.SelectionType
						    WHERE s1.MarketId = s.MarketId
						    ORDER BY s2.SelectionName FOR XML PATH, TYPE
						).value
						(N'.[1]', N'varchar(max)'), 1, 2, '')
				   FROM bodb02.dbo.SMP_MarketSelection14 AS s
				   GROUP BY s.MarketId
			    );
	   END;

    IF @WinlostDate < @balanceupdate
	  OR @IsFullRange = 1
	   BEGIN
		  INSERT INTO #Selection(MarketId
						   , SelectionName)
			    (
				   SELECT s.MarketId
					   , Selection = STUFF(
						(
						    SELECT '; '+s2.SelectionName
						    FROM bodb_Archive.dbo.SMP_MarketSelection_bk AS s1
							   INNER JOIN bodb02.dbo.SMP_Selection AS s2 ON s1.SelectionType = s2.SelectionType
						    WHERE s1.MarketId = s.MarketId
						    ORDER BY s2.SelectionName FOR XML PATH, TYPE
						).value
						(N'.[1]', N'varchar(max)'), 1, 2, '')
				   FROM bodb_Archive.dbo.SMP_MarketSelection_bk AS s
				   GROUP BY s.MarketId
			    );
	   END;

    SELECT MarketId
	    , SelectionName
    FROM #Selection
    ORDER BY SelectionName;

    DROP TABLE #Selection;
END;
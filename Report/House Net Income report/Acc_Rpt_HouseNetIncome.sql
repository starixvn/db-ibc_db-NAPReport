/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome @FromDate DATE,
                                           @ToDate DATE,
										   @BaseCurrencyName VARCHAR(10) = 'MYR',
                                           @DepositType TINYINT = 2,
                                           @DataMode TINYINT = 1
AS

/*
	Created:	20201117@Ned.Le
    Task:		Get data for Hosue Net Income report
    DB:			DBWH/bodb_dwrs
   
    Revisions:
		20201117@Ned.Le: DHWL Email/Letstalk - Restructure source code to improve performance & Separate House Income into Credit Income and Licensee Income (#143208)
		20210616@Danny:  Support Licensee Performance view mode (#156727)
		20210803@Danny:  Change Data Source to retrieve yesterday data from Bettrans table (#151993)

	Param's Explanation:
		@FromDate:         Begin date of data report
        @ToDate:           End date of data report
        @BaseCurrencyName: 'MYR' or 'CNY'
		@DepositType:      0 - Credit Only
					       1 - Deposit Only
					       2 - All
        @DataMode:         1 - Get data from ORI table
                           2 - Get data from UAT table
	
	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome '20210801', '20210818', 'MYR', 2, 1
*/

BEGIN
	
    SET NOCOUNT ON


    -----------------------
    -- DECLARE variables --

    DECLARE @sqlSupport                         VARCHAR(MAX),
            @sqlQuery                           VARCHAR(MAX)

	DECLARE @isTest BIT = 0
    SET @isTest = bodb_dwrs.dbo.f_CheckSPVersion(@@PROCID)


    -----------------------
    -- CREATE temp table --

    -- CREATE temp table
    CREATE TABLE #tmpHNIResultDataset (
        [FromDate]          DATE,
        [ToDate]            DATE,
        [BaseCurrencyName]  DATE,
        [isDeposit]			SMALLINT,
        [OrderByProduct]	SMALLINT,
        [OrderByFigure]		SMALLINT,
        [SiteGroup]			VARCHAR(100),
        [ProductCategory]	VARCHAR(100),
        [ProductGroup]		VARCHAR(100),
        [ProductName]		VARCHAR(100),
        [ProductShortName]	VARCHAR(100),
        [Figure]			VARCHAR(100),
        [SubFigure]			VARCHAR(100),
        [Monthly]			DECIMAL(19,4),
        [MTD]				DECIMAL(19,4),
        [01]				DECIMAL(19,4),
        [02]				DECIMAL(19,4),
        [03]				DECIMAL(19,4),
        [04]				DECIMAL(19,4),
        [05]				DECIMAL(19,4),
        [06]				DECIMAL(19,4),
        [07]				DECIMAL(19,4),
        [08]				DECIMAL(19,4),
        [09]				DECIMAL(19,4),
        [10]				DECIMAL(19,4),
        [11]				DECIMAL(19,4),
        [12]				DECIMAL(19,4),
        [13]				DECIMAL(19,4),
        [14]				DECIMAL(19,4),
        [15]				DECIMAL(19,4),
        [16]				DECIMAL(19,4),
        [17]				DECIMAL(19,4),
        [18]				DECIMAL(19,4),
        [19]				DECIMAL(19,4),
        [20]				DECIMAL(19,4),
        [21]				DECIMAL(19,4),
        [22]				DECIMAL(19,4),
        [23]				DECIMAL(19,4),
        [24]				DECIMAL(19,4),
        [25]				DECIMAL(19,4),
        [26]				DECIMAL(19,4),
        [27]				DECIMAL(19,4),
        [28]				DECIMAL(19,4),
        [29]				DECIMAL(19,4),
        [30]				DECIMAL(19,4),
        [31]				DECIMAL(19,4)
    )

    -- Get UAT data for temp table
    IF (@isTest = 1 OR @DataMode = 2)
    BEGIN
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM bodb_Account.dbo.HNIResultDatasetUAT (NOLOCK)
        WHERE [FromDate] = @FromDate
              AND [ToDate] = @ToDate
              AND [BaseCurrencyName] = @BaseCurrencyName
              AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
    END

    -- Get PRO data for temp table
    IF (@isTest = 0 AND @DataMode = 1)
    BEGIN
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM bodb_Account.dbo.HNIResultDataset (NOLOCK)
        WHERE [FromDate] = @FromDate
              AND [ToDate] = @ToDate
              AND [BaseCurrencyName] = @BaseCurrencyName
              AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
    END


    ----------------------------
    -- SELECT data for report --

	SET @sqlSupport = NULL

	;WITH CTE_RptDate AS (
		SELECT ('f.[' + LEFT(CONVERT(VARCHAR(5), PK_DATE, 106), 2) + ']') RptDate
		FROM bodb_Account.dbo.DimDate
		WHERE PK_Date >= @FromDate AND PK_Date <= @ToDate
	)
	SELECT @sqlSupport = COALESCE(@sqlSupport + ', ' + RptDate, RptDate)
	FROM CTE_RptDate

	SET @sqlQuery = 'SELECT f.[isDeposit], f.[OrderByProduct], f.[OrderByFigure], f.[SiteGroup], f.[ProductCategory], f.[ProductGroup], f.[ProductName], f.[ProductShortName], f.[Figure], f.[SubFigure], f.[Monthly], f.[MTD], ' + @sqlSupport + CHAR(13) +
					'FROM #tmpHNIResultDataset f' + CHAR(13) +
					'ORDER BY f.[isDeposit], f.[SiteGroup], f.[OrderByProduct], f.[OrderByFigure]'

	EXEC (@sqlQuery)


    ----------------------
    -- DROP temp tables --

    DROP TABLE #tmpHNIResultDataset

END

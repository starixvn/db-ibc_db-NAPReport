/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome @FromDate         DATE,
                                           @ToDate           DATE,
                                           @IsLicPerf        BIT         = 0,
                                           @BaseCurrencyName VARCHAR(10) = 'MYR',
                                           @DepositType      TINYINT     = 2,
                                           @DataMode         TINYINT     = 1
AS

/*
    Created: 20201117@Ned.Le
    Task:    Get data for Hosue Net Income report
    DB:      DBWH/bodb_dwrs

    Revisions:
        20201117@Ned.Le: DHWL Email/Letstalk - Restructure source code to improve performance & Separate House Income into Credit Income and Licensee Income (#143208)
        20210616@Danny:  Support Licensee Performance view mode (#156727)
        20210803@Danny:  Change Data Source to retrieve yesterday data from Bettrans table (#151993)
        20230201@Ned.Le: Email/Letstalk reports- Change layout for the report id #1 & #2 (#183142)
        20230315@Ned.Le: Email/Letstalk Report ID #01 - Implement new chart report for comparing monthly.Year To Date Winloss/Margin (#185000)
        20230403@Ned.Le: House Net Income Email/Letstalk Reports - Enhance the solution when regenerating new Data into our Data Source (#186350)

    Param's Explanation:
        @FromDate:         Begin date of data report
        @ToDate:           End date of data report
        @IsLicPerf:        0 or 1
        @BaseCurrencyName: 'MYR' or 'CNY'
        @DepositType:      0 - Credit Only
                           1 - Deposit Only
                           2 - All
        @DataMode:         1 - Get data from ORI                    | HNIResultDataset          | For using on default daily and monthly data processing
                           2 - Get data from UAT                    | HNIResultDatasetUAT       | For using on UAT testing
                           3 - Get data from MONTHLY BACKUP         | HNIResultDataset_BK_Month | For using on daily margin MTD chart report
                           4 - Get data from DAILY & MONTHLY BACKUP | HNIResultDataset_BK_Date  | For using on new monthly YTD chart report
                                                                    | HNIResultDataset_BK_Month
                           5 - Get full data from DAILY BACKUP      | HNIResultDataset_BK_Date  | For using when need to get old DAILY BACKUP snapshot data
                           6 - Get full data from MONTHLY BACKUP    | HNIResultDataset_BK_Month | For using when need to get old MONTHLY BACKUP snapshot data

    Example:
        EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome '20210801', '20210818', 0, 'MYR', 2, 1
*/

BEGIN

    SET NOCOUNT ON


    -----------------------
    -- DECLARE variables --

    DECLARE @sqlSupport VARCHAR(MAX)
    DECLARE @sqlQuery   VARCHAR(MAX)


    -----------------------
    -- CREATE temp table --

    -- CREATE temp table
    CREATE TABLE #tmpHNIResultDataset (
        [FromDate]         DATE,
        [ToDate]           DATE,
        [isLicPerf]        SMALLINT,
        [BaseCurrencyName] VARCHAR(50),
        [isDeposit]        SMALLINT,
        [OrderByProduct]   SMALLINT,
        [OrderByFigure]    SMALLINT,
        [SiteGroup]        VARCHAR(100),
        [ProductCategory]  VARCHAR(100),
        [ProductGroup]     VARCHAR(100),
        [ProductName]      VARCHAR(100),
        [ProductShortName] VARCHAR(100),
        [Figure]           VARCHAR(100),
        [SubFigure]        VARCHAR(100),
        [Monthly]          DECIMAL(19,4),
        [MTD]              DECIMAL(19,4),
        [01]               DECIMAL(19,4),
        [02]               DECIMAL(19,4),
        [03]               DECIMAL(19,4),
        [04]               DECIMAL(19,4),
        [05]               DECIMAL(19,4),
        [06]               DECIMAL(19,4),
        [07]               DECIMAL(19,4),
        [08]               DECIMAL(19,4),
        [09]               DECIMAL(19,4),
        [10]               DECIMAL(19,4),
        [11]               DECIMAL(19,4),
        [12]               DECIMAL(19,4),
        [13]               DECIMAL(19,4),
        [14]               DECIMAL(19,4),
        [15]               DECIMAL(19,4),
        [16]               DECIMAL(19,4),
        [17]               DECIMAL(19,4),
        [18]               DECIMAL(19,4),
        [19]               DECIMAL(19,4),
        [20]               DECIMAL(19,4),
        [21]               DECIMAL(19,4),
        [22]               DECIMAL(19,4),
        [23]               DECIMAL(19,4),
        [24]               DECIMAL(19,4),
        [25]               DECIMAL(19,4),
        [26]               DECIMAL(19,4),
        [27]               DECIMAL(19,4),
        [28]               DECIMAL(19,4),
        [29]               DECIMAL(19,4),
        [30]               DECIMAL(19,4),
        [31]               DECIMAL(19,4)
    )

    -- [@DataMode = 1] For using on default daily and monthly data processing
    IF (@DataMode = 1)
    BEGIN
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [isLicPerf],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [isLicPerf],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM bodb_Account.dbo.HNIResultDataset (NOLOCK)
        WHERE [FromDate] = @FromDate
              AND [ToDate] = @ToDate
              AND [isLicPerf] = @IsLicPerf
              AND [BaseCurrencyName] = @BaseCurrencyName
              AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
    END

    -- [@DataMode = 2] For using on UAT testing
    IF (@DataMode = 2)
    BEGIN
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [isLicPerf],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [isLicPerf],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM bodb_Account.dbo.HNIResultDatasetUAT (NOLOCK)
        WHERE [FromDate] = @FromDate
              AND [ToDate] = @ToDate
              AND [isLicPerf] = @IsLicPerf
              AND [BaseCurrencyName] = @BaseCurrencyName
              AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
    END

    -- [@DataMode = 3] For using on daily margin MTD chart report
    IF (@DataMode = 3)
    BEGIN
        -- + Gen data to temp table
        ;WITH CTE_Data AS (
            SELECT [FromDate],
                   [ToDate],
                   [isLicPerf],
                   [BaseCurrencyName],
                   [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                   [Monthly], [MTD],
                   [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31],
                   [CreateDate],
                   DENSE_RANK() OVER(ORDER BY CreateDate DESC) CrateDate_Rank
            FROM bodb_account.dbo.HNIResultDataset_BK_Month (NOLOCK)
            WHERE @FromDate >= [FromDate]
                  AND @ToDate <= [ToDate]
                  AND [isLicPerf] = @IsLicPerf
                  AND [BaseCurrencyName] = @BaseCurrencyName
                  AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
        )
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [isLicPerf],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [isLicPerf],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM CTE_Data
        WHERE CrateDate_Rank = 1

        -- + Update data for column [Monthly] & [MTD]
        SET @sqlSupport = NULL

        ;WITH CTE_RptDate AS (
            SELECT ('ISNULL([' + LEFT(CONVERT(VARCHAR(5), PK_DATE, 106), 2) + '], 0)') RptDate
            FROM bodb_Account.dbo.DimDate
            WHERE PK_Date >= @FromDate AND PK_Date <= @ToDate
        )
        SELECT @sqlSupport = COALESCE(@sqlSupport + ' + ' + RptDate, RptDate)
        FROM CTE_RptDate

        SET @sqlQuery = 'UPDATE f' + CHAR(13) +
                        'SET f.[Monthly] = 0, f.[MTD] = (' + @sqlSupport + ')' + CHAR(13) +
                        'FROM #tmpHNIResultDataset f'

        EXEC (@sqlQuery)
    END

    -- [@DataMode = 4] For using on new monthly YTD chart report
    IF (@DataMode = 4)
    BEGIN
        -- + Prepare data
        DECLARE @thisyear_end   DATE = @FromDate
        DECLARE @thisyear_begin DATE = DATEADD(YY, DATEDIFF(YY, 0, @thisyear_end), 0)
        DECLARE @lastyear_end   DATE = DATEADD(YY, -1, @thisyear_end)
        DECLARE @lastyear_begin DATE = DATEADD(YY, DATEDIFF(YY, 0, @lastyear_end), 0)

        CREATE TABLE #tmpCalendar (MonthOfYear VARCHAR(20), FirstDate DATE, LastDate DATE, isProcess BIT DEFAULT 0)
        INSERT INTO  #tmpCalendar (MonthOfYear, FirstDate, LastDate)
        SELECT DISTINCT
               LEFT(CONVERT(VARCHAR(50), d.Month, 120), 7) MonthOfYear,
               CAST(d.Month AS DATE) FirstDate,
               CAST(DATEADD(MM, DATEDIFF(MM, -1, d.Month), -1) AS DATE) LastDate
        FROM bodb_account.dbo.DimDate d WITH (NOLOCK)
        WHERE (d.PK_Date >= @thisyear_begin AND d.PK_Date <= @thisyear_end) OR
              (d.PK_Date >= @lastyear_begin AND d.PK_Date <= @lastyear_end)
        ORDER BY MonthOfYear

        -- + Process data
        DECLARE @counttable INT = 0
        DECLARE @firstdate  DATE
        DECLARE @lastdate   DATE

        WHILE (1=1)
        BEGIN
            -- + --> Check to break the loop
            SELECT @counttable = COUNT(1) FROM #tmpCalendar WHERE isProcess = 0
            IF (@counttable = 0) BREAK

            -- + --> Gen data to variables
            SELECT TOP 1 @firstdate = FirstDate,
                         @lastdate  = LastDate
            FROM #tmpCalendar
            WHERE isProcess = 0
            ORDER BY MonthOfYear
            
            -- + --> Get data from MONTHLY BACKUP table
            IF (@firstdate <> @FromDate)
            BEGIN
                ;WITH CTE_Data AS (
                    SELECT [FromDate],
                           [ToDate],
                           [isLicPerf],
                           [BaseCurrencyName],
                           [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                           [Monthly], [MTD],
                           [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31],
                           [CreateDate],
                           DENSE_RANK() OVER(ORDER BY CreateDate DESC) CrateDate_Rank
                    FROM bodb_account.dbo.HNIResultDataset_BK_Month (NOLOCK)
                    WHERE [FromDate] = @firstdate
                          AND [ToDate] = @lastdate
                          AND [isLicPerf] = @IsLicPerf
                          AND [BaseCurrencyName] = @BaseCurrencyName
                          AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
                )
                INSERT INTO #tmpHNIResultDataset (
                    [FromDate],
                    [ToDate],
                    [isLicPerf],
                    [BaseCurrencyName],
                    [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                    [Monthly], [MTD],
                    [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
                )
                SELECT [FromDate],
                       [ToDate],
                       [isLicPerf],
                       [BaseCurrencyName],
                       [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                       [Monthly], [MTD],
                       [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
                FROM CTE_Data
                WHERE CrateDate_Rank = 1
            END

            -- + --> Get data from DAILY BACKUP table
            IF (@firstdate = @FromDate)
            BEGIN
                ;WITH CTE_Data AS (
                    SELECT [FromDate],
                           [ToDate],
                           [isLicPerf],
                           [BaseCurrencyName],
                           [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                           [Monthly], [MTD],
                           [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31],
                           [CreateDate],
                           DENSE_RANK() OVER(ORDER BY CreateDate DESC) CrateDate_Rank
                    FROM bodb_account.dbo.HNIResultDataset_BK_Date (NOLOCK)
                    WHERE [FromDate] = @firstdate
                          AND [ToDate] = @lastdate
                          AND [isLicPerf] = @IsLicPerf
                          AND [BaseCurrencyName] = @BaseCurrencyName
                          AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
                )
                INSERT INTO #tmpHNIResultDataset (
                    [FromDate],
                    [ToDate],
                    [isLicPerf],
                    [BaseCurrencyName],
                    [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                    [Monthly], [MTD],
                    [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
                )
                SELECT [FromDate],
                       [ToDate],
                       [isLicPerf],
                       [BaseCurrencyName],
                       [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                       [Monthly], [MTD],
                       [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
                FROM CTE_Data
                WHERE CrateDate_Rank = 1
            END

            -- + --> Update data to continue the loop
            UPDATE c
            SET c.isProcess = 1
            FROM #tmpCalendar c
            WHERE c.FirstDate = @firstdate
                  AND c.LastDate = @lastdate
        END

        -- + Drop data
        DROP TABLE #tmpCalendar
    END

    -- [@DataMode = 5] For using when need to get old DAILY BACKUP snapshot data
    IF (@DataMode = 5)
    BEGIN
        ;WITH CTE_Data AS (
            SELECT [FromDate],
                   [ToDate],
                   [isLicPerf],
                   [BaseCurrencyName],
                   [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                   [Monthly], [MTD],
                   [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31],
                   [CreateDate],
                   DENSE_RANK() OVER(ORDER BY CreateDate DESC) CrateDate_Rank
            FROM bodb_account.dbo.HNIResultDataset_BK_Date (NOLOCK)
            WHERE [FromDate] = @FromDate
                  AND [ToDate] = @ToDate
                  AND [isLicPerf] = @IsLicPerf
                  AND [BaseCurrencyName] = @BaseCurrencyName
                  AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
        )
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [isLicPerf],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [isLicPerf],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM CTE_Data
        WHERE CrateDate_Rank = 1
    END

    -- [@DataMode = 6] For using when need to get old MONTHLY BACKUP snapshot data
    IF (@DataMode = 6)
    BEGIN
        ;WITH CTE_Data AS (
            SELECT [FromDate],
                   [ToDate],
                   [isLicPerf],
                   [BaseCurrencyName],
                   [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
                   [Monthly], [MTD],
                   [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31],
                   [CreateDate],
                   DENSE_RANK() OVER(ORDER BY CreateDate DESC) CrateDate_Rank
            FROM bodb_account.dbo.HNIResultDataset_BK_Month (NOLOCK)
            WHERE [FromDate] = @FromDate
                  AND [ToDate] = @ToDate
                  AND [isLicPerf] = @IsLicPerf
                  AND [BaseCurrencyName] = @BaseCurrencyName
                  AND ((@DepositType = 2) OR ([isDeposit] = @DepositType))
        )
        INSERT INTO #tmpHNIResultDataset (
            [FromDate],
            [ToDate],
            [isLicPerf],
            [BaseCurrencyName],
            [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
            [Monthly], [MTD],
            [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        )
        SELECT [FromDate],
               [ToDate],
               [isLicPerf],
               [BaseCurrencyName],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM CTE_Data
        WHERE CrateDate_Rank = 1
    END


    ----------------------------
    -- SELECT data for report --

    -- @DateMode=1|2|3|5|6
    IF (@DataMode IN (1, 2, 3, 5, 6))
    BEGIN
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
    END

    -- @DataMode=4
    IF (@DataMode IN (4))
    BEGIN
        SELECT LEFT(CONVERT(VARCHAR(50), FromDate, 120), 7) [MonthOfYear],
               [isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure],
               [Monthly], [MTD],
               [01], [02], [03], [04], [05], [06], [07], [08], [09], [10], [11], [12], [13], [14], [15], [16], [17], [18], [19], [20], [21], [22], [23], [24], [25], [26], [27], [28], [29], [30], [31]
        FROM #tmpHNIResultDataset
        ORDER BY [MonthOfYear], [isDeposit], [SiteGroup], [OrderByProduct], [OrderByFigure]
    END


    ----------------------
    -- DROP temp tables --

    DROP TABLE #tmpHNIResultDataset

END
GO
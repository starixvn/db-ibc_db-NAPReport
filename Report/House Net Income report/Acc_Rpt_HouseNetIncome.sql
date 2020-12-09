/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome @FromDate DATE,
										   @ToDate DATE,
										   @ProductList VARCHAR(MAX) = 'ALL',
										   @DepositType	TINYINT = 2,
										   @IsOldView BIT = 0

AS

/*
	Created:	20201117@Ned.Le
    Task:		Synthesize all data from child SPs for Hosue Net Income report
    DB:			DBWH/bodb_dwrs
   
    Revisions:
		20201117@Ned.Le: DHWL Email/Letstalk - Restructure source code to improve performance & Separate House Income into Credit Income and Licensee Income (#143208)

	Param's Explanation:
	
	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome '20200901', '20200930', 'ALL', 2, 0
*/

BEGIN

    SET NOCOUNT ON

	-- Declare variable
	DECLARE @sqlQuery VARCHAR(MAX)
	DECLARE @sqlSupport VARCHAR(MAX)

	-- Create temp table
	CREATE TABLE #tmpFinalData (
		[isDeposit]			BIT,
		[OrderByProduct]	INT,
		[OrderByFigure]		INT,
		[SiteGroup] 		VARCHAR(20),
		[ProductGroup] 		VARCHAR(50),
		[ProductName] 		VARCHAR(50),
		[ProductShortName] 	VARCHAR(50), 
		[Figure] 			VARCHAR(200),
		[Monthly] 			DECIMAL(19, 4) DEFAULT 0,
		[MTD] 				DECIMAL(19, 4) DEFAULT 0,
		[01] 				DECIMAL(19, 4) DEFAULT 0,
		[02] 				DECIMAL(19, 4) DEFAULT 0,
		[03] 				DECIMAL(19, 4) DEFAULT 0,
		[04] 				DECIMAL(19, 4) DEFAULT 0,
		[05] 				DECIMAL(19, 4) DEFAULT 0,
		[06] 				DECIMAL(19, 4) DEFAULT 0,
		[07] 				DECIMAL(19, 4) DEFAULT 0,
		[08] 				DECIMAL(19, 4) DEFAULT 0,
		[09] 				DECIMAL(19, 4) DEFAULT 0,
		[10] 				DECIMAL(19, 4) DEFAULT 0,
		[11] 				DECIMAL(19, 4) DEFAULT 0,
		[12] 				DECIMAL(19, 4) DEFAULT 0,
		[13] 				DECIMAL(19, 4) DEFAULT 0,
		[14] 				DECIMAL(19, 4) DEFAULT 0,
		[15] 				DECIMAL(19, 4) DEFAULT 0,
		[16] 				DECIMAL(19, 4) DEFAULT 0,
		[17] 				DECIMAL(19, 4) DEFAULT 0,
		[18] 				DECIMAL(19, 4) DEFAULT 0,
		[19] 				DECIMAL(19, 4) DEFAULT 0,
		[20] 				DECIMAL(19, 4) DEFAULT 0,
		[21] 				DECIMAL(19, 4) DEFAULT 0,
		[22] 				DECIMAL(19, 4) DEFAULT 0,
		[23] 				DECIMAL(19, 4) DEFAULT 0,
		[24] 				DECIMAL(19, 4) DEFAULT 0,
		[25] 				DECIMAL(19, 4) DEFAULT 0,
		[26] 				DECIMAL(19, 4) DEFAULT 0,
		[27] 				DECIMAL(19, 4) DEFAULT 0,
		[28] 				DECIMAL(19, 4) DEFAULT 0,
		[29] 				DECIMAL(19, 4) DEFAULT 0,
		[30] 				DECIMAL(19, 4) DEFAULT 0,
		[31] 				DECIMAL(19, 4) DEFAULT 0
	)

	-- Insert data to temp table
	SET @sqlSupport = NULL
	;WITH CTE_RptDate AS (
		SELECT ('[' + LEFT(CONVERT(VARCHAR(5), PK_DATE, 106), 2) + ']') RptDate
		FROM bodb_Account.dbo.DimDate
		WHERE PK_Date >= @FromDate AND PK_Date <= @ToDate
	)
	SELECT @sqlSupport = COALESCE(@sqlSupport + ', ' + RptDate, RptDate)
	FROM CTE_RptDate

	SET @sqlQuery = NULL
	SET @sqlQuery = 'INSERT INTO #tmpFinalData ([isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductGroup], [ProductName], [ProductShortName], [Figure], [Monthly], [MTD], ' + @sqlSupport + ')'
	SET @sqlQuery = @sqlQuery + CHAR(13) +
	                'EXEC(''' +
					'EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Credit ' +
					'@FromDate = ''''' + CONVERT(VARCHAR(50), @FromDate, 112) + ''''', ' +
					'@ToDate = ''''' +    CONVERT(VARCHAR(50), @ToDate, 112) + ''''', ' +
					'@ProductList = ''''' + @ProductList + '''''''' +
					') AT DBWH'
	EXEC (@sqlQuery)

	SET @sqlQuery = NULL
	SET @sqlQuery = 'INSERT INTO #tmpFinalData ([isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductGroup], [ProductName], [ProductShortName], [Figure], [Monthly], [MTD], ' + @sqlSupport + ')'
	SET @sqlQuery = @sqlQuery + CHAR(13) +
	                'EXEC(''' +
					'EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Deposit ' +
					'@FromDate = ''''' + CONVERT(VARCHAR(50), @FromDate, 112) + ''''', ' +
					'@ToDate = ''''' +    CONVERT(VARCHAR(50), @ToDate, 112) + ''''', ' +
					'@ProductList = ''''' + @ProductList + '''''''' +
					') AT DBWH'
	EXEC (@sqlQuery)

	SET @sqlQuery = NULL
	SET @sqlQuery = 'INSERT INTO #tmpFinalData ([isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductGroup], [ProductName], [ProductShortName], [Figure], [Monthly], [MTD], ' + @sqlSupport + ')'
	SET @sqlQuery = @sqlQuery + CHAR(13) +
	                'EXEC(''' +
					'EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_PayToSupplierGMT ' +
					'@FromDate = ''''' + CONVERT(VARCHAR(50), @FromDate, 112) + ''''', ' +
					'@ToDate = ''''' +    CONVERT(VARCHAR(50), @ToDate, 112) + ''''', ' +
					'@ProductList = ''''' + @ProductList + ''''', ' +
					'@DepositType = ''''' + CAST(@DepositType AS VARCHAR(10)) + ''''', ' +
					'@IsOldView = ''''' + CAST(@IsOldView AS VARCHAR(10)) + '''''''' +
					') AT DBEXT'
	EXEC (@sqlQuery)

	-- Select data from temp table
	SET @sqlSupport = NULL
	;WITH CTE_RptDate AS (
		SELECT ('f.[' + LEFT(CONVERT(VARCHAR(5), PK_DATE, 106), 2) + ']') RptDate
		FROM bodb_Account.dbo.DimDate
		WHERE PK_Date >= @FromDate AND PK_Date <= @ToDate
	)
	SELECT @sqlSupport = COALESCE(@sqlSupport + ', ' + RptDate, RptDate)
	FROM CTE_RptDate

	SET @sqlQuery = NULL
	SET @sqlQuery = 'SELECT f.[isDeposit], f.[OrderByProduct], f.[OrderByFigure], f.[SiteGroup], f.[ProductGroup], f.[ProductName], f.[ProductShortName], f.[Figure], f.[Monthly], f.[MTD], ' + @sqlSupport + CHAR(13) +
					'FROM #tmpFinalData f' + CHAR(13) +
					'ORDER BY f.[isDeposit], f.[SiteGroup], f.[OrderByProduct], f.[OrderByFigure]'

	EXEC (@sqlQuery)

	-- Drop temp table
	DROP TABLE #tmpFinalData

END

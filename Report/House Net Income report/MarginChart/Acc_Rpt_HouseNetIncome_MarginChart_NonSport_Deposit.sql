/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit]
	@FromDate		DATE,
	@ToDate			DATE,
	@ProductList	VARCHAR(MAX) = ''
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20180806@Harper - DHWL Margin Chart - Create new message notification to NSD group based on Product List [#RedmineID: 98611]

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB' - if group is NSD Group

	Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit '2018-05-01', '2018-05-17'
  
*/ 
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @DefaulProductList VARCHAR(MAX) = 'EX,GD,FW,AB,VB,CB,BT,CO,MGCLC,MGCRNG,AGC,KN,LT,CS,NG'

	-- Select ProductList
	SELECT @ProductList = CASE WHEN LEN(ISNULL(@ProductList, '')) > 0  THEN @ProductList ELSE @DefaulProductList END

	IF LEN(ISNULL(@ProductList, '')) > 0 
	BEGIN
		SELECT val AS ProductPrefix
		INTO #tmpProduct
		FROM dbo.strSplit(@ProductList, ',')
	END

	DECLARE @SQL VARCHAR(MAX)
	SELECT @SQL = '-- Create Temp Table Final Return Data ' + CHAR(13)

	
	DECLARE @SumValue VARCHAR(1000)	
	SET @SumValue = 'SELECT ''NonSport'' AS ProductCode, [Order], Figure, SUM(FullRange) AS FullRange '

	SELECT @SQL = @SQL + 'CREATE TABLE #MarginChartResult (ProductCode VARCHAR(50), [Order] TINYINT, Figure NVARCHAR(100), FullRange MONEY, ' + CHAR(13)
			
	DECLARE @tmpDate DATE, @date VARCHAR(5)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		
		SELECT @date = CONVERT(VARCHAR(2), @tmpDate, 106)

		SELECT @SQL = @SQL + '[' + @date + ']' + ' MONEY, '
		SELECT @SumValue = @SumValue + ', SUM(' + '[' + @date + ']' + ') AS ' + + '[' + @date + ']'

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @SQL = LEFT(@SQL, DATALENGTH(@SQL) -2) + ')'	+ CHAR(13)
	SELECT @SumValue = @SumValue + ' FROM #MarginChartResult GROUP BY [Order], Figure ORDER BY [Order]'
	
	--EXEC (@DynamicTable)
	
	-- 12. EX
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'EX')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 11. GD
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'GD')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_GD_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 10. FW
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'FW')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 9. AB
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'AB')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_AB_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 8. Macau Game
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'VB')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_MacauGames_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 7. CB
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'CB')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_CB @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END

	-- 6. BT + CO
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix IN ('BT', 'CO'))
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_BT_CO_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END
	
	-- 5. Microgaming
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix IN ('MGCLC', 'MGCRNG'))
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_MGC_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 4. AGC
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'AGC')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_AGC_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 3. KN + LT
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix IN ('KN', 'LT'))
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_KN_LT_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 2. CS
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'CS')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_CS_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END	

	-- 1. NG
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'NG')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_NG_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END
		
	-- Region: Return final result
	SELECT @SQL = @SQL + @SumValue + CHAR(13)
	SELECT @SQL = @SQL + 'DROP TABLE #MarginChartResult' + CHAR(13)
	
	EXEC (@SQL)	
END
GO
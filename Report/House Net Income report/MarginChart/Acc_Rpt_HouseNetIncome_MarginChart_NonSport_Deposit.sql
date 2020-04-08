/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit 
	@FromDate       DATE
   ,@ToDate         DATE
   ,@ProductList    VARCHAR(MAX) = ''   
AS

/*
	Created:	20180126@Harper 
	Task:		HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:			DBEXT-bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20180806@Harper - DHWL Margin Chart - Create new message notification to NSD group based on Product List [#RedmineID: 98611]
		- 20180813@Harper - DHWL Non-sports Margin Chart - Integrate OneRNG Jackpot & Pragmatic [#RedmineID: 97562]
		- 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20191107@Robert -  NPH - House Net Income, Licensee Performance Email/Letstalk Report Integration [122516]
		- 20191127@Robert: Rename Product from 'NPH Promotion' to 'Saba Promotion'
		- 20200224@Kean: #123734 - Integrate SG (Spadegaming) product
		- 20200313@Kean - Change the "Pay to supplier" formula of SG - #126465
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200403@Percy: Integrate Xoc Dia (CC), Bluesprint's games (Macau Games), Table Games [RedmineID: #]

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB' - if group is NSD Group

	Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit '2018-07-01', '2018-07-30'
  
*/ 
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @DefaulProductList VARCHAR(MAX) = 'EX,GD,FW,AB,VB,CB,CO,AGC,KN,LT,CS,NG,PP,CC,SP,SG,VRG,SAG,I4D,TG'

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

	-- 20. TG
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'TG')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_TG_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END
	
	-- 19. I4D
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'I4D')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_I4D_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END

	-- 18. SA
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'SAG')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_SA_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END

	-- 17. VG
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'VRG')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_VG_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END

	-- 16. SG
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'SG')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_SG_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END

	-- 15. NPH
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'SP')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC DBWH.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_SP_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END		

	-- 14. CC
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'CC')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_CC_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END		

	-- 13. PP
	IF EXISTS (SELECT 1 FROM #tmpProduct WHERE ProductPrefix = 'PP')
	BEGIN
		SELECT @SQL = @SQL  + 'INSERT INTO #MarginChartResult ' + CHAR(13)
							+ 'EXEC Acc_Rpt_HouseNetIncome_MarginChart_PP_Deposit @FromDate = ''' + CONVERT(VARCHAR(10), @FDate, 120) + ''', @ToDate = ''' + CONVERT(VARCHAR(10), @TDate, 120) + '''' + CHAR(13)
	END		
	
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

	DROP TABLE #tmpProduct
END
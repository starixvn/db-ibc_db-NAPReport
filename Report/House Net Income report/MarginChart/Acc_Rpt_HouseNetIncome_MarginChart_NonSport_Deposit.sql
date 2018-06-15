/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:				DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit '2018-05-01', '2018-05-17'
  
*/ 
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	IF OBJECT_ID('tempdb..##FinalResult', 'U') IS NOT NULL
		DROP TABLE ##FinalResult

	DECLARE @DynamicTable VARCHAR(1000), @SumValue VARCHAR(1000)
	SET @DynamicTable = 'CREATE TABLE ##FinalResult (ProductCode VARCHAR(50), [Order] TINYINT, Figure NVARCHAR(100), FullRange MONEY, '
	SET @SumValue = 'SELECT ''NonSport'' AS ProductCode, [Order], Figure, SUM(FullRange) AS FullRange '
			
	DECLARE @tmpDate DATE, @date VARCHAR(5)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		
		SELECT @date = CONVERT(VARCHAR(2), @tmpDate, 106)

		SELECT @DynamicTable = @DynamicTable + '[' + @date + ']' + ' MONEY, '
		SELECT @SumValue = @SumValue + ', SUM(' + '[' + @date + ']' + ') AS ' + + '[' + @date + ']'

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DynamicTable = LEFT(@DynamicTable, DATALENGTH(@DynamicTable) -2) + ')'	
	SELECT @SumValue = @SumValue + ' FROM ##FinalResult GROUP BY [Order], Figure ORDER BY [Order]'
	
	EXEC (@DynamicTable)
	
	-- 13. EX
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_EX_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 11. GD
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_GD_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 10. FW
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_FW_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 9. AB
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_AB_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 8. Macau Game
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_MacauGames_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 7. CB
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_CB @FromDate = @FDate, @ToDate = @TDate

	-- 6. BT + CO
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_BT_CO_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 5. Microgaming
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_MGC_Deposit @FromDate = @FDate, @ToDate = @TDate	

	-- 4. AGC
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_AGC_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 3. KN + LT
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_KN_LT_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 2. CS
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_CS_Deposit @FromDate = @FDate, @ToDate = @TDate

	-- 1. NG
	INSERT INTO ##FinalResult
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NG_Deposit @FromDate = @FDate, @ToDate = @TDate
		
	EXEC (@SumValue)

	-- Region: Drop tmp table	
	DROP TABLE ##FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit] TO vnteam
GO
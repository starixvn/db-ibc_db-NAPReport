/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit]
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

	Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit '2018-05-01', '2018-05-17'
  
*/ 
BEGIN  
	SET NOCOUNT ON 

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @DynamicTable VARCHAR(1000), @SumValue VARCHAR(1000)
	SET @DynamicTable = 'CREATE TABLE ##FinalResultCredit (ProductCode VARCHAR(50), [Order] TINYINT, Figure NVARCHAR(100), FullRange MONEY, '
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
	SELECT @SumValue = @SumValue + ' FROM ##FinalResultCredit GROUP BY [Order], Figure ORDER BY [Order]'
	
	EXEC (@DynamicTable)
	
	---- 12. VS2
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_VS2_Credit @FromDate = @FDate, @ToDate = @TDate
	
	---- 11. LT
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_LT_Credit @FromDate = @FDate, @ToDate = @TDate

	-- 10. LK3
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_LK3_Credit @FromDate = @FDate, @ToDate = @TDate

	-- 9. GD
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_GD_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 8. FW
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_FW_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 7. AB
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_AB_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 6. Macau Game
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_MacauGames_Credit @FromDate = @FDate, @ToDate = @TDate
		
	---- 5. NG2
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NG2_Credit @FromDate = @FDate, @ToDate = @TDate	
	
	---- 4. KN
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_KN_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 3. CS
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_CS_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 2. VS
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_VS_Credit @FromDate = @FDate, @ToDate = @TDate

	---- 1. NG
	INSERT INTO ##FinalResultCredit
	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NG_Credit @FromDate = @FDate, @ToDate = @TDate
		
	EXEC (@SumValue)

	-- Region: Drop tmp table	
	DROP TABLE ##FinalResultCredit	
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit] TO vnteam
GO
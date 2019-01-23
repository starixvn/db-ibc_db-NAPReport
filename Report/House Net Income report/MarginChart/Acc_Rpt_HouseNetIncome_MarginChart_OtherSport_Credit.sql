/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit]
	@FromDate DATE 
    ,@ToDate	DATE 
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Other Sport[#RedmineID: 89632]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit '2017-12-01', '2017-12-31'
  
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Handle data of Soccer

    CREATE TABLE #FinalResult(
	    RptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , ExtraPT     MONEY
	  , TurnOver    MONEY);

    INSERT INTO #FinalResult(RptDate
					  , HouseWL
					  , ExtraPT
					  , TurnOver)
		 SELECT 'FullRange'
			 , 0
			 , 0
			 , 0;
    -- Date list to draw chart

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, HouseWL
							, ExtraPT
							, TurnOver)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0
				    , 0
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    -- House WL of Other Sport

    CREATE TABLE #TmpHouseWL(
	    rptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , HouseWL					 
					 , ExtraPT
					 , TurnOver)
    EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Sub
	    @FDate
	  , @TDate
	  , @IsDeposit = 0;

    UPDATE f
		 SET
			f.HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0)
		   , f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0)
		   , f.ExtraPT = ISNULL(f.ExtraPT, 0) + ISNULL(wl.ExtraPT, 0)
    FROM #FinalResult f
	   INNER JOIN #TmpHouseWL wl ON wl.rptDate = f.RptDate;
				
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''OtherSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table	
	DROP TABLE #TmpHouseWL	
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Credit] TO [dwrs]
GO

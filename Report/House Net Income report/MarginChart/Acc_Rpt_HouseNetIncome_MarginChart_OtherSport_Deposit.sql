/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Deposit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Other Sport[#RedmineID: 89632]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		- 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		- 20200701@Percy: Remove PayToMuayThai [RedmineID: #136792]

	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit '2017-12-01', '2017-12-31'
  
*/    
BEGIN  
    SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
    SELECT  @FDate = @FromDate, @TDate = @ToDate

	CREATE TABLE #__OtherSportWL
	(
		rptDate		VARCHAR(2)
		,HouseWL    MONEY
		,TurnOver   MONEY
		,ExtraPT    MONEY
	)
    INSERT INTO #__OtherSportWL (rptDate, HouseWL, ExtraPT, TurnOver)
    EXEC dbwh.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Sub @FDate, @TDate, 1

    CREATE TABLE #FinalResult
	(
		rptDate		VARCHAR(10)
		,HouseWL    MONEY DEFAULT (0)
		,TurnOver   MONEY DEFAULT (0)
		,ExtraPT    MONEY DEFAULT (0)
	)

	INSERT INTO #FinalResult (rptDate)
	VALUES ('FullRange')

	;WITH CTE_Date AS
	(
		SELECT @FDate AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_Date
		WHERE rptDate < @TDate
	)
	INSERT INTO #FinalResult (rptDate, HouseWL, ExtraPT, TurnOver)
	SELECT CONVERT(VARCHAR(2), d.rptDate, 106), ISNULL(t.HouseWL, 0), ISNULL(t.ExtraPT, 0), ISNULL(t.TurnOver, 0)
	FROM CTE_Date d
		LEFT JOIN #__OtherSportWL t ON CONVERT(VARCHAR(2), d.rptDate, 106) = t.rptDate

    DECLARE @DateList VARCHAR(1000)
	SELECT  @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #FinalResult

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT  @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''OtherSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)
	
	DROP TABLE #FinalResult	
	DROP TABLE #__OtherSportWL
END
GO
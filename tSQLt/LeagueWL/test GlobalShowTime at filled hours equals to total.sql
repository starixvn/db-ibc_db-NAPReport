USE bodb02
GO

ALTER PROCEDURE testLeagueWinloss.[test GlobalShowTime at custom hours equals to total]
AS
	/*created by Jaden*/
	/*execution: `tSQLt.Run 'testLeagueWinloss.[test GlobalShowTime at custom hours equals to total]'`*/
BEGIN
    -------------------------------------------------------------
    IF OBJECT_ID('tempdb..#actual') IS NOT NULL DROP TABLE #actual
    IF OBJECT_ID('tempdb..#expected') IS NOT NULL DROP TABLE #expected
    -------------------------------------------------------------
    EXEC dbo.[__set up tests__]
	-------------------------------------------------------------
	DECLARE 
	 @ReportDate DATETIME= '20201028'
	,@SportBetType VARCHAR(MAX)= '1_913,1_472,1_175,1_447,1_416,1_488,1_451,1_912,1_398,10000_9,10000_29,10001_999'
    -------------------------------------------------------------
	CREATE TABLE #actual ( SportType            INT,
                           Sport				VARCHAR(50),
                           LeagueName			VARCHAR(50),
						   MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)

	CREATE TABLE #expected(SportType            INT,
                           Sport				VARCHAR(50),
                           LeagueName			VARCHAR(50),
                           MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)
    -------------------------------------------------------------
	INSERT INTO #expected
	EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype_xtest @StartDate=@ReportDate, @EndDate=@ReportDate, 
		@SportBettype=@SportBetType, @GlobalShowTime = '1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24'

    INSERT INTO #actual
	EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Sporttype_xtest @StartDate=@ReportDate, @EndDate=@ReportDate, 
		@SportBettype=@SportBetType, @GlobalShowTime = '0'
		
	-- @GlobalShowTime = '0' includes parlay & odds spread data
	DELETE FROM #actual WHERE SportType IN (10000, 10001) 
	EXEC tSQLt.AssertEquals 2, @@ROWCOUNT
    -------------------------------------------------------------
    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
    -------------------------------------------------------------
END;
GO

tSQLt.Run 'testLeagueWinloss.[test GlobalShowTime at filled hours equals to total]'
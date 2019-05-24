/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
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
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit '2017-12-01', '2017-12-31'
  
*/    
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate       DATE
	   , @TDate       DATE
	   , @tmpDate     DATE
	   , @DateList    VARCHAR(200);

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate
	    , @tmpDate = @FDate;

    DECLARE @PayToMuayThai TABLE(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY);

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY
	  , HouseWL          MONEY DEFAULT 0
	  , ExtraPT          MONEY DEFAULT 0
	  , TurnOver         MONEY DEFAULT 0);

    INSERT INTO #FinalResult(rptDate
					  , PayToMuayThai)
		 (
			SELECT 'FullRange'
				, 0 AS PayToMuayThai
		 );

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMuayThai)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    ---------------------------------------------------- Pay to Muay Thai -------------------------------------------------------

    INSERT INTO @PayToMuayThai(RptDate
					    , PayToMuayThai)
    EXEC Acc_Rpt_HouseNetIncome_SB_PayToMuayThai
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @DepositType = 1;

    UPDATE f
		 SET
			f.PayToMuayThai = p.PayToMuayThai
    FROM #FinalResult f
	   INNER JOIN @PayToMuayThai p ON f.RptDate = p.rptDate
    WHERE f.RptDate <> 'FullRange';
    ----------------------------------------------------End Pay to Muay Thai -------------------------------------------------------

    --- GET TO & House Income

    CREATE TABLE #TmpHouseWL(
	    rptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , HouseWL
					 , ExtraPT
					 , TurnOver)

    EXEC dbwh.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Sub
	    @FDate
	  , @TDate
	  , @IsDeposit = 1;

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
							'SELECT ''OtherSport'', 8, ''Turn Over'', TurnOver' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 6, ''Pay to Muay Thai'', PayToMuayThai) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)
	
	DROP TABLE #FinalResult	
	DROP TABLE #TmpHouseWL
END
GO

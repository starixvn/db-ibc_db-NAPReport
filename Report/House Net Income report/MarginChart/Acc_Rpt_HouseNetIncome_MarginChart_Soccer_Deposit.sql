/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Soccer [#RedmineID: 89632]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		- 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Deposit '2018-04-01', '2018-04-30'
  
*/    
BEGIN  
	   SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Handle data of Soccer

    CREATE TABLE #FinalResult(
	    RptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY
	  , HouseWL              MONEY DEFAULT 0
	  , ExtraPT              MONEY DEFAULT 0
	  , TurnOver             MONEY DEFAULT 0
	  , PayToGenius          MONEY DEFAULT 0);

    DECLARE @PayToMetricGaming TABLE(
	    RptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY);

    DECLARE @PayToBetBuilder TABLE(
	    rptDate        VARCHAR(10)
	  , PayToGenius    MONEY);

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);	

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 SELECT ExchangeDate
			 , ExchangeID
			 , BaseCurrencyRate
		 FROM bodb02.dbo.LA_f_ExchangeDailySel
			 (@FDate, @TDate, 'MYR');

    INSERT INTO #FinalResult(rptDate
					  , PayToMetricGaming
					  , PayToGenius)
		 SELECT 'FullRange'
			 , 0
			 , 0;
    -- Date list to draw chart

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMetricGaming
							, PayToGenius)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0 AS PayToMetricGaming
				    , 0 AS PayToGenius;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    -- End region	

    ---------------------------------------------------- Pay to Metric Gaming ----------------------------------------------------

    INSERT INTO @PayToMetricGaming(RptDate
						   , PayToMetricGaming)
    EXEC Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @DepositType = 1;

    UPDATE f
		 SET
			f.PayToMetricGaming = p.PayToMetricGaming
    FROM #FinalResult f
	   INNER JOIN @PayToMetricGaming p ON f.RptDate = p.RptDate
    WHERE f.RptDate <> 'FullRange';
    ---------------------------------------------------- Pay To Bet Builder -------------------------------------------------------

    INSERT INTO @PayToBetBuilder(rptDate
						 , PayToGenius)
    EXEC Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @DepositType = 1;   

    UPDATE f
		 SET
			f.PayToGenius = p.PayToGenius
    FROM #FinalResult f
	   INNER JOIN @PayToBetBuilder p ON f.RptDate = p.rptDate
    WHERE f.RptDate <> 'FullRange';
    -- Get Turnover, House Income from DW [Credit]

    CREATE TABLE #TmpHouseWL(
	    rptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , HouseWL
					 , ExtraPT
					 , TurnOver)
    EXEC dbwh.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MarginChart_Soccer_Sub
	    @FDate
	  , @TDate
	  , @isDeposit = 1;

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
							'(SELECT ''Soccer'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 8, ''Turn Over'', TurnOver' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 7, ''Pay to Metric Gaming'', PayToMetricGaming' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''Soccer'', 9, ''Pay to Bet Genius'', PayToGenius) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop temp table
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult	
	DROP TABLE #TmpHouseWL	
END

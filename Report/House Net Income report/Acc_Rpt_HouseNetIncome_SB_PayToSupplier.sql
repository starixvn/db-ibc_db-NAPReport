/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SB_PayToSupplier]
	@FromDate DATE
	, @ToDate	DATE 
	, @DepositType    SMALLINT = 2	
AS  
/*  
	Created: Robert
	Date: 20200203
    Task : - 20200203@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
    DB: DBEXT/bodb02  
   
    Revisions:		
		- 20200203@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report

	Param's Explanation:  
		  - DepositType  
				    = 2 All
				    = 1 Deposit Only 
				    = 0 Credit Only 

	EXEC Acc_Rpt_HouseNetIncome_SB_PayToSupplier '2017-12-01', '2017-12-31'
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @PayToBetBuilder TABLE(
	    rptDate        VARCHAR(10)
	  , PayToGenius    MONEY);

    DECLARE @PayToMetricGaming TABLE(
	    rptDate              VARCHAR(10)
	  , PayToMetricGaming    MONEY);

    DECLARE @PayToMuayThai TABLE(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY);

    CREATE TABLE #FinalResult(
	    RptDate              VARCHAR(10)
	  , PayToMuayThai        MONEY
	  , PayToMetricGaming    MONEY
	  , PayToGenius          MONEY);

    INSERT INTO #FinalResult(rptDate
					  , PayToMuayThai
					  , PayToMetricGaming
					  , PayToGenius)
		 SELECT 'FullRange'
			 , 0 AS PayToMuayThai
			 , 0 AS PayToMetricGaming
			 , 0 AS PayToGenius;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMuayThai
							, PayToMetricGaming
							, PayToGenius)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106) AS RptDate
				    , 0 AS PayToMuayThai
				    , 0 AS PayToMetricGaming
				    , 0 AS PayToGenius;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
    -- End region
    ---------------------------------------------------- Pay to Metric Gaming -------------------------------------------------------

    INSERT INTO @PayToMetricGaming(rptDate
						   , PayToMetricGaming)
    EXEC Acc_Rpt_HouseNetIncome_SB_PayToMetricGaming 
	    @FDate
	  , @TDate
	  , @DepositType;

    UPDATE f
		 SET 
			f.PayToMetricGaming = p.PayToMetricGaming
    FROM #FinalResult f
	   INNER JOIN @PayToMetricGaming p ON f.RptDate = p.rptDate;
    ---------------------------------------------------- Pay To Bet Builder -------------------------------------------------------

    INSERT INTO @PayToBetBuilder(rptDate
						 , PayToGenius)
    EXEC Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder 
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @DepositType = @DepositType;

    UPDATE f
		 SET 
			f.PayToGenius = p.PayToGenius
    FROM #FinalResult f
	   INNER JOIN @PayToBetBuilder p ON f.RptDate = p.rptDate;
    ---------------------------------------------------- Pay to Muay Thai -------------------------------------------------------

    INSERT INTO @PayToMuayThai(RptDate
					    , PayToMuayThai)
    EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToMuayThai 
	    @FromDate = @FDate
	  , @ToDate = @TDate
	  , @DepositType = @DepositType;

    UPDATE f
		 SET 
			f.PayToMuayThai = p.PayToMuayThai
    FROM #FinalResult f
	   INNER JOIN @PayToMuayThai p ON f.RptDate = p.rptDate;
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +							
							'(SELECT ''SB'', 6, ''Pay to Muay Thai'', PayToMuayThai' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 7, ''Pay to Metric Gaming'', PayToMetricGaming' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 8, ''Pay to Bet Genius'', PayToGenius) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)
	DROP TABLE #FinalResult
END
GO

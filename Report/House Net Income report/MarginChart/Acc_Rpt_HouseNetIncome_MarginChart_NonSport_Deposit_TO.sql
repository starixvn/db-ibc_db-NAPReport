/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit_TO
	@FromDate       DATE
   , @ToDate         DATE
   , @ProductList    VARCHAR(MAX) = ''
AS;
/*  	
    Created:		20190121@Robert - Deposit TO
    Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:			DBWH/bodb_dwrs  
   
    Revisions:
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]		
		- 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
		- 20200224@Kean: #123734 - House Net Income - Integrate SG (Spadegaming) product
		- 20200304@Kean: #129756 - Exclude bettype 4299 on Deposit TO
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200422@Percy: Integrate 3D Lottery (CC), Saba.Club, Sexy Gaming [RedmineID: #132790,#132791,#132792]

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB,SG' - if group is NSD Group

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Deposit_TO '2018-05-01', '2018-05-31'
  
*/  
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @Deposit    VARCHAR(MAX) = 'NG,CS,KN,LT,AGC,CO,CB,VB,AB,GD,BX,VS,VS2,PP,CC,SG,VRG,SAG,I4D,TG,SBC,SXG';

    CREATE TABLE #Exchange(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    CREATE TABLE #tmpProduct(
	    ProductPrefix    VARCHAR(20));

    INSERT INTO #Exchange(ExchangeDate
				    , ExchangeID
				    , Rate)
		 (
			SELECT ExchangeDate
				, Currency
				, Rate
			FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK)
			WHERE ExchangeDate BETWEEN @FDate AND @TDate
		 );

    IF LEN(ISNULL(@ProductList, '')) > 0
	   BEGIN
		  INSERT INTO #tmpProduct(ProductPrefix)
			    (
				   SELECT val AS ProductPrefix
				   FROM dbo.strSplit
					   (@ProductList, ',')
			    );
	   END;

    CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #Exchange(ExchangeDate, ExchangeID);

    CREATE TABLE #FinalResult(
	    RptDate     VARCHAR(10)
	  , TurnOver    MONEY);

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200) = '[FullRange]';

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, TurnOver)
			    (
				   SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
					   , 0
			    );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;

    CREATE TABLE #SportBettypeMatrix(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));

    CREATE TABLE #TmpData(
	    rptDate       DATE
	  , ProductID     INT
	  , CurrencyID    INT
	  , TurnOver      MONEY);

    INSERT INTO #SportBettypeMatrix(ProductID
						    , Bettype
						    , EventType
						    , SubProduct)
		 (
			SELECT ProductID
				, BetType
				, EventType
				, SubProduct
			FROM bodb02.dbo.f_SportBettypeMatrix_Sel
				(0, 0, 0, 2, '', @Deposit, 0) AS sel
			WHERE ISNULL(@ProductList, '') = ''
				 OR EXISTS
						 (
							SELECT 1
							FROM #tmpProduct AS p
							WHERE sel.ProductPrefix = p.ProductPrefix
						 )
		 ); 

    INSERT INTO #TmpData(rptDate
				   , ProductID
				   , CurrencyID
				   , TurnOver)
		 (
			SELECT b.rptDate
				, sb.ProductID
				, b.CurrencyID
				, SUM(CASE
						WHEN TurnoverIBC = 0
						THEN 0
						ELSE TurnoverIBC - ExtraTO
					 END * CASE
							 WHEN VarianceVR > 0
							 THEN VarianceVR + 1
							 ELSE 1
						  END * ex.Rate) AS TurnOver
			FROM bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			    INNER JOIN #exchange AS ex ON b.rptdate = ex.exchangedate
									    AND b.currencyid = ex.ExchangeID
			    INNER JOIN #SportBettypeMatrix AS sb ON sb.Bettype = b.bettype
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.TicketStatus NOT IN(-1, 18, 9, 10, 14)
				 AND b.BetType NOT IN (4299, 4300)
				 AND SiteID IN
							(
							    SELECT SiteID
							    FROM bodb_Account.dbo.tbl_Site
							    WHERE isDeposit = 1
							)-- Deposit data only
			GROUP BY b.rptDate
				  , sb.ProductID
				  , b.CurrencyID
		 );
    -- Final Return

    WITH totalcte
	    AS (
	    SELECT rptDate
		    , SUM(ISNULL(TurnOver, 0)) AS TurnOver
	    FROM #TmpData
	    GROUP BY rptDate)
	    UPDATE f
			 SET
				TurnOver = f.TurnOver + wl.TurnOver
	    FROM #FinalResult f
		   INNER JOIN totalcte wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate;    

    INSERT INTO #FinalResult(RptDate
					  , TurnOver)
		 (
			SELECT 'FullRange'
				, 0
		 );
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +						
							'(SELECT ''NonSport'', 8, ''Turn Over'', TurnOver) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpData
	DROP TABLE #Exchange	
	DROP TABLE #FinalResult
	DROP TABLE #tmpProduct
END
GO

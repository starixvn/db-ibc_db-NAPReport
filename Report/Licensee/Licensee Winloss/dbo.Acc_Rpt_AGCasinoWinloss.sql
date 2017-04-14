USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_AGCasinoWinloss]    Script Date: 09/29/2014 17:02:27 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER  PROCEDURE [dbo].[Acc_Rpt_AGCasinoWinloss] 
 @LicenseeID	INT,
 @Currency		INT = 0,
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @ReportType	TINYINT = 1,
 @TableType 	TINYINT = 1,
 @excludeTest   BIT = 0
AS  

/*

exec Acc_Rpt_AGCasinoWinloss
 @LicenseeID=1
,@Currency=0,@FromDate='2014-07-01 00:00:00',@ToDate='2014-08-31 00:00:00',@ReportType=1,@excludeTest=1
*/
/*  Created: Jim
	Date: 2014-09-18
    Task : AG Win Loss report 
    DB: DBACC.bodb02  
    Revisions: 
	-20150127@Winnie: Add base currency GBP 
		
	Param's Explanation:  
	  + @excludeTest: remove currency UUS
*/   


BEGIN

	CREATE TABLE #tmpResult (Winlostdate DATETIME
							 ,Currency 		  INT
							 ,TurnOver 		  MONEY
							 ,TotalTrans	  INT	
							 ,Winlost  		  MONEY
							 ,LicenseeWinlost MONEY
							)
						
	CREATE TABLE #tmpAg (CustId   INT
						,Currency INT
						)
		
	DECLARE @VNDCurrencyName VARCHAR(20)
			,@ChargeRate 	 FLOAT      
			,@EffectiveDate	 DATETIME
			
	SELECT @VNDCurrencyName = currency 
		   ,@ChargeRate = 0.15
	FROM  dbo.Exchange WITH (NOLOCK) 
	WHERE ExchangeId = 51
	
	SELECT @EffectiveDate = EffectiveDate
	FROM DBLIC.bodb_licensee.dbo.LicenseeProduct3rd WITH (NOLOCK)
	WHERE LicenseeID  = @LicenseeID
		AND ProductID = 10 --- AG Casino
		
	INSERT INTO #tmpAg (CustID,Currency)	
	SELECT CustID,Currency
	FROM DBLIC.bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK)
	WHERE LicenseeID = @LicenseeID
		AND (@Currency = 0 OR (@Currency <> 0 AND Currency = @Currency))
		AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	
	
	INSERT INTO #tmpResult ( Winlostdate 
							 ,Currency 	
							 ,TurnOver 	
							 ,TotalTrans
							 ,Winlost  	
							 ,LicenseeWinlost 
							)

	SELECT c.Winlostdate
		   ,co.Currency
		   ,SUM(c.TurnOver) AS TurnOver
		   ,SUM(c.BetCount) AS TotalTrans
		   ,SUM(c.Winlost)  AS Winlost
		   ,-SUM(c.Winlost) AS LicenseeWinlost
	FROM  bodb_report.dbo.rptDepWinlost_AGCasino c  WITH (NOLOCK)
		INNER JOIN dbo.Custinfo co WITH  (NOLOCK) ON c.CustID = co.CustID
		INNER JOIN #tmpAg ag ON co.recommend = ag.CustID
	WHERE c.Winlostdate BETWEEN @FromDate AND @ToDate 
		  AND c.Winlostdate >= @EffectiveDate
	GROUP BY c.Winlostdate
		    ,co.Currency
	
	SELECT ExchangeDate
		   ,ExchangeId
		   ,Code
		   ,USD
		   ,EUR
		   ,MYR
		   ,GBP
	INTO #TempExchange 
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #tmpResult)
	
	SELECT CASE WHEN @ReportType = 1 THEN r.winlostdate
			WHEN @ReportType = 2 THEN Dateadd(d,1-DATEPART(d,r.winlostdate),r.winlostdate)--- CONVERT(VARCHAR(6),w.winlostdate,112)  
			ELSE '0' END ReportType
		   ,r.Currency
		   ,CASE WHEN Currency=51  THEN  @VNDCurrencyName
				 ELSE e.Code 
				 END CurrencyName		
		   ,SUM(r.TurnOver)   	 				AS TurnOver
		   ,SUM(r.TotalTrans) 	 				AS TotalTrans
		   ,SUM(r.Winlost)		 				AS Winlost
		   ,SUM(r.LicenseeWinlost) 				AS LicenseeWL
		   ,SUM(r.LicenseeWinlost*@ChargeRate)  AS AmtDueToAGC
		---MYR
			,SUM(r.TurnOver*e.MYR)   	 			  AS TurnOverMYR
			,SUM(r.Winlost*e.MYR)		 			  AS WinlostMYR
			,SUM(r.LicenseeWinlost*e.MYR) 			  AS LicenseeWLMYR
			,SUM(r.LicenseeWinlost*@ChargeRate*e.MYR)  AS AmtDueToAGCMYR
		---USD
			,SUM(r.TurnOver*e.USD)   	 			  AS TurnOverUSD
			,SUM(r.Winlost*e.USD)		 			  AS WinlostUSD
			,SUM(r.LicenseeWinlost*e.USD) 			  AS LicenseeWLUSD
			,SUM(r.LicenseeWinlost*@ChargeRate*e.USD)  AS AmtDueToAGCUSD
		---EUR
			,SUM(r.TurnOver*e.EUR)   	 	AS TurnOverEUR
			,SUM(r.Winlost*e.EUR)		 	AS WinlostEUR
			,SUM(r.LicenseeWinlost*e.EUR)   AS LicenseeWLEUR
			,SUM(r.LicenseeWinlost*@ChargeRate*e.EUR)  AS AmtDueToAGCEUR
		---GBP
			,SUM(r.TurnOver*e.GBP)   	 	AS TurnOverGBP
			,SUM(r.Winlost*e.GBP)		 	AS WinlostGBP
			,SUM(r.LicenseeWinlost*e.GBP)   AS LicenseeWLGBP
			,SUM(r.LicenseeWinlost*@ChargeRate*e.GBP)  AS AmtDueToAGCGBP
			
	FROM #tmpResult r
		INNER JOIN #TempExchange e ON r.Winlostdate = e.ExchangeDate AND r.currency = e.ExchangeId
	GROUP BY  CASE WHEN @ReportType = 1 THEN r.winlostdate
			 WHEN @ReportType = 2 THEN Dateadd(d,1-DATEPART(d,r.winlostdate),r.winlostdate)--- CONVERT(VARCHAR(6),w.winlostdate,112)  
								  ELSE '0' 
								  END 
			 ,r.Currency
			 ,CASE WHEN Currency=51  THEN  @VNDCurrencyName
				 ELSE e.Code 
				 END 		
	ORDER BY CASE WHEN @ReportType = 1 THEN r.winlostdate
			WHEN @ReportType = 2 THEN Dateadd(d,1-DATEPART(d,r.winlostdate),r.winlostdate)--- CONVERT(VARCHAR(6),w.winlostdate,112)  
			ELSE '0' END
	---------
	DROP TABLE #tmpResult
	DROP TABLE #tmpAg
	DROP TABLE #TempExchange 
	
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_AGCasinoWinloss] TO [bodbAdminNet]  
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_AGCasinoWinloss] TO [vnteam]  
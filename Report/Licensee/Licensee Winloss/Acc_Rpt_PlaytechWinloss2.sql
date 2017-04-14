SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

 
CREATE PROCEDURE [dbo].[Acc_Rpt_PlaytechWinloss2] 
 @LicenseeID	INT,
 @Currency		INT = 0,
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @ReportType	TINYINT = 1,
 @excludeTest BIT = 0
AS  
/*  Created: Hannah  
	Date: 2014-04-14
    Task : Playtech Casino - Win Loss Report 
    DB: DB06.bodb02  
   
    Revisions:  
		- 20150211@Jim: support base on GBP
	Param's Explanation:  
	  + @ReportType: 1-Daily; 2-Monthly;  
	  + @BackupDay: The day we move tickets to rptDepWinlostByProduct_bk
	  + @excludeTest: remove currency UUS
*/  
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #SAgWinLoss  
	(  
		winlostdate		DATETIME,  
		Currency		INT,
		TurnOver		MONEY,   	
		Winlost			MONEY,  
		LicenseeWL		MONEY, 
		AmtDueTo		MONEY,
		PlayerComm 		MONEY,
		BetCount		BIGINT
	)  

	DECLARE @tempAg	TABLE(custID INT, currency INT) 
	DECLARE @LicenseeName VARCHAR(50)
			,@VNDCurrencyName VARCHAR(20)
			,@BackupDay SMALLDATETIME
			,@SqlCmd    VARCHAR(4000)
			,@Rate		VARCHAR(3)
			,@i 		TINYINT
			,@maxID		INT
			
	SELECT @BackupDay = MIN(winlostdate)
	FROM [bodb_report].[dbo].[rptDepWinlostByProduct] WITH (NOLOCK)

	SELECT @LicenseeName = LicenseeName 
	FROM DBLIC.bodb_Licensee.dbo.Licensees WITH (NOLOCK) 
	WHERE LicenseeID = @LicenseeID

	INSERT INTO @tempAg (custID, currency) 
	SELECT custID, currency 
	FROM DBLIC.bodb_Licensee.dbo.LicenseeCust WITH (NOLOCK) 
	WHERE 
		LicenseeID = @LicenseeID
		AND (@Currency = 0 OR (@Currency <> 0 AND Currency = @Currency))
		AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	

	SELECT @VNDCurrencyName = currency 
	FROM exchange (NOLOCK) 
	WHERE ExchangeId = 51

	DECLARE @Super AS TABLE (custid INT PRIMARY KEY, currency INT)
	INSERT INTO @Super(custid, currency)  
	SELECT CustID, currency 
	FROM bodb02.dbo.Dep_CustSuper WITH (NOLOCK)  
	WHERE site = @LicenseeName	

	DECLARE @TempFromDate DATETIME 
	DECLARE @TempToDate DATETIME 
	DECLARE @FDate DATETIME 
	DECLARE @TDate DATETIME 
	--to Deal With Parameter Sniffing
	SELECT @FDate = @FromDate, @TDate = @ToDate 

	IF @TDate >= @BackupDay
	BEGIN
		IF @FDate < @BackupDay 
			SET @TempFromDate = @BackupDay
		ELSE
			SET @TempFromDate = @FDate
	
		INSERT INTO #SAgWinLoss
		SELECT   
			r.winlostdate,  
			s.currency,
			SUM(r.turnover) AS Turnover, 
			SUM(r.winlost) AS Winlost,  
			SUM(-1 *r.winlost) AS LicenseeWL,
			SUM(-0.01 *r.winlost) AS AmountDueTo,
			SUM(r.PlayerComm) AS PlayerComm,
			SUM(r.BetCount) AS BetCount	
		FROM 
			bodb_report.dbo.rptDepWinlostByProduct r WITH (NOLOCK)
			INNER JOIN bodb02.dbo.custInfo ci WITH ( NOLOCK) ON ci.CustID = r.CustID
			INNER JOIN @Super s ON ci.srecommend = s.custid
			INNER JOIN @TempAg a ON ci.recommend = a.custid
		WHERE
			r.winlostdate BETWEEN @TempFromDate AND @TDate 
			AND r.sporttype = 254
		GROUP BY   
			r.winlostdate,s.currency
	END  

	IF @FDate < @BackupDay 
	BEGIN
		IF @TDate >= @BackupDay
				SET @TempToDate = DATEADD(DAY, -1, @BackupDay)
			ELSE
				SET  @TempToDate = @TDate	
	
		INSERT INTO #SAgWinLoss  
		SELECT 
			r.winlostdate,  
			s.currency, 
			SUM(r.Turnover) AS Turnover,     
			SUM(r.Winlost) AS Winlost,  
			- SUM(r.winlost) AS LicenseeWL ,
			SUM(-0.01 *r.winlost) AS AmountDueTo,
			SUM(r.playercomm ) AS PlayerComm, 
			SUM(r.BetCount) AS BetCount
		FROM 
			bodb_report.dbo.rptDepWinlostByProduct_bk r WITH ( NOLOCK )  
			INNER JOIN bodb02.dbo.custInfo ci WITH ( NOLOCK) ON ci.CustID = r.CustID
			INNER JOIN @Super s ON ci.srecommend = s.custid
			INNER JOIN @TempAg ag ON ag.custid = ci.recommend
		WHERE  
			r.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND r.sporttype = 254
		GROUP BY  r.winlostdate, s.currency
	END 
	CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss(Currency)
	SELECT * INTO #TempExchange 
	FROM Lrf_f_GetExchangeDaily(@FDate,@TDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #SAgWinLoss)
	SET @SqlCmd  = ''
	SELECT @SqlCmd  = @SqlCmd  +
								'SELECT' +CHAR(13)+
								CASE WHEN  @ReportType = 1 THEN 'CONVERT(VARCHAR(8),w.winlostdate,112) '
									 WHEN  @ReportType = 2 THEN 'CONVERT(VARCHAR(6),w.winlostdate,112) ' 	
									 ELSE '0' END +'ReportType,'+CHAR(13)+
								'Currency,'	 + CHAR(13)+
								'CASE WHEN Currency = 51 THEN '''+CONVERT(VARCHAR(20),@VNDCurrencyName) +''''+CHAR(13)+
									'ELSE e.Code END CurrencyName,'+CHAR(13)+
								'SUM(TurnOver)	AS Turnover, '	   +CHAR(13)+
								'SUM(Winlost)		AS Winlost,'   +CHAR(13)+
								'SUM(LicenseeWL)  AS LicenseeWL,'  +CHAR(13)+
								'SUM(PlayerComm)  AS PlayerComm,'  +CHAR(13)+
							    'SUM(AmtDueto)    AS AmtDueTo,'    +CHAR(13)+
							    'SUM(Betcount)	AS BetCount,'	   +CHAR(13)		 
	SELECT  @i = 1
			,@maxID = MAX(ID)
	FROM dbo.Lrf_f_basecurrency (@ToDate)
	WHILE (@i <= @maxID)
	BEGIN
		SELECT @Rate = Currency
		FROM dbo.Lrf_f_basecurrency (@ToDate)
		WHERE ID = @i
		SELECT @SqlCmd  = @SqlCmd  + '----'+CONVERT(VARCHAR(3),@Rate)+CHAR(13)+
									+'CAST(SUM(TurnOver*e.'+CONVERT(VARCHAR(3),@Rate)+')   AS MONEY) AS Turnover'+@Rate+','+CHAR(13)+
									+'CAST(SUM(Winlost*e.'+CONVERT(VARCHAR(3),@Rate)+')    AS MONEY) AS Winlost'+@Rate+','+CHAR(13)+
									+'CAST(SUM(LicenseeWL*e.'+CONVERT(VARCHAR(3),@Rate)+') AS MONEY) AS LicenseeWL'+@Rate+','+CHAR(13)+
									+'CAST(SUM(PlayerComm*e.'+CONVERT(VARCHAR(3),@Rate)+') AS MONEY) AS PlayerComm'+@Rate+','+CHAR(13)+
									+'CAST(SUM(AmtDueto*e.'+CONVERT(VARCHAR(3),@Rate)+')   AS MONEY) AS AmtDueTo'+@Rate+','+CHAR(13)
		SET @i = @i+1							
	END
	
	SELECT @SqlCmd  = SUBSTRING(@SqlCmd,1,LEN(@SqlCmd)-2) +CHAR(13) +'FROM'+CHAR(13)	+
								'#SAgWinLoss w  '+CHAR(13)+
								'INNER JOIN  #TempExchange e
								ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId'+CHAR(13)+
							'GROUP BY   
								Currency,'+CHAR(13)+
								CASE WHEN @ReportType = 1 THEN ' CONVERT(VARCHAR(8),w.winlostdate,112)' 
									  WHEN @ReportType = 2 THEN ' CONVERT(VARCHAR(6),w.winlostdate,112)'
									  ELSE '0' END +','+CHAR(13)+
								' CASE WHEN Currency = 51 THEN '''+CONVERT(VARCHAR(20),@VNDCurrencyName)+''''+CHAR(13)+
										'ELSE e.Code END'+CHAR(13)+
							'ORDER BY ReportType' +CHAR(13) 
	EXEC (@SqlCmd)
	DROP TABLE #TempExchange
	DROP TABLE #SAgWinLoss   
END   

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_PlaytechWinloss2] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_PlaytechWinloss2] TO [bodbLicenseeNet]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_PlaytechWinloss2] TO [bodbAdminNet]
GO 

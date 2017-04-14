CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Spondemo]
	@CustID		INT = 0,
	@FromDate	SMALLDATETIME,
	@ToDate		SMALLDATETIME,
	@showSB		BIT =1,
	@showHR		BIT = 0,
	@ReportType	TINYINT = 0,
	@BaseCurrency	INT=0,
	@BalanceUpDay	SMALLDATETIME
AS
/*
	Created: Johnson
	Date: 2010-11-13
	Task: Report Winloss for Spondemo
	DB: DB052.BODB02
	
	Param's Explanation:  
	  + @CustID: SuperID  
	  + @ReportType: 1-Daily; 2-Monthly; 3-Sports   
	  + @BaseCurrency (input currencyID): 2-RM ; 3-US$ 
*/
BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #SAgWinloss(
		WinlostDate		DATETIME,
		CustId			INT,
		Sporttype		INT,
		Turnover		MONEY,
		GrossComm		MONEY,
		Winlost			MONEY,
		Comm			MONEY,
		AWinlost		MONEY,
		AComm			MONEY,
		Company			MONEY)
	DECLARE @TmpCond		TABLE (sporttype INT, bettype INT)
	DECLARE @TmpCondSumWL	TABLE (sporttype INT, bettype INT)
	DECLARE @TmpSponSAg		TABLE (custID INT PRIMARY KEY)

	IF @CustID = 0
	BEGIN
		INSERT INTO @TmpSponSAg (custID)
			SELECT custID FROM dbo.f_DepSUperByCurrency('Spondemo')
	END
	ELSE BEGIN
		INSERT INTO @TmpSponSAg (custID) VALUES (@custID)
	END
	
	IF @showSB = 1
	BEGIN
		--Bettrans 
		INSERT INTO @TmpCond (sporttype, bettype) 
		SELECT 0 AS sporttype, typeid FROM bettype (NOLOCK) WHERE typeid < 31
		--Sum_Winloss
		INSERT INTO @TmpCondSumWL (sporttype, bettype)
		VALUES(0,0)
	END

	IF @showHR = 1
	BEGIN
		--Bettrans
		INSERT INTO @TmpCond (sporttype, bettype)
			SELECT 151 , 31 UNION ALL  SELECT 151, 32 UNION ALL SELECT 151, 33 UNION ALL
			SELECT 151 , 41 UNION ALL	SELECT 151,42 UNION ALL SELECT 151, 43
		--Sum_Winloss
		INSERT INTO @TmpCondSumWL (sporttype, bettype)
		VALUES ( 151, 0)
	END
	
	IF @ToDate > @BalanceUpDay
	BEGIN
		INSERT INTO #SAgWinloss
		SELECT
			b.winlostdate,
			b.srecommend,
			t.sporttype,
			SUM(CASE WHEN b.liveawayscore = 0 and b.bettype in (33,43) THEN  b.stake/2 ELSE b.stake END) AS turnover,
			SUM(scomm/(1-tpositiontaking)) AS GrossComm,
			SUM(b.winlost - b.actual_stake) AS Winlost,
			SUM(b.playercomm) AS Comm,
			SUM(b.swinlost + b.mwinlost + b.awinlost) AS AWinlost,
			SUM(b.scomm - b.playercomm) AS AComm,
			- SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost -b.actual_stake + b.scomm) Company
		FROM bettrans b WITH(NOLOCK)
			INNER JOIN @TmpCond t ON b.bettype = t.bettype
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate AND
			b.bettype < 99 AND
			b.ruben = 1 AND
			-- b.status NOT IN ('VOID','REJECT','REFUND')  		
			b.statusID NOT IN (101,102,103) AND
			b.srecommend IN (SELECT custid FROM @TmpSponSAg)
		GROUP BY b.winlostdate, b.srecommend, t.sporttype,b.bettype

		IF  @BalanceUpDay < @FromDate
			SELECT @BalanceUpDay = @FromDate

		INSERT INTO #SAgWinloss
		SELECT 
			b.winlostdate,
			b.srecommend,
			b.sporttype,
			b.turnover,
			b.grosscomm as GrossComm,
			b.winlost,
			b.playercomm,
			b.swinlost + b.mwinlost + b.awinlost,
			b.scomm - b.playercomm,
			-(b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm) Company
		FROM dbo.Sum_Winloss b WITH (NOLOCK)
			INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype 
		WHERE b.winlostdate BETWEEN @BalanceUpDay AND @ToDate
			AND b.roleid = 3
			AND b.srecommend  IN (SELECT custid FROM @TmpSponSAg)
	END

	IF @FromDate < @BalanceUpDay
	BEGIN
		IF @ToDate >= DATEADD(dd,-1,@BalanceUpDay)
			SELECT @ToDate = DATEADD(dd,-1,@BalanceUpDay)
		INSERT INTO #SAgWinloss	
		SELECT
			b.winlostdate,
			b.srecommend,
			b.sporttype,
			b.turnover,
			b.grosscomm AS GrossComm,
			b.winlost,
			b.playercomm,
			b.swinlost + b.mwinlost + b.awinlost,
			b.scomm - b.playercomm, 
			-(b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm) Company
		FROM bodb_Summary.dbo.Sum_Winloss_Old b WITH(NOLOCK)
			INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0
		WHERE 
			b.winlostdate BETWEEN @FromDate AND @ToDate AND
			b.roleid = 3 AND
			b.srecommend IN (SELECT custid FROM @TmpSponSAg)
	END

	SELECT 
		CASE WHEN @Reporttype = 1 THEN CONVERT(VARCHAR(8),w.winlostdate, 112)
			 WHEN @Reporttype = 2 THEN CONVERT(VARCHAR(6),w.winlostdate, 112)
			 WHEN @Reporttype = 3 THEN w.sporttype
			 ELSE 0 END Reporttype,
		CASE WHEN @BaseCurrency IN (2,3) THEN 0 ELSE h.currency END currency,
		SUM(TurnOver)	AS TurnOver,
		SUM(GrossComm)	AS GrossComm,
		SUM(Winlost)	AS Winlost,
		SUM(Comm)		AS Comm,
		SUM(AWinlost)	AS AWinlost,
		SUM(AComm)		AS AComm,
		SUM(Company)	AS Company,
		--Base USD
		SUM(TurnOver*h.USDRate)	AS TurnOverUSD,
		SUM(GrossComm*h.USDRate)	AS GrossCommUSD,
		SUM(Winlost*h.USDRate)	AS WinlostUSD,
		SUM(Comm*h.USDRate)		AS CommUSD,
		SUM(AWinlost*h.USDRate)	AS AWinlostUSD,
		SUM(AComm*h.USDRate)	AS ACommUSD,
		SUM(Company*h.USDRate)	AS CompanyUSD,
		--Base RM
		SUM(TurnOver*h.actualrate)	AS TurnOverRM,
		SUM(GrossComm*h.actualrate)	AS GrossCommRM,
		SUM(Winlost*h.actualrate)	AS WinlostRM,
		SUM(Comm*h.actualrate)		AS CommRM,
		SUM(AWinlost*h.actualrate)	AS AWinlostRM,
		SUM(AComm*h.actualrate)		AS ACommRM,
		SUM(Company*h.actualrate)	AS CompanyRM
	FROM #SAgWinLoss w
		INNER JOIN Exchange_History h WITH(NOLOCK) ON w.winlostdate = h.winlostdate AND w.custid = h.srecommendSPON
	GROUP BY
		CASE WHEN @BaseCurrency IN (2,3) THEN 0 ELSE h.currency END,
		CASE WHEN @Reporttype = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)
			WHEN @Reporttype = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)
			WHEN @Reporttype = 3 THEN w.sporttype
			ELSE 0 END
	ORDER BY Reporttype, currency

DROP TABLE #SAgWinLoss
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Spondemo] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Spondemo] TO [vnteam]

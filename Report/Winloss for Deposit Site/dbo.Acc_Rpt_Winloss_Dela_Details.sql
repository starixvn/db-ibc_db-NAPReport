CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Dela_Details]  
 @CustID		INT=0,  
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @showSB		BIT=1,  
 @showHR		BIT=0,  
 @BaseCurrency	INT = 0,  
 @BalanceUpDay	SMALLDATETIME  
AS  
/*  Created: Henry  
	Date: 2010-06-29  
    Task : Winloss Report for DELA  
    DB: DB052.bodb02  
   

  
 Param's Explanation:  
  + @CustID: SuperID  
  + @BaseCurrency (input currencyID): 2-RM ; 3-US$  
  
*/  
BEGIN  
 SET NOCOUNT ON  
 CREATE TABLE #SAgWinLoss (  
	  winlostdate	DATETIME,  
	  CustID		INT,   
	  Username		VARCHAR(30),  
	  SRecommend	INT,  
	  TurnOver		MONEY,   
	  GrossComm		MONEY,   
	  Winlost		MONEY,  
	  Comm			MONEY,   
	  AWinlost		MONEY,   
	  AComm			MONEY,   
	  Company		MONEY) 
 DECLARE @TmpCond		TABLE( sporttype INT, bettype INT)  
 DECLARE @TmpCondSumWL	TABLE( sporttype INT, bettype INT)  
 DECLARE @tmpDelaSAg		TABLE( custID INT PRIMARY KEY) 

 IF @custID = 0 
 BEGIN
	INSERT INTO @tmpDelaSAg(custID) SELECT custID FROM dbo.f_DepSuperByCurrency('DELA')
 END
 ELSE 
 BEGIN
	INSERT INTO @tmpDelaSAg(custID) VALUES(@custID)
 END 
  
 IF @ShowSB = 1  
 BEGIN  
	  --Bettrans  
	INSERT INTO @TmpCond(Sporttype, Bettype)  
	SELECT 0 AS sporttype, typeid FROM bettype (NOLOCK)  
	WHERE typeid < 31 
	--Sum_winloss  
	INSERT INTO @TmpCondSumWL(sporttype, bettype)  
	VALUES(0,0)  
 END  
  
 IF @ShowHR = 1  
 BEGIN  
	--Bettrans  
	INSERT INTO @TmpCond(Sporttype, Bettype)  
	SELECT 151, 31 UNION ALL SELECT 151, 32 UNION ALL SELECT 151, 33 UNION ALL 
	SELECT 151, 41 UNION ALL SELECT 151, 42 UNION ALL SELECT 151, 43 

	--Sum_winloss  
	INSERT INTO @TmpCondSumWL(sporttype, bettype)  
	VALUES(151,0)  
 END  
  
 IF @Todate >= @BalanceUpDay   
 BEGIN   
  INSERT INTO #SAgWinLoss  
  SELECT   
    b.winlostdate,  
    b.custid,  
    b.username,  
    b.srecommend,   
    SUM(CASE WHEN b.liveawayscore = 0 and b.bettype in(33,43) THEN b.stake/2 ELSE b.stake END) AS turnover,   
    SUM(comm/(1-apositiontaking)) AS GrossComm,   
    SUM(b.winlost - b.actual_stake) AS Winlost,  
    SUM(b.playercomm) Comm,  
    SUM(b.swinlost + b.mwinlost + b.awinlost)AWinlost,  
    SUM(b.scomm - b.playercomm) Acomm,  
    - SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost - b.actual_stake + b.scomm) Company  
   
  FROM	dbo.bettrans b WITH (NOLOCK)   
		INNER JOIN @TmpCond t ON b.bettype = t.bettype  
  WHERE b.winlostdate BETWEEN @FromDate AND @ToDate AND  
    --b.status NOT IN ('VOID', 'REJECT', 'Refund') AND  
    b.bettype < 99 AND  
    b.ruben=1 AND   
    b.statusID NOT IN (101, 102, 103) AND
    SRecommend IN ( SELECT custid FROM @tmpDelaSAg)    
  GROUP BY   
    b.winlostdate, b.custid, b.srecommend, b.bettype, b.username   
    
  IF @BalanceUpDay < @FromDate  
   SELECT @BalanceUpDay=@FromDate  
  
  INSERT INTO #SAgWinLoss  
  SELECT b.winlostdate,   
    b.custid,   
    b.username,   
    b.srecommend,  
    SUM(b.turnover),     
    SUM(b.grosscomm) AS GrossComm,  
    SUM(b.winlost),  
    SUM(b.playercomm),  
    SUM(b.swinlost + b.mwinlost + b.awinlost),  
    SUM(b.scomm - b.playercomm),  
    - SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm)   
  
  FROM	dbo.sum_winloss b WITH (NOLOCK)   
		INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0
  WHERE b.winlostdate BETWEEN @BalanceUpDay AND @todate  
		AND b.roleid = 1   
		AND b.SRecommend IN ( SELECT custid FROM @tmpDelaSAg) 
  GROUP BY b.winlostdate, b.custid, b.srecommend , b.username   
 END  
  
 IF @FromDate < @BalanceUpDay   
 BEGIN  
  IF @ToDate >= DATEADD(dd, -1, @BalanceUpDay)  
   SELECT @ToDate = DATEADD(dd, -1, @BalanceUpDay)  
    
  INSERT INTO #SAgWinLoss  
  SELECT b.winlostdate,  
    b.custid,   
    b.username,  
    b.srecommend,   
    SUM(b.turnover),     
    SUM(b.grosscomm) AS GrossComm,  
    SUM(b.winlost),  
    SUM(b.playercomm),  
    SUM(b.swinlost + b.mwinlost + b.awinlost),  
    SUM(b.scomm - b.playercomm),  
    - SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm)     
  FROM  bodb_Summary.dbo.Sum_WinLoss_Old b WITH(NOLOCK)   
		INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0
  WHERE  
		b.Winlostdate BETWEEN @FromDate AND @ToDate  
		AND b.roleid = 1   
		AND b.SRecommend IN ( SELECT custid FROM @tmpDelaSAg) 
  GROUP BY b.winlostdate, b.custid, b.srecommend, b.username    
 END  
  
 SELECT   
   w.username,  
   w.custid,  
   SUM(TurnOver)		AS Turnover,   
   sum(GrossComm)		AS GrossComm,  
   SUM(Winlost)			AS Winlost,  
   SUM(Comm)			AS Comm,  
   SUM(AWinlost)		AS AWinlost,  
   SUM(AComm)			AS AComm,  
   SUM(Company)			AS Company,  
   --BaseUSD  
   SUM(TurnOver*h.USDRate)  AS TurnoverUSD,  
   SUM(GrossComm*h.USDRate) AS GrossCommUSD,  
   SUM(Winlost*h.USDRate)	AS WinlostUSD,  
   SUM(Comm*h.USDRate)		AS CommUSD,  
   SUM(AWinlost*h.USDRate)  AS AWinlostUSD,  
   SUM(AComm*h.USDRate)		AS ACommUSD,  
   SUM(Company*h.USDRate)	AS CompanyUSD,  
   --BaseRM  
   SUM(TurnOver*h.actualrate)	AS TurnoverRM,   
   sum(GrossComm*h.actualrate)	AS GrossCommRM,  
   SUM(Winlost*h.actualrate)	AS WinlostRM,  
   SUM(Comm*h.actualrate)		AS CommRM,  
   SUM(AWinlost*h.actualrate)	AS AWinlostRM,  
   SUM(AComm*h.actualrate)		AS ACommRM,  
   SUM(Company*h.actualrate)	AS CompanyRM       
 FROM	#SAgWinLoss w   
		INNER JOIN Exchange_History h WITH (NOLOCK) ON w.winlostdate = h.winlostdate AND w.srecommend = h.srecommendDELA  
 GROUP BY w.custid, w.username  
 DROP TABLE #SAgWinLoss
END    
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Dela_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Dela_Details] TO [vnteam]
ALTER PROCEDURE [dbo].[Acc_Rpt_LicWinlossDetail_SAg2]    
 @LicenseeID INT,  
 @Currency  INT = 0,  
 @FromDate  SMALLDATETIME,    
 @ToDate  SMALLDATETIME,     
 @showSB  BIT=1,    
 @ShowRB  BIT=0,    
 @ShowNG  BIT=0,   
 @ShowBA  BIT=0,  
 @ShowLC  BIT=0,  
 @ShowVS  BIT=0,  
 @ShowCS  BIT=0, -- RNG Casino
 @ShowKN  BIT=0, -- Keno
 @showMGCLC BIT=1, -- MGC-LC
 @showMGCRnG BIT=1, -- MGC-RNG
 @ShowAGC BIT=0, --AG Casino
 @ShowGD  BIT=0, -- Gold Deluxe
 @MoveBetsDay SMALLDATETIME,  
 @IsOld BIT = 0,  
 @drawfilter SMALLINT = 1,  
 @excludeTest BIT = 0  
AS    
/*   
	Created: Scott   
	Date: 2013-02-15    
    Task : Winloss Report for Licensee Super Level  
    DB: DB052.bodb02    
     
    Revisions: 
		- 20130527@Jim: support RNG Casino
		- 20140401@Hannah: offer Keno
		- 20140704@Jim: support Sporting solution
		- 20141205@Winnie: change from LicenseeCust to f_SelLicenseeCust, from DepCustSuper to f_SelDepCustSuper ( task change currency KeenOcean)
		- 20150123@Jim: support base on GBP currency 
		- 20150518@Florent: Add AGC and GD
		- 20150710@Jim:  Microgaming integration (Feature #38168)
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]

 Param's Explanation:    
   + @CustID: SuperID    
   + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)  
   + @IsOld: 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old.   
   + @excludeTest: remove currency UUS  
   + @showSB: Show SportsBook bets  
   + @ShowRB: Show RB bets  
   + @ShowNG: Show Number game bets  
   + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)  
   + @MoveBetsDay: The day we move tickets to bettrans14  
    
*/

    
BEGIN    
SET NOCOUNT ON    
  
CREATE TABLE #SAgWinLoss (    
 winlostdate  DATETIME,    
 CustID   INT,     
 Currency  INT,    
 TurnOver  MONEY,      
 Winlost   MONEY,  
 LicenseeWL  MONEY,   
 WinlossRB  MONEY,    
 AmtDueToBA  MONEY,     
 AmtDueToRB  MONEY,  
 CommBA   MONEY,     
 CommRB   MONEY,    
 PlayerComm   MONEY,  
 Company   MONEY,  
 Betcount  BIGINT  
)    

DECLARE @VNDCurrencyName VARCHAR(20)  
DECLARE @Super AS TABLE (custid int primary key, currency int)  
DECLARE @bettype AS TABLE (bettype INT PRIMARY KEY)  
DECLARE @sporttype TABLE(sporttype INT)  
---- Party and config
DECLARE @PartyId INT, @ProductList VARCHAR(100)
SELECT @PartyId = p.PartyID 
FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) 
WHERE p.OldRefID = @LicenseeID
	AND p.PartyType = 1

SELECT @ProductList = COALESCE(@ProductList + ',' + CAST(ProductPrefix AS VARCHAR), CAST(ProductPrefix AS VARCHAR))
FROM bodb_licensee.dbo.LA_f_Products3rd('')
WHERE (@ShowAGC = 1 AND ProductPrefix = 'AGC')
	OR (@ShowGD = 1 AND ProductPrefix = 'GD')

DECLARE @tmpParty AS TABLE (PartyId INT, LicenseeId INT, ProductID INT, Rate MONEY, FromDate SMALLDATETIME, ToDate SMALLDATETIME)

IF ISNULL(@ProductList, '') != ''
BEGIN
	INSERT INTO @tmpParty(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
		(
			SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID, @FromDate, @ToDate, @ProductList, 'OA', @excludeTest)
			WHERE DI_Rate > 0
		)
END
-----
SELECT @VNDCurrencyName = currency FROM dbo.Exchange (NOLOCK) WHERE ExchangeId = 51   
    
INSERT INTO @Super(custid,currency)    
SELECT DISTINCT CustID,currency FROM bodb_licensee.dbo.f_SelDepCustSuper((SELECT LicenseeName FROM bodb_Licensee.dbo.Licensees (NOLOCK) WHERE LicenseeID = @LicenseeID )  )--Dep_CustSuper WITH (NOLOCK)    
--WHERE  site = (SELECT LicenseeName FROM bodb_Licensee.dbo.Licensees (NOLOCK) WHERE LicenseeID = @LicenseeID )  
	--AND
	WHERE (@Currency = 0 OR (@Currency<> 0 AND Currency=@Currency))  
	AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))   

IF @ShowSB = 1    
	INSERT  INTO @sporttype( sporttype)
	VALUES  (0)   
  
IF @ShowRB = 1    
BEGIN    
	INSERT  INTO @sporttype( Sporttype) VALUES  (151)  
      
	INSERT INTO @bettype(bettype)  
	SELECT typeid 
	FROM bettype (NOLOCK)  
	WHERE (typeid BETWEEN 31 AND 33)  
END    

IF @ShowNG = 1  
BEGIN  
	INSERT INTO @sporttype(Sporttype)    
	VALUES(161)    

	INSERT INTO @bettype(bettype)  
	SELECT typeid FROM bettype (NOLOCK)  
	WHERE (typeid BETWEEN 81 AND 120)  
END   
IF @ShowLC = 1  
BEGIN  
	INSERT  INTO @sporttype( Sporttype)  
	VALUES  (162)  

	INSERT INTO @bettype(bettype)  
	SELECT typeid FROM bettype (NOLOCK)  
	WHERE (typeid BETWEEN 1101 AND 1199)  
END  

IF @ShowVS = 1  
BEGIN  
	INSERT  INTO @sporttype( Sporttype)  
	VALUES  (180)  

	INSERT INTO @bettype(bettype)  
	SELECT typeid FROM bettype (NOLOCK)  
	WHERE (typeid BETWEEN 1201 AND 1299)  
END  

IF @ShowCS=1 -- RNG Casino
BEGIN
	INSERT INTO @sporttype(sporttype)
	VALUES (251)
	INSERT INTO @bettype(bettype)
	VALUES(71)
END

IF @ShowKN=1 -- Keno
BEGIN 
	INSERT INTO @sporttype (sporttype)
	VALUES(202)
	INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 1501 AND 1599)
END 

IF @showMGCLC =1 -- MGC-LC
BEGIN 
	INSERT INTO @sporttype (sporttype)
	VALUES(203)

	INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 2001 AND 2007)
END

IF @showMGCRnG =1 -- MGC-RNG
BEGIN 
	INSERT INTO @sporttype (sporttype)
	VALUES(205)

	INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 2008 AND 2009)
END 

  
DECLARE @TempFromDate DATETIME   
DECLARE @TempToDate DATETIME   
DECLARE @MaxOldDate DATETIME  
DECLARE @FDate DATETIME   
DECLARE @TDate DATETIME  
--to Deal With Parameter Sniffing  
SELECT @FDate=@FromDate,@TDate=@ToDate   
     
IF @TDate > @MoveBetsDay  
BEGIN  
	IF @FDate <= @MoveBetsDay   
		SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)  
	ELSE  
		SET @TempFromDate = @FDate  
  
	IF @ShowBA = 1  
	BEGIN  
	
		INSERT INTO #SAgWinLoss    
		SELECT b.winlostdate, b.srecommend,b.currency,   
			SUM(stake *  
				CASE WHEN @drawfilter IN (2,3) THEN  
					CASE WHEN b.statusID = 111 THEN 0  
						WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5  
					ELSE 1 END  
				ELSE 1 END  
			) turnover,	
			SUM(b.winlost - b.actual_stake) AS Winlost,    
			0 as LicenseeWL,  
			0 AS WinlossRB,  
			- SUM (b.winlost - b.actual_stake + awinlost + comm ) AS AmountDueToBA,  
			0 AS AmountDueToRB,  
			SUM (comm) AS CommBA,  
			0 AS CommRB,  
			SUM( b.playerComm  ) AS PlayerComm,  
			0 AS Company,  
			COUNT(b.transid) * CASE WHEN @drawfilter = 2 THEN  
									CASE WHEN b.statusID = 111 THEN 0  
									ELSE 1 END  
								ELSE 1 END  BetCount   
		FROM dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)      
			INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency=s.currency
			INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid=BA.srecommend and b.transid = BA.transid     
		WHERE	b.winlostdate BETWEEN @TempFromDate AND @TDate AND    
			b.statusID  IN (111, 112, 113) AND   
			b.bettype NOT IN (901,902,903)
		GROUP BY b.winlostdate,b.currency,b.srecommend,b.statusID   
	END   
   
	IF @ShowSB=1  
	BEGIN  
	
		INSERT INTO #SAgWinLoss  
	
		SELECT b.winlostdate, b.srecommend, s.currency, 
			sum(stake *  
				CASE WHEN @drawfilter IN (2,3) THEN  
					CASE WHEN b.statusID = 111 THEN 0  
						WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5  
					ELSE 1 END  
				ELSE 1 END) turnover,  
			SUM(b.winlost - b.actual_stake) AS Winlost,    
			- SUM(b.winlost - b.actual_stake) AS LicenseeWL,  
			0 AS WinlossRB,  
			0 AS AmountDueToBA,  
			0 AS AmountDueToRB,  
			0 AS CommBA,  
			0 AS CommRB,  
			SUM( b.playercomm ) AS PlayerComm,  
			- SUM (b.winlost - b.actual_stake + awinlost + comm ) Company  ,  
			COUNT(b.transid)  
			* CASE WHEN @drawfilter = 2 THEN  
			CASE WHEN b.statusID = 111 THEN 0  
			ELSE 1 END  
			ELSE 1 END BetCount  
		FROM dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend )   
			INNER JOIN @Super s ON b.srecommend = s.custid  AND s.currency=b.currency
		WHERE b.winlostdate BETWEEN @TempFromDate AND @TDate AND    
			b.statusID  IN (111, 112, 113) AND  
			(b.bettype<31 OR (b.bettype BETWEEN 121 AND 999 AND b.bettype NOT IN (901,902,903)) OR (b.bettype BETWEEN 1301 AND 1399)) AND  
			b.tpositiontaking <> 0  
		GROUP BY b.winlostdate,s.currency,b.srecommend, b.statusID    
	END  
   
	IF (@ShowNG=1 OR @ShowLC=1 OR @ShowVS=1 OR @ShowRB=1 OR @ShowCS=1 OR @showKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)
	BEGIN  
		INSERT INTO #SAgWinLoss  
		SELECT b.winlostdate,b.srecommend,s.currency,   
			sum(  
			CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END  
			*  
			CASE WHEN @drawfilter IN (2,3) THEN  
				CASE WHEN b.statusID = 111 THEN 0  
				WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5  
				ELSE 1 END  
				ELSE 1 END ) turnover,  
			SUM(b.winlost - b.actual_stake) AS Winlost,    
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END ) AS LicenseeWL,  
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END) AS WinlossRB,  
			0 AS AmountDueToBA,  
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END) as AmountDueToRB,  
			0 AS CommBA,  
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END) AS CommRB,  
			SUM( b.playercomm ) AS PlayerComm,  
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END) Company  ,  
			COUNT(b.transid)  
			* CASE WHEN @drawfilter = 2 THEN  
			CASE WHEN b.statusID = 111 THEN 0  
			ELSE 1 END  
			ELSE 1 END  
			BetCount  
		FROM dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend )   
			INNER JOIN @Super s ON b.srecommend = s.custid  AND s.currency=b.currency
			INNER JOIN @bettype bt ON b.bettype = bt.bettype  
		WHERE b.winlostdate BETWEEN @TempFromDate AND @TDate AND    
			b.statusID  IN (111, 112, 113)  
		GROUP BY b.winlostdate,s.currency,b.srecommend, b.statusID    
	END  
END    
   
IF @FDate <= @MoveBetsDay   
BEGIN  
 IF @TDate >= @MoveBetsDay  
   SET @TempToDate = @MoveBetsDay  
  ELSE  
   SET  @TempToDate = @TDate  
 IF @ShowBA = 1  
 BEGIN  
  INSERT INTO #SAgWinLoss    
  SELECT   
   b.winlostdate,    
   b.srecommend,  
   b.currency,  
   SUM(b.turnover  
    *  
    CASE WHEN @drawfilter IN (2,3) THEN  
     CASE WHEN b.statusID = 111  THEN 0  
     WHEN b.statusID IN (114,115) THEN 0.5  
     ELSE 1 END  
    ELSE 1 END  
   ),       
   SUM(b.winlost),    
   0 as LicenseeWL,  
   0 AS WinlossRB,  
   - SUM (b.winlost+b.awinlost+b.comm) AS AmountDueToBA,  
   0 AS AmountDueToRB,  
   SUM (comm ) AS CommBA,  
   0 AS CommRB,  
   SUM( b.playercomm) AS PlayerComm,  
   0 AS Company,  
   SUM(b.betcount)  
   * CASE WHEN @drawfilter = 2 THEN  
     CASE WHEN b.statusID = 111 THEN 0  
     ELSE 1 END  
    ELSE 1 END  
  FROM bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK )    
  INNER JOIN @Super s ON b.srecommend = s.custid AND s.currency=b.currency
  WHERE    
   b.Winlostdate BETWEEN @FDate AND @TempToDate    
   AND b.roleid = 2     
   AND b.statusID <> 101 --exclude REJECT bets  
   AND ISNULL(b.isBA,0) = 1  AND
   b.bettype NOT IN (901,902,903)
  GROUP BY  b.winlostdate,b.currency, b.srecommend  , b.statusID  
 END  
   
 --exclude BA tickets  
 IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC=1 OR @ShowVS=1 OR @ShowCS=1 OR @showKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)  
 BEGIN  

  INSERT INTO #SAgWinLoss    
  SELECT   
   b.winlostdate,    
   b.srecommend,  
   b.currency,  
   SUM(b.turnover  
    *  
    CASE WHEN @drawfilter IN (2,3) THEN  
     CASE WHEN b.statusID = 111  THEN 0  
     WHEN b.statusID IN (114,115) THEN 0.5  
     ELSE 1 END  
    ELSE 1 END  
   ),       
   SUM(b.winlost),    
   - SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END) AS LicenseeWL ,  
   SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,  
   0 AS AmountDueToBA,  
   - SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) AS AmountDueToRB,  
   0 AS CommBA,  
   SUM ( CASE WHEN b.sporttype = 151 THEN comm  ELSE 0 END) AS CommRB,  
   SUM( b.playercomm ) AS PlayerComm,   
   - SUM(CASE WHEN b.sporttype <> 151 THEN  b.awinlost + b.winlost + b.comm ELSE 0 END)  as Company   ,  
   SUM(b.betcount)  
   * CASE WHEN @drawfilter = 2 THEN  
     CASE WHEN b.statusID = 111 THEN 0  
     ELSE 1 END  
    ELSE 1 END  
  FROM   
   bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK )    
   INNER JOIN @Super s ON b.srecommend = s.custid AND s.currency=b.currency
   INNER JOIN @sporttype t ON b.sporttype = t.sporttype  
  WHERE    
   b.Winlostdate BETWEEN @FDate AND @TempToDate    
   AND b.roleid = 2     
   AND b.statusID <> 101 --exclude REJECT bets  
   AND ISNULL(b.isBA,0) = 0  AND
   b.bettype NOT IN (901,902,903)
  GROUP BY  b.winlostdate,b.currency, b.srecommend, b.statusID  
 END  
   
     
 END   
 IF @IsOld = 1   
 BEGIN  
 SELECT @MaxOldDate = max(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (NOLOCK)  
 IF @TDate >= @MaxOldDate  
   SET @TempToDate = @MaxOldDate  
  ELSE  
   SET  @TempToDate = @TDate  
   
 IF @ShowBA = 1  
 BEGIN  
  INSERT INTO #SAgWinLoss    
  SELECT   
   b.winlostdate,    
   b.srecommend,  
   b.currency,  
   SUM(b.turnover  
    *  
    CASE WHEN @drawfilter IN (2,3) THEN  
     CASE WHEN b.statusID = 111  THEN 0  
     WHEN b.statusID IN (114,115) THEN 0.5  
     ELSE 1 END  
    ELSE 1 END  
   ),       
   SUM(b.winlost),    
   0 as LicenseeWL,  
   0 AS WinlossRB,  
   - SUM (b.winlost+b.awinlost+b.comm) AS AmountDueToBA,  
   0 AS AmountDueToRB,  
   SUM ( CASE WHEN ISNULL(b.isBA,0) = 1 THEN comm   ELSE 0 END) AS CommBA,  
   0 AS CommRB,  
   SUM( b.PlayerComm ) AS PlayerCommm,  
   0 AS Company,  
   SUM(b.betcount)  
   * CASE WHEN @drawfilter = 2 THEN  
     CASE WHEN b.statusID = 111 THEN 0  
     ELSE 1 END  
    ELSE 1 END  
  FROM   
   bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK)    
   INNER JOIN @super s ON s.custid = b.srecommend  AND s.currency=b.Currency
  WHERE    
   b.Winlostdate BETWEEN @FDate AND @TempToDate    
   AND b.roleid = 2     
   AND b.statusID <> 101 --exclude REJECT bets  
   AND ISNULL(b.isBA,0) = 1  AND
   b.bettype NOT IN (901,902,903)
  GROUP BY  b.winlostdate,b.currency, b.srecommend, b.statusID  
 END  
   
 --exclude BA tickets  
 IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC=1 OR @ShowVS=1 OR @ShowCS=1 OR @showKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)  
 BEGIN  

  INSERT INTO #SAgWinLoss    
  SELECT   
   b.winlostdate,    
   b.srecommend,  
   b.currency,  
   SUM(b.turnover  
    *  
    CASE WHEN @drawfilter IN (2,3) THEN  
     CASE WHEN b.statusID = 111  THEN 0  
     WHEN b.statusID IN (114,115) THEN 0.5  
     ELSE 1 END  
    ELSE 1 END  
   ),       
   SUM(b.winlost),    
   - SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END) AS LicenseeWL ,  
   SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,  
   0 AS AmountDueToBA,  
   - SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) AS AmountDueToRB,  
   0 AS CommBA,  
   SUM ( CASE WHEN b.sporttype = 151 THEN comm ELSE 0 END) AS CommRB,  
   SUM(b.playercomm) AS PlayerComm,  
   - SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END)  as Company   ,  
   SUM(b.betcount)  
   * CASE WHEN @drawfilter = 2 THEN  
     CASE WHEN b.statusID = 111 THEN 0  
     ELSE 1 END  
    ELSE 1 END  
  FROM   
   bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK)    
   INNER JOIN @super s ON s.custid = b.srecommend  AND s.currency=b.Currency
   INNER JOIN @sporttype t ON b.sporttype = t.sporttype  
  WHERE    
   b.Winlostdate BETWEEN @FDate AND @TempToDate    
   AND b.roleid = 2     
   AND b.statusID <> 101 --exclude REJECT bets  
   AND ISNULL(b.isBA,0) = 0  AND
   b.bettype NOT IN (901,902,903)
  GROUP BY  b.winlostdate,b.currency, b.srecommend, b.statusID  
 END  
   
 END  
	--
	DECLARE @Recommend VARCHAR(8000) = '', @SQL VARCHAR(8000) = ''
	CREATE TABLE #DataWinloss3rd (Recommend	INT, Winlostdate DATETIME, SportType INT, Currency INT, TurnOver MONEY, TotalTrans INT, Winloss MONEY)
	DECLARE @TempSMAG AS TABLE( LicenseeeID INT,SuperId INT, MasterId INT, CustId INT, CurrencyId INT)

	--get licensee recommend				
	INSERT INTO @TempSMAG(LicenseeeID, SuperId, MasterId, CustId, CurrencyId)
	SELECT DISTINCT LicenseeID, ci.srecommend, ci.mrecommend, lc.CustID, lc.Currency
	FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID) lc
		LEFT JOIN dbo.custInfo ci WITH (NOLOCK) ON lc.CustID = ci.recommend
	WHERE (@Currency = 0 OR (@Currency <> 0 AND lc.Currency = @Currency))
		AND lc.Currency <> 20
	
	SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ',' 
	FROM @TempSMAG 

	--truncate comma
	SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))	

	IF @ShowAGC = 1 -- AG Casino
		BEGIN
			SELECT @sql = 'SELECT Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss
							FROM OPENQUERY(DBACC,''EXEC bodb02.dbo.LA_Rpt_3rdProductWinloss
													@ProductCodes		= ''''@ProductCodes_''''
												, @Recommend		= ''''@Recommend_''''
												, @Currency 		= @Currency_
												, @FromDate 		= ''''@FromDate_''''
												, @ToDate 			= ''''@ToDate_''''
												, @DrawFilter 			= ''''@DrawFilter_''''
												'')'
			SET @SQL = REPLACE(@SQL, '@ProductCodes_', @ProductList)
			SET @SQL = REPLACE(@SQL, '@Recommend_', @Recommend)
			SET @SQL = REPLACE(@SQL, '@Currency_', @Currency)
			SET @SQL = REPLACE(@SQL, '@FromDate_', CONVERT( VARCHAR(10),@FromDate, 120))
			SET @SQL = REPLACE(@SQL, '@ToDate_', CONVERT( VARCHAR(10),@ToDate, 120))			
			SET @SQL = REPLACE(@SQL, '@DrawFilter_', @drawfilter)	
			
			INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss)
			EXECUTE (@SQL)
			
			INSERT INTO #SAgWinLoss(winlostdate, CustID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, PlayerComm, Company, Betcount)
			(
				SELECT   			   
					b.Winlostdate     
					, ag.SuperId
					, CurrencyID		   
					, SUM(Turnover) AS Turnover
					, SUM(WinLoss) AS Winlost			
					, - SUM(Winloss) AS LicenseeWL				
					, 0 AS WinlossRB
					, 0 AS AmtDueToBA
					, 0 AS AmtDueToRB
					, 0 AS CommBA
					, 0 AS CommRB
					, 0 AS PlayerComm
					, - SUM(WinLoss * p.Rate) AS Company 
					, SUM(b.TotalTrans) AS BetCount	  	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempSMAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId AND p.ProductID = 10
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.Winlostdate, ag.SuperId, CurrencyID 
			)			
		END
	IF @ShowGD = 1 -- GD
	BEGIN
		-- reset 
		DELETE #DataWinloss3rd		

		INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, Currency, TurnOver, TotalTrans, Winloss)
		EXECUTE dbo.LA_Rpt_ThirdPartyProductWinloss
				@ProductCodes	= @ProductList
				, @Recommend	= @Recommend
				, @Currency 	= @Currency
				, @DrawFilter	= @drawfilter
				, @FromDate 	= @FromDate
				, @ToDate 		= @ToDate
			
		INSERT INTO #SAgWinLoss(winlostdate,CustID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, PlayerComm, Company, Betcount)
			(
				SELECT   			   
					b.Winlostdate     
					, ag.SuperId
					, b.currency	   
					, SUM(Turnover) AS Turnover
					, SUM(WinLoss) AS Winlost			
					, - SUM(Winloss) AS LicenseeWL				
					, 0 AS WinlossRB
					, 0 AS AmtDueToBA
					, 0 AS AmtDueToRB
					, 0 AS CommBA
					, 0 AS CommRB
					, 0 AS PlayerComm
					, - SUM(WinLoss * p.Rate) AS Company 
					, SUM(b.TotalTrans) AS BetCount	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempSMAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId	AND p.ProductID = 11								
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.Winlostdate, ag.SuperId, b.Currency
			)			
	END 

 CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss(Currency)  
 SELECT * INTO #TempExchange  
 FROM Lrf_f_GetExchangeDaily (@Fdate,@Tdate)  
 WHERE exchangeid IN (SELECT DISTINCT Currency FROM #SAgWinLoss)  

 SELECT     
 c.username,    
 w.custid,   
 w.currency,  
 CASE WHEN w.Currency = 51 THEN @VNDCurrencyName   
   ELSE e.Code END AS CurrencyName,  
 SUM(TurnOver) AS Turnover,     
 SUM(Winlost)  AS Winlost,    
 SUM(LicenseeWL) AS LicenseeWL,  
 SUM(WinlossRB) AS WinlossRB,  
 SUM(CommBA) AS CommBA,  
 SUM(CommRB) AS CommRB,  
 SUM(PlayerComm) AS PlayerComm,  
 SUM(AmtDuetoBA) AS AmtDuetoBA,  
 SUM(AmtDuetoRB) AS AmtDuetoRB,  
 SUM(Company) AS Company,  
 SUM(Betcount) AS Betcount,  
 --BaseRM    
 CAST(SUM(TurnOver*e.MYR) AS MONEY) AS TurnoverMYR,     
 CAST(SUM(Winlost*e.MYR) AS MONEY) AS WinlostMYR,    
 CAST(SUM(LicenseeWL*e.MYR) AS MONEY) AS LicenseeWLMYR,  
 CAST(SUM(WinlossRB*e.MYR) AS MONEY) AS WinlossRBMYR,  
 CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR,  
 CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR,  
 CAST(SUM(PlayerComm*e.MYR) AS MONEY) AS PlayerCommMYR,  
 CAST(SUM(AmtDuetoBA*e.MYR) AS MONEY) AS AmtDuetoBAMYR,  
 CAST(SUM(AmtDuetoRB*e.MYR) AS MONEY) AS AmtDuetoRBMYR,  
 CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR,  
 --BaseUSD    
 CAST(SUM(TurnOver*e.USD) AS MONEY) AS TurnoverUSD,     
 CAST(SUM(Winlost*e.USD) AS MONEY) AS WinlostUSD,    
 CAST(SUM(LicenseeWL*e.USD) AS MONEY) AS LicenseeWLUSD,  
 CAST(SUM(WinlossRB*e.USD) AS MONEY) AS WinlossRBUSD,  
 CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD,  
 CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD,  
 CAST(SUM(PlayerComm*e.USD) AS MONEY) AS PlayerCommUSD,  
 CAST(SUM(AmtDuetoBA*e.USD) AS MONEY) AS AmtDuetoBAUSD,  
 CAST(SUM(AmtDuetoRB*e.USD) AS MONEY) AS AmtDuetoRBUSD,   
 CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD,  
 --BaseEUR    
 CAST(SUM(TurnOver*e.EUR) AS MONEY) AS TurnoverEUR,     
 CAST(SUM(Winlost*e.EUR) AS MONEY) AS WinlostEUR,    
 CAST(SUM(LicenseeWL*e.EUR) AS MONEY) AS LicenseeWLEUR,  
 CAST(SUM(WinlossRB*e.EUR) AS MONEY) AS WinlossRBEUR,  
 CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR,  
 CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR,  
 CAST(SUM(PlayerComm*e.EUR) AS MONEY) AS PlayerCommEUR,  
 CAST(SUM(AmtDuetoBA*e.EUR) AS MONEY) AS AmtDuetoBAEUR,  
 CAST(SUM(AmtDuetoRB*e.EUR) AS MONEY) AS AmtDuetoRBEUR,  
 CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR ,
 --BaseGBP   
 CAST(SUM(TurnOver*e.GBP) AS MONEY) 	AS TurnoverGBP,     
 CAST(SUM(Winlost*e.GBP) AS MONEY)		AS WinlostGBP,    
 CAST(SUM(LicenseeWL*e.GBP) AS MONEY)   AS LicenseeWLGBP,  
 CAST(SUM(WinlossRB*e.GBP) AS MONEY)    AS WinlossRBGBP,  
 CAST(SUM(CommBA * e.GBP) AS MONEY) 	AS CommBAGBP,  
 CAST(SUM(CommRB * e.GBP) AS MONEY) 	AS CommRBGBP,  
 CAST(SUM(PlayerComm*e.GBP) AS MONEY) 	AS PlayerCommGBP,  
 CAST(SUM(AmtDuetoBA*e.GBP) AS MONEY) 	AS AmtDuetoBAGBP,  
 CAST(SUM(AmtDuetoRB*e.GBP) AS MONEY) 	AS AmtDuetoRBGBP,  
 CAST(SUM(Company * e.GBP) AS MONEY) 	AS CompanyGBP  
             
 FROM #SAgWinLoss w     
  INNER JOIN #TempExchange e  
  ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId  
  INNER JOIN Customer c WITH(NOLOCK) ON w.custid = c.custid  
  GROUP BY w.currency,w.custid, c.username,   
   CASE WHEN w.Currency = 51 THEN @VNDCurrencyName   
    ELSE e.Code END  
  ORDER BY w.currency  
  
DROP TABLE #SAgWinLoss   
DROP TABLE #TempExchange  
DROP TABLE #DataWinloss3rd  
END


GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_LicWinlossDetail_SAg2] TO [bodbAdminNet] AS [dbo]
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_LicWinlossDetail_SAg2] TO [bodbLicenseeNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicWinlossDetail_SAg2] TO [vnteam] AS [dbo]
GO
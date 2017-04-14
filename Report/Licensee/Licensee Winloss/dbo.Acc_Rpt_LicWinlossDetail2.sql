ALTER PROCEDURE [dbo].[Acc_Rpt_LicWinlossDetail2]  
	@LicenseeID	INT,
	@Currency	INT = 0,
	@CustID		INT = 0, --AgentID			
	@FromDate	SMALLDATETIME,  
	@ToDate		SMALLDATETIME,   
	@showSB		BIT=1,  
	@ShowRB		BIT=0,  
	@ShowNG		BIT=0,
	@ShowBA		BIT=0,
	@ShowLC 	BIT=0,
	@ShowVS		BIT=0,
	@ShowCS  	BIT=0, -- RNG Casino
	@ShowKN  	BIT=0, -- Keno
	@ShowAGC	BIT = 0, --AG Casino
	@ShowGD		BIT = 0, -- Gold Deluxe
	@showMGCLC 	BIT	= 1, -- MGC-LC
	@showMGCRnG BIT	= 1, -- MGC-RNG
	@MoveBetsDay SMALLDATETIME,
	@IsOld BIT = 0,
	@drawfilter SMALLINT = 1,
	@excludeTest BIT = 0

AS  
/*  Created: Henry  
	Date: 2011-07-06  
    Task : Winloss Report for Licensee Member Level
    DB: DB052.bodb02  
   
    Revisions:  
		- 20110729@Henry: offer 3 new bettypes for Number Game
		- 20110903@Henry: support HALF WON/LOSE FOR ONLY bettype in (1,3,7,8,17,18)
		- 20110907@Henry: support to view Licensee Fee
		- 20110930@Henry: put a check for non-BA block
		- 20111013@Henry: change to use rptLicWinloss2
		- 20111208@Jim: change condition bettype <31 
		- 20120214@Jim: change to use  table ExchangeDaily by use function Lrf_f_GetExchangeDaily_xtest
		- 20120507@Jim: enhance query performance 
		- 20120803@Jim: add PlayerComm Value 
		- 20120816@Jim: add live casino
		- 20120905@Henry: add Virtual Sports
		- 20130527@Jim: support RNG Casino
		- 20140331@Hannah: offer Keno
		- 20140704@Jim: offer sporting solution
		- 20141205@Winnie: change from LicenseeCust to f_SelLicenseeCust, from DepCustSuper to f_SelDepCustSuper ( task change currency KeenOcean)
		- 20150123@Jim: support base on GBP currency
		- 20150518@Florent: Add AGC and GD
		- 20150710@Jim:  Microgaming integration (Feature #38168)
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]

	Param's Explanation:  
	  + @CustID: SuperID  
	  + @BaseCurrency (input currencyID): 2-MYR ; 3-USD; 6-EUR
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @IsOld: 0 - query IN table rptLicWinloss, 1 - query IN table rptLicWinloss_old. 
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live Casino
	  + @ShowVS: Show Virtual Sports
	  + @MoveBetsDay: The day we move tickets to bettrans14
	  
  
*/  
BEGIN  
SET NOCOUNT ON  

CREATE TABLE  #SAgWinLoss  (  
	CustID			INT,   
	Currency		INT,  
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY,
	WinlossRB		MONEY,
	AmtDueToBA	MONEY,   
	AmtDueToRB	MONEY,
	CommBA			MONEY,   
	CommRB		MONEY,
	PlayerComm  MONEY,	
	Company		MONEY,
	
	--MYR
	TurnOverMYR		MONEY,   	
	WinlostMYR			MONEY,  
	LicenseeWLMYR		MONEY,
	WinlossRBMYR		MONEY,
	AmtDueToBAMYR	MONEY,   
	AmtDueToRBMYR	MONEY,
	CommBAMYR			MONEY,   
	CommRBMYR		MONEY,
	PlayerCommMYR  MONEY,	
	CompanyMYR		MONEY,
	
	--USD
	TurnOverUSD		MONEY,   	
	WinlostUSD			MONEY,  
	LicenseeWLUSD		MONEY,
	WinlossRBUSD		MONEY,
	AmtDueToBAUSD	MONEY,   
	AmtDueToRBUSD	MONEY,
	CommBAUSD			MONEY,   
	CommRBUSD		MONEY,
	PlayerCommUSD  MONEY,	
	CompanyUSD		MONEY,
	
	--EUR
	TurnOverEUR		MONEY,   	
	WinlostEUR			MONEY,  
	LicenseeWLEUR		MONEY,
	WinlossRBEUR		MONEY,
	AmtDueToBAEUR	MONEY,   
	AmtDueToRBEUR	MONEY,
	CommBAEUR			MONEY,   
	CommRBEUR		MONEY,
	PlayerCommEUR  MONEY,	
	CompanyEUR		MONEY,
	--GBP
	TurnOverGBP		MONEY,   	
	WinlostGBP			MONEY,  
	LicenseeWLGBP		MONEY,
	WinlossRBGBP		MONEY,
	AmtDueToBAGBP	MONEY,   
	AmtDueToRBGBP	MONEY,
	CommBAGBP			MONEY,   
	CommRBGBP		MONEY,
	PlayerCommGBP  MONEY,	
	CompanyGBP		MONEY,
	
	Betcount		BIGINT
)  


DECLARE @tempAg	TABLE( custID INT PRIMARY KEY, Currency INT)  
DECLARE @Code VARCHAR(20), @TempCurrencyID INT
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
SELECT TOP 1 @TempCurrencyID=currency FROM @tempAg 

IF @TempCurrencyID=51
	SELECT @Code = currency FROM exchange (nolock) WHERE ExchangeId = 51
ELSE
	SELECT @Code = code FROM exchange (nolock) WHERE exchangeid=@TempCurrencyID

INSERT INTO @tempAg (custID,currency) 
SELECT DISTINCT custID,currency FROM bodb_Licensee.dbo.f_SelLicenseeCust(@LicenseeID )--LicenseeCust (NOLOCK) 
WHERE 
	--LicenseeID = @LicenseeID AND
	 (@CustID=0 OR (@CustID<>0 AND CustiD=@CustID))
	AND (@Currency = 0 OR (@Currency<> 0 AND Currency=@Currency))
	AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	

DECLARE @site VARCHAR(50)
SELECT @site=LicenseeName FROM bodb_licensee.dbo.Licensees (NOLOCK) 
WHERE LicenseeID=@LicenseeID

DECLARE @Super AS TABLE (custid int , currency int)
INSERT INTO @Super(custid,currency)  
SELECT DISTINCT CustID,currency FROM bodb_Licensee.dbo.f_SelDepCustSuper(@site)--Dep_CustSuper WITH (NOLOCK)  
--WHERE  site = @site

DECLARE @Exchange TABLE(ExchangeDate SMALLDATETIME, ExchangeId INT, USD FLOAT, EUR FLOAT,MYR FLOAT,GBP FLOAT,Code VARCHAR(10), PRIMARY KEY(ExchangeDate,ExchangeId))

IF @ShowSB = 1  
BEGIN  
	INSERT  INTO @sporttype( sporttype)
    VALUES  (0)	
END  

IF @ShowRB = 1  
BEGIN  
	INSERT  INTO @sporttype( Sporttype)
    VALUES  (151)
    
    INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
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
    
INSERT INTO @Exchange (exchangedate,exchangeid,usd,eur,myr,GBP,code)
SELECT exchangedate,exchangeid,usd,eur,myr,GBP,code
FROM Lrf_f_GetExchangeDaily (@FDate,@TDate)
WHERE exchangeid IN (SELECT Currency FROM @TempAg)	    
    
IF @TDate > @MoveBetsDay
BEGIN
	IF @FDate <= @MoveBetsDay 
		SET @TempFromDate =  dateadd(day,1,@MoveBetsDay)
	ELSE
		SET @TempFromDate = @FDate
		
	IF @ShowBA = 1
	BEGIN
		INSERT INTO #SAgWinLoss 
		SELECT   
			b.custid,
			b.currency, 
			
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover,
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			0 as LicenseeWL,
			0 as WinlossRB,
			- SUM (b.winlost - b.actual_stake + awinlost + comm ) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm) AS CommBA,
			0 AS CommRB,
			SUM( PlayerComm  ) AS PlayerComm,
			0 AS Company,
			
			--MYR
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.MYR
			) turnoverMYR,
			SUM((b.winlost - b.actual_stake)* e.MYR) AS WinlostMYR,  
			0 as LicenseeWLMYR,
			0 as WinlossRBMYR,
			- SUM ((b.winlost - b.actual_stake + awinlost + comm )* e.MYR) as AmountDueToBAMYR,
			0 as AmountDueToRBMYR,
			SUM (comm * e.MYR) AS CommBAMYR,
			0 AS CommRBMYR,
			SUM( PlayerComm * e.MYR  ) AS PlayerCommMYR,
			0 AS CompanyMYR,
			
			--USD
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.USD
			) turnoverUSD,
			SUM((b.winlost - b.actual_stake)* e.USD) AS WinlostUSD,  
			0 as LicenseeWLUSD,
			0 as WinlossRBUSD,
			- SUM ((b.winlost - b.actual_stake + awinlost + comm )* e.USD) as AmountDueToBAUSD,
			0 as AmountDueToRBUSD,
			SUM (comm * e.USD) AS CommBAUSD,
			0 AS CommRBUSD,
			SUM( PlayerComm * e.USD  ) AS PlayerCommUSD,
			0 AS CompanyUSD,
			
			--EUR
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.EUR
			) turnoverEUR,
			SUM((b.winlost - b.actual_stake)* e.EUR) AS WinlostEUR,  
			0 as LicenseeWLEUR,
			0 as WinlossRBEUR,
			- SUM ((b.winlost - b.actual_stake + awinlost + comm )* e.EUR) as AmountDueToBAEUR,
			0 as AmountDueToRBEUR,
			SUM (comm * e.EUR) AS CommBAEUR,
			0 AS CommRBEUR,
			SUM( PlayerComm * e.EUR  ) AS PlayerCommEUR,
			0 AS CompanyEUR,
			--GBP
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.GBP
			) turnoverGBP,
			SUM((b.winlost - b.actual_stake)* e.GBP) AS WinlostGBP,  
			0 as LicenseeWLGBP,
			0 as WinlossRBGBP,
			- SUM ((b.winlost - b.actual_stake + awinlost + comm )* e.GBP) as AmountDueToBAGBP,
			0 as AmountDueToRBGBP,
			SUM (comm * e.GBP) AS CommBAGBP,
			0 AS CommRBGBP,
			SUM( PlayerComm * e.GBP  ) AS PlayerCommGBP,
			0 AS CompanyGBP,
			
			COUNT(b.transid) 
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
			   BetCount
		FROM 
			dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)    
			INNER JOIN @TempAg tma ON tma.CustID=b.recommend AND tma.Currency=b.currency
			INNER JOIN @Super s ON b.srecommend = s.custid AND s.Currency=b.currency
			INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid=BA.srecommend and b.transid = BA.transid 	 
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID IN (111, 112, 113) AND
			b.bettype NOT IN (901,902,903)
		GROUP BY   
			b.currency,b.custid , b.statusID
	END		

	IF @ShowSB=1
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT   
			b.custid,
			s.currency, 
			
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover,
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			- SUM(b.winlost - b.actual_stake) AS LicenseeWL,
			0 AS WinlossRB,
			0 as AmountDueToBA,
			0 as AmountDueToRB,
			0 AS CommBA,
			0 AS CommRB,
			SUM( b.playercomm ) AS PlayerComm, 
			- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company  ,
			
			--MYR
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.MYR
			) turnoverMYR,
			SUM((b.winlost - b.actual_stake)* e.MYR) AS WinlostMYR,  
			- SUM((b.winlost - b.actual_stake)* e.MYR) AS LicenseeWLMYR,
			0 AS WinlossRBMYR,
			0 as AmountDueToBAMYR,
			0 as AmountDueToRBMYR,
			0 AS CommBAMYR,
			0 AS CommRBMYR,
			SUM( b.playercomm * e.MYR ) AS PlayerCommMYR, 
			- SUM((b.awinlost + b.winlost - b.actual_stake + b.comm)*e.MYR) CompanyMYR  ,
			
			--USD
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.USD
			) turnoverUSD,
			SUM((b.winlost - b.actual_stake)* e.USD) AS WinlostUSD,  
			- SUM((b.winlost - b.actual_stake)* e.USD) AS LicenseeWLUSD,
			0 AS WinlossRBUSD,
			0 as AmountDueToBAUSD,
			0 as AmountDueToRBUSD,
			0 AS CommBAUSD,
			0 AS CommRBUSD,
			SUM( b.playercomm * e.USD ) AS PlayerCommUSD, 
			- SUM((b.awinlost + b.winlost - b.actual_stake + b.comm)*e.USD) CompanyUSD  ,
			
			--EUR
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.EUR
			) turnoverEUR,
			SUM((b.winlost - b.actual_stake)* e.EUR) AS WinlostEUR,  
			- SUM((b.winlost - b.actual_stake)* e.EUR) AS LicenseeWLEUR,
			0 AS WinlossRBEUR,
			0 as AmountDueToBAEUR,
			0 as AmountDueToRBEUR,
			0 AS CommBAEUR,
			0 AS CommRBEUR,
			SUM( b.playercomm * e.EUR ) AS PlayerCommEUR, 
			- SUM((b.awinlost + b.winlost - b.actual_stake + b.comm)*e.EUR) CompanyEUR  ,
			
			--GBP
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.GBP
			) turnoverGBP,
			SUM((b.winlost - b.actual_stake)* e.GBP) AS WinlostGBP,  
			- SUM((b.winlost - b.actual_stake)* e.GBP) AS LicenseeWLGBP,
			0 AS WinlossRBGBP,
			0 as AmountDueToBAGBP,
			0 as AmountDueToRBGBP,
			0 AS CommBAGBP,
			0 AS CommRBGBP,
			SUM( b.playercomm * e.GBP ) AS PlayerCommGBP, 
			- SUM((b.awinlost + b.winlost - b.actual_stake + b.comm)*e.GBP) CompanyGBP  ,
			
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
			   BetCount
		FROM 
			dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend )  
			INNER JOIN @Super s ON b.srecommend = s.custid AND s.currency=b.currency
			INNER JOIN @TempAg a ON b.recommend = a.custid AND a.Currency=b.currency
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID  IN (111, 112, 113) AND
			(b.bettype<31 OR (b.bettype BETWEEN 121 AND 999) OR (b.bettype BETWEEN 1301 AND 1399)) AND
			b.tpositiontaking <> 0 AND
			b.bettype NOT IN (901,902,903)
			
		GROUP BY   
			s.currency,b.custid,b.statusID
	END

	IF (@ShowNG=1 OR @ShowLC=1 OR @ShowVS = 1 OR @ShowRB = 1 OR @ShowCS=1 OR @showKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT   
			b.custid,
			s.currency, 
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover,
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END ) AS LicenseeWL,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END) as AmountDueToRB,
			0 AS CommBA,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END) AS CommRB,
			SUM( b.playercomm ) AS PlayerComm, 
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END) Company  ,
			
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.MYR
			) turnoverMYR,
			SUM((b.winlost - b.actual_stake) * e.MYR) AS WinlostMYR,  
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END * e.MYR ) AS LicenseeWLMYR,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END * e.MYR) AS WinlossRBMYR,
			0 as AmountDueToBAMYR,
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END * e.MYR) as AmountDueToRBMYR,
			0 AS CommBAMYR,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END * e.MYR) AS CommRBMYR,
			SUM( b.playercomm * e.MYR ) AS PlayerCommMYR, 
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END * e.MYR) CompanyMYR  ,
			
			--USD
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.USD
			) turnoverUSD,
			SUM((b.winlost - b.actual_stake) * e.USD) AS WinlostUSD,  
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END * e.USD ) AS LicenseeWLUSD,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END * e.USD) AS WinlossRBUSD,
			0 as AmountDueToBAUSD,
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END * e.USD) as AmountDueToRBUSD,
			0 AS CommBAUSD,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END * e.USD) AS CommRBUSD,
			SUM( b.playercomm * e.USD ) AS PlayerCommUSD, 
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END * e.USD) CompanyUSD  ,
			
			--EUR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.EUR
			) turnoverEUR,
			SUM((b.winlost - b.actual_stake) * e.EUR) AS WinlostEUR,  
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END * e.EUR ) AS LicenseeWLEUR,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END * e.EUR) AS WinlossRBEUR,
			0 as AmountDueToBAEUR,
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END * e.EUR) as AmountDueToRBEUR,
			0 AS CommBAEUR,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END * e.EUR) AS CommRBEUR,
			SUM( b.playercomm * e.EUR ) AS PlayerCommEUR, 
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END * e.EUR) CompanyEUR  ,
			
			--GBP
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
				* e.GBP
			) turnoverGBP,
			SUM((b.winlost - b.actual_stake) * e.GBP) AS WinlostGBP,  
			SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN  -1 *(b.winlost - b.actual_stake) ELSE   0 END * e.GBP ) AS LicenseeWLGBP,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END * e.GBP) AS WinlossRBGBP,
			0 as AmountDueToBAGBP,
			- SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.winlost - b.actual_stake + awinlost + comm ELSE 0 END * e.GBP) as AmountDueToRBGBP,
			0 AS CommBAGBP,
			SUM (CASE WHEN b.bettype BETWEEN 31 AND 33 THEN comm ELSE 0 END * e.GBP) AS CommRBGBP,
			SUM( b.playercomm * e.GBP ) AS PlayerCommGBP, 
			- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.awinlost + b.winlost - b.actual_stake + b.comm ELSE 0 END * e.GBP) CompanyGBP  ,
			
			
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
			   BetCount
		FROM 
			dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend )  
			INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency=s.currency
			INNER JOIN @TempAg a ON b.recommend = a.custid AND a.Currency=b.currency
			INNER JOIN @bettype bt ON b.bettype = bt.bettype
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID  IN (111, 112, 113)
			
		GROUP BY   
			s.currency,b.custid,b.statusID
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
			b.custid,
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
			- SUM (b.winlost+b.awinlost+b.comm) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm ) AS CommBA,
			0 AS CommRB,
			SUM(b.playercomm ) AS PlayerComm, 
			0 AS Company,
			
			--MYR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.MYR	
			),     
			SUM(b.winlost * e.MYR),  
			0 as LicenseeWLMYR,
			0 AS WinlossRBMYR,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.MYR) as AmountDueToBAMYR,
			0 as AmountDueToRBMYR,
			SUM (comm * e.MYR) AS CommBAMYR,
			0 AS CommRBMYR,
			SUM(b.playercomm * e.MYR ) AS PlayerCommMYR, 
			0 AS CompanyMYR,
			
			--USD
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.USD	
			),     
			SUM(b.winlost * e.USD),  
			0 as LicenseeWLUSD,
			0 AS WinlossRBUSD,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.USD) as AmountDueToBAUSD,
			0 as AmountDueToRBUSD,
			SUM (comm * e.USD) AS CommBAUSD,
			0 AS CommRBUSD,
			SUM(b.playercomm * e.USD ) AS PlayerCommUSD, 
			0 AS CompanyUSD,
			
			--EUR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.EUR	
			),     
			SUM(b.winlost * e.EUR),  
			0 as LicenseeWLEUR,
			0 AS WinlossRBEUR,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.EUR) as AmountDueToBAEUR,
			0 as AmountDueToRBEUR,
			SUM (comm * e.EUR) AS CommBAEUR,
			0 AS CommRBEUR,
			SUM(b.playercomm * e.EUR ) AS PlayerCommEUR, 
			0 AS CompanyEUR,
			--GBP
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.GBP	
			),     
			SUM(b.winlost * e.GBP),  
			0 as LicenseeWLGBP,
			0 AS WinlossRBGBP,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.GBP) as AmountDueToBAGBP,
			0 as AmountDueToRBGBP,
			SUM (comm * e.GBP) AS CommBAGBP,
			0 AS CommRBGBP,
			SUM(b.playercomm * e.GBP ) AS PlayerCommGBP, 
			0 AS CompanyGBP,
			
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
		FROM bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK  )  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND ag.Currency=b.Currency
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 1
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 1
			AND b.bettype NOT IN (901,902,903)
		GROUP BY  b.currency,b.custid,  b.statusID
	END
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC=1  OR @ShowVS=1 OR @ShowCS=1 OR @ShowKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)
	BEGIN
		INSERT INTO #SAgWinLoss 
		SELECT 
			b.custid,
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
			0 as AmountDueToBA,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) as AmountDueToRB,
			0 AS CommBA,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END) AS CommRB,
			SUM( b.playercomm ) AS PlayerComm,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END)  as Company   ,
			
			--MYR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.MYR	
			),     
			SUM(b.winlost * e.MYR),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.MYR) AS LicenseeWLMYR ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.MYR) AS WinlossRBMYR,
			0 as AmountDueToBAMYR,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.MYR) as AmountDueToRBMYR,
			0 AS CommBAMYR,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.MYR) AS CommRBMYR,
			SUM( b.playercomm * e.MYR) AS PlayerCommMYR,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.MYR)  as CompanyMYR   ,
			
			--USD
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.USD	
			),     
			SUM(b.winlost * e.USD),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.USD) AS LicenseeWLUSD ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.USD) AS WinlossRBUSD,
			0 as AmountDueToBAUSD,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.USD) as AmountDueToRBUSD,
			0 AS CommBAUSD,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.USD) AS CommRBUSD,
			SUM( b.playercomm * e.USD) AS PlayerCommUSD,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.USD)  as CompanyUSD   ,
			
			--EUR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.EUR	
			),     
			SUM(b.winlost * e.EUR),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.EUR) AS LicenseeWLEUR ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.EUR) AS WinlossRBEUR,
			0 as AmountDueToBAEUR,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.EUR) as AmountDueToRBEUR,
			0 AS CommBAEUR,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.EUR) AS CommRBEUR,
			SUM( b.playercomm * e.EUR) AS PlayerCommEUR,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.EUR)  as CompanyEUR   ,
			
			--GBP
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.GBP	
			),     
			SUM(b.winlost * e.GBP),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.GBP) AS LicenseeWLGBP ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.GBP) AS WinlossRBGBP,
			0 as AmountDueToBAGBP,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.GBP) as AmountDueToRBGBP,
			0 AS CommBAGBP,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.GBP) AS CommRBGBP,
			SUM( b.playercomm * e.GBP) AS PlayerCommGBP,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.GBP)  as CompanyGBP   ,
			
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
		FROM bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK  )  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND ag.Currency=b.Currency
			INNER JOIN @sporttype t ON b.sporttype = t.sporttype
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 1
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 0
			AND b.bettype NOT IN (901,902,903)
		GROUP BY  b.currency,b.custid,b.statusID
	END
	
			
 END 
 IF @IsOld = 1 
 BEGIN
	SELECT @MaxOldDate = MAX(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (nolock)
	IF @TDate >= @MaxOldDate
			SET @TempToDate = @MaxOldDate
		ELSE
			SET  @TempToDate = @TDate
 
	IF @ShowBA = 1
	BEGIN
		INSERT INTO #SAgWinLoss 
		SELECT 
			b.custid,
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
			- SUM (b.winlost+b.awinlost+b.comm) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm ) AS CommBA,
			0 AS CommRB,
			SUM(b.playercomm ) AS PlayerComm, 
			0 AS Company,
			
			--MYR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.MYR	
			),     
			SUM(b.winlost * e.MYR),  
			0 as LicenseeWLMYR,
			0 AS WinlossRBMYR,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.MYR) as AmountDueToBAMYR,
			0 as AmountDueToRBMYR,
			SUM (comm * e.MYR) AS CommBAMYR,
			0 AS CommRBMYR,
			SUM(b.playercomm * e.MYR ) AS PlayerCommMYR, 
			0 AS CompanyMYR,
			
			--USD
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.USD	
			),     
			SUM(b.winlost * e.USD),  
			0 as LicenseeWLUSD,
			0 AS WinlossRBUSD,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.USD) as AmountDueToBAUSD,
			0 as AmountDueToRBUSD,
			SUM (comm * e.USD) AS CommBAUSD,
			0 AS CommRBUSD,
			SUM(b.playercomm * e.USD ) AS PlayerCommUSD, 
			0 AS CompanyUSD,
			
			--EUR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.EUR	
			),     
			SUM(b.winlost * e.EUR),  
			0 as LicenseeWLEUR,
			0 AS WinlossRBEUR,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.EUR) as AmountDueToBAEUR,
			0 as AmountDueToRBEUR,
			SUM (comm * e.EUR) AS CommBAEUR,
			0 AS CommRBEUR,
			SUM(b.playercomm * e.EUR ) AS PlayerCommEUR, 
			0 AS CompanyEUR,
			
			--GBP
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.GBP	
			),     
			SUM(b.winlost * e.GBP),  
			0 as LicenseeWLGBP,
			0 AS WinlossRBGBP,
			- SUM ((b.winlost+b.awinlost+b.comm) * e.GBP) as AmountDueToBAGBP,
			0 as AmountDueToRBGBP,
			SUM (comm * e.GBP) AS CommBAGBP,
			0 AS CommRBGBP,
			SUM(b.playercomm * e.GBP ) AS PlayerCommGBP, 
			0 AS CompanyGBP,
			
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
		FROM bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK)  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND ag.Currency=b.Currency
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 1   
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 1
			AND b.bettype NOT IN (901,902,903)
		GROUP BY  b.currency,b.custid,b.statusID
	END
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC=1 OR @ShowVS=1 OR @ShowCS=1 OR @ShowKN=1 OR @showMGCLC =1 OR @showMGCRnG =1)
	BEGIN
		INSERT INTO #SAgWinLoss 
		SELECT 
			b.custid,
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
			0 as AmountDueToBA,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) as AmountDueToRB,
			0 AS CommBA,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END) AS CommRB,
			SUM( b.playercomm ) AS PlayerComm,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END)  as Company   ,
			
			--MYR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.MYR	
			),     
			SUM(b.winlost * e.MYR),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.MYR) AS LicenseeWLMYR ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.MYR) AS WinlossRBMYR,
			0 as AmountDueToBAMYR,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.MYR) as AmountDueToRBMYR,
			0 AS CommBAMYR,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.MYR) AS CommRBMYR,
			SUM( b.playercomm * e.MYR) AS PlayerCommMYR,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.MYR)  as CompanyMYR   ,
			
			--USD
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.USD	
			),     
			SUM(b.winlost * e.USD),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.USD) AS LicenseeWLUSD ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.USD) AS WinlossRBUSD,
			0 as AmountDueToBAUSD,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.USD) as AmountDueToRBUSD,
			0 AS CommBAUSD,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.USD) AS CommRBUSD,
			SUM( b.playercomm * e.USD) AS PlayerCommUSD,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.USD)  as CompanyUSD   ,
			
			--EUR
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.EUR	
			),     
			SUM(b.winlost * e.EUR),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.EUR) AS LicenseeWLEUR ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.EUR) AS WinlossRBEUR,
			0 as AmountDueToBAEUR,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.EUR) as AmountDueToRBEUR,
			0 AS CommBAEUR,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.EUR) AS CommRBEUR,
			SUM( b.playercomm * e.EUR) AS PlayerCommEUR,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.EUR)  as CompanyEUR   ,
			--GBP
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			* e.GBP	
			),     
			SUM(b.winlost * e.GBP),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180,251,202,203,205))  THEN b.winlost ELSE 0 END * e.GBP) AS LicenseeWLGBP ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END * e.GBP) AS WinlossRBGBP,
			0 as AmountDueToBAGBP,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END * e.GBP) as AmountDueToRBGBP,
			0 AS CommBAGBP,
			SUM ( CASE WHEN b.sporttype = 151 THEN comm   ELSE 0 END * e.GBP) AS CommRBGBP,
			SUM( b.playercomm * e.GBP) AS PlayerCommGBP,
			- SUM(CASE WHEN b.sporttype <> 151 THEN b.awinlost + b.winlost + b.comm ELSE 0 END * e.GBP)  as CompanyGBP   ,
			
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
		
		FROM bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK )  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND ag.Currency=b.Currency
			INNER JOIN @sporttype t ON b.sporttype = t.sporttype
			LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 1   
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 0
			AND b.bettype NOT IN (901,902,903)
		GROUP BY  b.currency, b.custid,b.statusID
	END
	
 END
 --
	DECLARE @Recommend VARCHAR(8000) = '', @SQL VARCHAR(8000) = ''
	CREATE TABLE #DataWinloss3rd (CustId INT, Recommend	INT, Winlostdate DATETIME, SportType INT, Currency INT, TurnOver MONEY, TotalTrans INT, Winloss MONEY)		
	DECLARE @TempSMAG AS TABLE( LicenseeeID INT,SuperId INT, MasterId INT, CustId INT, CurrencyId INT)

	--get licensee recommend				
	INSERT INTO @TempSMAG(LicenseeeID, SuperId, MasterId, CustId, CurrencyId)
	SELECT DISTINCT LicenseeID, ci.srecommend, ci.mrecommend, lc.CustID, lc.Currency
	FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID) lc
		INNER JOIN dbo.custInfo ci WITH (NOLOCK) ON lc.CustID = ci.recommend
	WHERE (@Currency = 0 OR (@Currency <> 0 AND lc.Currency = @Currency))
		AND lc.Currency <> 20
		AND (@CustId = 0 OR (@CustId <> 0 AND ci.recommend = @CustId))
	SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ',' 
	FROM @TempSMAG 
	--truncate comma
	SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))

	IF @ShowAGC = 1 -- AG Casino
		BEGIN						
			SET @SQL =
					'SELECT CustId, Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss
					FROM OPENQUERY(DBACC, ''SELECT ag.Custid
											 , Winlostdate
											 , SportType
											 , ag.Currency
											 , TurnOver - CASE WHEN '+ CAST(@DrawFilter AS varchar) +' IN (1,2) THEN DrawTO ELSE 0 END AS TurnOver
											 , BetCount - CASE WHEN '+ CAST(@DrawFilter AS varchar) +' IN (1) THEN DrawBetCount ELSE 0 END AS TotalTrans
											 , Winlost AS Winloss
											 , c.recommend
											FROM bodb_report.dbo.rptDepWinlost_AGCasino ag WITH (NOLOCK)
												INNER JOIN bodb02.dbo.custInfo c WITH (NOLOCK) ON ag.Custid = c.custid
											WHERE Winlostdate BETWEEN '''''+ CONVERT( VARCHAR(10),@FromDate, 120) +''''' AND '''''+ CONVERT( VARCHAR(10),@FromDate, 120) +'''''
												AND c.recommend IN ('+ ISNULL(@recommend, 0) +')
									'')'
													
			INSERT INTO #DataWinloss3rd(CustId, Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss)
			EXECUTE (@SQL)

			INSERT INTO #SAgWinLoss(CustID, Currency
								, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, PlayerComm, Company
								, TurnOverMYR, WinlostMYR, LicenseeWLMYR, WinlossRBMYR, AmtDueToBAMYR, AmtDueToRBMYR, CommBAMYR, CommRBMYR, PlayerCommMYR, CompanyMYR
								, TurnOverUSD, WinlostUSD, LicenseeWLUSD, WinlossRBUSD, AmtDueToBAUSD, AmtDueToRBUSD, CommBAUSD, CommRBUSD, PlayerCommUSD, CompanyUSD
								, TurnOverEUR, WinlostEUR, LicenseeWLEUR, WinlossRBEUR, AmtDueToBAEUR, AmtDueToRBEUR, CommBAEUR, CommRBEUR, PlayerCommEUR, CompanyEUR
								, TurnOverGBP, WinlostGBP, LicenseeWLGBP, WinlossRBGBP, AmtDueToBAGBP, AmtDueToRBGBP, CommBAGBP, CommRBGBP, PlayerCommGBP, CompanyGBP
								, Betcount)
			(
				SELECT b.CustId
					, CurrencyID						AS Currency 
					--original
					, SUM(Turnover)						AS Turnover
					, SUM(WinLoss)						AS Winlost			
					, - SUM(Winloss)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate)			AS Company
					--MYR
					, SUM(Turnover * e.MYR)						AS Turnover
					, SUM(WinLoss * e.MYR)						AS Winlost			
					, - SUM(Winloss * e.MYR)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.MYR)			AS Company
					--USD
					, SUM(Turnover * e.USD)						AS Turnover
					, SUM(WinLoss * e.USD)						AS Winlost			
					, - SUM(Winloss * e.USD)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.USD)			AS Company
					--EUR
					, SUM(Turnover * e.EUR)						AS Turnover
					, SUM(WinLoss * e.EUR)						AS Winlost			
					, - SUM(Winloss * e.EUR)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.EUR)			AS Company 

					--GBP
					, SUM(Turnover * e.GBP)						AS Turnover
					, SUM(WinLoss * e.GBP)						AS Winlost			
					, - SUM(Winloss * e.GBP)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.GBP)			AS Company 

					, SUM(b.TotalTrans)					AS BetCount	  	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempSMAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId AND p.ProductID = 10
					LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.CustId, CurrencyID 
			)			
		END
	IF @ShowGD = 1 -- GD
	BEGIN
		-- reset 
		DELETE #DataWinloss3rd		

		INSERT INTO #DataWinloss3rd(CustId, Recommend, Winlostdate, Currency, TurnOver, TotalTrans, Winloss)
		SELECT c.Custid
				, co.recommend			AS Recommend	
				, c.Winlostdate			AS Winlostdate
				, c.Currency			
				, SUM(c.TurnOver - 
						CASE WHEN @DrawFilter IN (2, 3) 
								THEN c.DrawTO 
							ELSE 0 
						END)			AS TurnOver
				, SUM(c.BetCount - 
						CASE WHEN @DrawFilter = 2
										THEN c.DrawBetCount
									ELSE 0 
								END)	AS TotalTrans
				, SUM(c.Winlost)		AS Winloss
			FROM bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty c WITH (NOLOCK)
				INNER JOIN dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
				INNER JOIN @TempSMAG ag ON co.recommend = ag.CustId
			WHERE c.Winlostdate BETWEEN @FromDate AND @Todate				
				AND (c.ProductId IN (SELECT ProductID FROM bodb_licensee.dbo.LRF_f_Products3rd(@ProductList)))
			GROUP BY c.Custid, co.recommend, c.Winlostdate, c.Currency	
			
		INSERT INTO #SAgWinLoss(CustID, Currency
								, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, PlayerComm, Company
								, TurnOverMYR, WinlostMYR, LicenseeWLMYR, WinlossRBMYR, AmtDueToBAMYR, AmtDueToRBMYR, CommBAMYR, CommRBMYR, PlayerCommMYR, CompanyMYR
								, TurnOverUSD, WinlostUSD, LicenseeWLUSD, WinlossRBUSD, AmtDueToBAUSD, AmtDueToRBUSD, CommBAUSD, CommRBUSD, PlayerCommUSD, CompanyUSD
								, TurnOverEUR, WinlostEUR, LicenseeWLEUR, WinlossRBEUR, AmtDueToBAEUR, AmtDueToRBEUR, CommBAEUR, CommRBEUR, PlayerCommEUR, CompanyEUR
								, TurnOverGBP, WinlostGBP, LicenseeWLGBP, WinlossRBGBP, AmtDueToBAGBP, AmtDueToRBGBP, CommBAGBP, CommRBGBP, PlayerCommGBP, CompanyGBP
								, Betcount)
			(
				SELECT b.CustId
					, CurrencyID						AS Currency 
					--original
					, SUM(Turnover)						AS Turnover
					, SUM(WinLoss)						AS Winlost			
					, - SUM(Winloss)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate)			AS Company
					--MYR
					, SUM(Turnover * e.MYR)						AS Turnover
					, SUM(WinLoss * e.MYR)						AS Winlost			
					, - SUM(Winloss * e.MYR)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.MYR)			AS Company
					--USD
					, SUM(Turnover * e.USD)						AS Turnover
					, SUM(WinLoss * e.USD)						AS Winlost			
					, - SUM(Winloss * e.USD)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.USD)			AS Company
					--EUR
					, SUM(Turnover * e.EUR)						AS Turnover
					, SUM(WinLoss * e.EUR)						AS Winlost			
					, - SUM(Winloss * e.EUR)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.EUR)			AS Company 

					--GBP
					, SUM(Turnover * e.GBP)						AS Turnover
					, SUM(WinLoss * e.GBP)						AS Winlost			
					, - SUM(Winloss * e.GBP)	AS LicenseeWL				
					, 0									AS WinlossRB
					, 0									AS AmtDueToBA
					, 0									AS AmtDueToRB
					, 0									AS CommBA
					, 0									AS CommRB
					, 0									AS PlayerComm
					, - SUM(WinLoss * p.Rate * e.GBP)			AS Company 

					, SUM(b.TotalTrans)					AS BetCount	  	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempSMAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId AND p.ProductID = 11
					LEFT JOIN @Exchange e  ON e.ExchangeDate = b.winlostdate AND e.exchangeid = b.currency
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.CustId, CurrencyID
			)			
	END
 SELECT 
	c.username,  
	SUBSTRING(c.username2, CHARINDEX('$', c.username2) + 1,LEN(c.username2) - CHARINDEX('$',c.username2)) AS nickname,
	w.custid, 
	w.currency,
	@Code AS CurrencyName,
	SUM(TurnOver)	AS Turnover,   
	SUM(Winlost)		AS Winlost,  
	SUM(LicenseeWL) AS LicenseeWL,
	SUM(WinlossRB)	AS WinlossRB,
	SUM(CommBA) AS CommBA,
	SUM(CommRB) AS CommRB,
	SUM(PlayerComm) AS PlayerComm, 
	SUM(AmtDuetoBA) AS AmtDuetoBA,
	SUM(AmtDuetoRB) AS AmtDuetoRB,
	SUM(Company) AS Company,
	SUM(Betcount)	AS Betcount,
	--BaseRM  
	CAST(SUM(TurnOverMYR) AS MONEY)	AS TurnoverMYR,   
	CAST(SUM(WinlostMYR) AS MONEY)	AS WinlostMYR,  
	CAST(SUM(LicenseeWLMYR) AS MONEY) AS LicenseeWLMYR,
	CAST(SUM(WinlossRBMYR) AS MONEY)	AS WinlossRBMYR,
	CAST(SUM(CommBAMYR) AS MONEY) AS CommBAMYR,
	CAST(SUM(CommRBMYR) AS MONEY) AS CommRBMYR,
	CAST(SUM(PlayerCommMYR) AS MONEY) AS PlayerCommMYR,
	CAST(SUM(AmtDuetoBAMYR) AS MONEY) AS AmtDuetoBAMYR,
	CAST(SUM(AmtDuetoRBMYR) AS MONEY) AS AmtDuetoRBMYR,
	CAST(SUM(CompanyMYR) AS MONEY) AS CompanyMYR,
	--BaseUSD   
	CAST(SUM(TurnOverUSD) AS MONEY)	AS TurnoverUSD,   
	CAST(SUM(WinlostUSD) AS MONEY)	AS WinlostUSD,  
	CAST(SUM(LicenseeWLUSD) AS MONEY) AS LicenseeWLUSD,
	CAST(SUM(WinlossRBUSD) AS MONEY)	AS WinlossRBUSD,
	CAST(SUM(CommBAUSD) AS MONEY) AS CommBAUSD,
	CAST(SUM(CommRBUSD) AS MONEY) AS CommRBUSD,
	CAST(SUM(PlayerCommUSD) AS MONEY) AS PlayerCommUSD,
	CAST(SUM(AmtDuetoBAUSD) AS MONEY) AS AmtDuetoBAUSD,
	CAST(SUM(AmtDuetoRBUSD) AS MONEY) AS AmtDuetoRBUSD,
	CAST(SUM(CompanyUSD) AS MONEY) AS CompanyUSD,
	--BaseEUR  
	CAST(SUM(TurnOverEUR) AS MONEY)	AS TurnoverEUR,   
	CAST(SUM(WinlostEUR) AS MONEY)	AS WinlostEUR,  
	CAST(SUM(LicenseeWLEUR) AS MONEY) AS LicenseeWLEUR,
	CAST(SUM(WinlossRBEUR) AS MONEY)	AS WinlossRBEUR,
	CAST(SUM(CommBAEUR) AS MONEY) AS CommBAEUR,
	CAST(SUM(CommRBEUR) AS MONEY) AS CommRBEUR,
	CAST(SUM(PlayerCommEUR) AS MONEY) AS PlayerCommEUR,
	CAST(SUM(AmtDuetoBAEUR) AS MONEY) AS AmtDuetoBAEUR,
	CAST(SUM(AmtDuetoRBEUR) AS MONEY) AS AmtDuetoRBEUR,
	CAST(SUM(CompanyEUR) AS MONEY) AS CompanyEUR,
	--BaseGBP  
	CAST(SUM(TurnOverGBP) AS MONEY)	AS TurnoverGBP,   
	CAST(SUM(WinlostGBP) AS MONEY)	AS WinlostGBP,  
	CAST(SUM(LicenseeWLGBP) AS MONEY) AS LicenseeWLGBP,
	CAST(SUM(WinlossRBGBP) AS MONEY)	AS WinlossRBGBP,
	CAST(SUM(CommBAGBP) AS MONEY) AS CommBAGBP,
	CAST(SUM(CommRBGBP) AS MONEY) AS CommRBGBP,
	CAST(SUM(PlayerCommGBP) AS MONEY) AS PlayerCommGBP,
	CAST(SUM(AmtDuetoBAGBP) AS MONEY) AS AmtDuetoBAGBP,
	CAST(SUM(AmtDuetoRBGBP) AS MONEY) AS AmtDuetoRBGBP,
	CAST(SUM(CompanyGBP) AS MONEY) AS CompanyGBP
	      
	FROM	#SAgWinLoss w   
	INNER JOIN Customer c WITH (NOLOCK) ON w.custid = c.custid
	
	GROUP BY w.currency,w.custid, c.username,c.username2
	ORDER BY c.username
  
DROP TABLE #SAgWinLoss 
DROP TABLE #DataWinloss3rd
END


GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_LicWinlossDetail2] TO [bodbAdminNet] AS [dbo]
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_LicWinlossDetail2] TO [bodbLicenseeNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicWinlossDetail2] TO [vnteam] AS [dbo]
GO
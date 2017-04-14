SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_Letstalk_DCWL    Script Date: 2/3/2017 2:21:16 PM ******/

/****** Object:  Stored Procedure dbo.Acc_Rpt_Letstalk_DCWL    Script Date: 11/8/2016 3:28:07 PM ******/

CREATE PROCEDURE [dbo].[Acc_Rpt_Letstalk_DCWL]
	@WinlostDate	DATETIME

AS
/*
	Created: 20161107@Sophia
	Task :	Letstalk Report - DCWL - Daily Report [Redmine: #66828]
	DB:		DBACC/bodb02
	Original: Acc_Rpt_NonSportsProductStatistics_Daily
	Revisions:
	
		- 20170203@Sophia: Remove SLI Live Casino. Now show only for RNG Casino  [Redmine: #71013]

	Param's Explanation:
			 - @username:  + Search by keyword, member only
			 - @Site: List of Company filter
				'ALL': All sites (MBC + Licensees)
				'MBC': MBC sites only
				'12bet' : Specific Licensee Name 
			 - @ProductID: string filter by Product 
			 - @BetType: string filter by bettype
			 - @LeagueId: string filter by LeagueId (ProductID = 3 - Number Game get LeagueId)  
			 - @Sporttype: string filter by Sporttype (ProductID = 5 - Virtual Sports get Sporttype)
			 - @GameTableId: filter by specific game table (ProductID = 4 - Live Casino get leagueID)
			 - @currency: 
				-1: All and convert to RM
				 0: All without convert (original)
				>0: Filter by currency ID without convert (original)  
			 - @TotalBetType : 
				 1 : is >=
				-1 : is <=
			 - @TotalBetValue : Value to compare with @TotalBetType
			 - @HousePTType : 
				 1 : is >=
				-1 : is <=
			 - @HousePTValue : Value to compare with @HousePTType
			 - @IsDrillDown: If click on Grand Total or on the Grid of column Currency
				
	Query exam: 

exec Acc_Rpt_NonSportsProductStatistics_Daily @TotalBetValue=0.0000,@IsDrillDown=0,@Sporttype='',@ProductId='4,6',
@Username='',@BetType='1103,1104,1101,1102,2201,2203,2202,2204,2206,2205,2301,2303,2302,2305,2304,2308,2310,2307,2306,2309,2143,2145,2144,2146,2101,2113,2142,2102,2103,2112,2119,2177,71,2105,72,2157,2155,2172,2158,2173,2171,2115,2148,2121,2118,2139,2114,2140,2162,2166,2151,2135,2149,2132,2168,2160,2161,2136,2169,2110,2152,2147,2170,2127,2128,2137,2133,2167,2126,2159,2175,2131,2107,2150,2117,2125,2124,2164,2163,2106,2134,2138,2104,2123,2108,2111,2176,2109,2130,2141,2165,2174,2120,2122,2116,2129,2156,2154,2153',@GameIncomeValue=0.0000,@HousePTValue=0.0000,@HousePTType=0,@GameIncomeType=0,@WinlostDate='2016-11-03 00:00:00',
@TotalBetType=0,@ExcludeTest=1,@LeagueId='',@Device='a,d,e,h,i,f,j,l,m,n,p,s,u,w',
@GameTableId='22994,22995,22996,23618,23751,26120,26121,28680,28681,28682,28683,32157',@Currency=-1,@Site='All'

 
exec Acc_Rpt_Letstalk_DCWL @WinlostDate='2016-11-03 00:00:00' 

*/


BEGIN 
SET NOCOUNT ON 

DECLARE
	@ProductId		VARCHAR(MAX) = '6',
	--@Username		VARCHAR(50) = '',
	--@Site			VARCHAR(MAX) = 'ALL',	
	--@BetType		VARCHAR(MAX) = '',
	--@LeagueId		VARCHAR(MAX) = '',
	--@Sporttype		VARCHAR(MAX) = '',
	--@GameTableId	VARCHAR(MAX) = '',
	@Currency		SMALLINT = 0,	
	@Device			VARCHAR(200) = '',
	@ExcludeTest	BIT = 1
	--@TotalBetType	SMALLINT = 0,
	--@TotalBetValue  MONEY = NULL,
	--@GameIncomeType	SMALLINT = 0,
	--@GameIncomeValue MONEY = NULL,	 
	--@HousePTType	SMALLINT = 0,
	--@HousePTValue   MONEY = 0,
	--@IsDrillDown	BIT = 0


	DECLARE @WLDate DATETIME 
	---, @IsMBC BIT, @IsSite BIT
	SELECT @WLDate = @WinlostDate

	CREATE TABLE #Data (   ReportBy NVARCHAR(1000), ProductID INT , BetFrom VARCHAR(1),
						   BetCount INT, CurrencyId INT, Currency NVARCHAR(50), 
						   TotalBets MONEY, TotalBetsBase MONEY, 
						   TotalWins MONEY, TotalWinsBase MONEY, 
						   TotalRefund MONEY, TotalRefundBase MONEY, 
						   CompanyTurnover MONEY, CompanyTurnoverBase MONEY,
						   CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
						   CompanyComm MONEY,  CompanyCommBase MONEY
						   )

	CREATE TABLE #Result ( ReportBy NVARCHAR(1000), NoOfPlayers INT, 
						   BetCount INT, CurrencyId INT, Currency NVARCHAR(50), 
						   TotalBets MONEY, TotalBetsBase MONEY, 
						   TotalWins MONEY, TotalWinsBase MONEY, 
						   TotalRefund MONEY, TotalRefundBase MONEY, 
						   CompanyTurnover MONEY, CompanyTurnoverBase MONEY,
						   CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
						   CompanyComm MONEY,  CompanyCommBase MONEY
						   )
	
	--CREATE TABLE #Temp_MemIDs (
 --       CustID int
 --   )
	--CREATE TABLE #tmpProductID (
 --       ProductID int
 --   )  
    --CREATE TABLE #tmpBetType (
    --    Bettype INT
    --)
	--CREATE TABLE #tmpLeagueId (
 --       LeagueId INT
 --   )  
	--CREATE TABLE #tmpSporttype (
 --       Sporttype INT
 --   )
	--CREATE TABLE #tmpGameTableId (
 --       GameTableID INT
 --   )
	--CREATE TABLE #tmpAllDepSuper (
 --       Srecommend INT
 --   )
	--CREATE TABLE #tmpSiteSuper (
 --       Srecommend INT
 --   )
	--CREATE TABLE #tmpSite (
 --       Site VARCHAR(50)
 --   )
	CREATE TABLE #tmpDevice (
        Betfrom NVARCHAR(2)
    )	 

	--IF @ProductID <> ''
 --   BEGIN
	--	INSERT INTO #tmpProductID (ProductID)
	--	SELECT val FROM [dbo].strSplit(@ProductID, ',')
	--END
	


	--IF @Bettype <> ''
 --   BEGIN
	--	INSERT INTO #tmpBetType (Bettype)
	--	SELECT val FROM [dbo].strSplit(@Bettype, ',')
	--END

	--IF @LeagueId <> ''
 --   BEGIN
	--	INSERT INTO #tmpLeagueId (LeagueId)
	--	SELECT val FROM [dbo].strSplit(@LeagueId, ',')
	--END

	--IF @Sporttype <> ''
 --   BEGIN
	--	INSERT INTO #tmpSporttype (Sporttype)
	--	SELECT val FROM [dbo].strSplit(@Sporttype, ',')
	--END
		
	--IF @GameTableID <> ''
 --   BEGIN
	--	INSERT INTO #tmpGameTableId (GameTableID)
	--	SELECT val FROM [dbo].strSplit(@GameTableID, ',')
	--END

	IF @Device <> ''
    BEGIN
		INSERT INTO #tmpDevice (Betfrom)
		SELECT val FROM [dbo].strSplit(@Device, ',')
	END
	

	------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	 DECLARE @isTest BIT = 0
	 SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	 CREATE TABLE #SportBettype (ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500), RefTable SMALLINT)
	 INSERT INTO #SportBettype ( ProductID, Bettype, EventType, SubProduct, RefTable)
	 SELECT s.ProductID,
            s.Bettype,
            s.EventType,
            s.SubProduct,
			s.RefTable
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
    	--INNER JOIN #tmpProductID p 
		--		ON p.ProductId = s.ProductId	
	 WHERE s.ProductID = @ProductId
		 

	--DELETE	s
	--FROM	#SportBettype s
	--WHERE	s.ProductID NOT IN (3, 5)   ---- NumberGame , Virtual Sports
	--		AND NOT EXISTS (SELECT Bettype FROM #tmpBetType b WHERE b.Bettype = s.Bettype)


	--- End Sport Bettype Matrix------		

	--IF (@Username <> '')
 --   BEGIN
 --       INSERT INTO #Temp_MemIDs (CustID)
 --           SELECT	Custid
 --           FROM	dbo.CustInfo WITH (NOLOCK)
 --           WHERE	Username LIKE + @Username + '%'
	--				AND Roleid = 1
 --   END

	--------Get Site
	--SELECT @IsMBC = 0
	--SELECT @IsSite = 0

	--IF @Site <> 'ALL'
	--BEGIN 

	--	INSERT INTO #tmpSite (Site)
	--	SELECT RTRIM(LTRIM(val)) FROM [dbo].strSplit(@Site, ',')
		
	--	----Specific Site
	--	IF EXISTS (SELECT 1 FROM #tmpSite WHERE Site NOT IN ('MBC Group'))
	--	BEGIN 
	--		SELECT @IsSite = 1

	--		INSERT INTO #tmpSiteSuper (Srecommend)
	--		SELECT	f.custid 
	--		FROM	#tmpSite s
	--		CROSS APPLY f_DepSuper_1(s.Site) f		 
	--	END


	--	-- If 'MBC Group' : Credit Site only, so get the Srecommend of Deposit to exclude later  	
	--	IF EXISTS (SELECT 1 FROM #tmpSite WHERE Site IN ('MBC Group'))					
	--	BEGIN 

	--		SELECT @IsMBC = 1   

	--		INSERT INTO #tmpAllDepSuper (Srecommend)
	--		SELECT custid FROM f_DepSuper_1('ALL')
			
	--		IF @IsSite = 1
	--		BEGIN 				
	--			DELETE A
	--			FROM  #tmpAllDepSuper A
	--			INNER JOIN #tmpSiteSuper S
	--				ON A.Srecommend = S.Srecommend
	--		END 			
	--	END
					
	--END	 

 
	---------------------------------------------- 
	---1. By bettype for normal Product
		--INSERT INTO #Data (  ReportBy, ProductID, BetFrom,
		--					   BetCount, CurrencyId , 
		--					   TotalBets, TotalBetsBase, 
		--					   TotalWins, TotalWinsBase, 
		--					   TotalRefund, TotalRefundBase,
		--					   CompanyTurnover, CompanyTurnoverBase,  
		--					   CompanyGrossIncome, CompanyGrossIncomeBase, 
		--					   CompanyComm, CompanyCommBase							   
		--					   )
	
		--SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,s.ProductID, b.BetFrom,  
		--		COUNT(CASE WHEN b.StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) AS TotalBets,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) AS TotalWins,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END) AS TotalRefund,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
		--		- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
		--		- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

		--		- SUM(scomm) AS CompanyComm,
		--		- SUM(scomm *actualrate) AS CompanyCommBase
		--FROM  dbo.Bettrans b WITH (NOLOCK)
		--	INNER JOIN #SportBettype s 
		--		ON s.Bettype = b.bettype 
		--WHERE b.WinlostDate = @WLDate
		--	AND s.ProductID NOT IN (3,4,5)   --- NumberGame, SLI-Live Casino, Virtual Sport 
		--	AND s.RefTable IN (0,3)
		--	AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		--	AND (b.currency = @currency OR @currency IN (0,-1)) 			
		--	--AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
		--	AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
		--	--AND ( @Site = 'ALL'
		--	--	  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
		--	--	  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
		--	--	)
		--	AND (	
		--			(@HousePTType = -1 AND b.tpositiontaking <= @HousePTValue)
		--		 OR (@HousePTType = 1 AND b.tpositiontaking >= @HousePTValue)
		--		 OR @HousePTType = 0 
		--		 )
		--GROUP BY  b.WinlostDate,  b.Currency,s.ProductID, b.BetFrom
		 

		---1b. By bettype for Casino Product
		INSERT INTO #Data (  ReportBy, ProductID, BetFrom,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase							   
							   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,s.ProductID, b.BetFrom,  
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.BettransRNG b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.GameId 
		WHERE b.WinlostDate = @WLDate
			--AND s.ProductID NOT IN (3,4,5)   --- NumberGame, SLI-Live Casino, Virtual Sport 
			AND s.RefTable = 1
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			--AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			--AND ( @Site = 'ALL'
			--	  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
			--	  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			--	)
			--AND (	
			--		(@HousePTType = -1 AND b.tpositiontaking <= @HousePTValue)
			--	 OR (@HousePTType = 1 AND b.tpositiontaking >= @HousePTValue)
			--	 OR @HousePTType = 0 
			--	 )
		GROUP BY  b.WinlostDate,  b.Currency,s.ProductID, b.BetFrom

		 

		---1b. By bettype for Live Casino Product
		--INSERT INTO #Data (  ReportBy, ProductID, BetFrom,
		--					   BetCount, CurrencyId , 
		--					   TotalBets, TotalBetsBase, 
		--					   TotalWins, TotalWinsBase, 
		--					   TotalRefund, TotalRefundBase,
		--					   CompanyTurnover, CompanyTurnoverBase,  
		--					   CompanyGrossIncome, CompanyGrossIncomeBase, 
		--					   CompanyComm, CompanyCommBase							   
		--					   )
	
		--SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy, s.ProductID, b.BetFrom,
		--		COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) AS TotalBets,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) AS TotalWins,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END) AS TotalRefund,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
		--		- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
		--		- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

		--		- SUM(scomm) AS CompanyComm,
		--		- SUM(scomm *actualrate) AS CompanyCommBase
		--FROM  dbo.BettransLC b WITH (NOLOCK)
		--	INNER JOIN #SportBettype s 
		--		ON s.Bettype = b.GameId 
		--WHERE b.WinlostDate = @WLDate
		--	AND s.ProductID NOT IN (3,4,5)   --- NumberGame, SLI-Live Casino, Virtual Sport 
		--	AND s.RefTable = 2
		--	AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		--	AND (b.currency = @currency OR @currency IN (0,-1)) 			
		--	--AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
		--	AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
		--	--AND ( @Site = 'ALL'
		--	--	  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
		--	--	  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
		--	--	)
		--	AND (	
		--			(@HousePTType = -1 AND b.tpositiontaking <= @HousePTValue)
		--		 OR (@HousePTType = 1 AND b.tpositiontaking >= @HousePTValue)
		--		 OR @HousePTType = 0 
		--		 )
		--GROUP BY  b.WinlostDate,  b.Currency, s.ProductID, b.BetFrom


	----2. NumberGame & Live Casino & VirtualSport (Soccer) 
		--INSERT INTO #Data ( ReportBy, ProductID, BetFrom,
		--				BetCount, CurrencyId , 
		--				TotalBets, TotalBetsBase, 
		--				TotalWins, TotalWinsBase, 
		--				TotalRefund, TotalRefundBase,
		--				CompanyTurnover, CompanyTurnoverBase,  
		--				CompanyGrossIncome, CompanyGrossIncomeBase, 
		--				CompanyComm, CompanyCommBase							   
		--			   )
	
		--SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy, s.ProductID, b.BetFrom,
		--		COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) AS TotalBets,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) AS TotalWins,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END) AS TotalRefund,
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

		--		SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
		--		SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
		--		- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
		--		- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

		--		- SUM(scomm) AS CompanyComm,
		--		- SUM(scomm *actualrate) AS CompanyCommBase
		--FROM  dbo.Bettrans b WITH (NOLOCK)
		--	INNER JOIN #SportBettype s 
		--		ON s.Bettype = b.bettype 
		--	INNER JOIN Match m WITH (NOLOCK) 
		--		ON m.MatchId = b.matchid
		--WHERE b.WinlostDate = @WLDate
		--	AND s.ProductID IN (3,4,5) --- NumberGame, SLI-Live Casino, VirtualSport
		--	AND s.Eventtype = 1
		--	AND (
		--			(
		--				(EXISTS (SELECT 1 From #tmpLeagueId l WHERE l.LeagueId = m.leagueid) AND s.ProductID = 3)
		--				OR (@LeagueId = '' AND s.ProductID = 3)
		--			)
		--		OR (
		--				(EXISTS (SELECT 1 From #tmpGameTableId g WHERE g.GameTableID = m.leagueid) AND s.ProductID = 4)
		--				OR (@GameTableId = '' AND s.ProductID = 4)
		--			)
		--		OR (
		--				(EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = m.sporttype) AND s.ProductID = 5)
		--				OR (@Sporttype = '' AND s.ProductID = 5)
		--			)
		--		)
		--	AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		--	AND (b.currency = @currency OR @currency IN (0,-1)) 			
		--	--AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
		--	AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
		--	--AND ( @Site = 'ALL'
		--	--	  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
		--	--	  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
		--	--	)
		--	--AND (	
		--	--		(@HousePTType = -1 AND b.tpositiontaking <= @HousePTValue)
		--	--	 OR (@HousePTType = 1 AND b.tpositiontaking >= @HousePTValue)
		--	--	 OR @HousePTType = 0 
		--	--	 )
		--GROUP BY  b.WinlostDate,  b.Currency, s.ProductID, b.BetFrom


	------3.  VirtualSport (HR) 
	--	INSERT INTO #Data ( ReportBy, ProductID, BetFrom,
	--					BetCount, CurrencyId , 
	--					TotalBets, TotalBetsBase, 
	--					TotalWins, TotalWinsBase, 
	--					TotalRefund, TotalRefundBase,
	--					CompanyTurnover, CompanyTurnoverBase,  
	--					CompanyGrossIncome, CompanyGrossIncomeBase, 
	--					CompanyComm, CompanyCommBase							   
	--				   )
	
	--	SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,  s.ProductID, b.BetFrom,  
	--			COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

	--			SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) AS TotalBets,
	--			SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

	--			SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) AS TotalWins,
	--			SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

	--			SUM(CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END) AS TotalRefund,
	--			SUM((CASE WHEN b.statusID IN (101,102,103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

	--			SUM(CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
	--			SUM((CASE WHEN b.statusID IN (101,102,103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
	--			- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
	--			- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

	--			- SUM(scomm) AS CompanyComm,
	--			- SUM(scomm *actualrate) AS CompanyCommBase
	--	FROM  dbo.Bettrans b WITH (NOLOCK)
	--		INNER JOIN #SportBettype s 
	--			ON s.Bettype = b.bettype 
	--		INNER JOIN VSRaceInfo r WITH (NOLOCK) 
	--			ON r.EventId = b.matchid
	--	WHERE b.WinlostDate = @WLDate
	--		AND s.ProductID = 5 --- VirtualSport (HR)
	--		AND s.Eventtype = 3
	--		AND (	
	--				EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = r.sporttype)
	--				OR @Sporttype = ''
	--			)
	--		AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
	--		AND (b.currency = @currency OR @currency IN (0,-1)) 			
	--		--AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
	--		AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
	--		--AND ( @Site = 'ALL'
	--		--	  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
	--		--	  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
	--		--	)
	--		AND (	
	--				(@HousePTType = -1 AND b.tpositiontaking <= @HousePTValue)
	--			 OR (@HousePTType = 1 AND b.tpositiontaking >= @HousePTValue)
	--			 OR @HousePTType = 0 
	--			 )
	--	GROUP BY  b.WinlostDate,  b.Currency, s.ProductID, b.BetFrom


---Get CurrencyName
		UPDATE  R   
		SET		Currency = E.currency
		FROM #Data R
		INNER JOIN Exchange e 
			ON E.exchangeid = R.CurrencyId

			 
---Get data 

--IF @Currency = -1  ----BASE RM 
--BEGIN 
--		IF @IsDrillDown = 0  --Main 
--		BEGIN 
--			INSERT INTO #Result (ReportBy, NoOfPlayers, BetCount, CurrencyId, Currency, 
--								TotalBets, TotalWins, TotalRefund, CompanyTurnover, CompanyGrossIncome, CompanyComm)
--			SELECT  ReportBy, 
--					COUNT(DISTINCT CustID) AS NoOfPlayers, 
--					0 As NoOfPlayers,
--					SUM(BetCount) AS BetCount ,
--					-1 as CurrencyId, 'RM' AS Currency,
--					SUM (TotalBetsBase) AS TotalBets, 
--					SUM (TotalWinsBase) AS TotalWins,
--					SUM (TotalRefundBase) AS TotalRefund,
--					SUM (CompanyTurnoverBase) AS CompanyTurnover,
--					SUM (CompanyGrossIncomeBase) AS CompanyGrossIncome,
--					SUM (CompanyCommBase) AS CompanyComm
--			FROM	#Data
--			GROUP BY ReportBy 
--			HAVING (@TotalBetType = 0
--					OR (@TotalBetType = 1 AND SUM(TotalBetsBase) >= @TotalBetValue) 
--					OR (@TotalBetType = -1 AND SUM(TotalBetsBase) <= @TotalBetValue)
--					)
--				AND (@GameIncomeType = 0
--					OR (@GameIncomeType = 1 AND SUM(TotalBetsBase - TotalWinsBase) >= @GameIncomeValue) 
--					OR (@GameIncomeType = -1 AND SUM(TotalBetsBase - TotalWinsBase) <= @GameIncomeValue)
--					)  						      
--		END 
		--ELSE IF @IsDrillDown = 1 --- Click on Currency or Grand Total (Of Mode Base to RM )
		--BEGIN 
		--	INSERT INTO #Result (ReportBy, NoOfPlayers, BetCount, CurrencyId, Currency, 
		--						TotalBets, TotalWins, TotalRefund, CompanyTurnover, CompanyGrossIncome, CompanyComm)
		--	SELECT  ReportBy, 
		--			COUNT(DISTINCT CustID) AS NoOfPlayers, 
		--			SUM(BetCount) AS BetCount ,
		--			CurrencyId, Currency,
		--			SUM (TotalBetsBase) AS TotalBets, 
		--			SUM (TotalWinsBase) AS TotalWins,
		--			SUM (TotalRefundBase) AS TotalRefund,
		--			SUM (CompanyTurnoverBase) AS CompanyTurnover,
		--			SUM (CompanyGrossIncomeBase) AS CompanyGrossIncome,
		--			SUM (CompanyCommBase) AS CompanyComm
		--	FROM	#Data
		--	GROUP BY ReportBy,CurrencyId, Currency
		--	HAVING (@TotalBetType = 0
		--			OR (@TotalBetType = 1 AND SUM(TotalBetsBase) >= @TotalBetValue) 
		--			OR (@TotalBetType = -1 AND SUM(TotalBetsBase) <= @TotalBetValue)
		--			)
		--		AND (@GameIncomeType = 0
		--			OR (@GameIncomeType = 1 AND SUM(TotalBetsBase - TotalWinsBase) >= @GameIncomeValue) 
		--			OR (@GameIncomeType = -1 AND SUM(TotalBetsBase - TotalWinsBase) <= @GameIncomeValue)
		--			) 
		--END 
--END 
--ELSE 
--BEGIN 
--		INSERT INTO #Result (  ReportBy, NoOfPlayers,
--							   BetCount, CurrencyId , Currency,
--							   TotalBets, TotalBetsBase, 
--							   TotalWins, TotalWinsBase, 
--							   TotalRefund, TotalRefundBase,
--							   CompanyTurnover, CompanyTurnoverBase,  
--							   CompanyGrossIncome, CompanyGrossIncomeBase, 
--							   CompanyComm, CompanyCommBase	)
--		SELECT   ReportBy, 
--				 COUNT(DISTINCT CustID) AS NoOfPlayers,  
--				 SUM(BetCount) AS BetCount, 
--				 CurrencyId, Currency,
--				 SUM(TotalBets) AS TotalBets, 
--				 SUM(TotalBetsBase) AS TotalBetsBase, 
--				 SUM(TotalWins) AS TotalWins, 
--				 SUM(TotalWinsBase) AS TotalWinsBase, 
--				 SUM(TotalRefund) AS TotalRefund, 
--				 SUM(TotalRefundBase) AS TotalRefundBase, 
--				 SUM(CompanyTurnover) AS CompanyTurnover, 
--				 SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
--				 SUM(CompanyGrossIncome) AS CompanyGrossIncome, 
--				 SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase, 
--				 SUM(CompanyComm) AS CompanyComm, 
--				 SUM(CompanyCommBase) AS CompanyCommBase
--		FROM	#Data
--		GROUP BY ReportBy, CurrencyId, Currency
--		HAVING (@TotalBetType = 0
--				OR (@TotalBetType = 1 AND SUM(TotalBets) >= @TotalBetValue) 
--				OR (@TotalBetType = -1 AND SUM(TotalBets) <= @TotalBetValue)
--				)
--			AND (@GameIncomeType = 0
--				OR (@GameIncomeType = 1 AND SUM(TotalBets - TotalWins) >= @GameIncomeValue) 
--				OR (@GameIncomeType = -1 AND SUM(TotalBets - TotalWins) <= @GameIncomeValue)
--				)
--END 

--SELECT  ReportBy, NoOfPlayers, BetCount, CurrencyId, Currency, 
--		TotalBets, TotalWins, TotalRefund, 
--		CompanyTurnover, CompanyGrossIncome, CompanyComm
--FROM    #Result 
--ORDER BY ReportBy
  
  
		DECLARE @ProductData AS TABLE (ProductID INT,  ProductName Varchar(50), Betfrom  Varchar(50) )
		INSERT INTO @ProductData 

		SELECT  P.ProductId, 
				P.ProductName, 
				A.BetFrom
		FROM dbo.Products P WITH (NOLOCK) 
		CROSS APPLY 
		(	SELECT 'Mobile' AS BetFrom
			UNION ALL
			SELECT 'Desktop' AS BetFrom
		) A
		WHERE P.ProductID IN (6)



		CREATE TABLE  #ResultData (ProductId INT, ProductName Varchar(50), Betfrom  Varchar(50), CompanyTurnoverBase MONEY, CompanyNetIncomeBase MONEY )
		INSERT INTO #ResultData
		SELECT	P.ProductId, P.ProductName, 
				CASE WHEN A.BetFrom IS NULL THEN P.Betfrom ELSE A.BetFrom END AS BetFrom, 
				CASE WHEN A.BetFrom IS NULL THEN 0 ELSE A.CompanyTurnoverBase END AS CompanyTurnoverBase, 
				CASE WHEN A.BetFrom IS NULL THEN 0 ELSE A.CompanyNetIncomeBase END AS CompanyNetIncomeBase  
		FROM	@ProductData P 
		LEFT  JOIN 
		(
		SELECT  D.ProductId, 
				P.ProductName, 
				CASE WHEN BetFrom IN ('i','d','e','a','u','j') THEN 'Desktop' ELSE 'Mobile' END  As BetFrom,  
				SUM (TotalBetsBase) AS CompanyTurnoverBase , 
				SUM (CompanyGrossIncomeBase) + SUM (CompanyCommBase) AS CompanyNetIncomeBase
		FROM	#Data D
			INNER JOIN dbo.Products P WITH (NOLOCK) ON P.ProductID = D.ProductID
		WHERE BetFrom IN ('i','d','e','a','u','j','p','h','n','s','l','w','m') 
		GROUP BY D.ProductId, 
				P.ProductName, 
				CASE WHEN BetFrom IN ('i','d','e','a','u','j') THEN 'Desktop' ELSE 'Mobile' END ) A
				
			ON A.ProductID = P.ProductID AND A.BetFrom = P.Betfrom
		 

		SELECT  ProductId, ProductName, IndicatorName,
				CASE WHEN betfrom = 'SUM' and  indicatorname = 'Winloss' THEN 'HWL'  ELSE CASE WHEN betfrom = 'SUM' and  indicatorname = 'Turnover' THEN 'TO' ELSE betfrom END END as IndicatorKey,
				IndicatorValue
		FROM 
		(
			 SELECT ProductId, ProductName, 'SUM' as betfrom, SUM(CompanyTurnoverBase) as Turnover, SUM(CompanyNetIncomeBase) as Winloss
			 FROM	#ResultData D
			 GROUP BY Productid, ProductName 
 
			 UNION ALL

			 SELECT Productid, ProductName, betfrom, CompanyTurnoverBase as Turnover ,CompanyNetIncomeBase as Winloss
			 FROM #ResultData D  

		) AS tmp
		UNPIVOT (
				IndicatorValue
				FOR IndicatorName in (Winloss,Turnover)
				) unpiv
		ORDER BY ProductId , IndicatorName DESC , betfrom DESC





-------------------------------------------------------
	----- Get Line Total base on RM 
	--IF @Currency = -1 ----BASE RM 
	--BEGIN 
	--	SELECT	ReportBy, 
	--			SUM(NoOfPlayers) AS NoOfPlayers, 
	--			SUM(BetCount) AS BetCount, 
	--			-1 as CurrencyId, 'RM' AS Currency,
	--			SUM(TotalBets) AS TotalBets,
	--			SUM(TotalWins) AS TotalWins, 
	--			SUM(TotalRefund) AS TotalRefund, 
	--			SUM(CompanyTurnover) AS CompanyTurnover, 
	--			SUM(CompanyGrossIncome) AS CompanyGrossIncome, 
	--			SUM(CompanyComm) AS CompanyComm
	--	FROM   #Result 
	--	GROUP BY ReportBy 	
	--	ORDER BY ReportBy 

	--END 
	--ELSE 
	--BEGIN 
	--	SELECT  ReportBy, 
	--			SUM(NoOfPlayers) AS NoOfPlayers, 
	--			SUM(BetCount) AS BetCount ,
	--			-1 as CurrencyId, 'RM' AS Currency,
	--			SUM (TotalBetsBase) AS TotalBets, 
	--			SUM (TotalWinsBase) AS TotalWins,
	--			SUM (TotalRefundBase) AS TotalRefund,
	--			SUM (CompanyTurnoverBase) AS CompanyTurnover,
	--			SUM (CompanyGrossIncomeBase) AS CompanyGrossIncome,
	--			SUM (CompanyCommBase) AS CompanyComm
	--	FROM	#Result
	--	GROUP BY ReportBy 	
	--	ORDER BY ReportBy 
	--END

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	--DROP TABLE #Temp_MemIDs
	--DROP TABLE #tmpAllDepSuper
	--DROP TABLE #tmpBetType
	DROP TABLE #tmpDevice
	--DROP TABLE #tmpGameTableId
	--DROP TABLE #tmpLeagueId
	--DROP TABLE #tmpProductID
	--DROP TABLE #tmpSite
	--DROP TABLE #tmpSiteSuper
	--DROP TABLE #tmpSporttype


END 


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_Letstalk_DCWL] TO [bodbAdminNet]
GO 

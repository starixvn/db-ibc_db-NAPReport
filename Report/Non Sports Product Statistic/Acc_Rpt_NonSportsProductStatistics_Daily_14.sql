Use BODB02
GO 

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Daily_14]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@GameTableId	VARCHAR(MAX) = '',
	@Currency		SMALLINT = 0,	
	@Device			VARCHAR(200) = '',
	@ExcludeTest	BIT = 1, 
	@TotalBetType	SMALLINT = 0,
	@TotalBetValue  MONEY = NULL,
	@GameIncomeType	SMALLINT = 0,
	@GameIncomeValue MONEY = NULL,	 
	@HousePTType	SMALLINT = 0,
	@HousePTValue   MONEY = 0,
	@IsDrillDown	BIT = 0,
	@IsGrandTotal	BIT = 0 -- dont need to use in this report


AS
/*
	Created: 20160906@Sophia
	Task :	Non Sports Product Statistic - Daily Report [#Redmine: 62430]
	DB:		DBACC/bodb02
	Original: Acc_Rpt_CasinoGameStatistics_GameType_bettrans
	Revisions:
		- 20170227@Percy: support search multiple username [RedmineID: #71342]
		- 20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		- 20170815@Cherry: Non-Sport Statistics Phase 5 (#71923)
		- 20171006@Cherry: Add filter of Number Game Bettype (#83101)
		- 20180328@Cherry: Integrate One RNG Jackpot (#89459)
		- 20180808@Cherry: Integrate Poker Games (#97809)

	Param's Explanation:
			 - @username:  + Search by keyword, member only
			 - @Site: List of Company filter
				'ALL': All sites (MBC + Licensees)
				'MBC': MBC sites only
				'12bet' : Specific Licensee Name 
			 - @ProductID: string filter by Product 
			 - @BetType: string filter by bettype
			 - @LeagueId: string filter by LeagueId (ProductID = 3 - Number Game get LeagueId)  
			 - @Sporrtype: string filter by Sporrtype (ProductID = 5 - Virtual Sports get Sporttype)
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

	EXEC Acc_Rpt_NonSportsProductStatistics_Daily @WinlostDate = '2016-09-22' ,
	@ProductID='4,12,21,11,13,6,17,14,22,3,8,5', 
	@Bettype='1101, 1102, 1103, 1104,1700, 1701, 1702, 1703,2401, 2402, 2403, 2404, 2405,1800, 1801, 1802, 1803, 1804,2001, 2002, 2003, 2004, 2005, 2006, 2007,2008, 2009,1900,1501,1515',
 	@LeagueID='15223, 50717',
 	@Sporttype='180, 181, 182, 183, 184, 185, 186'
*/

BEGIN 
SET NOCOUNT ON 

	DECLARE @CustList VARCHAR(MAX)

	IF CHARINDEX(',', @Username) <> 0
	BEGIN
		EXEC dbo.Acc_CustomerSelCustByUsernameList @Username = @Username, @RoleId = 1, @CustList = @CustList OUTPUT

		IF @CustList IS NULL -- invalid username
		BEGIN
			SELECT TOP 0 *
			FROM (
				SELECT
					NULL AS ReportById,
					NULL AS ReportBy,
					NULL AS NoOfPlayers,
					NULL AS BetCount,
					NULL AS CurrencyId,
					NULL AS Currency,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnover,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm
			) A
		
			-- Grand Total
			SELECT
				NULL AS ReportBy,
				NULL AS NoOfPlayers,
				NULL AS BetCount,
				NULL AS CurrencyId,
				NULL AS Currency,
				NULL AS TotalBets,
				NULL AS TotalWins,
				NULL AS TotalRefund,
				NULL AS CompanyTurnover,
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm

			RETURN
		END
	END
	
	DECLARE @WLDate DATETIME , @IsMBC BIT, @IsSite BIT
	SELECT @WLDate = @WinlostDate

	CREATE TABLE #Data ( ReportBy NVARCHAR(1000), CustId INT,
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
	
	CREATE TABLE #Temp_MemIDs (CustID int)
	CREATE TABLE #tmpProductID (ProductID int)  
    CREATE TABLE #tmpBetType (Bettype INT)
	CREATE TABLE #tmpLeagueId (LeagueId INT, Bettype INT)  
	CREATE TABLE #tmpSporttype (Sporttype INT)
	CREATE TABLE #tmpGameTableId (GameTableID INT)
	CREATE TABLE #tmp_Site (Site VARCHAR(50))	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), Srecommend INT)
	CREATE TABLE #tmpDevice (Betfrom NVARCHAR(2))

	IF @ProductID <> ''
    BEGIN
		INSERT INTO #tmpProductID (ProductID)
		SELECT val FROM [dbo].strSplit(@ProductID, ',')
	END

	IF @Bettype <> ''
    BEGIN
		INSERT INTO #tmpBetType (Bettype)
		SELECT val FROM [dbo].strSplit(@Bettype, ',')
	END
	
	DECLARE @splitter1 char(1) = ',', @splitter2 char(1) = '-',
		@league int, @bettypeid int,
		@start int, @leaguebettype nvarchar(4000), 
		@charindex1 int, @charindex2 int

	IF @LeagueId <> ''
    BEGIN
		IF substring (@LeagueID, len(@LeagueID), 1) <> @splitter1
			SET @LeagueID = @LeagueID + @splitter1
		SET @start = 1
		SET @charindex1 = charindex(@splitter1, @LeagueID, @start)
		SET @charindex2 = charindex(@splitter2, @LeagueID, @start)

		WHILE (@charindex1 <> 0)
		BEGIN
			SET @leaguebettype = substring(@LeagueID, @start, @charindex1 - @start)       
			SET @charindex2 = charindex(@splitter2, @leaguebettype, 1)
			SET @league = substring(@leaguebettype, 1, @charindex2 - 1)
			SET @bettypeid = substring(@leaguebettype, @charindex2 + 1, LEN(@leaguebettype))
			INSERT INTO #tmpLeagueID(LeagueID, Bettype) VALUES (@league, @bettypeid)
			SET @start = @charindex1 +1
			SET @charindex1 = charindex(@splitter1, @LeagueID, @start)          
		END
	END

	IF @Sporttype <> ''
    BEGIN
		INSERT INTO #tmpSporttype (Sporttype)
		SELECT val FROM [dbo].strSplit(@Sporttype, ',')
	END
		
	IF @GameTableID <> ''
    BEGIN
		INSERT INTO #tmpGameTableId (GameTableID)
		SELECT val FROM [dbo].strSplit(@GameTableID, ',')
	END

	IF @Device <> ''
    BEGIN
		INSERT INTO #tmpDevice (Betfrom)
		SELECT val FROM [dbo].strSplit(@Device, ',')
	END
	
	IF @Username <> ''
	BEGIN
		IF @CustList IS NOT NULL
		BEGIN
			INSERT INTO #Temp_MemIDs (CustID)
			SELECT val FROM dbo.strSplit(@CustList, ',')
		END
		ELSE
		BEGIN
			INSERT INTO #Temp_MemIDs (CustID)
			SELECT custid
			FROM dbo.Customer WITH(NOLOCK)
			WHERE username LIKE @Username + '%' AND roleid = 1

			IF @Username NOT LIKE '%[^0-9]%' AND LEN(@Username) < 10
			BEGIN
			INSERT INTO #Temp_MemIDs (CustID)
			SELECT cu.custid FROM dbo.Customer cu WITH(NOLOCK) WHERE cu.custid = @Username AND cu.roleid = 1
				AND NOT EXISTS (SELECT 1 FROM #Temp_MemIDs c WHERE cu.custid = c.custid)
			END
		END
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
		INNER JOIN #tmpProductID p 
				ON p.ProductId = s.ProductId	

	DELETE	s
	FROM	#SportBettype s
	WHERE	s.ProductID NOT IN (3, 5, 27)   ---- NumberGame , Virtual Sports, Virtual Sports 2
			AND NOT EXISTS (SELECT Bettype FROM #tmpBetType b WHERE b.Bettype = s.Bettype)


	--- End Sport Bettype Matrix------

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site NOT IN ('MBC Group')) -- Deposit Or Credit Drill Down
		BEGIN	
			INSERT INTO #tmp_Company (SiteName, Srecommend)
			SELECT s.Site, c.srecommend
			FROM #tmp_Site s
				INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.Site = c.site
			WHERE c.roleid = 4
		END

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site IN ('MBC Group'))					
		BEGIN
			INSERT INTO #tmp_Company (SiteName, Srecommend)
			SELECT c.site, c.srecommend
			FROM dbo.Customer c WITH (NOLOCK)
			WHERE c.roleid = 4
				AND NOT EXISTS (SELECT 1 FROM dbo.f_DepSuper_1('ALL') f WHERE c.srecommend = f.CustID)
		END			
	END	 	 

	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID NOT IN (3, 4, 5, 27))
	BEGIN
		---1. By bettype for normal Product
		INSERT INTO #Data (  ReportBy, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase							   
							   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				CASE WHEN s.ProductID = 33 THEN SUM(CASE WHEN b.statusID IN (111, 112, 113) THEN b.betid ELSE 0 END)  --Poker Games
					ELSE COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) END AS BetCount,  b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN s.ProductID = 33 THEN 0  --Poker Games
						 WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN s.ProductID = 33 THEN 0  --Poker Games
						  WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5, 27)   --- NumberGame, SLI-Live Casino, Virtual Sport , Virtual Sports 2
			AND s.RefTable IN (0,3)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  s.ProductID, b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
		 
		---1b. By bettype for Casino Product
		INSERT INTO #Data (  ReportBy, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase							   
							   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) AND b.gameID NOT IN (2198, 2398, 2998) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
							ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END) AS CompanyGrossIncome,
				- SUM((CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
							ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.BettransRNG14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.GameId 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5,27)   --- NumberGame, SLI-Live Casino, Virtual Sport , Virtual Sports 2
			AND s.RefTable = 1
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END

		---1b. By bettype for Casino Product
		INSERT INTO #Data (  ReportBy, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase							   
							   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.BettransLC14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.GameId 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5,27)   --- NumberGame, SLI-Live Casino, Virtual Sport, Virtual Sports 2 
			AND s.RefTable = 2
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
	END

	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID IN (3, 4, 5))
	BEGIN
		----2. NumberGame & Live Casino & VirtualSport (Soccer) 
		INSERT INTO #Data ( ReportBy, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase							   
					   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
			INNER JOIN Match14 m WITH (NOLOCK) 
				ON m.MatchId = b.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID IN (3,4,5) --- NumberGame, SLI-Live Casino, VirtualSport
			AND s.Eventtype = 1
			AND (
					(
						(EXISTS (SELECT 1 From #tmpLeagueId l WHERE l.LeagueId = m.leagueid AND l.Bettype = b.bettype) AND s.ProductID = 3)
						OR (@LeagueId = '' AND s.ProductID = 3)
					)
				OR (
						(EXISTS (SELECT 1 From #tmpGameTableId g WHERE g.GameTableID = m.leagueid) AND s.ProductID = 4)
						OR (@GameTableId = ''  AND s.ProductID = 4)
					)
				OR (
						(EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = m.sporttype) AND s.ProductID = 5)
						OR (@Sporttype = '' AND s.ProductID = 5)
					)
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END

		----3.  VirtualSport (HR) 
		INSERT INTO #Data ( ReportBy, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase							   
					   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
			INNER JOIN VSRaceInfo r WITH (NOLOCK) 
				ON r.EventId = b.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID = 5 --- VirtualSport (HR)
			AND s.Eventtype = 3
			AND (	
					EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = r.sporttype)
					OR @Sporttype = ''
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
	END
	
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 27)
	BEGIN	
		-- Virtual Sports 2
		INSERT INTO #Data ( ReportBy, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase							   
					   )
	
		SELECT  CONVERT(VARCHAR(20),b.WinlostDate,107) AS ReportBy,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID = 27
			AND ((s.Eventtype = 1 AND EXISTS(SELECT 1 FROM dbo.match14 m WITH (NOLOCK) 
														INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype 
											WHERE m.matchid = b.matchid))
				OR (s.EventType = 0 AND EXISTS(SELECT 1 FROM dbo.bettransm14 bm WITH(NOLOCK)
														INNER JOIN dbo.match14 m WITH(NOLOCK) ON bm.matchid = m.matchid 
														INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype 
												WHERE bm.refno = b.refno))	
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.WinlostDate,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
	END

---Get CurrencyName
		UPDATE  R   
		SET		Currency = E.currency
		FROM #Data R
		INNER JOIN Exchange e 
			ON E.exchangeid = R.CurrencyId

			 
---Get data 

	IF @Currency = -1  ----BASE RM 
	BEGIN 		
		INSERT INTO #Result (ReportBy, NoOfPlayers, BetCount, CurrencyId, Currency, 
							TotalBets, TotalWins, TotalRefund, CompanyTurnover, CompanyGrossIncome, CompanyComm,
							TotalBetsBase, TotalWinsBase, TotalRefundBase, CompanyTurnoverBase, CompanyGrossIncomeBase, CompanyCommBase)
		SELECT  ReportBy, 
				COUNT(DISTINCT CustID) AS NoOfPlayers, 
				SUM(BetCount) AS BetCount ,
				-1 as CurrencyId, 'RM' AS Currency,
				SUM (TotalBetsBase) AS TotalBets, 
				SUM (TotalWinsBase) AS TotalWins,
				SUM (TotalRefundBase) AS TotalRefund,
				SUM (CompanyTurnoverBase) AS CompanyTurnover,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncome,
				SUM (CompanyCommBase) AS CompanyComm,
				SUM (TotalBetsBase) AS TotalBetsBase, 
				SUM (TotalWinsBase) AS TotalWinsBase,
				SUM (TotalRefundBase) AS TotalRefundBase,
				SUM (CompanyTurnoverBase) AS CompanyTurnoverBase,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM (CompanyCommBase) AS CompanyCommBase
		FROM	#Data
		GROUP BY ReportBy 
		HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(TotalBetsBase) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(TotalBetsBase) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(TotalBetsBase - TotalWinsBase) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(TotalBetsBase - TotalWinsBase) <= @GameIncomeValue)
				)  						      
	END 		
	ELSE 
	BEGIN 
		INSERT INTO #Result (  ReportBy, NoOfPlayers,
								BetCount, CurrencyId , Currency,
								TotalBets, TotalBetsBase, 
								TotalWins, TotalWinsBase, 
								TotalRefund, TotalRefundBase,
								CompanyTurnover, CompanyTurnoverBase,  
								CompanyGrossIncome, CompanyGrossIncomeBase, 
								CompanyComm, CompanyCommBase	)
		SELECT   ReportBy, 
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(BetCount) AS BetCount, 
					CurrencyId, Currency,
					SUM(TotalBets) AS TotalBets, 
					SUM(TotalBetsBase) AS TotalBetsBase, 
					SUM(TotalWins) AS TotalWins, 
					SUM(TotalWinsBase) AS TotalWinsBase, 
					SUM(TotalRefund) AS TotalRefund, 
					SUM(TotalRefundBase) AS TotalRefundBase, 
					SUM(CompanyTurnover) AS CompanyTurnover, 
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
					SUM(CompanyGrossIncome) AS CompanyGrossIncome, 
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase, 
					SUM(CompanyComm) AS CompanyComm, 
					SUM(CompanyCommBase) AS CompanyCommBase
		FROM	#Data
		GROUP BY ReportBy, CurrencyId, Currency
		HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(TotalBets) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(TotalBets) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(TotalBets - TotalWins) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(TotalBets - TotalWins) <= @GameIncomeValue)
				)
	END 

	------------------------------------------IV. Return Detail ------------------------------------------------------
	IF @IsGrandTotal = 0
	BEGIN
		IF @IsDrillDown = 0
		BEGIN
			SELECT  ReportBy, NoOfPlayers, BetCount, CurrencyId, Currency, 
				TotalBets, TotalWins, TotalRefund, 
				CompanyTurnover AS HouseTurnover, 
				CompanyGrossIncome AS HouseGrossIncome, 
				CompanyComm AS HouseComm
			FROM    #Result 
			ORDER BY ReportBy, Currency
		END
		ELSE
		BEGIN
			SELECT 
				b.ReportBy AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm
		
			FROM #Data b	
				INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.ReportBy = r.ReportBy	
			GROUP BY b.ReportBy, b.CurrencyID , b.Currency	
			ORDER BY b.Currency
		END
	END
	ELSE
	BEGIN
		SELECT b.CurrencyID AS ReportById,
				b.Currency AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm
		
		FROM #Data b	
			INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.ReportBy = r.ReportBy	
		GROUP BY b.CurrencyID , b.Currency	
		ORDER BY b.Currency
	END
	
	------------------------------------------V. Return Total Rows ------------------------------------------------------ 
	SELECT  'GrandTotalRM' AS ReportBy, 
			COUNT(DISTINCT b.CustId) AS NoOfPlayers, 
			SUM(b.BetCount) AS BetCount ,
			-1 as CurrencyId, 'RM' AS Currency,
			SUM (b.TotalBetsBase) AS TotalBets, 
			SUM (b.TotalWinsBase) AS TotalWins,
			SUM (b.TotalRefundBase) AS TotalRefund,
			SUM (b.CompanyTurnoverBase) AS HouseTurnover,
			SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM (b.CompanyCommBase) AS HouseComm
	FROM #Data b	
			INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.ReportBy = r.ReportBy	
	
	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #Temp_MemIDs
	DROP TABLE #tmpBetType
	DROP TABLE #tmpDevice
	DROP TABLE #tmpGameTableId
	DROP TABLE #tmpLeagueId
	DROP TABLE #tmpProductID
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_Company
	DROP TABLE #tmpSporttype


END 
GO 
 
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Daily_14] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Daily_14] TO [vnteam]
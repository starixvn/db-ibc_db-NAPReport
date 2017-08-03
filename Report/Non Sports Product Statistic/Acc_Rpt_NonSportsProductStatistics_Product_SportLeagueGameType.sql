USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Product_SportLeagueGameType]
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
	@IsGrandTotal	BIT = 0
AS
/*
	Created	: 20161121@Harper
	Task	: #62430_Non Sports Product Statistic - Product Report - Group by SportType/League/GameType
	DB		: DBACC/bodb02
	
	Revision:
		- 20170227@Percy: support search multiple username [RedmineID: #71342]
		- 20170726@Cherry: Integrate Betradar Virtual Sports (#78495)

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

	EXEC [Acc_Rpt_NonSportsProductStatistics_Product_SportLeagueGameType] @WinlostDate = '2016-11-20',
	@ProductID = '6', 
	@Bettype = '1101,1102,1103,1104,1700,1701,1702,1703,2401,2402,2403,2404,2405,1800,1801,1802,1803,1804,2001,2002,2003,2004,2005,2006,2007,2008,2009,1900,1501,1515',
 	@LeagueID = '15223, 50717',
 	@Sporttype = '208,209,210,251',
 	@Device = 'a,d,e,f,h,i,j,l,m,n,p,s,t,u,w',
 	@GameTableId = '22994,22995,22996,23618,23751,26120,26121,28680,28681,28682,28683,32157',
 	@Currency = -1,
 	@IsDrillDown = 0
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
					NULL AS CompanyTurnOver,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm
			) A
		
			-- Grand total
			SELECT
				NULL AS ReportBy,
				NULL AS NoOfPlayers,
				NULL AS BetCount,
				NULL AS CurrencyId, 
				NULL AS Currency,
				NULL AS TotalBets,
				NULL AS TotalWins,
				NULL AS TotalRefund,
				NULL AS CompanyTurnOver,
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm

			RETURN
		END
	END
	
	DECLARE @WLDate DATETIME
	SELECT @WLDate = @WinlostDate

	CREATE TABLE #Data ( Bettype INT, BettypeName NVARCHAR(1000), CustID INT,
						 BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets MONEY, TotalBetsBase MONEY,
						 TotalWins MONEY, TotalWinsBase MONEY,
						 TotalRefund MONEY, TotalRefundBase MONEY,
						 CompanyTurnOver MONEY, CompanyTurnOverBase MONEY,
						 CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
						 CompanyComm MONEY, CompanyCommBase MONEY
						)
	CREATE TABLE #Result (  Bettype INT, BettypeName NVARCHAR(1000), NoOfPlayers INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets MONEY, TotalBetsBase MONEY,
							TotalWins MONEY, TotalWinsBase MONEY,
							TotalRefund MONEY, TotalRefundBase MONEY,
							CompanyTurnOver MONEY, CompanyTurnOverBase MONEY,
							CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
							CompanyComm MONEY, CompanyCommBase MONEY							
						)

	------------------------------------------I. Handle Parameter ------------------------------------------------------

	CREATE TABLE #tmp_ProductID		(ProductID INT)
	CREATE TABLE #tmp_BetType		(Bettype INT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT)
	CREATE TABLE #tmp_SportType		(Sporttype INT)
	CREATE TABLE #tmp_GameTableID	(GameTableID INT)
	CREATE TABLE #tmp_Devide		(Betfrom NVARCHAR(2))
	CREATE TABLE #tmp_Site			(Site VARCHAR(50))
	CREATE TABLE #tmp_MemIDs		(CustID INT)

	-- Get Info from Pars list
	IF @ProductId <> ''
	BEGIN
		INSERT INTO #tmp_ProductID (ProductID)
		SELECT val FROM dbo.strSplit(@ProductId, ',')

		DELETE #tmp_ProductID
		WHERE ProductID = 8 -- Keno don't have this type of report
	END

	IF @BetType <> ''
	BEGIN
		INSERT INTO #tmp_BetType (Bettype)
		SELECT val FROM dbo.strSplit(@BetType, ',')
	END

	IF @LeagueId <> ''
	BEGIN
		INSERT INTO #tmp_LeagueID (LeagueID)
		SELECT val FROM dbo.strSplit(@LeagueId, ',')
	END

	IF @Sporttype <> ''
	BEGIN
		INSERT INTO #tmp_SportType (Sporttype)
		SELECT val FROM dbo.strSplit(@Sporttype, ',')
	END

	IF @GameTableId <> ''
	BEGIN
		INSERT INTO #tmp_GameTableID (GameTableID)
		SELECT val FROM dbo.strSplit(@GameTableId, ',')
	END

	IF @Device <> ''
	BEGIN
		INSERT INTO #tmp_Devide (Betfrom)
		SELECT val FROM dbo.strSplit(@Device, ',')
	END
	-- End Info from Pars list

	-- Get Cust Info
	IF @Username <> ''
	BEGIN
		IF @CustList IS NOT NULL
		BEGIN
			INSERT INTO #tmp_MemIDs (CustID)
			SELECT val FROM dbo.strSplit(@CustList, ',')
		END
		ELSE
		BEGIN
			INSERT INTO #tmp_MemIDs (CustID)
			SELECT custid
			FROM dbo.Customer WITH(NOLOCK)
			WHERE username LIKE @Username + '%' AND roleid = 1

			IF @Username NOT LIKE '%[^0-9]%' AND LEN(@Username) < 10
			BEGIN
			INSERT INTO #tmp_MemIDs (CustID)
			SELECT cu.custid FROM dbo.Customer cu WITH(NOLOCK) WHERE cu.custid = @Username AND cu.roleid = 1
				AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs c WHERE cu.custid = c.custid)
			END
		END
	END
	-- End Cust Info

	-- Get Sport Bettype Matrix
	DECLARE @isTest BIT = 0
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype (ProductID INT, Bettype INT, EvenType INT, SubProduct VARCHAR(500), RefTable SMALLINT, TypeName NVARCHAR(1000))
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.RefTable
	FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN #tmp_ProductID p ON p.ProductID = s.ProductID

	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID NOT IN (3, 5, 27) -- NumberGame, Virtual Sports, Virtual Sports 2
		AND NOT EXISTS (SELECT b.Bettype FROM #tmp_BetType b WHERE b.Bettype = s.Bettype)
	-- End Sport Bettype Matrix

	-- Handle Sport Type/League/GameType		
	UPDATE s
	SET s.TypeName = b.typenamee
	FROM #SportBettype s
		INNER JOIN dbo.bettype b ON s.Bettype = b.typeid
	WHERE s.ProductID NOT IN (3, 5, 6, 27) -- NG, Virtual Sports, RNG Casino, Virtual Sports 2
	-- End Sport Type/League/GameType

	-- Get Site	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), Srecommend INT, isDeposit BIT)

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site NOT IN ('MBC Group')) -- Deposit Or Credit Drill Down
		BEGIN	
			INSERT INTO #tmp_Company (SiteName, Srecommend, isDeposit)
			SELECT s.Site, c.srecommend, ss.isDeposit
			FROM #tmp_Site s
				INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
				INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
			WHERE c.roleid = 4
		END

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site IN ('MBC Group'))					
		BEGIN
			INSERT INTO #tmp_Company (SiteName, Srecommend, isDeposit)
			SELECT c.site, c.srecommend, 0
			FROM dbo.Customer c WITH (NOLOCK)
			WHERE c.roleid = 4
				AND NOT EXISTS (SELECT 1 FROM dbo.f_DepSuper_1('ALL') f WHERE c.srecommend = f.CustID)
		END			
	END
	-- Don't need to handle 'ALL' site, because with this case we will get all ticket

	CREATE NONCLUSTERED INDEX Idx_SrecommendID ON #tmp_Company (Srecommend)
	-- End Site	

	------------------------------------------II. Get Real Data For Report ------------------------------------------------------
	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans ( Bettype INT, BettypeName NVARCHAR(1000), CustID INT,
						 BetCount BIGINT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets MONEY, TotalBetsBase MONEY,
						 TotalWins MONEY, TotalWinsBase MONEY,
						 TotalRefund MONEY, TotalRefundBase MONEY,
						 CompanyTurnOver MONEY, CompanyTurnOverBase MONEY,
						 CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
						 CompanyComm MONEY, CompanyCommBase MONEY,
						 RefTable SMALLINT, EvenType INT, Matchid INT, ProductID INT
						)
	INSERT INTO #tmp_bettrans
	        ( Bettype ,
			  BettypeName,
			  CustID,
	          BetCount ,
	          CurrencyID ,
	          TotalBets ,
	          TotalBetsBase ,
	          TotalWins ,
	          TotalWinsBase ,
	          TotalRefund ,
	          TotalRefundBase ,
	          CompanyTurnOver ,
	          CompanyTurnOverBase ,
	          CompanyGrossIncome ,
	          CompanyGrossIncomeBase ,
	          CompanyComm ,
	          CompanyCommBase,
			  RefTable,
			  EvenType,
			  Matchid,
			  ProductID
	        )	
	SELECT b.bettype, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.currency,

			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

			SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
			SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
			SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
			SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

			SUM(scomm) AS CompanyComm,
			SUM(scomm *actualrate) AS CompanyCommBase,

			s.RefTable, s.EvenType, 
			CASE WHEN s.ProductID = 27 AND s.EvenType = 0 THEN bm.sporttype ELSE b.matchid END matchid, 
			s.ProductID

	FROM  dbo.bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON s.Bettype = b.bettype
		LEFT JOIN (SELECT DISTINCT bm.refno, m.sporttype
					FROM dbo.bettransm bm WITH (NOLOCK)
						INNER JOIN dbo .match m WITH (NOLOCK) ON bm.matchid = m.matchid
						INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
					) bm ON b.refno = bm.refno
	WHERE b.winlostdate = @WLDate
		AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
		AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		AND (b.currency = @Currency OR @Currency IN (0, -1))
		AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
		AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
		AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
		)
		AND (
			@HousePTType = 0
			OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
			OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
		)
	GROUP BY b.bettype, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, s.RefTable, s.EvenType, 
		CASE WHEN s.ProductID = 27 AND s.EvenType = 0 THEN bm.sporttype ELSE b.matchid END, s.ProductID

	--- Check condition 
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID NOT IN (3, 4, 5, 27)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( Bettype,
				  BettypeName,
				  CustID ,
				  BetCount ,
				  CurrencyID ,	         
				  TotalBets ,
				  TotalBetsBase ,
				  TotalWins ,
				  TotalWinsBase ,
				  TotalRefund ,
				  TotalRefundBase ,
				  CompanyTurnOver ,
				  CompanyTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase
				)
		SELECT b.Bettype, b.BettypeName, b.custid,
				SUM( BetCount ) AS BetCount, b.CurrencyID,

				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase)  AS TotalBetsBase,

				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,

				SUM(TotalRefund) AS TotalRefund,
				SUM(TotalRefundBase) AS TotalRefundBase,

				SUM(CompanyTurnover) AS CompanyTurnover,	
				SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,		
								
				- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
				- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,

				- SUM(CompanyComm) AS CompanyComm,
				- SUM(CompanyCommBase) AS CompanyCommBase

		FROM  #tmp_bettrans b
		WHERE b.RefTable IN (0, 3) AND b.ProductID NOT IN (3, 4, 5, 27)
		GROUP BY b.Bettype, b.BettypeName, b.custid, b.CurrencyID
		
		-- 2a. By Bettype for Casino Product
		INSERT INTO #Data
				( Bettype ,
				  BettypeName,
				  CustID ,
				  BetCount ,
				  CurrencyID ,	          
				  TotalBets ,
				  TotalBetsBase ,
				  TotalWins ,
				  TotalWinsBase ,
				  TotalRefund ,
				  TotalRefundBase ,
				  CompanyTurnOver ,
				  CompanyTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase
				)
		SELECT	b.gameID, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.currency, 

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
		FROM dbo.bettransRnG b WITH (NOLOCK)
			INNER JOIN #SportBettype s ON s.Bettype = b.gameID
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.RefTable = 1		
			AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @Currency OR @Currency IN (0, -1))	
			AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
			AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.gameID, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( Bettype ,
				  BettypeName,
				  CustID ,
				  BetCount ,
				  CurrencyID ,	          
				  TotalBets ,
				  TotalBetsBase ,
				  TotalWins ,
				  TotalWinsBase ,
				  TotalRefund ,
				  TotalRefundBase ,
				  CompanyTurnOver ,
				  CompanyTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase
				)
		SELECT	b.gameID, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
		FROM dbo.bettransLC b WITH (NOLOCK)
			INNER JOIN #SportBettype s ON s.Bettype = b.gameID
		WHERE b.winlostdate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.RefTable = 2	
			AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @Currency OR @Currency IN (0, -1))			
			AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
			AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.gameID, s.TypeName, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency		
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (3, 4, 5))
	BEGIN
		-- 3. NumberGame - Live Casino - Virtual Sport (Soccer)
		INSERT INTO #Data
				( Bettype ,
				  BettypeName,
				  CustID ,
				  BetCount ,
				  CurrencyID ,
				  TotalBets ,
				  TotalBetsBase ,
				  TotalWins ,
				  TotalWinsBase ,
				  TotalRefund ,
				  TotalRefundBase ,
				  CompanyTurnOver ,
				  CompanyTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase
				)	
		SELECT	CASE WHEN b.ProductID = 3 THEN m.leagueid WHEN b.ProductID = 4 THEN b.Bettype ELSE m.sporttype END AS Bettype, 
				CASE WHEN b.ProductID = 4 THEN b.BettypeName ELSE '' END AS BettypeName,
				b.custid,
				SUM( BetCount ) AS BetCount, b.CurrencyID,

				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase)  AS TotalBetsBase,

				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,

				SUM(TotalRefund) AS TotalRefund,
				SUM(TotalRefundBase) AS TotalRefundBase,

				SUM(CompanyTurnover) AS CompanyTurnover,	
				SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,		
								
				- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
				- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,

				- SUM(CompanyComm) AS CompanyComm,
				- SUM(CompanyCommBase) AS CompanyCommBase

		FROM  #tmp_bettrans b
			INNER JOIN dbo.match m WITH (NOLOCK) ON m.matchid = b.matchid
		WHERE b.EvenType = 1 AND b.ProductID IN (3,4,5)
			AND (
				(b.ProductID = 3 AND (@LeagueId = '' OR (EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = m.leagueid)))) OR
				(b.ProductID = 4 AND (@GameTableId = '' OR (EXISTS (SELECT 1 FROM #tmp_GameTableID g WHERE g.GameTableID = m.leagueid)))) OR
				(b.ProductID = 5 AND (@Sporttype = '' OR (EXISTS (SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = m.sporttype))))
			)	
		GROUP BY CASE WHEN b.ProductID = 3 THEN m.leagueid WHEN b.ProductID = 4 THEN b.Bettype ELSE m.sporttype END, 
			CASE WHEN b.ProductID = 4 THEN b.BettypeName ELSE '' END,
			b.custid, b.CurrencyID
	
		-- 4. Virtual Sport (HR)
		INSERT INTO #Data
				( Bettype ,
				  CustID ,
				  BetCount ,
				  CurrencyID ,	          
				  TotalBets ,
				  TotalBetsBase ,
				  TotalWins ,
				  TotalWinsBase ,
				  TotalRefund ,
				  TotalRefundBase ,
				  CompanyTurnOver ,
				  CompanyTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase
				)
		SELECT	r.SportType, b.custid,
				SUM( BetCount ) AS BetCount, b.CurrencyID,

				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase)  AS TotalBetsBase,

				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,

				SUM(TotalRefund) AS TotalRefund,
				SUM(TotalRefundBase) AS TotalRefundBase,

				SUM(CompanyTurnover) AS CompanyTurnover,	
				SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,		
								
				- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
				- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,

				- SUM(CompanyComm) AS CompanyComm,
				- SUM(CompanyCommBase) AS CompanyCommBase

		FROM  #tmp_bettrans b
			INNER JOIN dbo.VSRaceInfo r WITH (NOLOCK) ON r.EventID = b.matchid
		WHERE b.ProductID = 5
			AND b.EvenType = 3
			AND (@Sporttype = '' OR (EXISTS(SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = r.SportType)))			  
		GROUP BY r.SportType, b.custid, b.CurrencyID
	END
	
	-- Virtual Sports 2
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)
	BEGIN
		INSERT INTO #Data
					( Bettype ,
					  BettypeName,
					  CustID ,
					  BetCount ,
					  CurrencyID ,
					  TotalBets ,
					  TotalBetsBase ,
					  TotalWins ,
					  TotalWinsBase ,
					  TotalRefund ,
					  TotalRefundBase ,
					  CompanyTurnOver ,
					  CompanyTurnOverBase ,
					  CompanyGrossIncome ,
					  CompanyGrossIncomeBase ,
					  CompanyComm ,
					  CompanyCommBase
					)	
			SELECT	CASE WHEN b.EvenType = 0 THEN b.Matchid ELSE m.sporttype END AS Sporttype, 
					'' AS BettypeName,
					b.custid,
					SUM( BetCount ) AS BetCount, b.CurrencyID,

					SUM(TotalBets) AS TotalBets,
					SUM(TotalBetsBase)  AS TotalBetsBase,

					SUM(TotalWins) AS TotalWins,
					SUM(TotalWinsBase) AS TotalWinsBase,

					SUM(TotalRefund) AS TotalRefund,
					SUM(TotalRefundBase) AS TotalRefundBase,

					SUM(CompanyTurnover) AS CompanyTurnover,	
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,		
									
					- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
					- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,

					- SUM(CompanyComm) AS CompanyComm,
					- SUM(CompanyCommBase) AS CompanyCommBase

			FROM  #tmp_bettrans b
				LEFT JOIN dbo.match m WITH (NOLOCK) ON m.matchid = b.matchid
			WHERE b.ProductID = 27
				AND ((b.EvenType = 0 AND EXISTS(SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = b.Matchid))
					OR (m.matchid IS NOT NULL AND EXISTS(SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = m.sporttype))
					)				
			GROUP BY CASE WHEN b.EvenType = 0 THEN b.Matchid ELSE m.sporttype END, 
					b.custid, b.CurrencyID
	END

	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name

	DECLARE @IsDrillDownFromRM INT
	SELECT @IsDrillDownFromRM = COUNT (*) FROM #tmp_SportType

	IF (EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 6)) AND @IsDrillDownFromRM = 1
	BEGIN		
		DELETE d		
		FROM #Data d
		WHERE NOT EXISTS (SELECT 1 
						FROM dbo.SportBettypeMatrix m WITH (NOLOCK) 							
						WHERE m.ProductID = 6 AND d.Bettype = m.BetType 
							AND m.SportType IN (SELECT Sporttype FROM #tmp_SportType)						
						)															
	END
	-- Get Bettype Name
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		UPDATE d
		SET d.BettypeName = l.leaguename
		FROM #Data d 
			INNER JOIN dbo.league l WITH (NOLOCK) ON d.Bettype = l.leagueid
	END
	ELSE IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (5,27))
	BEGIN
		UPDATE d
		SET d.BettypeName = s.SportName
		FROM #Data d 
			INNER JOIN dbo.Sports s WITH (NOLOCK) ON d.Bettype = s.SportType
	END
	ELSE IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 6)
	BEGIN
		UPDATE d
		SET d.BettypeName = s.SportName
		FROM #Data d 
			INNER JOIN dbo.SportBettypeMatrix m WITH (NOLOCK) ON d.Bettype = m.BetType
			INNER JOIN dbo.Sports s WITH (NOLOCK) ON m.SportType = s.SportType

		UPDATE d
		SET d.Bettype = s.SportType
		FROM #Data d 
			INNER JOIN dbo.SportBettypeMatrix m WITH (NOLOCK) ON d.Bettype = m.BetType
			INNER JOIN dbo.Sports s WITH (NOLOCK) ON m.SportType = s.SportType
	END
	-- End Bettype Name
		
	------------------------------------------III. Drill down data ------------------------------------------------------

	IF @Currency = -1 -- BaseRM
	BEGIN		
		INSERT INTO #Result
			(	Bettype,
				BettypeName ,
			    NoOfPlayers ,
			    BetCount ,
			    CurrencyID ,
			    Currency ,
			    TotalBets ,
			    TotalWins ,
			    TotalRefund ,
			    CompanyTurnOver ,
			    CompanyGrossIncome ,
			    CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnOverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase
			    )
		SELECT b.Bettype, b.BettypeName,
			COUNT(DISTINCT b.CustID) AS NoOfPlayers,
			SUM(b.BetCount) AS BetCount,
			-1 AS CurrencyID,
			'RM' AS Currency,
			SUM(b.TotalBetsBase) AS TotalBets,
			SUM(b.TotalWinsBase) AS TotalWins,
			SUM(b.TotalRefundBase) AS TotalRefund,
			SUM(b.CompanyTurnOverBase) AS CompanyTurnOver,
			SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncome,            
			SUM(b.CompanyCommBase) AS CompanyComm,
			SUM(b.TotalBetsBase) AS TotalBetsBase,
			SUM(b.TotalWinsBase) AS TotalWinsBase,
			SUM(b.TotalRefundBase) AS TotalRefundBase,
			SUM(b.CompanyTurnOverBase) AS CompanyTurnOverBase,
			SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,            
			SUM(b.CompanyCommBase) AS CompanyCommBase
		FROM #Data b
		GROUP BY b.Bettype, b.BettypeName
		HAVING (@TotalBetType = 0
			OR (@TotalBetType = 1 AND SUM(b.TotalBetsBase) >= @TotalBetValue) 
			OR (@TotalBetType = -1 AND SUM(b.TotalBetsBase) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
			OR (@GameIncomeType = 1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) >= @GameIncomeValue) 
			OR (@GameIncomeType = -1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
				)		
	END
	ELSE -- @Currency <> -1 => Original Currency
	BEGIN
		INSERT INTO #Result
		    (	Bettype,
				BettypeName ,
		        NoOfPlayers ,
		        BetCount ,
		        CurrencyID ,
		        Currency ,
		        TotalBets ,
		        TotalWins ,
		        TotalRefund ,
		        CompanyTurnOver ,
		        CompanyGrossIncome ,
		        CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnOverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase
		        )
		SELECT b.Bettype, b.BettypeName,
				COUNT(DISTINCT b.custid) NoOfPlayers,
				SUM(b.BetCount) BetCount,
				b.CurrencyId AS CurrencyId,
				b.currency AS Currency,				
				SUM(b.TotalBets) AS TotalBets,
				SUM(b.TotalWins) AS TotalWins,
				SUM(b.TotalRefund) AS TotalRefund,
				SUM(b.CompanyTurnOver) AS CompanyTurnOver,
				SUM(b.CompanyGrossIncome) AS CompanyGrossIncome,            
				SUM(b.CompanyComm) AS CompanyComm,
				SUM(b.TotalBetsBase) AS TotalBetsBase,
				SUM(b.TotalWinsBase) AS TotalWinsBase,
				SUM(b.TotalRefundBase) AS TotalRefundBase,
				SUM(b.CompanyTurnOverBase) AS CompanyTurnOverBase,
				SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,            
				SUM(b.CompanyCommBase) AS CompanyCommBase
			FROM #Data b
			GROUP BY b.Bettype, b.BettypeName, b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(b.TotalBets) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(b.TotalBets) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(b.TotalBets - b.TotalWins) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(b.TotalBets - b.TotalWins) <= @GameIncomeValue)
					)
	END	
	
	-- Return Detail data
	IF @IsGrandTotal = 0
	BEGIN		
		IF @IsDrillDown = 0
		BEGIN
			SELECT  Bettype AS ReportById,
					BettypeName AS ReportBy, 
					NoOfPlayers,
					BetCount,
					CurrencyId,
					Currency,
					TotalBets,
					TotalWins,
					TotalRefund,
					CompanyTurnOver,
					CompanyGrossIncome,
					CompanyComm 
			FROM #Result	
			ORDER BY BettypeName, Currency		
		END
		ELSE
		BEGIN
			SELECT b.Bettype AS ReportById,
				b.BettypeName AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS CompanyTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS CompanyGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS CompanyComm
		
			FROM #Data b	
				INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.BettypeName = r.BettypeName	
			GROUP BY b.Bettype, b.BettypeName, b.CurrencyID , b.Currency	
			ORDER BY b.Currency
		END
	END		
	ELSE
	BEGIN
		SELECT  d.CurrencyId AS ReportById,
				d.Currency AS ReportBy, 
				d.CurrencyId,
				d.Currency,
				COUNT(DISTINCT d.CustID) AS NoOfPlayers,
				SUM(d.BetCount) AS BetCount,
				CASE WHEN @Currency = -1 THEN SUM(d.TotalBetsBase) ELSE SUM(d.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(d.TotalWinsBase) ELSE SUM(d.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(d.TotalRefundBase) ELSE SUM(d.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyTurnOverBase) ELSE SUM(d.CompanyTurnOver) END AS CompanyTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyGrossIncomeBase) ELSE SUM(d.CompanyGrossIncome) END AS CompanyGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyCommBase) ELSE SUM(d.CompanyComm) END AS CompanyComm
		
		FROM #Result r
			INNER JOIN #Data d ON (r.CurrencyID = -1 OR r.CurrencyID = d.CurrencyID) AND d.BettypeName = r.BettypeName
		GROUP BY d.CurrencyId, d.Currency
		ORDER BY ReportBy
	END	
	
	------------------------------------------IV. Return Total Rows ------------------------------------------------------
	SELECT
        'GrandTotal' AS ReportBy,
        COUNT(DISTINCT d.CustID) AS NoOfPlayers,
        SUM(d.BetCount) BetCount,
        2 as CurrencyId, 
        'RM' AS Currency,
        SUM(d.TotalBetsBase) TotalBets,
        SUM(d.TotalWinsBase) TotalWins,
        SUM(d.TotalRefundBase) TotalRefund,
        SUM(d.CompanyTurnOverBase) CompanyTurnOver,
		SUM(d.CompanyGrossIncomeBase) CompanyGrossIncome,
		SUM(d.CompanyCommBase) CompanyComm
    FROM #Result r
		INNER JOIN #Data d ON (r.CurrencyID = -1 OR r.CurrencyID = d.CurrencyID) AND r.Bettype = d.Bettype

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #tmp_Company
	DROP TABLE #tmp_Devide
	DROP TABLE #tmp_GameTableID
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_SportType
	DROP TABLE #tmp_bettrans
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Product_SportLeagueGameType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Product_SportLeagueGameType] TO [vnteam];
GO

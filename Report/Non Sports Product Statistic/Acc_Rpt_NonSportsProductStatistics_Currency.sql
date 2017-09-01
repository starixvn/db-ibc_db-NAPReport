USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Currency]
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
	@DrillDownCurrency	SMALLINT = 0,
	@IsGrandTotal	BIT = 0 -- don't need to use in this report
AS
/*
	Created	: 20161114@Harper
	Task	: #62430_Non Sports Product Statistic - Currency Report
	DB		: DBACC/bodb02
	
	Revision:
		- 20170227@Percy: support search multiple username [RedmineID: #71342]
		- 20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		- 20170815@Cherry: Non-Sport Statistics Phase 5 (#71923)

	Param's Explanation:
		- @Username:  + Search by keyword, member only
		- @Site: List of Company filter
			'ALL': All sites (MBC + Licensees)
			'MBC': MBC sites only
			'12bet' : Specific Licensee Name 
		- @ProductID: string filter by Product 
		- @BetType: string filter by bettype
		- @LeagueId: string filter by LeagueId (ProductID = 3 - Number Game get LeagueId)  
		- @Sporttype: string filter by Sporttype (ProductID = 5 - Virtual Sports get Sporttype)
		- @GameTableId: filter by specific game table (ProductID = 4 - Live Casino get leagueID)
		- @Currency: 
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
		- @DrillDownCurrency: 
			0	: Not drilldown
			> 0	: drilldown with this currency to Company level

	exec Acc_Rpt_NonSportsProductStatistics_Currency_14 @TotalBetValue=0.0000,@Sporttype='',@ProductId='21',
	@Username='',@BetType='2401,2405,2403,2404,2402',@GameIncomeValue=0.0000,
	@HousePTValue=0.0000,@HousePTType=0,@GameIncomeType=0,@TotalBetType=0,@WinlostDate='2016-11-06 00:00:00',
	@DrillDownCurrency=47,@ExcludeTest=1,@LeagueId='',@Device='a,d,e,h,i,f,j,l,m,n,p,s,u,w',
	@GameTableId='',@Currency=-1,@Site='All'
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
					NULL AS Reportby,
					NULL AS Currency,
					NULL AS CurrencyID,
					NULL AS NoOfPlayers,
					NULL AS BetCount,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnOver,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm
			) A

			-- grand total
			SELECT
				'Grand Total RM' AS ReportBy,
				'RM' AS Currency,
				0 AS CurrencyID,
				NULL AS NoOfPlayers,
				NULL AS BetCount,
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

	CREATE TABLE #Data ( recommend INT, CustID INT,
						 BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets MONEY, TotalBetsBase MONEY,
						 TotalWins MONEY, TotalWinsBase MONEY,
						 TotalRefund MONEY, TotalRefundBase MONEY,
						 CompanyTurnOver MONEY, CompanyTurnOverBase MONEY,
						 CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
						 CompanyComm MONEY, CompanyCommBase MONEY
						)

	CREATE TABLE #ResultByCompany (  
							IsDeposit BIT, SiteName VARCHAR(50), NoOfPlayers INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets MONEY, TotalBetsBase MONEY,
							TotalWins MONEY, TotalWinsBase MONEY,
							TotalRefund MONEY, TotalRefundBase MONEY,
							CompanyTurnOver MONEY, CompanyTurnOverBase MONEY,
							CompanyGrossIncome MONEY, CompanyGrossIncomeBase MONEY,
							CompanyComm MONEY, CompanyCommBase MONEY							
						)

	CREATE TABLE #ResultByCurrency (  
							CurrencyID INT, Currency NVARCHAR(50),
							NoOfPlayers INT, BetCount INT, 
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

	CREATE TABLE #SportBettype (ProductID INT, Bettype INT, EvenType INT, SubProduct VARCHAR(500), RefTable SMALLINT)
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, SubProduct, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.SubProduct, s.RefTable
	FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN #tmp_ProductID p ON p.ProductID = s.ProductID

	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID NOT IN (3, 5, 27) -- NumberGame, Virtual Sports, Virtual Sports 2
		AND NOT EXISTS (SELECT b.Bettype FROM #tmp_BetType b WHERE b.Bettype = s.Bettype)
	-- End Sport Bettype Matrix

	-- Get Site	
	CREATE TABLE #recommend (SiteName VARCHAR(50), recommend INT, isDeposit BIT)

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site NOT IN ('MBC Group')) -- Deposit Or Credit Drill Down
		BEGIN	
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT s.Site, c.recommend, ss.isDeposit
			FROM #tmp_Site s
				INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
				INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
			WHERE c.roleid = 2
		END

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site IN ('MBC Group'))					
		BEGIN
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT c.site, c.recommend, 0
			FROM dbo.Customer c WITH (NOLOCK)
			WHERE c.roleid = 2
				AND NOT EXISTS (SELECT 1 FROM dbo.f_DepSuper_1('ALL') f WHERE c.srecommend = f.CustID)
		END
		
	END
	ELSE -- ALL
	BEGIN
		INSERT INTO #recommend (SiteName, recommend, isDeposit)
		SELECT ss.site, c.recommend, ss.isDeposit
		FROM dbo.Customer c WITH (NOLOCK) 
			INNER JOIN dbo.Site ss WITH (NOLOCK) ON ss.Site = c.site
		WHERE c.roleid = 2	
	END

	CREATE NONCLUSTERED INDEX Idx_recommendID ON #recommend (recommend)
	-- End Site	

	------------------------------------------II. Get Real Data For Report ------------------------------------------------------
	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans ( recommend INT, CustID INT,
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
	        ( recommend ,
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
	          CompanyCommBase,
			  RefTable,
			  EvenType,
			  Matchid,
			  ProductID
	        )	
	SELECT b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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

				s.RefTable, s.EvenType, b.matchid, s.ProductID

	FROM  dbo.bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON s.Bettype = b.bettype
	WHERE b.winlostdate = @WLDate
		AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
		AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		AND (b.currency = @Currency OR @Currency IN (0, -1))
		AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
		AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
		AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
		AND (
			@HousePTType = 0
			OR (@HousePTType = -1 AND b.tpositiontaking >= 1 - @HousePTValue) -- 1-tpositiontaking <= @HousePTValue
			OR (@HousePTType = 1 AND b.tpositiontaking <= 1 - @HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		AND b.bettype <> 2799 AND b.matchid >= 0
	GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, s.RefTable, s.EvenType, b.matchid, s.ProductID	

	--Mix Parlay Virtual Sports 2
	INSERT INTO #tmp_bettrans
	        ( recommend ,
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
	          CompanyCommBase,
			  RefTable,
			  EvenType,
			  Matchid,
			  ProductID
	        )	
	SELECT b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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

				s.RefTable, s.EvenType, b.matchid, s.ProductID

	FROM  dbo.bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON s.Bettype = b.bettype
	WHERE b.winlostdate = @WLDate
		AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
		AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
		AND (b.currency = @Currency OR @Currency IN (0, -1))
		AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
		AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
		AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
		AND (
			@HousePTType = 0
			OR (@HousePTType = -1 AND b.tpositiontaking >= 1 - @HousePTValue) -- 1-tpositiontaking <= @HousePTValue
			OR (@HousePTType = 1 AND b.tpositiontaking <= 1 - @HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		AND b.bettype = 2799 AND b.matchid = 2799
		AND EXISTS (SELECT 1 FROM dbo.bettransm bm WITH (NOLOCK)
									INNER JOIN dbo.match m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno)			
	GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, s.RefTable, s.EvenType, b.matchid, s.ProductID	

	--- Check condition 
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID NOT IN (3, 4, 5, 27)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( recommend,
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
		SELECT b.recommend, b.custid,
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
		GROUP BY b.recommend, b.custid, b.CurrencyID
		
		-- 2a. By Bettype for Casino Product
		INSERT INTO #Data
				( recommend ,
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
		SELECT	b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1 - @HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1 - @HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				) 
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( recommend ,
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
		SELECT	b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1 - @HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1 - @HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency		
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (3, 4, 5))
	BEGIN
		-- 3. NumberGame - Live Casino - Virtual Sport (Soccer)
		INSERT INTO #Data
				( recommend ,
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
		SELECT	b.recommend, b.custid,
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
		WHERE b.EvenType = 1
			AND b.ProductID IN (3, 4, 5)
			AND (
				(b.ProductID = 3 AND (@LeagueId = '' OR (EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = m.leagueid)))) OR
				(b.ProductID = 4 AND (@GameTableId = '' OR (EXISTS (SELECT 1 FROM #tmp_GameTableID g WHERE g.GameTableID = m.leagueid)))) OR
				(b.ProductID = 5 AND (@Sporttype = '' OR (EXISTS (SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = m.sporttype))))
			)	
		GROUP BY b.recommend, b.custid, b.CurrencyID
	
		-- 4. Virtual Sport (HR)
		INSERT INTO #Data
				( recommend ,
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
		SELECT	b.recommend, b.custid,
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
		GROUP BY b.recommend, b.custid, b.CurrencyID
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)
	BEGIN
		-- Betradar Virtual Sport 
		INSERT INTO #Data
				( recommend ,
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
		SELECT	b.recommend, b.custid,
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
		WHERE b.ProductID = 27
			AND (b.EvenType = 0 OR
				(EXISTS (SELECT 1 FROM dbo.match m WITH (NOLOCK)
								INNER JOIN #tmp_SportType st ON m.Sporttype = st.sporttype
						 WHERE b.Matchid = m.matchid))
			)	
		GROUP BY b.recommend, b.custid, b.CurrencyID
	END

	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name

	------------------------------------------III. Drill down data ------------------------------------------------------

	IF @DrillDownCurrency = 0 -- Report with level 1 - Not Drilldown
	BEGIN
		IF @Currency = -1 -- Base RM
		BEGIN
			INSERT INTO #ResultByCurrency
			        ( CurrencyID ,
			          Currency ,
			          NoOfPlayers ,
			          BetCount ,
			          TotalBets ,
			          TotalWins ,
			          TotalRefund ,
			          CompanyTurnOver ,
			          CompanyGrossIncome ,
			          CompanyComm 
			        )
			SELECT b.CurrencyID,
					b.Currency,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(b.BetCount) AS BetCount,
					SUM(b.TotalBetsBase) AS TotalBets,
					SUM(b.TotalWinsBase) AS TotalWins,
					SUM(b.TotalRefundBase) AS TotalRefund,
					SUM(b.CompanyTurnOverBase) AS CompanyTurnOver,
					SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncome,
					SUM(b.CompanyCommBase) AS CompanyComm
			FROM #Data b
			GROUP BY b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
					OR (@TotalBetType = 1 AND SUM(b.TotalBetsBase) >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND SUM(b.TotalBetsBase) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
					)
		END
		ELSE -- Original Currency
		BEGIN
			INSERT INTO #ResultByCurrency
			        ( CurrencyID ,
			          Currency ,
			          NoOfPlayers ,
			          BetCount ,
			          TotalBets ,
			          TotalWins ,
			          TotalRefund ,
			          CompanyTurnOver ,
			          CompanyGrossIncome ,
			          CompanyComm 
			        )
			SELECT b.CurrencyID,
					b.Currency,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(b.BetCount) AS BetCount,
					SUM(b.TotalBets) AS TotalBets,
					SUM(b.TotalWins) AS TotalWins,
					SUM(b.TotalRefund) AS TotalRefund,
					SUM(b.CompanyTurnOver) AS CompanyTurnOver,
					SUM(b.CompanyGrossIncome) AS CompanyGrossIncome,
					SUM(b.CompanyComm) AS CompanyComm
			FROM #Data b
			GROUP BY b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
					OR (@TotalBetType = 1 AND SUM(b.TotalBets) >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND SUM(b.TotalBets) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND SUM(b.TotalBets - b.TotalWins) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND SUM(b.TotalBets - b.TotalWins) <= @GameIncomeValue)
					)
		END
	END
	ELSE -- @DrillDownCurrency > 0 => Drilldown with selected Currency to Company level
	BEGIN
		IF @Currency = -1 -- Base RM
		BEGIN
			INSERT INTO #ResultByCompany
		        ( SiteName ,
		          NoOfPlayers ,
		          BetCount ,
		          CurrencyID ,
		          Currency ,
		          TotalBets ,
		          TotalWins ,
		          TotalRefund ,
		          CompanyTurnOver ,
		          CompanyGrossIncome ,
		          CompanyComm
		        )
			SELECT c.SiteName,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(b.BetCount) AS BetCount,
					b.CurrencyID AS CurrencyID,
					b.Currency AS Currency,
					SUM(b.TotalBetsBase) AS TotalBets,
					SUM(b.TotalWinsBase) AS TotalWins,
					SUM(b.TotalRefundBase) AS TotalRefund,
					SUM(b.CompanyTurnOverBase) AS CompanyTurnOver,
					SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncome,
					SUM(b.CompanyCommBase) AS CompanyComm
			FROM #Data b
				INNER JOIN #recommend c ON b.recommend = c.recommend
			GROUP BY c.SiteName, b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
					OR (@TotalBetType = 1 AND SUM(b.TotalBetsBase) >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND SUM(b.TotalBetsBase) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
					)

		END
		ELSE -- Original Currency
		BEGIN
			INSERT INTO #ResultByCompany
		        ( SiteName ,
		          NoOfPlayers ,
		          BetCount ,
		          CurrencyID ,
		          Currency ,
		          TotalBets ,
		          TotalWins ,
		          TotalRefund ,
		          CompanyTurnOver ,
		          CompanyGrossIncome ,
		          CompanyComm
		        )
			SELECT c.SiteName,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(b.BetCount) AS BetCount,
					b.CurrencyID AS CurrencyID,
					b.Currency AS Currency,
					SUM(b.TotalBets) AS TotalBets,
					SUM(b.TotalWins) AS TotalWins,
					SUM(b.TotalRefund) AS TotalRefund,
					SUM(b.CompanyTurnOver) AS CompanyTurnOver,
					SUM(b.CompanyGrossIncome) AS CompanyGrossIncome,
					SUM(b.CompanyComm) AS CompanyComm
			FROM #Data b
				INNER JOIN #recommend c ON b.recommend = c.recommend
			GROUP BY c.SiteName, b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
					OR (@TotalBetType = 1 AND SUM(b.TotalBets) >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND SUM(b.TotalBets) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND SUM(b.TotalBets - b.TotalWins) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND SUM(b.TotalBets - b.TotalWins) <= @GameIncomeValue)
					)
		END
	END

	------------------------------------------IV. Return Total Rows ------------------------------------------------------
	
	IF @DrillDownCurrency = 0
	BEGIN
		SELECT Currency AS Reportby,
			Currency AS Currency,
			CurrencyID,
			NoOfPlayers,
			BetCount,
			TotalBets,
			TotalWins,
			TotalRefund,
			CompanyTurnOver AS HouseTurnOver,
			CompanyGrossIncome AS HouseGrossIncome,
			CompanyComm AS HouseComm
		FROM #ResultByCurrency
		ORDER BY Currency

		SELECT 'Grand Total RM' AS ReportBy,
			'RM' AS Currency,
			0 AS CurrencyID,
			COUNT(DISTINCT custid) AS NoOfPlayers,
			SUM(b.BetCount) AS BetCount,
			SUM(b.TotalBetsBase) AS TotalBets,
			SUM(b.TotalWinsBase) AS TotalWins,
			SUM(b.TotalRefundBase) AS TotalRefund,
			SUM(b.CompanyTurnOverBase) AS HouseTurnOver,
			SUM(b.CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM(b.CompanyCommBase) AS HouseComm
		FROM #Data b
			INNER JOIN #ResultByCurrency c ON b.CurrencyID = c.CurrencyID
	END
	ELSE -- @DrillDownCurrency > 0 => Drill down to Company
	BEGIN
		SELECT SiteName AS Reportby,			
			NoOfPlayers,
			BetCount,
			Currency,
			TotalBets,
			TotalWins,
			TotalRefund,
			CompanyTurnOver AS HouseTurnOver,
			CompanyGrossIncome AS HouseGrossIncome,
			CompanyComm AS HouseComm
		FROM #ResultByCompany
		ORDER BY SiteName

		SELECT 'Grand Total RM' AS ReportBy,			
			COUNT(DISTINCT custid) AS NoOfPlayers,
			SUM(b.BetCount) AS BetCount,
			'RM' AS Currency,
			SUM(b.TotalBetsBase) AS TotalBets,
			SUM(b.TotalWinsBase) AS TotalWins,
			SUM(b.TotalRefundBase) AS TotalRefund,
			SUM(b.CompanyTurnOverBase) AS HouseTurnOver,
			SUM(b.CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM(b.CompanyCommBase) AS HouseComm
		FROM #Data b			
		WHERE EXISTS ( SELECT 1 
					   FROM #recommend c INNER JOIN #ResultByCompany s ON c.SiteName = s.SiteName 
					   WHERE b.recommend = c.recommend)
	END

	DROP TABLE #Data
	DROP TABLE #ResultByCompany
	DROP TABLE #ResultByCurrency
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #recommend
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

GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Currency] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Currency] TO [vnteam];
GO


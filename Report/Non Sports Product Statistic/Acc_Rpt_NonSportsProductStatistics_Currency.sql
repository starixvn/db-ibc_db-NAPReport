/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

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
		20170227@Percy: support search multiple username [RedmineID: #71342]
		20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		20170815@Cherry: Non-Sport Statistics Phase 5 (#71923)
		20171006@Cherry: Add filter of Number Game Bettype (#83101)
		20180328@Cherry: Integrate One RNG Jackpot (#89459)
		20180808@Cherry: Integrate Poker Games (#97809)
		20181018@Cherry: Integrate NG2 (#102229)
		20181108@Cherry: Improve performance (#101547)

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
	
	DECLARE @WLDate SMALLDATETIME
	SELECT @WLDate = CAST (@WinlostDate AS SMALLDATETIME)

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
	CREATE TABLE #tmp_LeagueID		(LeagueID INT, Bettype INT)
	CREATE TABLE #tmp_SportType		(Sporttype INT)
	CREATE TABLE #tmp_GameTableID	(GameTableID INT)
	CREATE TABLE #tmp_Device		(Betfrom NVARCHAR(2))
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
			INSERT INTO #tmp_LeagueID(LeagueID, Bettype) VALUES (@league, @bettypeid)
			SET @start = @charindex1 +1
			SET @charindex1 = charindex(@splitter1, @LeagueID, @start)          
		END
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

	CREATE TABLE #Device (Betfrom NVARCHAR(2))
	IF @Device <> ''
	BEGIN
		INSERT INTO #tmp_Device (Betfrom)
		SELECT val FROM dbo.strSplit(@Device, ',')	
		
		INSERT INTO #Device (Betfrom)
		SELECT Betfrom
		FROM DBWH.bodb_Account.dbo.tbl_Betfrom
		WHERE betfrom NOT IN ('t', 'b')

		IF NOT EXISTS(SELECT 1 FROM #Device d LEFT JOIN #tmp_Device t ON t.Betfrom = d.Betfrom WHERE t.Betfrom IS NULL) 
			SET @Device = ''	
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
	WHERE s.ProductID NOT IN (3, 5, 27, 23) -- NumberGame, Virtual Sports, Virtual Sports 2, NG2
		AND NOT EXISTS (SELECT b.Bettype FROM #tmp_BetType b WHERE b.Bettype = s.Bettype)
		
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID = 23 --NG2
		AND NOT EXISTS (SELECT b.Bettype 
						FROM #tmp_SportType st INNER JOIN bodb02.dbo.SportBettypeMatrix b WITH(NOLOCK) ON st.Sporttype = b.SportType 
						WHERE b.BetType = s.Bettype AND (b.IsTest = 0 OR b.IsTest = @isTest))
		
	-- End Sport Bettype Matrix

	-- Get Site	
	CREATE TABLE #recommend (SiteName VARCHAR(50), recommend INT, isDeposit BIT)
	CREATE TABLE #DepositSuper (CustId INT)

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
			INSERT INTO #DepositSuper
			SELECT CustId
			FROM f_DepSuper_1( 'All' )
			
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT c.site, c.recommend, 0
			FROM dbo.Customer c WITH (NOLOCK)
				LEFT JOIN #DepositSuper s ON c.srecommend = s.CustId 
			WHERE c.roleid = 2
				AND s.CustId IS NULL
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

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sport 2
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
		SELECT b.recommend, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency, 

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

		FROM  dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
		
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
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM dbo.bettransRnG b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE Bettype NOT IN (2198, 2398, 2998) AND RefTable = 1)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
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
				0 AS BetCount, b.currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase
		FROM dbo.bettransRnG b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE Bettype IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
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
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency		
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33) --Poker Games
	BEGIN
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
		SELECT b.recommend, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				SUM(CASE WHEN b.statusID IN (111, 112, 113) THEN b.betid ELSE 0 END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				0 AS CompanyTurnover,	
				0 AS CompanyTurnoverBase,			
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,


				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase

		FROM  dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
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
		SELECT	b.recommend, 
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

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid  AND l.Bettype = b.bettype)
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
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
		SELECT	b.recommend, 
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

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_GameTableId g ON g.GameTableID = m.LeagueID WHERE m.matchid = b.matchid)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
	END
		
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
	BEGIN
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
		SELECT	b.recommend, 
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

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_Sporttype sp ON sp.Sporttype = m.sporttype WHERE m.matchid = b.matchid)	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
	
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
		SELECT	b.recommend, 
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

		FROM  dbo.Bettrans b WITH (NOLOCK)
			INNER JOIN VSRaceInfo r WITH (NOLOCK) ON r.EventId = b.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND Eventype = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@Sporttype = '' OR
					EXISTS (SELECT 1 From #tmp_Sporttype sp WHERE sp.Sporttype = r.sporttype)					
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)				  
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
	END
	
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27) -- Virtual Sports 2 
	BEGIN				
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
		SELECT	b.recommend, 
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
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS(SELECT 1 FROM dbo.match m WITH (NOLOCK) 
									INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype 
								WHERE m.matchid = b.matchid)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
		
		--Mix parlay Virtual Sport 2
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
		
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
		SELECT	b.recommend, 
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
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS(SELECT 1 FROM #tmp_bettransm bm WHERE bm.refno = b.refno)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			AND (@DrillDownCurrency = 0 OR b.currency = @DrillDownCurrency)
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency
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
	DROP TABLE #tmp_Device
	DROP TABLE #tmp_GameTableID
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_SportType
	DROP TABLE #tmp_bettransm
	DROP TABLE #DepositSuper
	DROP TABLE #Device
	
END



/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Product_BettypeGameTable]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
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
		20170227@Percy: support search multiple username [RedmineID: #71342]
		20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		20170815@Cherry: Non-Sport Statistics Phase 5 (#71923)
		20171006@Cherry: Add filter of Number Game Bettype (#83101)
		20180328@Cherry: Integrate One RNG Jackpot (#89459)
		20180808@Cherry: Integrate Poker Games (#97809)
		20181018@Cherry: Integrate NG2 (#102229)
		20181108@Cherry: Improve performance (#101547)
		20190214@Cherry: Integrate Video Poker Games (#108735)
		20190322@Cherry: Add betfrom b,f (#110653)
		20190510@Cherry: Appy ExtraPT (#111676)
		20190724@Cherry: ExtraPT in House Turnover (#116766)
		20190812@Cherry: Add betfrom t (#115937)
		20191225@Cherry: Apply ExtraPT in bettrans table (#123697)

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

	EXEC [Acc_Rpt_NonSportsProductStatistics_Product_BettypeGameTable] @WinlostDate = '2016-11-20',
	@ProductID = '6', 
	@Bettype = '1103',
 	@LeagueID = '15223',
 	@Sporttype = '180',
 	@Device = 'a,d,e,f,h,i,j,l,m,n,p,s,t,u,w',
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
					NULL AS CompanyComm,
					NULL AS ExtraPT
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
				NULL AS CompanyComm,
				NULL AS ExtraPT
			RETURN
		END
	END
	
	DECLARE @WLDate SMALLDATETIME
	SELECT @WLDate = CAST(@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #Data ( ReportBy INT, ReportByName NVARCHAR(1000), 
	                     CustID INT, bettype INT, srecommend INT,
						 BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						 CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
						 ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)
						)
	CREATE TABLE #Result (  ReportBy INT, ReportByName NVARCHAR(1000), NoOfPlayers INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
							TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
							TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
							CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
							CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
							CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
							ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)							
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
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))		

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

	CREATE TABLE #Device (Betfrom NVARCHAR(2))
	IF @Device <> ''
	BEGIN
		INSERT INTO #tmp_Device (Betfrom)
		SELECT val FROM dbo.strSplit(@Device, ',')
		
		INSERT INTO #Device (Betfrom)
		SELECT Betfrom
		FROM DBWH.bodb_Account.dbo.tbl_Betfrom

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

	CREATE TABLE #SportBettype (ProductID INT, Bettype INT, EvenType INT, SubProduct VARCHAR(500), RefTable SMALLINT, TypeName NVARCHAR(1000))
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.RefTable
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

	DECLARE @IsDrillDownFromRM INT
	SELECT @IsDrillDownFromRM = COUNT (*) FROM #tmp_BetType

	IF @IsDrillDownFromRM = 1
	BEGIN
		DELETE s
		FROM #SportBettype s
		WHERE NOT EXISTS (SELECT 1 FROM #tmp_BetType b WHERE b.Bettype = s.Bettype)
	END 
	-- End Sport Bettype Matrix

	-- Handle Sport Type/League/GameType		
	UPDATE s
	SET s.TypeName = b.typenamee
	FROM #SportBettype s
		INNER JOIN dbo.bettype b WITH (NOLOCK) ON s.Bettype = b.typeid	
	-- End Sport Type/League/GameType

	-- Get Site	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), Srecommend INT, isDeposit BIT)
	CREATE TABLE #DepositSuper (CustId INT)

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
			INSERT INTO #DepositSuper
			SELECT CustId
			FROM f_DepSuper_1( 'All' )
		
			INSERT INTO #tmp_Company (SiteName, Srecommend, isDeposit)
			SELECT c.site, c.srecommend, 0
			FROM dbo.Customer c WITH (NOLOCK)
				LEFT JOIN #DepositSuper d ON c.srecommend = d.CustId 
			WHERE c.roleid = 4
				AND d.CustId IS NULL
		END			
	END
	-- Don't need to handle 'ALL' site, because with this case we will get all ticket
                        
	INSERT INTO #ExtraComm
               ( ProductID,
                 SuperID,
                 ExtraComm
               )
               SELECT ProductID,
                      SuperId,
                      SUM(ExtraCommRate) AS ExtraComm
               FROM bodb02.dbo.Acc_GroupExtraCommRateSetting a WITH ( NOLOCK )
               WHERE @WLDate BETWEEN FromDate AND Todate
					AND a.ProductId IN (SELECT ProductID FROM #tmp_ProductID)
               GROUP BY ProductID,
                        SuperId   
	-- End ExtraPT

	CREATE NONCLUSTERED INDEX Idx_SrecommendID ON #tmp_Company (Srecommend)
	-- End Site	
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)

	------------------------------------------II. Get Real Data For Report ------------------------------------------------------
	--- Check condition 
	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Poker Games
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		
		OPTION(RECOMPILE)
		
		-- 2a. By Bettype for Casino Product
		INSERT INTO #Data
				( ReportBy ,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT	b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, b.gameID, b.srecommend,
				COUNT(CASE WHEN StatusID IN (111,112,113) AND b.gameID NOT IN (2198, 2398, 2998) THEN b.TransId ELSE NULL END) AS BetCount, b.currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM dbo.bettransRnG b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND Bettype NOT IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) 	
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)
		GROUP BY b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend
		
		INSERT INTO #Data
				( ReportBy ,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT	b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, b.gameID, b.srecommend,
				0 AS BetCount, b.currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((b.ContributionRate * b.BetStake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((b.ContributionRate * b.BetStake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.bettransRnG b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE Bettype IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) 	
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)
		GROUP BY b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( ReportBy ,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT	b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, b.gameID, b.srecommend,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase		
				
		FROM dbo.bettransLC b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)
		GROUP BY b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend	
	END
	
	-- Poker Games
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33)
	BEGIN
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
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
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM(ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) ExtraPT,
				- SUM((ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
	END

	-- NumberGame
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase			

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
	END
	
	-- Live Casino
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT  m.leagueid ReportBy, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM dbo.Bettrans b WITH (NOLOCK) 
			INNER JOIN match m WITH (NOLOCK) ON b.matchid = m.matchid 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY m.leagueid, b.bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sport
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
	BEGIN
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
		
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
	END

	-- Virtual Sports 2 
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)
	BEGIN		
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
					
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT m.matchid FROM dbo.match m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		
		INSERT INTO #Data
				( ReportBy,
				  CustID ,
				  bettype,
				  srecommend,
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
				  ExtraPT,
				  ExtraPTBase
				)
		SELECT b.Bettype, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID, b.bettype, b.srecommend,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase				

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency IN (0,-1) OR b.currency = @currency) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Bettype, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend
		OPTION(RECOMPILE)
	END
	
	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name
	
	-- Get Bettype name
	UPDATE d
	SET d.ReportByName = s.TypeName
	FROM #Data d
		INNER JOIN (SELECT DISTINCT Bettype, TypeName
					FROM #SportBettype WHERE ProductID <> 4) s ON d.Bettype = s.Bettype 		

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		UPDATE d
		SET d.ReportByName = l.leaguename
		FROM #Data d
			INNER JOIN dbo.league l WITH (NOLOCK) ON d.Bettype = l.leagueid
	END
	-- End Bettype name	

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 6)
	BEGIN
		DELETE d
		FROM #Data d
		WHERE NOT EXISTS (SELECT 1 FROM dbo.SportBettypeMatrix m WITH (NOLOCK) WHERE m.ProductID = 6 AND d.Bettype = m.BetType AND m.SportType IN (SELECT Sporttype FROM #tmp_SportType))
	END
		
	------------------------------------------III. Drill down data ------------------------------------------------------

	IF @Currency = -1 -- BaseRM
	BEGIN		
		INSERT INTO #Result
			(	ReportBy,
				ReportByName ,
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
				CompanyCommBase,
				ExtraPT,
				ExtraPTBase
			    )
		SELECT b.ReportBy, b.ReportByName,
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
			SUM(b.CompanyCommBase) AS CompanyCommBase,
			SUM(b.ExtraPTBase) ExtraPT,
			SUM(b.ExtraPTBase) ExtraPTBase
		FROM #Data b
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
		GROUP BY b.ReportBy, b.ReportByName
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
		    (	ReportBy,
				ReportByName ,
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
				CompanyCommBase,
				ExtraPT,
				ExtraPTBase
		        )
		SELECT b.ReportBy, b.ReportByName,
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
				SUM(b.CompanyCommBase) AS CompanyCommBase,
				SUM(b.ExtraPT) ExtraPT,
				SUM(b.ExtraPTBase) ExtraPTBase
			FROM #Data b
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			GROUP BY b.ReportBy, b.ReportByName, b.CurrencyID, b.Currency
			HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(b.TotalBets) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(b.TotalBets) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(b.TotalBets - b.TotalWins) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(b.TotalBets - b.TotalWins) <= @GameIncomeValue)
					)
	END	

	------------------------------------------IV. Return Detail ------------------------------------------------------

	IF @IsGrandTotal = 0
	BEGIN		
		IF @IsDrillDown = 0
		BEGIN
			SELECT  ReportBy AS ReportById,
					ReportByName AS ReportBy, 
					NoOfPlayers,
					BetCount,
					CurrencyId,
					Currency,
					TotalBets,
					TotalWins,
					TotalRefund,
					CompanyTurnOver AS HouseTurnOver,
					CompanyGrossIncome AS HouseGrossIncome,
					CompanyComm AS HouseComm,
					ExtraPT
			FROM #Result	
			ORDER BY ReportByName, Currency		
		END
		ELSE
		BEGIN
			SELECT b.ReportBy AS ReportById,
				b.ReportByName AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyTurnOverBase) 
					 ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = -1 THEN SUM(b.ExtraPTBase) 
					ELSE SUM(b.ExtraPT) END AS ExtraPT
			FROM #Data b	
				INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.ReportByName = r.ReportByName	
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			GROUP BY b.ReportBy, b.ReportByName, b.CurrencyID , b.Currency	
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
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyTurnOverBase) 
					 ELSE SUM(d.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyGrossIncomeBase) ELSE SUM(d.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(d.CompanyCommBase) ELSE SUM(d.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = -1 THEN SUM(d.ExtraPTBase) 
					ELSE SUM(d.ExtraPT) END AS ExtraPT
		FROM #Result r
			INNER JOIN #Data d ON (r.CurrencyID = -1 OR r.CurrencyID = d.CurrencyID) AND d.ReportByName = r.ReportByName
			INNER JOIN #SportBettype s ON d.bettype = s.Bettype 
		GROUP BY d.CurrencyId, d.Currency
		ORDER BY ReportBy
	END	
	
	------------------------------------------V. Return Total Rows ------------------------------------------------------
	SELECT
        'GrandTotal' AS ReportBy,
        COUNT(DISTINCT d.CustID) AS NoOfPlayers,
        SUM(d.BetCount) BetCount,
        2 as CurrencyId, 
        'RM' AS Currency,
        SUM(d.TotalBetsBase) TotalBets,
        SUM(d.TotalWinsBase) TotalWins,
        SUM(d.TotalRefundBase) TotalRefund,
        SUM(d.CompanyTurnOverBase) HouseTurnOver,
		SUM(d.CompanyGrossIncomeBase) HouseGrossIncome,
		SUM(d.CompanyCommBase) HouseComm,
		SUM(d.ExtraPTBase) ExtraPT
    FROM #Result r
		INNER JOIN #Data d ON (r.CurrencyID = -1 OR r.CurrencyID = d.CurrencyID) AND r.ReportBy = d.ReportBy
		INNER JOIN #SportBettype s ON d.bettype = s.Bettype 

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #tmp_Company
	DROP TABLE #tmp_Device
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_SportType
	DROP TABLE #tmp_bettransm
	DROP TABLE #DepositSuper 
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	
END

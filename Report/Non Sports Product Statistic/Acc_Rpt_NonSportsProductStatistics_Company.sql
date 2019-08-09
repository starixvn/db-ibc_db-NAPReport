/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Company]
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
	Created	: 20161104@Harper
	Task	: #62430_Non Sports Product Statistic - Company Report
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
		20190809@Cherry: Add betfrom t (#115937)

	Param's Explanation:
		- @username:  + Search by keyword, member only
		- @Site: List of Company filter
			'ALL': All sites (MBC + Licensees)
			'MBC': MBC sites only
			'12bet' : Specific Licensee Name 
		- @ProductID: string filter by Product 
		- @BetType: string filter by bettype
		- @LeagueId: string filter by LeagueId (ProductID = 3 - Number Game get LeagueId)  
		- @Sporttype: string filter by Sporttype (ProductID IN (5,23) - Virtual Sports, NG2 get Sporttype)
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

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CustList VARCHAR(MAX)
	
	IF CHARINDEX(',', @Username) <> 0
	BEGIN
		EXEC dbo.Acc_CustomerSelCustByUsernameList @Username = @Username, @RoleId = 1, @CustList = @CustList OUTPUT

		IF @CustList IS NULL -- invalid username
		BEGIN
			IF @IsDrillDown = 0
				SELECT
					NULL AS IsDeposit,
					'Licensee Group' AS ReportBy,
					NULL AS NoOfPlayers,
					NULL AS BetCount,
					@Currency AS CurrencyId,
					'RM' AS Currency,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnOver,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm,
					NULL AS ExtraPT
				UNION ALL
				SELECT
					2 AS IsDeposit,
					'GrandTotalRM' AS ReportBy,
					NULL AS NoOfPlayers,
					NULL AS BetCount,
					-1 AS CurrencyId,
					'RM' AS Currency,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnOver,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm,
					NULL AS ExtraPT
			ELSE 
				SELECT
					2 AS IsDeposit,
					'GrandTotalRM' AS ReportBy,
					NULL AS NoOfPlayers,
					NULL AS BetCount,
					-1 AS CurrencyId,
					'RM' AS Currency,
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

	CREATE TABLE #Data ( recommend INT, srecommend INT, bettype INT,
						 CustID INT, IsDeposit BIT, SiteName VARCHAR(50),						 
						 BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						 CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
						 ExtraWL DECIMAL(19,8), ExtraWLBase DECIMAL(19,8),
						 ExtraComm DECIMAL(19,8), ExtraCommBase DECIMAL(19,8)	
						)
	CREATE TABLE #Result (  IsDeposit BIT, SiteName VARCHAR(50), NoOfPlayers INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
							TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
							TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
							CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
							CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
							CompanyComm DECIMAL(19,8), CompanyCommBase DECIMAL(19,8),
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
	
	CREATE TABLE #ExtraPT (ProductID INT, SuperID INT, ExtraPT DECIMAL(9, 8))
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
	WHERE s.ProductID NOT IN (3, 5, 27, 23) -- NumberGame, Virtual Sports, Virtual Sport 2, NG2
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
	DECLARE @isDrillDownLicensee BIT
	SELECT  @isDrillDownLicensee = 0

	IF @Site = 'All'
	BEGIN
		INSERT INTO #recommend (SiteName, recommend, isDeposit)
		SELECT ss.site, c.recommend, ss.isDeposit
		FROM dbo.Customer c WITH (NOLOCK)
			INNER JOIN dbo.Site ss WITH (NOLOCK) ON ss.Site = c.site
		WHERE c.roleid = 2
	END
	ELSE IF @Site = 'Licensee Group' -- all deposit drill down
	BEGIN
		INSERT INTO #recommend (SiteName, recommend, isDeposit)
		SELECT c.site, c.custid, 1
		FROM dbo.Dep_CustSuper d WITH (NOLOCK)
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON d.custid = c.srecommend
		WHERE c.roleid = 2
	END
	ELSE
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		IF EXISTS (SELECT TOP 1 1 FROM #tmp_Site WHERE Site IN ('MBC Group'))					
		BEGIN
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT c.site, c.custid, 0
			FROM dbo.Customer c WITH(NOLOCK)
				LEFT JOIN dbo.Dep_CustSuper d WITH(NOLOCK) ON c.srecommend = d.custid
			WHERE c.roleid = 2 AND d.custid IS NULL
		END

		IF EXISTS (SELECT TOP 1 1 FROM #tmp_Site WHERE Site NOT IN ('MBC Group', 'Licensee Group'))
		BEGIN	
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT c.site, c.custid, ss.isDeposit
			FROM dbo.Customer c WITH (NOLOCK) 
				INNER JOIN dbo.Site ss WITH (NOLOCK) ON ss.Site = c.site
				INNER JOIN #tmp_Site s ON ss.site = s.Site
			WHERE c.roleid = 2
			
			IF EXISTS (SELECT TOP 1 1 FROM #recommend WHERE isDeposit = 1)
				IF (SELECT COUNT(1) FROM #tmp_Site) <> 1
					SELECT @isDrillDownLicensee = 1
		END
		ELSE IF	EXISTS (SELECT TOP 1 1 FROM #tmp_Site WHERE Site IN ('Licensee Group'))
		BEGIN
			INSERT INTO #recommend (SiteName, recommend, isDeposit)
			SELECT c.site, c.custid, 1
			FROM dbo.Dep_CustSuper d WITH (NOLOCK)
				INNER JOIN dbo.Customer c WITH (NOLOCK) ON d.custid = c.srecommend
			WHERE c.roleid = 2
		END
	END

	CREATE NONCLUSTERED INDEX Idx_recommendID ON #recommend (recommend)	
	-- End Site	
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)
	CREATE CLUSTERED INDEX IX_GameTableID ON #tmp_GameTableId (GameTableID)
	
	INSERT INTO #ExtraPT
               ( ProductID,
                 SuperID,
                 ExtraPT
               )
               SELECT ProductID,
                      SuperId,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @WLDate BETWEEN FromDate AND Todate
					AND a.ProductId IN (SELECT ProductID FROM #tmp_ProductID)
               GROUP BY ProductID,
                        SuperId
                        
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
	
	------------------------------------------II. Get Real Data For Report ------------------------------------------------------	
	--- Check condition 
	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sport 2
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( recommend,
				  srecommend, 
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT b.recommend, srecommend, b.bettype,
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
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
				
		FROM  dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, srecommend, b.bettype 
		
		OPTION(RECOMPILE)
		
		-- 2a. By Bettype for Casino Product & Video Poker Games
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT	b.recommend, b.srecommend, b.gameID,
				CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
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
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend, b.gameID
		
		INSERT INTO #Data
				( recommend ,
				  srecommend, 
				  bettype ,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT	b.recommend, b.srecommend, b.gameID,
				CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(b.ContributionRate * b.BetStake) ExtraWL,
				- SUM((b.ContributionRate * b.BetStake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
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
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend, b.gameID
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT	b.recommend, b.srecommend, b.gameID,
				CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
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
		GROUP BY b.recommend, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency, b.srecommend, b.gameID		
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33) --Poker Games
	BEGIN
		INSERT INTO #Data
				( recommend,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(ISNULL(b.transid2, 0) * 1.0 / 10000) ExtraWL,
				- SUM((ISNULL(b.transid2, 0) * 1.0 / 10000) * actualrate) ExtraWLBase,
				
				- SUM(-b.oddsspread) ExtraComm,
				- SUM((-b.oddsspread) * actualrate) ExtraCommBase

		FROM  dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		OPTION(RECOMPILE)
		
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)	
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase

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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		OPTION(RECOMPILE)
		
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)	
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT matchid FROM Match WITH (NOLOCK)
								WHERE LeagueID IN (SELECT GameTableID FROM #tmp_GameTableId))
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		OPTION(RECOMPILE)
		
	END
		
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)	
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		OPTION(RECOMPILE)		
	
		-- 4. Virtual Sport (HR)
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase

		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND Eventype = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		OPTION(RECOMPILE)
	END
	
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27) -- Virtual Sports 2 
	BEGIN				
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)	
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT m.matchid FROM dbo.match m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		OPTION(RECOMPILE)
		
		--Mix parlay Virtual Sport 2
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
		
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  bettype,
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
				  ExtraWL,
				  ExtraWLBase,
				  ExtraComm,
				  ExtraCommBase
				)	
		SELECT	b.recommend, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
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
		GROUP BY b.recommend, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		OPTION(RECOMPILE)
	END

	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name	

	-- Get Site name
	UPDATE d
	SET d.SiteName = c.SiteName,
		d.IsDeposit = c.isDeposit
	FROM #Data d
		INNER JOIN #recommend c ON d.recommend = c.recommend
	-- End Site name

	------------------------------------------III. Drill down data ------------------------------------------------------
	IF @IsGrandTotal = 0
	BEGIN
		IF @Currency = -1 --BaseRM
		BEGIN			
			INSERT INTO #Result
					( IsDeposit ,
						SiteName ,
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
			SELECT b.IsDeposit,
					b.SiteName,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					SUM(BetCount) AS BetCount ,
					-1 as CurrencyId, 
					'RM' AS Currency,
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
					SUM (CompanyCommBase) AS CompanyCommBase,
					SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
					SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
			FROM #Data b
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
			GROUP BY b.IsDeposit, b.SiteName
			HAVING (@TotalBetType = 0
					OR (@TotalBetType = 1 AND SUM(b.TotalBetsBase) >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND SUM(b.TotalBetsBase) <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
					)			
		END		
		ELSE -- @Currency <> -1
		BEGIN
			INSERT INTO #Result
					( IsDeposit ,
						SiteName ,
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
			SELECT 
				b.IsDeposit AS IsDeposit,
				b.SiteName AS SiteName,
				COUNT(DISTINCT custid) AS NoOfPlayers,
				SUM(BetCount) AS BetCount ,
				b.CurrencyID AS CurrencyId, 
				b.Currency AS Currency,
				SUM (b.TotalBets) AS TotalBets, 
				SUM (b.TotalWins) AS TotalWins,
				SUM (b.TotalRefund) AS TotalRefund,
				SUM (b.CompanyTurnOver) AS CompanyTurnover,
				SUM (b.CompanyGrossIncome) AS CompanyGrossIncome,
				SUM (b.CompanyComm) AS CompanyComm,
				SUM (b.TotalBetsBase) AS TotalBetsBase, 
				SUM (b.TotalWinsBase) AS TotalWinsBase,
				SUM (b.TotalRefundBase) AS TotalRefundBase,
				SUM (b.CompanyTurnOverBase) AS CompanyTurnoverBase,
				SUM (b.CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM (b.CompanyCommBase) AS CompanyCommBase,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWL * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraComm * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWL + b.ExtraComm) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
			FROM #Data b
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
			GROUP BY b.IsDeposit,
				b.SiteName,
				b.CurrencyID , 
				b.Currency
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
	ELSE -- @IsGrandTotal = 1 (Click TO GrandTotal)
	BEGIN
		IF @Currency = -1
		BEGIN
			INSERT INTO #Result
						( IsDeposit ,
						  SiteName ,
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
		SELECT b.IsDeposit,
				b.SiteName,
				COUNT(DISTINCT custid) AS NoOfPlayers,
				SUM(BetCount) AS BetCount ,
				-1 AS CurrencyId, 
				'RM' AS Currency,
				SUM (TotalBetsBase) AS TotalBets, 
				SUM (TotalWinsBase ) AS TotalWins,
				SUM (TotalRefundBase ) AS TotalRefund,
				SUM (CompanyTurnoverBase ) AS CompanyTurnover,
				SUM (CompanyGrossIncomeBase ) AS CompanyGrossIncome,
				SUM (CompanyCommBase) AS CompanyComm,
				SUM (TotalBetsBase) AS TotalBetsBase, 
				SUM (TotalWinsBase) AS TotalWinsBase,
				SUM (TotalRefundBase) AS TotalRefundBase,
				SUM (CompanyTurnoverBase) AS CompanyTurnoverBase,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM (CompanyCommBase) AS CompanyCommBase,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
		FROM #Data b
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		GROUP BY b.IsDeposit, b.SiteName
		HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(TotalBetsBase ) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(TotalBetsBase) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(TotalBetsBase - TotalWinsBase) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
				)
		END
		ELSE
		BEGIN
			INSERT INTO #Result
						( IsDeposit ,
						  SiteName ,
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
		SELECT b.IsDeposit,
				b.SiteName,
				COUNT(DISTINCT custid) AS NoOfPlayers,
				SUM(BetCount) AS BetCount ,
				b.CurrencyID AS CurrencyId, 
				Currency AS Currency,
				SUM (b.TotalBets) AS TotalBets, 
				SUM (b.TotalWins) AS TotalWins,
				SUM (b.TotalRefund) AS TotalRefund,
				SUM (b.CompanyTurnOver) AS CompanyTurnover,
				SUM (b.CompanyGrossIncome) AS CompanyGrossIncome,
				SUM (b.CompanyComm) AS CompanyComm,
				SUM (TotalBetsBase) AS TotalBetsBase, 
				SUM (TotalWinsBase) AS TotalWinsBase,
				SUM (TotalRefundBase) AS TotalRefundBase,
				SUM (CompanyTurnoverBase) AS CompanyTurnoverBase,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM (CompanyCommBase) AS CompanyCommBase,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWL * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraComm * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWL + b.ExtraComm) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
		FROM #Data b
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		GROUP BY b.IsDeposit, b.SiteName, 
				b.CurrencyID, Currency
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

	------------------------------------------IV. Return Detail ------------------------------------------------------
	IF @IsGrandTotal = 0
	BEGIN
		IF @IsDrillDown = 0
		BEGIN
			SELECT IsDeposit,
					SiteName AS ReportBy,
					NoOfPlayers,
					BetCount,
					CurrencyID,
					Currency,
					TotalBets,
					TotalWins,
					TotalRefund,
					CompanyTurnOver AS HouseTurnOver,
					CompanyGrossIncome AS HouseGrossIncome,
					CompanyComm AS HouseComm,
					ExtraPT
			FROM #Result
			ORDER BY IsDeposit, SiteName, Currency
		END
		ELSE
		BEGIN
			SELECT 0 AS IsDeposit,
				CASE WHEN @isDrillDownLicensee = 1 THEN 'Licensee Group' ELSE @Site END AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = -1 THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = -1 THEN SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
														ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) 
					ELSE SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWL * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraComm * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWL + b.ExtraComm) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) END AS ExtraPT
		FROM #Data b	
			INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.SiteName = r.SiteName	
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		GROUP BY b.CurrencyID , b.Currency	
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
				CASE WHEN @Currency = -1 THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = -1 THEN SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
														ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) 
					ELSE SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWL * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraComm * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWL + b.ExtraComm) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) END AS ExtraPT
		FROM #Data b	
			INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.SiteName = r.SiteName	
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		GROUP BY b.CurrencyID , b.Currency		
		ORDER BY b.Currency
	END
	------------------------------------------V. Return Total Rows ------------------------------------------------------
	
	IF @IsDrillDown = 0
	BEGIN
		SELECT
			r.IsDeposit,
			CASE WHEN r.isDeposit = 0 THEN 'MBC Group' ELSE 'Licensee Group' END ReportBy,
			COUNT(DISTINCT custid) AS NoOfPlayers,
			SUM(b.BetCount) BetCount,
			@Currency CurrencyId, 
			'RM' AS Currency,
			SUM(b.TotalBetsBase) TotalBets,
			SUM(b.TotalWinsBase) TotalWins,
			SUM(b.TotalRefundBase) TotalRefund,
			SUM(b.CompanyTurnOverBase) HouseTurnOver,
			SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
			SUM(b.CompanyCommBase) HouseComm,
			SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT
		FROM #Data b
			INNER JOIN  #Result r ON (@Currency = -1 OR r.CurrencyId = b.CurrencyId) AND r.SiteName = b.SiteName
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		GROUP BY r.isDeposit,
			CASE WHEN r.isDeposit = 0 THEN 'MBC Group' ELSE 'Licensee Group' END
		UNION ALL
		SELECT
			2 AS IsDeposit,
			'GrandTotalRM' AS ReportBy,
			COUNT(DISTINCT custid) AS NoOfPlayers,
			SUM(b.BetCount) BetCount,
			-1 as CurrencyId, 
			'RM' AS Currency,
			SUM(b.TotalBetsBase) TotalBets,
			SUM(b.TotalWinsBase) TotalWins,
			SUM(b.TotalRefundBase) TotalRefund,
			SUM(b.CompanyTurnOverBase) HouseTurnOver,
			SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
			SUM(b.CompanyCommBase) HouseComm,
			SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT
		FROM #Data b
			INNER JOIN  #Result r ON (@Currency = -1 OR r.CurrencyId = b.CurrencyId) AND b.SiteName = r.SiteName
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
	END
	ELSE 
	BEGIN	
		IF @IsGrandTotal = 0
		BEGIN	
			SELECT
				2 AS IsDeposit,
				'GrandTotalRM' AS ReportBy,
				COUNT(DISTINCT custid) AS NoOfPlayers,
				SUM(b.BetCount) BetCount,
				-1 as CurrencyId, 
				'RM' AS Currency,
				SUM(b.TotalBetsBase) TotalBets,
				SUM(b.TotalWinsBase) TotalWins,
				SUM(b.TotalRefundBase) TotalRefund,
				SUM(b.CompanyTurnOverBase) HouseTurnOver,
				SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
				SUM(b.CompanyCommBase) HouseComm,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT
			FROM #Data b
				INNER JOIN  #Result r ON (b.SiteName = r.SiteName) AND (@Currency = -1 OR b.CurrencyID = r.CurrencyID)
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		END
		ELSE
		BEGIN
			SELECT
				2 AS IsDeposit,
				'GrandTotalRM' AS ReportBy,
				COUNT(DISTINCT custid) AS NoOfPlayers,
				SUM(b.BetCount) BetCount,
				-1 as CurrencyId, 
				'RM' AS Currency,
				SUM(b.TotalBetsBase) TotalBets,
				SUM(b.TotalWinsBase) TotalWins,
				SUM(b.TotalRefundBase) TotalRefund,
				SUM(b.CompanyTurnOverBase) HouseTurnOver,
				SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
				SUM(b.CompanyCommBase) HouseComm,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT
			FROM #Data b
				INNER JOIN  #Result r ON b.SiteName = r.SiteName AND (@Currency = -1 OR b.CurrencyID = r.CurrencyID)
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 	
		END
	END

	DROP TABLE #Data
	DROP TABLE #Result
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
	DROP TABLE #Device
	DROP TABLE #ExtraPT
	DROP TABLE #ExtraComm

END




/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Device_14]
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
	@IsGrandTotal	BIT =0
AS
/*
	Created	: 20161118@Harper
	Task	: #62430_Non Sports Product Statistic - Devide Report
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
					NULL AS CompanyComm,
					NULL AS ExtraPT
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
				NULL AS CompanyComm,
				NULL AS ExtraPT
			RETURN
		END
	END
	
	DECLARE @WLDate SMALLDATETIME
	SELECT @WLDate = CAST (@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #Data ( Betfrom NVARCHAR(5), Device NVARCHAR(50), DeviceGroup VARCHAR(50), 
						 srecommend INT, bettype INT, CustID INT,
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
	CREATE TABLE #Result (  Betfrom NVARCHAR(5), Device NVARCHAR(50), DeviceGroup VARCHAR(50), NoOfPlayers INT,
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
	CREATE TABLE #tmp_DeviceGroup	(Betfrom NVARCHAR(100), DeviceGroup VARCHAR(50))
	CREATE TABLE #tmp_Site			(Site VARCHAR(50))
	CREATE TABLE #tmp_MemIDs		(CustID INT)
	
	CREATE TABLE #ExtraPT (ProductID INT, SuperID INT, ExtraPT DECIMAL(9, 8))
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))
	
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
               GROUP BY ProductID,
                        SuperId                     

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
	DECLARE @AllDevice INT = 0
	IF @Device <> ''
	BEGIN
		INSERT INTO #tmp_Device (Betfrom)
		SELECT val FROM dbo.strSplit(@Device, ',')
		
		INSERT INTO #Device (Betfrom)
		SELECT Betfrom
		FROM DBWH.bodb_Account.dbo.tbl_Betfrom
		WHERE betfrom NOT IN ('t')

		IF NOT EXISTS(SELECT 1 FROM #Device d LEFT JOIN #tmp_Device t ON t.Betfrom = d.Betfrom WHERE t.Betfrom IS NULL) 
			SET @AllDevice = 1
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
		
	-- End Sport Bettype Matrix	
	
	-- Get Site	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), Srecommend INT)
	CREATE TABLE #DepositSuper (CustId INT)
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
			INSERT INTO #DepositSuper
			SELECT CustId
			FROM f_DepSuper_1( 'All' )

			INSERT INTO #tmp_Company (SiteName, Srecommend)
			SELECT c.site, c.srecommend
			FROM dbo.Customer c WITH (NOLOCK)
				LEFT JOIN #DepositSuper d ON c.srecommend = d.CustId 
			WHERE c.roleid = 4
				AND d.CustId IS NULL
		END			
	END
	-- Don't need to handle 'ALL' site, because with this case we will get all ticket

	CREATE NONCLUSTERED INDEX Idx_SrecommendID ON #tmp_Company (Srecommend)
	-- End Site	
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)
	CREATE CLUSTERED INDEX IX_GameTableID ON #tmp_GameTableId (GameTableID)

	------------------------------------------II. Get Real Data For Report ------------------------------------------------------
	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Poker Games
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( Betfrom,
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
		SELECT b.Betfrom, b.srecommend, b.bettype,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase							

		FROM  dbo.Bettrans14 b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 
			AND (EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom) OR @AllDevice = 1)
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.Betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		OPTION(RECOMPILE)
		
		-- 2a. By Bettype for Casino Product & Video Poker Games
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.gameID,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,
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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(winlost - actual_stake) ExtraWL,
				- SUM((winlost - actual_stake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
							
		FROM dbo.bettransRnG14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND Bettype NOT IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets		
			AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @Currency OR @Currency IN (0, -1))	
			AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
			AND (EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom) OR @AllDevice = 1)
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.currency, b.srecommend, b.gameID
		
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.gameID,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,
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
				- SUM((b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM(b.ContributionRate * b.BetStake) ExtraWL,
				- SUM((b.ContributionRate * b.BetStake) * actualrate) ExtraWLBase,
				
				- SUM(CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) ExtraComm,
				- SUM((CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * actualrate) ExtraCommBase
		FROM dbo.bettransRnG14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE Bettype IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets		
			AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @Currency OR @Currency IN (0, -1))	
			AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
			AND (EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom) OR @AllDevice = 1)
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.currency, b.srecommend, b.gameID
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.betfrom, b.srecommend, b.gameID,
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
		FROM dbo.bettransLC14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @Currency OR @Currency IN (0, -1))			
			AND (EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid) OR @Username = '')
			AND (EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom) OR @AllDevice = 1)
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.currency, b.srecommend, b.gameID		
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33)
	BEGIN
		INSERT INTO #Data
				( Betfrom,
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
		SELECT b.Betfrom, b.srecommend, b.bettype,
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

		FROM  dbo.Bettrans14 b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 
			AND (EXISTS (SELECT 1 From #tmp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom) OR @AllDevice = 1)
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.Betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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

		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM Match14 m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.Betfrom,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.srecommend, b.bettype
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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

		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT matchid FROM match14 WITH (NOLOCK)
								WHERE LeagueID IN (SELECT GameTableID FROM #tmp_GameTableId))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.Betfrom,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.srecommend, b.bettype
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
	BEGIN
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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

		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT matchid FROM dbo.match14 WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))		
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY  b.Betfrom,  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.srecommend, b.bettype
	
		-- 4. Virtual Sport (HR)
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND Eventype = 3)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)		  
		GROUP BY b.Betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
	END

	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)
	BEGIN
		-- Virtual Sports 2
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm14 bm WITH(NOLOCK)
					INNER JOIN dbo.match14 m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
					
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 1)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT m.matchid FROM dbo.match14 m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.Betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
		
		INSERT INTO #Data
				( Betfrom ,
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
		SELECT	b.Betfrom, b.srecommend, b.bettype,
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
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND Eventype = 0)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency IN (0, -1) OR b.currency = @Currency)	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@AllDevice = 1 OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.Betfrom, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, b.Currency, b.srecommend, b.bettype
	END
	
	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name	
	
	-- Get Device
	UPDATE d
	SET d.Device = f.fullname,
		d.DeviceGroup = f.DeviceGroup
	FROM #Data d
		INNER JOIN DBWH.bodb_Account.dbo.tbl_Betfrom f ON f.betfrom = d.Betfrom
	-- End Device
	
	------------------------------------------III. Drill down data ------------------------------------------------------
	
	IF @Currency = -1 -- BaseRM
	BEGIN		
		INSERT INTO #Result
			(	Betfrom ,
				Device ,
				DeviceGroup,
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
		SELECT b.Betfrom,
			b.Device,
			DeviceGroup,
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
			SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
			SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
		FROM #Data b
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
		GROUP BY b.Betfrom, b.Device, b.DeviceGroup
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
			(	Betfrom ,
				Device ,
				DeviceGroup,
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
		SELECT b.Betfrom,
				b.Device,
				b.DeviceGroup,
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
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWL * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraComm * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWL + b.ExtraComm) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPT,
				SUM(CASE WHEN s.ProductID = 33 AND s.RefTable = 0 THEN b.ExtraWLBase * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) + b.ExtraCommBase * CAST(ISNULL(c.ExtraComm,0) AS [decimal](10, 8))
							ELSE (b.ExtraWLBase + b.ExtraCommBase) * CAST(ISNULL(e.ExtraPT,0) AS [decimal](10, 8)) END) ExtraPTBase
			FROM #Data b
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
			GROUP BY b.Betfrom, b.Device, b.DeviceGroup, b.CurrencyID, b.Currency
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
		IF @IsDrillDown = 0 -- main page
		BEGIN
			SELECT DeviceGroup AS ReportById,
				Device AS ReportBy,
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
			ORDER BY Device, Currency
		END
		ELSE -- @IsDrillDown = 1 => click to RM
		BEGIN
			SELECT b.DeviceGroup AS ReportBy,
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
				INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.Device = r.Device
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
			GROUP BY b.DeviceGroup, b.CurrencyID, b.Currency
			ORDER BY b.Currency
		END
	END
	ELSE -- @IsGrandTotal = 1 => Click to GrandTotal
	BEGIN
		SELECT  b.CurrencyID AS ReportByID,
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
			INNER JOIN #Result r ON (@Currency = -1 OR b.CurrencyID = r.CurrencyID) AND b.Device = r.Device
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
				LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
				LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
		GROUP BY b.CurrencyID, b.Currency
		ORDER BY b.Currency
	END
	
	------------------------------------------V. Return Total Row ------------------------------------------------------
	-- Handle data for ReportByID	
	SELECT DISTINCT Betfrom, DeviceGroup
	INTO #tmp
	FROM #Result

	INSERT INTO #tmp_DeviceGroup (DeviceGroup, Betfrom)
	SELECT DISTINCT d2.DeviceGroup, 
    SUBSTRING (
        (
            Select ',' + d1.betfrom  AS [text()]
            From #tmp d1
            Where d1.DeviceGroup = d2.DeviceGroup
            ORDER BY d1.DeviceGroup
            For XML PATH ('')
        ), 2, 1000) [Devices]
	FROM #tmp d2
	-- End

	IF @IsDrillDown = 0
	BEGIN
		SELECT d.Betfrom AS ReportByID,	
			b.DeviceGroup AS ReportBy,
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
			INNER JOIN #Result r ON (@Currency = -1 OR r.CurrencyId = b.CurrencyId) AND r.Device = b.Device
			INNER JOIN #tmp_DeviceGroup d ON r.DeviceGroup = d.DeviceGroup
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
		GROUP BY b.DeviceGroup, d.Betfrom
		UNION ALL
		SELECT
			@Device AS ReportByID,
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
			INNER JOIN  #Result r ON (@Currency = -1 OR r.CurrencyId = b.CurrencyId) AND b.Device = r.Device
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
	END
	ELSE -- @IsDrillDown = 1
	BEGIN
		SELECT
			@Device AS ReportByID,
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
			INNER JOIN  #Result r ON (@Currency = -1 OR r.CurrencyId = b.CurrencyId) AND b.Device = r.Device
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
			LEFT JOIN #ExtraPT e ON b.srecommend = e.SuperID AND s.ProductID = e.ProductID 
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND s.ProductID = c.ProductID 
	END

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #tmp_Company
	DROP TABLE #tmp_Device
	DROP TABLE #tmp
	DROP TABLE #tmp_DeviceGroup
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


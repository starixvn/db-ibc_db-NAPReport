/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Product_14]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@Currency		VARCHAR(MAX) = '',	
	@Device			VARCHAR(200) = '',
	@ExcludeTest	BIT = 1, 
	@TotalBetType	SMALLINT = 0,
	@TotalBetValue  MONEY = NULL,
	@GameIncomeType	SMALLINT = 0,
	@GameIncomeValue MONEY = NULL,	 
	@HousePTType	SMALLINT = 0,
	@HousePTValue   MONEY = 0,
	@IsDrillDown	BIT = 0,
	@CasinoType		INT = -1,
	@IsGrandTotal	BIT = 0
AS
/*
	Created	: 20161118@Harper
	Task	: #62430_Non Sports Product Statistic - Product Report
	DB		: DBACC/bodb02
	
	Revisions:
		20170215@Percy: Remove hardcode product to support Fishing World [RedmineID: #71616]
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
		20200601@Cherry: Add Credit Site and support multiple currency (#135009)
		20200624@Cherry: Archive VSRaceInfo (#136256)

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

	EXEC [Acc_Rpt_NonSportsProductStatistics_Product_14] @WinlostDate = '2016-11-07',
	@ProductID = '4,12,21,11,13,6,17,14,22,3,8,5', 
	@Bettype = '1101,1102,1103,1104,1700,1701,1702,1703,2401,2402,2403,2404,2405,1800,1801,1802,1803,1804,2001,2002,2003,2004,2005,2006,2007,2008,2009,1900,1501,1515',
 	@LeagueID = '15223, 50717',
 	@Sporttype = '180, 181, 182, 183, 184, 185, 186',
 	@Device = 'a,d,e,f,h,i,j,l,m,n,p,s,t,u,w',
 	@Currency = -1,
 	@IsDrillDown = 0,
	@CasinoType = 2,
	@IsGrandTotal = 1
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

	CREATE TABLE #Data ( ProductID INT, ProductName VARCHAR(50), 
						 srecommend INT, bettype INT, CustID INT,
						 BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						 CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
						 ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)
						)
	CREATE TABLE #Result (  ProductID INT, ProductName VARCHAR(50), NoOfPlayers INT,
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
	CREATE TABLE #tmpCurrency		(CurrencyId INT)
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
	
	IF @Currency <> '-1'
    BEGIN
		INSERT INTO #tmpCurrency (CurrencyId)
		SELECT val FROM [dbo].strSplit(@Currency, ',')
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

	-- Handle Product Group		
	IF @CasinoType <> -1 -- @CasinoType = 0_KN, VS, NG, 1_RNG Casino, 2_Live Casino
	BEGIN
		DELETE s
		FROM #SportBettype s
		WHERE NOT EXISTS (SELECT 1 
						FROM dbo.Products p WITH (NOLOCK) 
						WHERE p.CasinoType = @CasinoType
								AND s.ProductID = p.ProductID)							
	END		
	-- End Product Group
	
	-- Get Site	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), Srecommend INT, isDeposit BIT)

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		INSERT INTO #tmp_Company (SiteName, Srecommend, isDeposit)
		SELECT s.Site, c.srecommend, ss.isDeposit
		FROM #tmp_Site s
			INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
		WHERE c.roleid = 4
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
	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans ( CustID INT, srecommend INT, Bettype INT,
						 BetCount BIGINT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						 CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
						 ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)
						)
						
	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Poker Games
	BEGIN
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, 
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
	
		OPTION(RECOMPILE)
	
	INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.gameID,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, 
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM  dbo.bettransRnG14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND Bettype NOT IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.gameID,
				0 AS BetCount, 
				b.currency,

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
									
				SUM(b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((b.ContributionRate * b.BetStake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((b.ContributionRate * b.BetStake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase								

		FROM  dbo.bettransRnG14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE Bettype IN (2198, 2398, 2998))
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.gameID,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, 
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase								

		FROM  dbo.bettransLC14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
	END
	
	-- Poker Games
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33)
	BEGIN
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				SUM(CASE WHEN b.statusID IN (111, 112, 113) THEN b.betid ELSE 0 END) AS BetCount, 
				b.currency,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				0 AS CompanyTurnover,	
				0 AS CompanyTurnoverBase,		
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				
				SUM(ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) ExtraPT,
				SUM((ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) * actualrate) ExtraPTBase

		FROM  dbo.bettrans14 b WITH (NOLOCK)
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.winlostdate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Number Game
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
								
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.statusID IN (111, 112, 113, 103) 
			AND EXISTS (SELECT 1 FROM Match14 m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Live Casino
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
								
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sports
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
	BEGIN
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT matchid FROM dbo.match14 WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))		
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
		
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 3)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo14 WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sports 2
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)  
	BEGIN
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm14 bm WITH(NOLOCK)
					INNER JOIN dbo.match14 m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
					
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase							

		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 1)
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT m.matchid FROM dbo.match14 m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
		
		INSERT INTO #tmp_bettrans
				( CustID ,
				  srecommend,
				  Bettype ,
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
		SELECT CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,
				b.currency,

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
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 0)
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.srecommend = b.srecommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END

	INSERT INTO #Data
			( ProductID,
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
			  ExtraPT,
			  ExtraPTBase
			)
	SELECT s.ProductID, srecommend, b.bettype, b.custid,
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
			- SUM(CompanyCommBase) AS CompanyCommBase,
			
			- SUM(ExtraPT) ExtraPT,
			- SUM(ExtraPTBase) ExtraPTBase

	FROM  #tmp_bettrans b
		INNER JOIN (SELECT DISTINCT Bettype, ProductID
					FROM #SportBettype) s ON b.Bettype = s.Bettype
	GROUP BY s.ProductID, srecommend, b.bettype, b.custid, b.CurrencyID		
	
	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name	

	-- Get Product Name
	IF @CasinoType = -1 -- Group in Product Group
	BEGIN
		UPDATE d
		SET d.ProductName = p.ProductName
		FROM #Data d
			INNER JOIN dbo.Products p ON d.ProductID = p.ProductID

		UPDATE s
		SET s.ProductID = 1,
			s.ProductName = 'RNG Casino'
		FROM #Data s			
		WHERE EXISTS (SELECT 1 FROM dbo.Products p WITH (NOLOCK) WHERE p.CasinoType = 1 AND s.ProductID = p.ProductID)

		UPDATE s
		SET s.ProductID = 2,
			s.ProductName = 'Live Casino'
		FROM #Data s
		WHERE EXISTS (SELECT 1 FROM dbo.Products p WITH (NOLOCK) WHERE p.CasinoType = 2 AND s.ProductID = p.ProductID)
	END
	ELSE -- @CasinoType <> -1
	BEGIN
		UPDATE d
		SET d.ProductName = CASE WHEN d.ProductId = 4 THEN 'SLI' ELSE p.ProductName END
		FROM #Data d
			INNER JOIN dbo.Products p ON d.ProductID = p.ProductID
		WHERE @CasinoType <> -1
	END
	--End Product Name
	------------------------------------------III. Drill down data ------------------------------------------------------

	IF @Currency = '-1' -- BaseRM
	BEGIN		
		INSERT INTO #Result
			(	ProductID ,
				ProductName ,
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
		SELECT b.ProductID,
			b.ProductName,
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
		GROUP BY b.ProductID, b.ProductName
		HAVING (@TotalBetType = 0
			OR (@TotalBetType = 1 AND SUM(b.TotalBetsBase) >= @TotalBetValue) 
			OR (@TotalBetType = -1 AND SUM(b.TotalBetsBase) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
			OR (@GameIncomeType = 1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) >= @GameIncomeValue) 
			OR (@GameIncomeType = -1 AND SUM(b.TotalBetsBase - b.TotalWinsBase) <= @GameIncomeValue)
				)		
	END	
	ELSE
	BEGIN
		INSERT INTO #Result
			(	ProductID ,
				ProductName ,
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
		SELECT b.ProductID,
				b.ProductName,
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
			GROUP BY b.ProductID, b.ProductName, b.CurrencyID, b.Currency
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
			SELECT  ProductID AS ReportById,
				ProductName AS ReportBy, 
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
			ORDER BY ProductName, Currency
		END
		ELSE
		BEGIN
			SELECT b.ProductID AS ReportById,
				b.ProductName AS ReportBy,
				COUNT(DISTINCT b.CustID) AS NoOfPlayers,
				SUM(b.BetCount) AS BetCount,
				b.CurrencyID,
				b.Currency,
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyTurnOverBase) 
					 ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) 
					ELSE SUM(b.ExtraPT) END AS ExtraPT
			FROM #Data b	
				INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.ProductName = r.ProductName
				INNER JOIN #SportBettype s ON b.bettype = s.Bettype 		
			GROUP BY b.ProductID, b.ProductName, b.CurrencyID , b.Currency	
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
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalBetsBase) ELSE SUM(b.TotalBets) END AS TotalBets,
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalWinsBase) ELSE SUM(b.TotalWins) END AS TotalWins,
				CASE WHEN @Currency = '-1' THEN SUM(b.TotalRefundBase) ELSE SUM(b.TotalRefund) END AS TotalRefund,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyTurnOverBase) 
					 ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) 
					ELSE SUM(b.ExtraPT) END AS ExtraPT
		FROM #Data b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.ProductName = r.ProductName	
			INNER JOIN #SportBettype s ON b.bettype = s.Bettype 
		GROUP BY b.CurrencyID , b.Currency	
		ORDER BY b.Currency
	END
		
	------------------------------------------V. Return Total Rows ------------------------------------------------------
	SELECT
        'GrandTotal' AS ReportBy,
        COUNT(DISTINCT b.CustID)AS NoOfPlayers,
        SUM(b.BetCount) BetCount,
        2 as CurrencyId, 
        'RM' AS Currency,
        SUM(b.TotalBetsBase) TotalBets,
        SUM(b.TotalWinsBase) TotalWins,
        SUM(b.TotalRefundBase) TotalRefund,
        SUM(b.CompanyTurnOverBase) HouseTurnOver,
		SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
		SUM(b.CompanyCommBase) HouseComm,
		SUM(b.ExtraPTBase) ExtraPT
    FROM #Result r
		INNER JOIN #Data b ON (r.CurrencyID = -1 OR r.CurrencyID = b.CurrencyID) AND r.ProductID = b.ProductID
		INNER JOIN #SportBettype s ON b.bettype = s.Bettype 	

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
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_bettransm
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	DROP TABLE #tmpCurrency
	
END


/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Product]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@SportBetType	VARCHAR(MAX) = '',
	@Currency		VARCHAR(MAX) = '',	
	@Device			VARCHAR(MAX) = '',
	@ExcludeTest	BIT = 1, 
	@TotalBetType	SMALLINT = 0,
	@TotalBetValue  MONEY = NULL,
	@GameIncomeType	SMALLINT = 0,
	@GameIncomeValue MONEY = NULL,	 
	@HousePTType	SMALLINT = 0,
	@HousePTValue   MONEY = 0,
	@IsDrillDown	BIT = 0,
	@CasinoType		INT = -1,
	@IsGrandTotal	BIT = 0,
	@IsExactly		BIT = 0
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
		20200710@Cherry: Integrate Pragmatic Jackpot (#137268)
		20200828@Cherry: Integrate Saba.club Free Bet (#140109)
		20200917@Cherry: Improve performance (#141844)
		20200922@Cherry: Improve performance (#142096)
		20200928@Cherry: Hot fix (#142436)
		20200929@Cherry: Hot fix (#142525)
		20201210@Cherry: Add Real Turnover (#146137)
		20201224@Cherry: Integrate Happy 5 Linked Games (#146537)
		20210120@Cherry: Integrate Saba Jackpot (#148293)
		20210506@Cherry: Integrate VGaming Jackpot (#154250)
		20220304@Cherry: Enhance username search for Non-sport games statistics report (#144260)
		20220512@Cherry: Hot fix (#172607)
		20220916@Cherry: Extend data type of Betfrom (#177655)
		20220926@Cherry: Change param @Device from Betfrom to Betfromid (#164955)
		20230609@Cherry: Not include dummy accounts in BetCount, NoOfPlayers (#188994)
		20230801@Cherry: Integrate Virtual Sports 3 (#189202)
		20240116@Cherry: Integrate Virtual Sports 4 (#198623)
		20240220@Cherry: Integrate AG Casino Jackpot Contribution (#200503)
		20240612@Cherry: Implement Product detail (#205894)

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

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CustList VARCHAR(MAX)
	
	IF CHARINDEX(',', @Username) <> 0
	BEGIN
		EXEC dbo.Acc_Rpt_NonSportsProductStatistics_CustSelByUsername @Username = @Username, @RoleId = 1, @IsExactly = @IsExactly, @CustList = @CustList OUTPUT

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
					NULL AS RealTurnOver,
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
				NULL AS RealTurnOver,
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
						 RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
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
							RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
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
	CREATE TABLE #tmp_Device		(Betfrom NVARCHAR(5))
	CREATE TABLE #tmp_Site			(Site VARCHAR(50))
	CREATE TABLE #tmp_MemIDs		(CustID INT)
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))	
	CREATE TABLE #tmpContributionBettype (Bettype INT, RefTable SMALLINT)	
	CREATE TABLE #tmpSportBetType (Sporttype INT, Bettype INT) 
	CREATE TABLE #tmpHouseProduct (ProductID INT)
	CREATE TABLE #tmpDummyCust (CustID INT)
	CREATE TABLE #tmpVirtualSport (ProductID INT)

	DECLARE @VirtualSportGroupStr VARCHAR(500)
    SELECT  @VirtualSportGroupStr = VValue
	FROM DBWH.bodb_account.dbo.SystemSettings WITH(NOLOCK)
	WHERE VID = 31		

    INSERT INTO #tmpVirtualSport (ProductID)
    SELECT val ProductID
    FROM bodb02.dbo.strSplit(@VirtualSportGroupStr, ',')
	WHERE val <> 49

	INSERT INTO #tmpDummyCust (CustID)
	SELECT c.custid
	FROM bodb02.dbo.customer c WITH(NOLOCK)
		INNER JOIN bodb02.dbo.Dep_CustSuper d WITH(NOLOCK) ON c.srecommend = d.custid 
		INNER JOIN bodb02.dbo.customer m WITH(NOLOCK) ON c.mrecommend = m.custid
	WHERE c.roleid = 1
		AND c.username LIKE '%Dummy3rd%' 
		AND m.username LIKE '%ACC%'	

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
		@sportid int, @sporttypebettype nvarchar(4000), 
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
	
	IF @SportBetType <> '' 
    BEGIN
		IF substring (@SportBetType, len(@SportBetType), 1) <> @splitter1
			SET @SportBetType = @SportBetType + @splitter1
		SET @start = 1
		SET @charindex1 = charindex(@splitter1, @SportBetType, @start)
		SET @charindex2 = charindex(@splitter2, @SportBetType, @start)

		WHILE (@charindex1 <> 0)
		BEGIN
			SET @sporttypebettype = substring(@SportBetType, @start, @charindex1 - @start)       
			SET @charindex2 = charindex(@splitter2, @sporttypebettype, 1)
			SET @sportid = substring(@sporttypebettype, 1, @charindex2 - 1)
			SET @bettypeid = substring(@sporttypebettype, @charindex2 + 1, LEN(@sporttypebettype))
			INSERT INTO #tmpSportBetType (Sporttype , Bettype) VALUES (@sportid, @bettypeid)
			SET @start = @charindex1 +1
			SET @charindex1 = charindex(@splitter1, @SportBetType, @start)          
		END
	END

	IF @Sporttype <> ''
	BEGIN
		INSERT INTO #tmp_SportType (Sporttype)
		SELECT val FROM dbo.strSplit(@Sporttype, ',')
	END

	CREATE TABLE #Device (BetfromID INT, Betfrom NVARCHAR(5))
	IF @Device <> ''
	BEGIN				
		INSERT INTO #Device (BetfromID, Betfrom)
		SELECT BetfromID, Betfrom
		FROM DBWH.bodb_Account.dbo.tbl_Betfrom WITH(NOLOCK)

		INSERT INTO #tmp_Device (Betfrom)
		SELECT d.Betfrom 
		FROM dbo.strSplit(@Device, ',') tmp
			INNER JOIN #Device d ON tmp.val = d.BetfromID

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
			IF @IsExactly = 0
				INSERT INTO #tmp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username LIKE @Username + '%' AND roleid = 1
			ELSE
				INSERT INTO #tmp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username = @Username AND roleid = 1

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
		
	INSERT INTO #tmpHouseProduct (ProductID)
	SELECT DISTINCT ProductID 
	FROM DBWH.bodb_Account.dbo.Product_Bettype WITH (NOLOCK)
	WHERE EventType = 255
		AND ProductID IN (SELECT ProductID FROM #tmp_ProductID)

	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID NOT IN (3, 23) 
		AND s.ProductID NOT IN (SELECT ProductID FROM #tmpVirtualSport)
		AND s.ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
		AND NOT EXISTS (SELECT b.Bettype FROM #tmp_BetType b WHERE b.Bettype = s.Bettype)
		
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID = 23 --NG2
		AND NOT EXISTS (SELECT b.Bettype 
						FROM #tmp_SportType st INNER JOIN bodb02.dbo.SportBettypeMatrix b WITH(NOLOCK) ON st.Sporttype = b.SportType 
						WHERE b.BetType = s.Bettype AND (b.IsTest = 0 OR b.IsTest = @isTest))
		
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
		AND NOT EXISTS (SELECT b.Bettype FROM #tmpSportBetType b WHERE b.Bettype = s.Bettype)
		
	DELETE t
	FROM #tmpSportBetType t LEFT JOIN #SportBettype s ON t.Bettype = s.Bettype
	WHERE s.Bettype IS NULL
	-- End Sport Bettype Matrix

	-- Handle Product Group		
	IF @CasinoType IN (0,1,2) -- @CasinoType = 0_KN, VS, NG, 1_RNG Casino, 2_Live Casino
	BEGIN
		DELETE s
		FROM #SportBettype s
		WHERE NOT EXISTS (SELECT 1 
						FROM dbo.Products p WITH (NOLOCK) 
						WHERE p.CasinoType = @CasinoType
								AND s.ProductID = p.ProductID)	
								
		DELETE s
		FROM #tmpSportBetType s
		WHERE NOT EXISTS (SELECT 1 
						FROM dbo.Products p WITH (NOLOCK) 
						WHERE p.CasinoType = @CasinoType
								AND p.ProductID IN (SELECT ProductID FROM #tmpHouseProduct)) --Saba.club, VGaming						
	END		
	-- End Product Group
	
	-- Get Site	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), recommend INT, isDeposit BIT)

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		INSERT INTO #tmp_Company (SiteName, recommend, isDeposit)
		SELECT s.Site, c.recommend, ss.isDeposit
		FROM #tmp_Site s
			INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
		WHERE c.roleid = 2
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

	CREATE NONCLUSTERED INDEX Idx_SrecommendID ON #tmp_Company (recommend)
	-- End Site				
	
	INSERT INTO #tmpContributionBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 10

	UPDATE b
	SET b.RefTable = s.RefTable
	FROM #tmpContributionBettype b
		INNER JOIN #SportBettype s ON b.Bettype = s.Bettype
	
	DELETE #tmpContributionBettype
	WHERE bettype NOT IN (SELECT bettype FROM #SportBettype) 

	DELETE #SportBettype
	WHERE bettype IN (SELECT bettype FROM #tmpContributionBettype)
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)	
	CREATE CLUSTERED INDEX IX_SporttypeBettype ON #tmpSportBetType (Sporttype, Bettype)  
	CREATE CLUSTERED INDEX IX_Bettype ON #tmpContributionBettype (Bettype) 

	------------------------------------------II. Get Real Data For Report ------------------------------------------------------
	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans ( CustID INT, srecommend INT, Bettype INT,
						 BetCount BIGINT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
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
				  RealTurnOver ,
				  RealTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase,
				  ExtraPT,
				  ExtraPTBase
				)	
		SELECT CASE WHEN d.CustID IS NOT NULL THEN NULL 
					WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
				COUNT(CASE WHEN d.CustID IS NOT NULL THEN NULL 
						WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, 
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
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) * actualrate) AS RealTurnoverBase,			
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase							

		FROM  dbo.bettrans b WITH (NOLOCK)
			LEFT JOIN #tmpDummyCust d ON b.custid = d.custid
		WHERE b.winlostdate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 33)
									AND ProductID NOT IN (SELECT ProductID FROM #tmpVirtualSport))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, 
			CASE WHEN d.CustID IS NOT NULL THEN NULL 
				WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
	
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
				  RealTurnOver ,
				  RealTurnOverBase ,
				  CompanyGrossIncome ,
				  CompanyGrossIncomeBase ,
				  CompanyComm ,
				  CompanyCommBase,
				  ExtraPT,
				  ExtraPTBase
				)	
		SELECT CASE WHEN d.CustID IS NOT NULL THEN NULL 
					WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END AS custid, 
				b.srecommend, b.bettype,
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
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) * actualrate) AS RealTurnoverBase,			
									
				SUM(ISNULL(b.betid,0.0)/100000000.0 + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((ISNULL(b.betid,0.0)/100000000.0 + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm * actualrate) AS CompanyCommBase,
				
				SUM((ISNULL(b.betid,0.0)/100000000.0 + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((ISNULL(b.betid,0.0)/100000000.0 + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase							

		FROM  dbo.bettrans b WITH (NOLOCK)
			LEFT JOIN #tmpDummyCust d ON b.custid = d.custid
		WHERE b.winlostdate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #tmpContributionBettype WHERE RefTable IN (0,3))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, 
			CASE WHEN d.CustID IS NOT NULL THEN NULL 
				WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
	
		OPTION(RECOMPILE)
		
		CREATE TABLE #tmpBettypeRNG (Bettype SMALLINT)
		INSERT INTO #tmpBettypeRNG (Bettype)
		SELECT Bettype
		FROM #SportBettype
		WHERE RefTable = 1 AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct)
		CREATE CLUSTERED INDEX IX_bettype ON  #tmpBettypeRNG(Bettype)
	
		IF EXISTS(SELECT 1 FROM #tmpBettypeRNG)
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
					SUM(scomm * actualrate) AS CompanyCommBase,
					
					SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase								

			FROM  dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpBettypeRNG)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
				AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
				AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
				AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
				AND ( @Site = 'ALL'
						  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
				)
			GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
			
			OPTION(RECOMPILE)
		END
			
		IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (SELECT ProductID FROM #tmpHouseProduct))
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
					SUM(scomm * actualrate) AS CompanyCommBase,
					
					SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase								

			FROM  dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate			
				AND EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
				AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
				AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
				AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
				AND ( @Site = 'ALL'
						  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
				)
			GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
			
			OPTION(RECOMPILE)
		END
		
		DELETE d
		FROM #tmp_bettrans d INNER JOIN #tmpContributionBettype b ON d.bettype = b.bettype AND b.RefTable = 1
		WHERE d.bettype IN (SELECT Bettype FROM #tmpSportBetType)
		
		IF EXISTS(SELECT 1 FROM #tmpContributionBettype) 
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
										
					SUM(b.ContributionStake3rd + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
					SUM((b.ContributionStake3rd + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

					SUM(scomm) AS CompanyComm,
					SUM(scomm *actualrate) AS CompanyCommBase,
					
					SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
		
			FROM  dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpContributionBettype WHERE RefTable = 1) 
				AND (b.gameID NOT IN (SELECT Bettype FROM #tmpSportBetType)
						OR EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
					)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
				AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
				AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
				AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
				AND ( @Site = 'ALL'
						  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
				)
			GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
			
			OPTION(RECOMPILE)
		END
		
		INSERT INTO #tmp_bettrans
				( CustID ,
				  b.srecommend,
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
				  RealTurnOver ,
				  RealTurnOverBase ,
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
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,		
									
				SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM  dbo.bettransLC b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.gameID, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		
		OPTION(RECOMPILE)
		
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

		FROM  dbo.bettrans b WITH (NOLOCK)
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.winlostdate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
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
								
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
				OR EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = 168 AND l.Bettype = b.bettype)
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
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
						
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (SELECT ProductID FROM #tmpVirtualSport))
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

		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID IN (SELECT ProductID FROM #tmpVirtualSport) AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))		
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
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
							
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sports Parlay
	CREATE TABLE #tmpVSBettype (Bettype INT)
	INSERT INTO #tmpVSBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH(NOLOCK)
	WHERE BettypeGroupID = 18
		AND Bettype IN (SELECT Bettype FROM #SportBettype)

	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmpVSBettype)  
	BEGIN
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
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

		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #tmpVSBettype)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
			)
		GROUP BY b.srecommend, b.bettype, CASE WHEN b.statusID IN (111, 112, 113) THEN b.custid ELSE NULL END, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Update Real Turnover
	CREATE TABLE #tmpNetStakeBettype (Bettype INT)
	INSERT INTO #tmpNetStakeBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 13
	
	UPDATE #tmp_bettrans
	SET RealTurnover = CompanyTurnover,
		RealTurnoverBase = CompanyTurnoverBase
	WHERE bettype NOT IN (SELECT Bettype FROM #tmpNetStakeBettype)
	----------------
	
	-- Update BetCount = 0
	CREATE TABLE #tmpNoBetCountBettype (Bettype INT)
	INSERT INTO #tmpNoBetCountBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 12
	
	UPDATE #tmp_bettrans
	SET BetCount = 0
	WHERE bettype IN (SELECT Bettype FROM #tmpNoBetCountBettype)
	---------------

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
			  RealTurnOver ,
			  RealTurnOverBase ,
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
			
			SUM(RealTurnover) AS RealTurnover,	
			SUM(RealTurnoverBase) AS RealTurnoverBase,	
							
			- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
			- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,

			- SUM(CompanyComm) AS CompanyComm,
			- SUM(CompanyCommBase) AS CompanyCommBase,
			
			- SUM(ExtraPT) ExtraPT,
			- SUM(ExtraPTBase) ExtraPTBase

	FROM  #tmp_bettrans b
		INNER JOIN (SELECT DISTINCT Bettype, ProductID
					FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)) s ON b.Bettype = s.Bettype
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
				RealTurnOver,
				CompanyGrossIncome ,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnOverBase,
				RealTurnOverBase,
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
			SUM(b.RealTurnOverBase) AS RealTurnOver,
			SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncome,            
			SUM(b.CompanyCommBase) AS CompanyComm,
			SUM(b.TotalBetsBase) AS TotalBetsBase,
			SUM(b.TotalWinsBase) AS TotalWinsBase,
			SUM(b.TotalRefundBase) AS TotalRefundBase,
			SUM(b.CompanyTurnOverBase) AS CompanyTurnOverBase,
			SUM(b.RealTurnOverBase) AS RealTurnOverBase,
			SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,            
			SUM(b.CompanyCommBase) AS CompanyCommBase,
			SUM(b.ExtraPTBase) ExtraPT,
			SUM(b.ExtraPTBase) ExtraPTBase
		FROM #Data b
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
				RealTurnOver ,
				CompanyGrossIncome ,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnOverBase,
				RealTurnOverBase,
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
				SUM(b.RealTurnOver) AS RealTurnOver,
				SUM(b.CompanyGrossIncome) AS CompanyGrossIncome,            
				SUM(b.CompanyComm) AS CompanyComm,
				SUM(b.TotalBetsBase) AS TotalBetsBase,
				SUM(b.TotalWinsBase) AS TotalWinsBase,
				SUM(b.TotalRefundBase) AS TotalRefundBase,
				SUM(b.CompanyTurnOverBase) AS CompanyTurnOverBase,
				SUM(b.RealTurnOverBase) AS RealTurnOverBase,
				SUM(b.CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,            
				SUM(b.CompanyCommBase) AS CompanyCommBase,
				SUM(b.ExtraPT) ExtraPT,
				SUM(b.ExtraPTBase) ExtraPTBase
			FROM #Data b
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
				RealTurnOver AS RealTurnOver,
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
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.RealTurnOverBase) ELSE SUM(b.RealTurnOver) END AS RealTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) 
					ELSE SUM(b.ExtraPT) END AS ExtraPT
			FROM #Data b	
				INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.ProductName = r.ProductName	
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
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyTurnOverBase) ELSE SUM(b.CompanyTurnOver) END AS HouseTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.RealTurnOverBase) ELSE SUM(b.RealTurnOver) END AS RealTurnOver,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyGrossIncomeBase) ELSE SUM(b.CompanyGrossIncome) END AS HouseGrossIncome,
				CASE WHEN @Currency = '-1' THEN SUM(b.CompanyCommBase) ELSE SUM(b.CompanyComm) END AS HouseComm,
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) 
					ELSE SUM(b.ExtraPT) END AS ExtraPT
		FROM #Data b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.ProductName = r.ProductName	
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
        SUM(b.RealTurnOverBase) RealTurnOver,
		SUM(b.CompanyGrossIncomeBase) HouseGrossIncome,
		SUM(b.CompanyCommBase) HouseComm,
		SUM(b.ExtraPTBase) ExtraPT
    FROM #Result r
		INNER JOIN #Data b ON (r.CurrencyID = -1 OR r.CurrencyID = b.CurrencyID) AND r.ProductID = b.ProductID

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #tmp_Company
	DROP TABLE #tmp_Device
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmpHouseProduct
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_SportType
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_bettransm
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	DROP TABLE #tmpCurrency
	DROP TABLE #tmpContributionBettype	
	DROP TABLE #tmpSportBetType
	DROP TABLE #tmpNetStakeBettype	
	DROP TABLE #tmpNoBetCountBettype
	DROP TABLE #tmpBettypeRNG
	DROP TABLE #tmpDummyCust
	DROP TABLE #tmpVirtualSport
	DROP TABLE #tmpVSBettype
	
END


/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Headline]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',	
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@SportBetType	VARCHAR(MAX) = '',
	@Currency		VARCHAR(MAX) = '',	
	@Device			VARCHAR(MAX) = '',
	@CustID			INT = 0,
	@ExcludeTest	BIT = 1, 
	@TotalBetType	SMALLINT = 0,
	@TotalBetValue  MONEY = NULL,
	@GameIncomeType	SMALLINT = 0,
	@GameIncomeValue MONEY = NULL,	 
	@HousePTType	SMALLINT = 0,
	@HousePTValue   MONEY = 0,
	@IsDrillDown	BIT = 0,
	@IsGrandTotal	BIT = 0,
	@IsExactly		BIT = 0,
	@ExcludeNoData BIT = 0
AS
/*
	Created	: 20240916@Cherry
	Task	: Non Sports Product Statistic - Headline Report
	DB		: DBACC/bodb02
	
	Revision:
		20240916@Cherry: Initial (#175453)		

	Param's Explanation:		
		- @Site: List of Company filter
			'ALL': All sites (MBC + Licensees)
			'MBC': MBC sites only
			'12bet' : Specific Licensee Name 
		- @ProductID: string filter by Product 
		- @BetType: string filter by bettype
		- @LeagueId: string filter by LeagueId (ProductID = 3 - Number Game get LeagueId)  
		- @Sporttype: string filter by Sporttype (ProductID IN (5,23) - Virtual Sports, NG2 get Sporttype)
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
	
	DECLARE @WLDate SMALLDATETIME
	SELECT @WLDate = CAST(@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #Data ( recommend INT, srecommend INT, mrecommend INT, CustID INT, 						 						 
						 bettype INT, BetCount INT, CurrencyID INT, Currency NVARCHAR(50),
						 TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
						 TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
						 TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
						 CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
						 RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
						 CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						 CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
						 ExtraPT DECIMAL(19,4), ExtraPTBase DECIMAL(19,4)
						)

	CREATE TABLE #tmpResult (  Headline VARCHAR(50), CustID INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
							TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
							TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
							CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
							RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
							CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
							CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
							ExtraPT DECIMAL(19,4), ExtraPTBase DECIMAL(19,4)							
						)

	CREATE TABLE #Result (  Headline VARCHAR(50), CustID INT,
							BetCount INT, CurrencyID INT, Currency NVARCHAR(50)	,
							TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),
							TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),
							TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),
							CompanyTurnOver DECIMAL(19,4), CompanyTurnOverBase DECIMAL(19,4),
							RealTurnOver DECIMAL(19,4), RealTurnOverBase DECIMAL(19,4),
							CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
							CompanyComm DECIMAL(19,4), CompanyCommBase DECIMAL(19,4),
							ExtraPT DECIMAL(19,4), ExtraPTBase DECIMAL(19,4)							
						)

	------------------------------------------I. Handle Parameter ------------------------------------------------------

	CREATE TABLE #tmp_ProductID		(ProductID INT)
	CREATE TABLE #tmp_BetType		(Bettype INT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT, Bettype INT)
	CREATE TABLE #tmp_SportType		(Sporttype INT)
	CREATE TABLE #tmpCurrency (CurrencyId INT)
	CREATE TABLE #tmp_Device		(Betfrom NVARCHAR(5))
	CREATE TABLE #tmp_Site			(Site VARCHAR(50))
	CREATE TABLE #tmp_MemIDs		(CustID INT)	
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))
	CREATE TABLE #tmpContributionBettype (Bettype INT, RefTable SMALLINT)
	CREATE TABLE #tmpSportBetType (Sporttype INT, Bettype INT)
	CREATE TABLE #tmpHouseProduct (ProductID INT)
	CREATE TABLE #tmpDummyCust (CustID INT)
	CREATE TABLE #tmpVirtualSport (ProductID INT)
	CREATE TABLE #tmpHeadline (CustID INT, Username VARCHAR(50), GroupID INT)
	CREATE TABLE #tmpSMA (SuperID INT, MasterID INT, AgentID INT, CustID INT, Headline INT)

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

	-- Get Sport Bettype Matrix
	DECLARE @isTest BIT = 0
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype (ProductID INT, Bettype INT, EvenType INT, SubProduct VARCHAR(500), RefTable SMALLINT)
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, SubProduct, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.SubProduct, s.RefTable
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

	-- Get Site	
	CREATE TABLE #recommend (SiteName VARCHAR(50), recommend INT)

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		INSERT INTO #recommend (SiteName, recommend)
		SELECT s.Site, c.recommend
		FROM #tmp_Site s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.Site = c.site
		WHERE c.roleid = 2
	END	
	-- End Site		
                        
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
	
	CREATE NONCLUSTERED INDEX Idx_recommendID ON #recommend (recommend)	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)	
	CREATE CLUSTERED INDEX IX_SporttypeBettype ON #tmpSportBetType (Sporttype, Bettype)  
	CREATE CLUSTERED INDEX IX_Bettype ON #tmpContributionBettype (Bettype) 
	
	------------------------------------------II. Get Real Data For Report ------------------------------------------------------	
	--- Check condition 
	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sport 2
	BEGIN		
		-- 1. By bettype for normal product
		INSERT INTO #Data
				( recommend,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				  
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
		SELECT b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,					

				COUNT(CASE WHEN d.CustID IS NOT NULL THEN NULL
						WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) * actualrate) AS RealTurnoverBase,	
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm * actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
		FROM  dbo.Bettrans b WITH (NOLOCK) 
			LEFT JOIN #tmpDummyCust d ON b.custid = d.custid
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 33)
										AND ProductID NOT IN (SELECT ProductID FROM #tmpVirtualSport))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 			
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.custid,			 
			b.Currency, srecommend, b.bettype 
		
		OPTION(RECOMPILE)		

		INSERT INTO #Data
					( recommend ,
					  srecommend, 
					  mrecommend,
					  custid,
					  bettype ,					  
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, 				
				b.bettype, 0 AS BetCount, b.currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
									
				- SUM(ISNULL(b.betid,0.0)/100000000.0 + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((ISNULL(b.betid,0.0)/100000000.0 + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
					
				- SUM((ISNULL(b.betid,0.0)/100000000.0 + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((ISNULL(b.betid,0.0)/100000000.0 + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
		FROM dbo.bettrans b WITH (NOLOCK)
			LEFT JOIN #tmpDummyCust d ON b.custid = d.custid
		WHERE b.winlostdate = @WLDate
			AND b.ruben = 1
			AND b.bettype IN (SELECT Bettype FROM #tmpContributionBettype WHERE RefTable IN (0,3)) 
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 			
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
					OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.recommend, b.mrecommend,	b.custid,			
				b.currency, b.srecommend, b.bettype
			
		OPTION(RECOMPILE)
		
		CREATE TABLE #tmpBettypeRNG (Bettype SMALLINT)
		INSERT INTO #tmpBettypeRNG (Bettype)
		SELECT Bettype
		FROM #SportBettype
		WHERE RefTable = 1 AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct)
		CREATE CLUSTERED INDEX IX_bettype ON  #tmpBettypeRNG(Bettype)		
		
		-- 2a. By Bettype for Casino Product & Video Poker Games
		IF EXISTS(SELECT 1 FROM #tmpBettypeRNG)
		BEGIN
			INSERT INTO #Data
					( recommend ,
					  srecommend,
					  mrecommend,
					  custid,
					  bettype,					  
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
			SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.gameID,
			
					COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.currency, 

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
									
					- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
					- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

					- SUM(scomm) AS CompanyComm,
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
		
			FROM dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpBettypeRNG)
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 				
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.recommend, b.mrecommend, b.currency, b.srecommend, b.gameID, b.custid
			
			OPTION(RECOMPILE)
		END
		
		IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (SELECT ProductID FROM #tmpHouseProduct))
		BEGIN
			INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				  
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
			SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.gameID,
					
					COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.currency, 

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
									
					- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
					- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

					- SUM(scomm) AS CompanyComm,
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
		
			FROM dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate
				AND EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 				
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.recommend, b.mrecommend, b.currency, b.srecommend, b.gameID, b.custid
			
			OPTION(RECOMPILE)
		END
		
		DELETE d
		FROM #Data d INNER JOIN #tmpContributionBettype b ON d.bettype = b.bettype AND b.RefTable = 1
		WHERE d.bettype IN (SELECT Bettype FROM #tmpSportBetType)			
		
		IF EXISTS (SELECT 1 FROM #tmpContributionBettype)
		BEGIN
			INSERT INTO #Data
					( recommend ,
					  srecommend, 
					  mrecommend,
					  custid,
					  bettype,					  
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
			SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.gameID,
					
					0 AS BetCount, b.currency, 

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
									
					- SUM(b.ContributionStake3rd + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
					- SUM((b.ContributionStake3rd + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,

					- SUM(scomm) AS CompanyComm,
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
			FROM dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpContributionBettype WHERE RefTable = 1) 
				AND (b.gameID NOT IN (SELECT Bettype FROM #tmpSportBetType)
					OR EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
					)
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets	
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 				
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.recommend, b.mrecommend, b.currency, b.srecommend, b.gameID, b.custid
			
			OPTION(RECOMPILE)
		END
		
		-- 2b. By Bettype for Casino Product
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				 
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.gameID,
				
				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,	
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
		FROM dbo.bettransLC b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 			
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY b.recommend, b.mrecommend, b.currency, b.srecommend, b.gameID, b.custid		
		
		OPTION(RECOMPILE)
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33) --Poker Games
	BEGIN
		INSERT INTO #Data
				( recommend,
				  srecommend,
				  mrecommend,
				  custid, 
				  bettype,
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
		SELECT b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,			

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
				
				- SUM(ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) ExtraPT,
				- SUM((ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) * actualrate) ExtraPTBase

		FROM  dbo.Bettrans b WITH (NOLOCK)
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 			
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		
		OPTION(RECOMPILE)
		
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid, 
				  bettype,				  
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
				  ExtraPTBase)
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,				

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase				

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid  AND l.Bettype = b.bettype)
				OR EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = 168 AND l.Bettype = b.bettype)
				)
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 			
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmp_Device f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		
		OPTION(RECOMPILE)
		
	END
	
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,				

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						 WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						 WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))				
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		
		OPTION(RECOMPILE)
		
	END

	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID IN (SELECT ProductID FROM #tmpVirtualSport))
	BEGIN
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				 
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,				

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID IN (SELECT ProductID FROM #tmpVirtualSport) AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))				
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		
		OPTION(RECOMPILE)		

		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,				
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,				

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM dbo.Bettrans b WITH (NOLOCK) 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID IN (SELECT ProductID FROM #tmpVirtualSport) AND EvenType = 5)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND b.matchid IN (SELECT Match3rdId FROM dbo.Match3rd WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))				
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		
		OPTION(RECOMPILE)		
	END
		
	IF EXISTS (SELECT 1 FROM #SportBettype WHERE Eventype = 3)
	BEGIN			
		-- Virtual Sport (HR)
		INSERT INTO #Data
				( recommend ,
				  srecommend,
				  mrecommend,
				  custid,
				  bettype,			
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
		SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,				

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE Eventype = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))				
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)				  
		GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
		OPTION(RECOMPILE)
	END

	CREATE TABLE #tmpVSBettype (Bettype INT)
	INSERT INTO #tmpVSBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH(NOLOCK)
	WHERE BettypeGroupID = 18
		AND Bettype IN (SELECT Bettype FROM #SportBettype)
	
	CREATE TABLE #tmp_bettransm (refno BIGINT)				
	--Mix parlay Virtual Sport 2
	INSERT INTO #tmp_bettransm (refno)
	SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
				INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
				INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype

	INSERT INTO #tmp_bettransm (refno)
	SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
				INNER JOIN dbo.Match3rd m WITH(NOLOCK) ON bm.matchid = m.Match3rdId 
				INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
		
	INSERT INTO #Data
			( recommend ,
				srecommend,
				mrecommend,
				custid,
				bettype,				
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
	SELECT	b.recommend, b.srecommend, b.mrecommend, b.custid, b.bettype,			

			COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

			SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
			SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

			SUM(CASE WHEN b.statusID IN (103) THEN 0 
					WHEN b.tpositiontaking = 1 THEN 0
					ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
			SUM((CASE WHEN b.statusID IN (103) THEN 0 
					WHEN b.tpositiontaking = 1 THEN 0
					ELSE (1- b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
								
			- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
			- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

			- SUM(scomm) AS CompanyComm,
			- SUM(scomm *actualrate) AS CompanyCommBase,
				
			- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase

	FROM  dbo.Bettrans b WITH (NOLOCK)
	WHERE b.WinlostDate = @WLDate
		AND b.bettype IN (SELECT Bettype FROM #tmpVSBettype)
		AND b.ruben = 1
		AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
		AND b.refno IN (SELECT refno FROM #tmp_bettransm)
		AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
		AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))			
		AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
		AND ( @Site = 'ALL'
				OR (EXISTS (SELECT 1 From #recommend s WHERE s.recommend = b.recommend))
			)
		AND (
			@HousePTType = 0
			OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
			OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
	GROUP BY b.recommend, b.mrecommend, b.Currency, b.srecommend, b.bettype, b.custid
	OPTION(RECOMPILE)
	
	--Update Real Turnover
	CREATE TABLE #tmpNetStakeBettype (Bettype INT)
	INSERT INTO #tmpNetStakeBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 13
	
	UPDATE #Data
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
	
	UPDATE #Data
	SET BetCount = 0
	WHERE bettype IN (SELECT Bettype FROM #tmpNoBetCountBettype)

	-- Get Currency name
	UPDATE d
	SET d.Currency = e.currency
	FROM #Data d
		INNER JOIN dbo.Exchange e ON e.exchangeid = d.CurrencyID
	-- End Currency Name	

	INSERT INTO #tmpHeadline (CustID, Username, GroupID)
	SELECT DISTINCT a.custid, c.username, a.groupID
	FROM bodb02.dbo.custAccount a WITH(NOLOCK)
		INNER JOIN bodb02.dbo.CustGroupHeadline h WITH(NOLOCK) ON a.custid = h.CustID
		INNER JOIN bodb02.dbo.Customer c WITH(NOLOCK) ON a.CustID = c.custid
	WHERE a.groupID <> 0
		AND a.IsGroupHeadLine = 1
		AND a.groupID = h.GroupID

	INSERT INTO #tmpSMA (SuperID, MasterID, AgentID, CustID, Headline)
	SELECT DISTINCT d.Srecommend, d.Mrecommend, d.Recommend, d.CustID, h.CustID
	FROM #Data d
		INNER JOIN bodb02.dbo.custAccount a WITH(NOLOCK) ON d.srecommend = a.custid
		INNER JOIN #tmpHeadline h ON a.groupID = h.GroupID
	UNION
	SELECT DISTINCT d.Srecommend, d.Mrecommend, d.Recommend, d.CustID, h.CustID
	FROM #Data d
		INNER JOIN bodb02.dbo.custAccount a WITH(NOLOCK) ON d.mrecommend = a.custid
		INNER JOIN #tmpHeadline h ON a.groupID = h.GroupID
	UNION
	SELECT DISTINCT d.Srecommend, d.Mrecommend, d.Recommend, d.CustID, h.CustID
	FROM #Data d
		INNER JOIN bodb02.dbo.custAccount a WITH(NOLOCK) ON d.recommend = a.custid
		INNER JOIN #tmpHeadline h ON a.groupID = h.GroupID
	UNION
	SELECT DISTINCT d.Srecommend, d.Mrecommend, d.Recommend, d.CustID, h.CustID
	FROM #Data d
		INNER JOIN bodb02.dbo.custAccount a WITH(NOLOCK) ON d.CustID = a.custid
		INNER JOIN #tmpHeadline h ON a.groupID = h.GroupID

	INSERT INTO #tmpResult
					( Headline,
						CustID ,
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
	SELECT h.username,
			h.CustID,
			SUM(BetCount) AS BetCount ,
			d.CurrencyId, 
			d.Currency,
			SUM (TotalBets) AS TotalBets, 
			SUM (TotalWins) AS TotalWins,
			SUM (TotalRefund) AS TotalRefund,
			SUM (CompanyTurnOver) AS CompanyTurnover,
			SUM (RealTurnOver) AS RealTurnover,
			SUM (CompanyGrossIncome) AS CompanyGrossIncome,
			SUM (CompanyComm) AS CompanyComm,
			SUM (TotalBetsBase) AS TotalBetsBase, 
			SUM (TotalWinsBase) AS TotalWinsBase,
			SUM (TotalRefundBase) AS TotalRefundBase,
			SUM (CompanyTurnOverBase) AS CompanyTurnoverBase,
			SUM (RealTurnOverBase) AS RealTurnoverBase,
			SUM (CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
			SUM (CompanyCommBase) AS CompanyCommBase,
			SUM(ExtraPT) ExtraPT,
			SUM(ExtraPTBase) ExtraPTBase
	FROM #Data d
		INNER JOIN #tmpSMA t ON d.Srecommend = t.SuperID AND d.Mrecommend = t.MasterID 
					AND d.Recommend = t.AgentID AND d.CustID = t.CustID
		INNER JOIN #tmpHeadline h ON t.Headline = h.CustID
	WHERE (@CustID = 0 OR h.CustID = @CustID)
	GROUP BY h.username, h.CustID, d.CurrencyId, d.Currency

	IF @Currency = '-1' --BaseRM
		BEGIN			
			INSERT INTO #Result
					( Headline,
						CustID ,
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
			SELECT Headline,
						CustID ,
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
			FROM #tmpResult
			WHERE (@TotalBetType = 0
					OR (@TotalBetType = 1 AND TotalBetsBase >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND TotalBetsBase <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND (TotalBetsBase - TotalWinsBase) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND (TotalBetsBase - TotalWinsBase) <= @GameIncomeValue)
					)										
		END		
		ELSE -- @Currency <> -1
		BEGIN
			INSERT INTO #Result
					( Headline ,
						CustID ,					
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
			SELECT 
				Headline,
						CustID ,
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
			FROM #tmpResult
			WHERE (@TotalBetType = 0
					OR (@TotalBetType = 1 AND TotalBets >= @TotalBetValue) 
					OR (@TotalBetType = -1 AND TotalBets <= @TotalBetValue)
					)
				AND (@GameIncomeType = 0
					OR (@GameIncomeType = 1 AND (TotalBets - TotalWins) >= @GameIncomeValue) 
					OR (@GameIncomeType = -1 AND (TotalBets - TotalWins) <= @GameIncomeValue)
					)				
		END

	IF @IsGrandTotal = 0
	BEGIN
		IF @IsDrillDown = 0
			IF @ExcludeNoData = 1
			BEGIN
				SELECT 
						Headline Username,
						CustID,
						SUM(BetCount) BetCount,
						CASE WHEN @Currency = '-1' THEN '-1' ELSE CurrencyId END CurrencyId,
						CASE WHEN @Currency = '-1' THEN 'RM' ELSE Currency END Currency,
						SUM(TotalBets) TotalBets,
						SUM(TotalWins) TotalWins,
						SUM(TotalRefund) TotalRefund,
						SUM(CompanyTurnOver) HouseTurnOver,
						SUM(RealTurnOver) RealTurnOver,
						SUM(CompanyGrossIncome) HouseGrossIncome,
						SUM(CompanyComm) HouseComm,
						SUM(ExtraPT) ExtraPT
				FROM #Result d
				GROUP BY Headline,
					CustID,
					CASE WHEN @Currency = '-1' THEN '-1' ELSE CurrencyId END,
					CASE WHEN @Currency = '-1' THEN 'RM' ELSE Currency END 
				ORDER BY Headline
			END
			ELSE
			BEGIN
				SELECT 
						h.Username,
						h.CustID,
						SUM(BetCount) BetCount,
						CASE WHEN @Currency = '-1' AND d.CustID IS NOT NULL THEN '-1' ELSE d.CurrencyId END CurrencyId,
						CASE WHEN @Currency = '-1' AND d.CustID IS NOT NULL THEN 'RM' ELSE d.Currency END Currency,
						SUM(TotalBets) TotalBets,
						SUM(TotalWins) TotalWins,
						SUM(TotalRefund) TotalRefund,
						SUM(CompanyTurnOver) HouseTurnOver,
						SUM(RealTurnOver) RealTurnOver,
						SUM(CompanyGrossIncome) HouseGrossIncome,
						SUM(CompanyComm) HouseComm,
						SUM(ExtraPT) ExtraPT
				FROM #tmpHeadline h
					LEFT JOIN #Result d ON h.CustID = d.CustId
				GROUP BY h.Username,
					h.CustID,
					CASE WHEN @Currency = '-1' AND d.CustID IS NOT NULL THEN '-1' ELSE d.CurrencyId END,
					CASE WHEN @Currency = '-1' AND d.CustID IS NOT NULL THEN 'RM' ELSE d.Currency END 
				ORDER BY h.Username
			END
		ELSE
		BEGIN
			SELECT r.Headline Username,
				b.CustID,
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
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) ELSE SUM(b.ExtraPT) END AS ExtraPT
		FROM #tmpResult b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.CustID = r.CustID	
		GROUP BY r.Headline, b.CustID, b.CurrencyID , b.Currency	
		ORDER BY b.Currency
		END
	END
	ELSE
	BEGIN
		SELECT 
				b.Currency AS Username,				
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
				CASE WHEN @Currency = '-1' THEN SUM(b.ExtraPTBase) ELSE SUM(b.ExtraPT) END AS ExtraPT
		FROM #tmpResult b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) AND b.CustID = r.CustID	
		GROUP BY b.CurrencyID , b.Currency		
		ORDER BY b.Currency
	END
	------------------------------------------V. Return Total Rows ------------------------------------------------------
	
	SELECT  'GrandTotalRM' AS ReportBy, 
			SUM(b.BetCount) AS BetCount ,
			-1 as CurrencyId, 'RM' AS Currency,
			SUM (b.TotalBetsBase) AS TotalBets, 
			SUM (b.TotalWinsBase) AS TotalWins,
			SUM (b.TotalRefundBase) AS TotalRefund,
			SUM (b.CompanyTurnoverBase) AS HouseTurnover,
			SUM (b.RealTurnoverBase) AS RealTurnover,
			SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM (b.CompanyCommBase) AS HouseComm,
			SUM (b.ExtraPTBase) ExtraPT
	FROM #tmpResult b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) 
									AND b.CustID = r.CustID 

	DROP TABLE #Data
	DROP TABLE #tmpResult
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #tmp_BetType
	DROP TABLE #recommend
	DROP TABLE #tmp_Device
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmpHouseProduct
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_SportType
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
	DROP TABLE #tmpHeadline	
	DROP TABLE #tmpSMA

END




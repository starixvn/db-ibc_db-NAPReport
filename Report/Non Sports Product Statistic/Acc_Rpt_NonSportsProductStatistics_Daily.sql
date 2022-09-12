/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

Use bodb02
GO 

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Daily]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@Site			VARCHAR(MAX) = 'ALL',	
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@SportBetType	VARCHAR(MAX) = '',
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
	@UsernameDrillDown	BIT = 0,
	@IsGrandTotal	BIT = 0, -- dont need to use in this report
	@IsExactly BIT = 0

AS
/*
	Created: 20160906@Sophia
	Task :	Non Sports Product Statistic - Daily Report [#Redmine: 62430]
	DB:		DBACC/bodb02
	Original: Acc_Rpt_CasinoGameStatistics_GameType_bettrans
	Revisions:
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
		20190708@Cherry: Fix issue VS + VS2
		20190724@Cherry: ExtraPT in House Turnover (#116766)
		20190812@Cherry: Add betfrom t (#115937)
		20190829@Cherry: Add param @UsernameDrillDown used for Nonsport Specific Member (#116766)
		20191225@Cherry: Apply ExtraPT in bettrans table (#123697)
		20200601@Cherry: Add Credit Site and support multiple currency (#135009)
		20200710@Cherry: Integrate Pragmatic Jackpot (#137268)
		20200828@Cherry: Integrate Saba.club Free Bet (#140109)
		20200917@Cherry: Improve performance (#141844)
		20200922@Cherry: Improve performance (#142096)
		20200928@Cherry: Hot fix (#142436)
		20201210@Cherry: Add Real Turnover (#146137)
		20201224@Cherry: Integrate Happy 5 Linked Games (#146537)
		20210120@Cherry: Integrate Saba Jackpot (#148293)
		20210506@Cherry: Integrate VGaming Jackpot (#154250)
		20220304@Cherry: Enhance username search for Non-sport games statistics report (#144260)
		20220512@Cherry: Hot fix (#172607)
		20220916@Cherry: Extend data type of Betfrom (#177655)

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
			 - @SportBetType (used for Saba.club - ProductID = 42)
				
	Query exam: 

	EXEC Acc_Rpt_NonSportsProductStatistics_Daily @WinlostDate = '2016-10-03' ,
	@ProductID='4,12,21,11,13,6,17,14,22,3,8,5', 
	@Bettype='1101, 1102, 1103, 1104,1700, 1701, 1702, 1703,2401, 2402, 2403, 2404, 2405,1800, 1801, 1802, 1803, 1804,2001, 2002, 2003, 2004, 2005, 2006, 2007,2008, 2009,1900,1501,1515',
 	@LeagueID='15223, 50717',
 	@Sporttype='180, 181, 182, 183, 184, 185, 186',@HousePTType	= 1,
	@HousePTValue  = 0.8
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
					NULL AS CompanyTurnover,
					NULL AS RealTurnover,
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
				NULL AS RealTurnover,
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm,
				NULL AS ExtraPT

			RETURN
		END
	END

	DECLARE @WLDate SMALLDATETIME , @IsMBC BIT, @IsSite BIT
	SELECT @WLDate = CAST (@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #Data (   srecommend INT, bettype INT, CustId INT,
						   BetCount INT, CurrencyId INT, Currency NVARCHAR(50), 
						   TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4), 
						   TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4), 
						   TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4), 
						   CompanyTurnover DECIMAL(19,4), CompanyTurnoverBase DECIMAL(19,4),
						   RealTurnover DECIMAL(19,4), RealTurnoverBase DECIMAL(19,4),
						   CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						   CompanyComm DECIMAL(19,4),  CompanyCommBase DECIMAL(19,4),
						   ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)
						   )

	CREATE TABLE #Result ( NoOfPlayers INT, 
						   BetCount INT, CurrencyId INT, Currency NVARCHAR(50), 
						   TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4), 
						   TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4), 
						   TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4), 
						   CompanyTurnover DECIMAL(19,4), CompanyTurnoverBase DECIMAL(19,4),
						   RealTurnover DECIMAL(19,4), RealTurnoverBase DECIMAL(19,4),
						   CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),
						   CompanyComm DECIMAL(19,4),  CompanyCommBase DECIMAL(19,4),
						   ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8)
						   )
	
	CREATE TABLE #Temp_MemIDs (CustID int)
	CREATE TABLE #tmpProductID (ProductID int)  
    CREATE TABLE #tmpBetType (Bettype INT)
	CREATE TABLE #tmpLeagueId (LeagueId INT, Bettype INT)  
	CREATE TABLE #tmpSporttype (Sporttype INT)
	CREATE TABLE #tmpCurrency (CurrencyId INT)
	CREATE TABLE #tmp_Site (Site VARCHAR(50))	
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), recommend INT)
	CREATE TABLE #tmpDevice (Betfrom NVARCHAR(3))
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))		
	CREATE TABLE #tmpContributionBettype (Bettype INT)
	CREATE TABLE #tmpSportBetType (Sporttype INT, Bettype INT)
	CREATE TABLE #tmpHouseProduct (ProductID INT)

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
	
	IF @Currency <> '-1'
    BEGIN
		INSERT INTO #tmpCurrency (CurrencyId)
		SELECT val FROM [dbo].strSplit(@Currency, ',')
	END
	
	DECLARE @splitter1 char(1) = ',', @splitter2 char(1) = '-',
		@league int, @bettypeid int,
		@start int, @leaguebettype nvarchar(4000), 
		@sportid int, @sporttypebettype nvarchar(4000), 
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
		INSERT INTO #tmpSporttype (Sporttype)
		SELECT val FROM [dbo].strSplit(@Sporttype, ',')
	END

	CREATE TABLE #Device (Betfrom NVARCHAR(3))
	IF @Device <> ''
    BEGIN
		INSERT INTO #tmpDevice (Betfrom)
		SELECT val FROM [dbo].strSplit(@Device, ',')
		
		INSERT INTO #Device (Betfrom)
		SELECT Betfrom
		FROM DBWH.bodb_Account.dbo.tbl_Betfrom

		IF NOT EXISTS(SELECT 1 FROM #Device d LEFT JOIN #tmpDevice t ON t.Betfrom = d.Betfrom WHERE t.Betfrom IS NULL) 
			SET @Device = ''
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
			IF @IsExactly = 0
				INSERT INTO #Temp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username LIKE @Username + '%' AND roleid = 1
			ELSE
				INSERT INTO #Temp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username = @Username AND roleid = 1

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
				
	INSERT INTO #tmpHouseProduct (ProductID)
	SELECT DISTINCT ProductID 
	FROM DBWH.bodb_Account.dbo.Product_Bettype WITH (NOLOCK)
	WHERE EventType = 255
		AND ProductID IN (SELECT ProductID FROM #tmpProductID)

	DELETE	s
	FROM	#SportBettype s
	WHERE	s.ProductID NOT IN (3, 5, 27, 23)   ---- NumberGame , Virtual Sports, Virtual Sports 2, NG2
			AND s.ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
			AND NOT EXISTS (SELECT Bettype FROM #tmpBetType b WHERE b.Bettype = s.Bettype)
			
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID = 23 --NG2
		AND NOT EXISTS (SELECT b.Bettype 
						FROM #tmpSporttype st INNER JOIN bodb02.dbo.SportBettypeMatrix b WITH(NOLOCK) ON st.Sporttype = b.SportType 
						WHERE b.BetType = s.Bettype AND (b.IsTest = 0 OR b.IsTest = @isTest))
						
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
		AND NOT EXISTS (SELECT b.Bettype FROM #tmpSportBetType b WHERE b.Bettype = s.Bettype)
		
	DELETE t
	FROM #tmpSportBetType t LEFT JOIN #SportBettype s ON t.Bettype = s.Bettype
	WHERE s.Bettype IS NULL

	--- End Sport Bettype Matrix------

	IF @Site <> 'ALL'
	BEGIN
		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		INSERT INTO #tmp_Company (SiteName, recommend)
		SELECT s.Site, c.recommend
		FROM #tmp_Site s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.Site = c.site
		WHERE c.roleid = 2
	END	 
                        
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
					AND a.ProductId IN (SELECT ProductID FROM #tmpProductID)
               GROUP BY ProductID,
                        SuperId      
    -- End ExtraPT         		
	
	INSERT INTO #tmpContributionBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 10
	
	DELETE #tmpContributionBettype
	WHERE bettype NOT IN (SELECT bettype FROM #SportBettype) 

	DELETE #SportBettype
	WHERE bettype IN (SELECT bettype FROM #tmpContributionBettype)
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EventType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmpSportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmpLeagueID (LeagueID, Bettype)
	CREATE CLUSTERED INDEX IX_SporttypeBettype ON #tmpSportBetType (Sporttype, Bettype)  
	CREATE CLUSTERED INDEX IX_Bettype ON #tmpContributionBettype (Bettype)  

	-- ProductID NOT IN (3, 4, 5, 27, 33))
	BEGIN
		---1. By bettype for normal Product
		INSERT INTO #Data (    srecommend, bettype, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   RealTurnover, RealTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase,
							   ExtraPT, ExtraPTBase			   
							   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
						  
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						 WHEN b.tpositiontaking = 1 THEN 0
						 ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						  WHEN b.tpositiontaking = 1 THEN 0
						  ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) * actualrate) AS RealTurnoverBase,		
								
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
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		
		OPTION(RECOMPILE)
		
		CREATE TABLE #tmpBettypeRNG (Bettype SMALLINT)
		INSERT INTO #tmpBettypeRNG (Bettype)
		SELECT Bettype
		FROM #SportBettype
		WHERE RefTable = 1 AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct)
		CREATE CLUSTERED INDEX IX_bettype ON  #tmpBettypeRNG(Bettype)
		 
		---1b. By bettype for Casino Product & Video Poker Games
		IF EXISTS(SELECT 1 FROM #tmpBettypeRNG)
		BEGIN
			INSERT INTO #Data (    srecommend, bettype, CustId,
								   BetCount, CurrencyId , 
								   TotalBets, TotalBetsBase, 
								   TotalWins, TotalWinsBase, 
								   TotalRefund, TotalRefundBase,
								   CompanyTurnover, CompanyTurnoverBase,  
								   CompanyGrossIncome, CompanyGrossIncomeBase, 
								   CompanyComm, CompanyCommBase,
								   ExtraPT, ExtraPTBase						   
								   )
		
			SELECT  srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
					
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			WHERE b.WinlostDate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpBettypeRNG)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
				AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
					)
			GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
			OPTION(RECOMPILE)
		END
		
		IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID IN (SELECT ProductID FROM #tmpHouseProduct)) 
		BEGIN
			INSERT INTO #Data (    srecommend, bettype, CustId,
								   BetCount, CurrencyId , 
								   TotalBets, TotalBetsBase, 
								   TotalWins, TotalWinsBase, 
								   TotalRefund, TotalRefundBase,
								   CompanyTurnover, CompanyTurnoverBase,  
								   CompanyGrossIncome, CompanyGrossIncomeBase, 
								   CompanyComm, CompanyCommBase,
								   ExtraPT, ExtraPTBase						   
								   )
		
			SELECT  srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
					
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			WHERE b.WinlostDate = @WLDate
				AND EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
				AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
					)
			GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
			OPTION(RECOMPILE)
		END
		
		DELETE d
		FROM #Data d INNER JOIN #tmpContributionBettype b ON d.bettype = b.bettype
		WHERE d.bettype IN (SELECT Bettype FROM #tmpSportBetType)
		
		IF EXISTS(SELECT 1 FROM #tmpContributionBettype) 
		BEGIN
			INSERT INTO #Data (    srecommend, bettype, CustId,
								   BetCount, CurrencyId , 
								   TotalBets, TotalBetsBase, 
								   TotalWins, TotalWinsBase, 
								   TotalRefund, TotalRefundBase,
								   CompanyTurnover, CompanyTurnoverBase,  
								   CompanyGrossIncome, CompanyGrossIncomeBase, 
								   CompanyComm, CompanyCommBase,
								   ExtraPT, ExtraPTBase					   
								   )
		
			SELECT  srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

					0 AS BetCount, b.Currency, 

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

					SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

					SUM(CASE WHEN b.statusID IN (103) THEN 0 
							WHEN tpositiontaking = 1 THEN 0
							ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN tpositiontaking = 1 THEN 0
							ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,		
									
					- SUM(b.ContributionStake3rd + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
					- SUM((b.ContributionStake3rd + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

					- SUM(scomm) AS CompanyComm,
					- SUM(scomm *actualrate) AS CompanyCommBase,
					
					- SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
					- SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			WHERE b.WinlostDate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #tmpContributionBettype) 
				AND (b.gameID NOT IN (SELECT Bettype FROM #tmpSportBetType)
					OR EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
					)	
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
				AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
				AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
				AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
				AND ( @Site = 'ALL'
					  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
					)
			GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
			OPTION(RECOMPILE)
		END
		 
		---1b. By bettype for Casino Product
		INSERT INTO #Data (    srecommend, bettype, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   RealTurnover, RealTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase,
							   ExtraPT, ExtraPTBase					   
							   )
	
		SELECT  srecommend, b.gameID,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency, 

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,

				SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,

				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,	
						
				SUM(CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,	
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,		
								
				- SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,

				- SUM(scomm) AS CompanyComm,
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.BettransLC b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue)
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
		OPTION(RECOMPILE)
	END
	
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 33) -- Poker Games
	BEGIN
		INSERT INTO #Data (    srecommend, bettype, CustId,
							   BetCount, CurrencyId , 
							   TotalBets, TotalBetsBase, 
							   TotalWins, TotalWinsBase, 
							   TotalRefund, TotalRefundBase,
							   CompanyTurnover, CompanyTurnoverBase,  
							   CompanyGrossIncome, CompanyGrossIncomeBase, 
							   CompanyComm, CompanyCommBase,
							   ExtraPT, ExtraPTBase						   
							   )
	
		SELECT  srecommend, b.bettype,
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
				
				- SUM(ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) ExtraPT,
				- SUM((ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) * actualrate) ExtraPTBase

		FROM  dbo.Bettrans b WITH (NOLOCK)
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33  AND RefTable = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.Currency <> 20 AND @ExcludeTest = 1))
			AND (@currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId)) 
			AND (@Username = '' OR EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId))
			AND (@Device = '' OR EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
	END
	
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 3)  -- Number Game
	BEGIN
		INSERT INTO #Data ( srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase									   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmpLeagueId l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
				OR EXISTS (SELECT 1 FROM #tmpLeagueId l WHERE l.LeagueID = 168 AND l.Bettype = b.bettype)
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue)
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
	END
		
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 4)  -- Live Casino
	BEGIN
		INSERT INTO #Data ( srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase								   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
							
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
	END
		
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 5)  -- Virtual Sports
	BEGIN
		INSERT INTO #Data ( srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase									   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EventType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmpSporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)

	----3.  VirtualSport (HR) 
		INSERT INTO #Data ( srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase									   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.Bettrans b WITH (NOLOCK)

		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EventType = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmpSporttype))				
				)		
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)
		GROUP BY b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
	END
		
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID = 27)  -- Virtual Sports 2
	BEGIN
		INSERT INTO #Data (srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase								   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
			
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EventType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT m.matchid FROM dbo.match m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmpSporttype))
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue)
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
				)
		GROUP BY b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
		
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype
					
		INSERT INTO #Data ( srecommend, bettype, CustID,   
						BetCount, CurrencyId , 
						TotalBets, TotalBetsBase, 
						TotalWins, TotalWinsBase, 
						TotalRefund, TotalRefundBase,
						CompanyTurnover, CompanyTurnoverBase,  
						CompanyGrossIncome, CompanyGrossIncomeBase, 
						CompanyComm, CompanyCommBase,
						ExtraPT, ExtraPTBase								   
					   )
	
		SELECT  srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

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
				- SUM(scomm *actualrate) AS CompanyCommBase,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase
				
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EventType = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@Username = '' OR EXISTS (SELECT 1 FROM #Temp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmpDevice d WHERE d.Betfrom = b.betfrom))
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmp_Company s WHERE s.recommend = b.recommend))
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue)
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue)
				)
		GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
	END
	
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
	---------------

---Get CurrencyName
		UPDATE  R   
		SET		Currency = E.currency
		FROM #Data R
		INNER JOIN Exchange e 
			ON E.exchangeid = R.CurrencyId

			 
---Get data 

	IF @Currency = '-1'  ----BASE RM 
	BEGIN 		
		INSERT INTO #Result (NoOfPlayers, BetCount, CurrencyId, Currency, 
							TotalBets, TotalWins, TotalRefund, CompanyTurnover, RealTurnover, CompanyGrossIncome, CompanyComm,
							TotalBetsBase, TotalWinsBase, TotalRefundBase, CompanyTurnoverBase, RealTurnoverBase,
							CompanyGrossIncomeBase, CompanyCommBase, ExtraPT, ExtraPTBase )
		SELECT  COUNT(DISTINCT CustID) AS NoOfPlayers, 
				SUM(BetCount) AS BetCount ,
				-1 as CurrencyId, 
				CASE WHEN @UsernameDrillDown = 0 THEN 'RM' ELSE ex.currency END Currency,	
				SUM (TotalBetsBase) AS TotalBets, 
				SUM (TotalWinsBase) AS TotalWins,
				SUM (TotalRefundBase) AS TotalRefund,
				SUM (CompanyTurnoverBase) AS CompanyTurnover,
				SUM (RealTurnoverBase) AS RealTurnover,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncome,
				SUM (CompanyCommBase) AS CompanyComm,
				SUM (TotalBetsBase) AS TotalBetsBase, 
				SUM (TotalWinsBase) AS TotalWinsBase,
				SUM (TotalRefundBase) AS TotalRefundBase,
				SUM (CompanyTurnoverBase) AS CompanyTurnoverBase,
				SUM (RealTurnoverBase) AS RealTurnoverBase,
				SUM (CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM (CompanyCommBase) AS CompanyCommBase,
				SUM (b.ExtraPTBase) ExtraPT,
				SUM (b.ExtraPTBase) ExtraPTBase
		FROM	#Data b
				INNER JOIN bodb02.dbo.exchange ex WITH (NOLOCK) ON b.CurrencyID = ex.exchangeid
		GROUP BY CASE WHEN @UsernameDrillDown = 0 THEN 'RM' ELSE ex.currency END
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
		INSERT INTO #Result (   NoOfPlayers,
								BetCount, CurrencyId , Currency,
								TotalBets, TotalBetsBase, 
								TotalWins, TotalWinsBase, 
								TotalRefund, TotalRefundBase,
								CompanyTurnover, CompanyTurnoverBase,  
								RealTurnover, RealTurnoverBase, 
								CompanyGrossIncome, CompanyGrossIncomeBase, 
								CompanyComm, CompanyCommBase,
								ExtraPT, ExtraPTBase	)
		SELECT   	COUNT(DISTINCT custid) AS NoOfPlayers,
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
					SUM(RealTurnover) AS RealTurnover, 
					SUM(RealTurnoverBase) AS RealTurnoverBase,
					SUM(CompanyGrossIncome) AS CompanyGrossIncome, 
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase, 
					SUM(CompanyComm) AS CompanyComm, 
					SUM(CompanyCommBase) AS CompanyCommBase,
					SUM(b.ExtraPT) ExtraPT,
					SUM(b.ExtraPTBase) ExtraPTBase
		FROM	#Data b
		GROUP BY CurrencyId, Currency
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
			SELECT CONVERT(VARCHAR(20), @WLDate, 107) AS  ReportBy, 
				NoOfPlayers, BetCount, CurrencyId, Currency, 
				TotalBets, TotalWins, TotalRefund, 
				CompanyTurnover AS HouseTurnover, 
				RealTurnover AS RealTurnover,
				CompanyGrossIncome AS HouseGrossIncome, 
				CompanyComm AS HouseComm,
				ExtraPT 
			FROM    #Result 
			ORDER BY Currency
		END
		ELSE
		BEGIN
			SELECT 
				CONVERT(VARCHAR(20), @WLDate, 107) AS ReportBy,
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
				INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID)
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
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) 	
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
			SUM (b.RealTurnoverBase) AS RealTurnover,
			SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM (b.CompanyCommBase) AS HouseComm,
			SUM (b.ExtraPTBase) ExtraPT
	FROM #Data b	
			INNER JOIN #Result r ON (@Currency = '-1' OR b.CurrencyID = r.CurrencyID) 
	
	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #Temp_MemIDs
	DROP TABLE #tmpBetType
	DROP TABLE #tmpDevice
	DROP TABLE #tmpLeagueId
	DROP TABLE #tmpProductID
	DROP TABLE #tmpHouseProduct
	DROP TABLE #tmp_Site
	DROP TABLE #tmp_Company
	DROP TABLE #tmpSporttype
	DROP TABLE #tmp_bettransm   
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	DROP TABLE #tmpCurrency
	DROP TABLE #tmpContributionBettype	
	DROP TABLE #tmpSportBetType
	DROP TABLE #tmpNetStakeBettype	
	DROP TABLE #tmpNoBetCountBettype
	DROP TABLE #tmpBettypeRNG

END  

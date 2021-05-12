/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_NonSportsProductStatistics_Hourly    Script Date: 8/30/2017 2:50:44 PM ******/

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Hourly]
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
	@UsernameDrillDown	BIT = 0

AS
/*
	Created: 20170612@Cherry
	Task :	Non Sports Product Statistic - Hourly Report [#Redmine: 71923]
	DB:		DBACC/bodb02
	Original: Acc_Rpt_NonSportsProductStatistics_Daily
	Revisions:	
		20170927@Cherry: Integrate Lucky 3 (#83101)
		20171006@Cherry: Add filter of Number Game Bettype (#83101)
		20171024@Cherry: Remove GamePayout (#85103)
		20171208@Cherry: Add param @UsernameDrillDown (#87888)
		20180328@Cherry: Integrate One RNG Jackpot (#89459)
		20181108@Cherry: Improve performance (#101547)
		20190314@Cherry: Integrate Video Poker Games (#108735)
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
		20201210@Cherry: Add Real Turnover (#146137)
		20210120@Cherry: Integrate Saba Jackpot (#148293)
		20210506@Cherry: Integrate VGaming Jackpot (#154250)

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
			 - @UsernameDrillDown = 1 if drilldown from Member
				
	Query exam: 

	EXEC Acc_Rpt_NonSportsProductStatistics_Hourly @WinlostDate = '2016-10-03' ,
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
					NULL AS GamePayout,
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
				NULL AS GamePayout,
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
	SELECT @WLDate = CAST(@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #Data (   [Hour] tinyint,  
						   srecommend INT, 
						   bettype INT,
						   CustId INT,
						   BetCount INT,
						   TotalBetsRM DECIMAL(19,4),
						   TotalWinsRM DECIMAL(19,4), 
						   TotalRefundRM DECIMAL(19,4),
						   CompanyTurnoverRM DECIMAL(19,4), 
						   RealTurnoverRM DECIMAL(19,4), 
						   CompanyGrossIncomeRM DECIMAL(19,4), 
						   CompanyCommRM DECIMAL(19,4),
						   ExtraPT DECIMAL(19,8)
						   )
						   
	CREATE TABLE #Result ( [Hour] tinyint,  
						   NoOfPlayers INT, 
						   BetCount INT, 
						   Currency VARCHAR(50),
						   TotalBets DECIMAL(19,4), 
						   TotalWins DECIMAL(19,4), 
						   GamePayout DECIMAL(19,4),
						   TotalRefund DECIMAL(19,4), 
						   CompanyTurnover DECIMAL(19,4), 
						   RealTurnover DECIMAL(19,4),
						   CompanyGrossIncome DECIMAL(19,4), 
						   CompanyComm DECIMAL(19,4),
						   ExtraPT DECIMAL(19,8)
						   )
	
	CREATE TABLE #Temp_MemIDs (
        CustID int
    )
	CREATE TABLE #tmpProductID (
        ProductID int
    )  
    CREATE TABLE #tmpBetType (
        Bettype INT
    )
	CREATE TABLE #tmpLeagueId (
        LeagueId INT, Bettype INT
    )  
	CREATE TABLE #tmpSporttype (
        Sporttype INT
    )
	CREATE TABLE #tmpSiteSuper (
        Srecommend INT
    )
	CREATE TABLE #tmpSite (
        Site VARCHAR(50)
    )
	CREATE TABLE #tmpDevice (
        Betfrom NVARCHAR(2)
    )
	CREATE TABLE #NonSportSetting(
		ProductID INT,
		Bettype INT,
		WalletType VARCHAR(50)
	)	
	CREATE TABLE #tmpCurrency (CurrencyId INT)	
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

	CREATE TABLE #Device (Betfrom NVARCHAR(2))
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
			IF @UsernameDrillDown = 0 
			BEGIN
				INSERT INTO #Temp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username LIKE @Username + '%' AND roleid = 1

				IF @Username NOT LIKE '%[^0-9]%' AND LEN(@Username) < 10
				BEGIN
				INSERT INTO #Temp_MemIDs (CustID)
				SELECT cu.custid FROM dbo.Customer cu WITH(NOLOCK) WHERE cu.custid = @Username AND cu.roleid = 1
					AND NOT EXISTS (SELECT 1 FROM #Temp_MemIDs c WHERE cu.custid = c.custid)
				END
			END
			ELSE	--@UsernameDrillDown = 1
			BEGIN
				INSERT INTO #Temp_MemIDs (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username = @Username AND roleid = 1
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
		AND ProductID IN (SELECT ProductID FROM #tmp_ProductID)

	DELETE	s
	FROM	#SportBettype s
	WHERE	s.ProductID NOT IN (3, 5, 27)   ---- NumberGame , Virtual Sports, Virtual Sports 2
			AND s.ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
			AND NOT EXISTS (SELECT Bettype FROM #tmpBetType b WHERE b.Bettype = s.Bettype)

	INSERT INTO #NonSportSetting (ProductID, Bettype, WalletType)
	SELECT ProductID, Bettype, WalletType
	FROM DBDW.bodb_Account.dbo.NonSportSetting
	WHERE WalletType = 'SingleWallet'
	
	DELETE s
	FROM	#SportBettype s LEFT JOIN #NonSportSetting t ON s.ProductID = t.ProductID AND s.Bettype = t.Bettype 
	WHERE t.Bettype IS NULL
	
	DELETE s
	FROM #SportBettype s
	WHERE s.ProductID IN (SELECT ProductID FROM #tmpHouseProduct) --Saba.club, VGaming
		AND NOT EXISTS (SELECT b.Bettype FROM #tmpSportBetType b WHERE b.Bettype = s.Bettype)
		
	DELETE t
	FROM #tmpSportBetType t LEFT JOIN #SportBettype s ON t.Bettype = s.Bettype
	WHERE s.Bettype IS NULL
	
	INSERT INTO #tmpContributionBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 10
	
	DELETE #tmpContributionBettype
	WHERE bettype NOT IN (SELECT bettype FROM #SportBettype) 

	DELETE #SportBettype
	WHERE bettype IN (SELECT bettype FROM #tmpContributionBettype)

	--- End Sport Bettype Matrix------
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EventType, RefTable)   
	CREATE CLUSTERED INDEX IX_SporttypeBettype ON #tmpSportBetType (Sporttype, Bettype)  
	CREATE CLUSTERED INDEX IX_Bettype ON #tmpContributionBettype (Bettype)  
	
	IF @Currency <> '-1'
    BEGIN
		INSERT INTO #tmpCurrency (CurrencyId)
		SELECT val FROM [dbo].strSplit(@Currency, ',')
	END

	------Get Site
	SELECT @IsMBC = 0
	SELECT @IsSite = 0

	IF @Site <> 'ALL'
	BEGIN 

		INSERT INTO #tmpSite (Site)
		SELECT RTRIM(LTRIM(val)) FROM [dbo].strSplit(@Site, ',')
		
		INSERT INTO #tmpSiteSuper (Srecommend)
		SELECT c.srecommend
		FROM #tmpSite s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.Site = c.site
		WHERE c.roleid = 4				
	END	 
	
	CREATE TABLE #ExtraComm (ProductID INT, SuperID INT, ExtraComm DECIMAL(9, 8))
                        
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
 
	---------------------------------------------- 
	---1. By bettype for normal Product
		INSERT INTO #Data ( [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   RealTurnoverRM,
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT		   
							   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], srecommend, b.bettype,					
				
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN b.StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,
						
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.oddsspread END) * actualrate) AS RealTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm * actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT							
				
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0,3) AND ProductID NOT IN (3,4,5,27,26))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
				
		OPTION(RECOMPILE)		 

		---1b. By bettype for Casino Product
		IF EXISTS(SELECT 1 FROM #SportBettype WHERE ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct))
		BEGIN
			INSERT INTO #Data (  [Hour] , 
							   srecommend, 
							   bettype, 
							   CustId ,
							   BetCount ,
							   TotalBetsRM ,
							   TotalWinsRM , 
							   TotalRefundRM ,
							   CompanyTurnoverRM , 
							   CompanyGrossIncomeRM , 
							   CompanyCommRM,
							   ExtraPT							   
								)
		
			SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

					COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
									
					- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

					- SUM(scomm * actualrate) AS CompanyCommRM,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT
						
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			
			WHERE b.WinlostDate = @WLDate
				AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct))
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
				AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
				AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
				AND ( @Site = 'ALL'
					  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END, 
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
					
			OPTION(RECOMPILE)	
		END
		
		IF EXISTS (SELECT 1 FROM #tmpProductID WHERE ProductID IN (SELECT ProductID FROM #tmpHouseProduct)) 
		BEGIN
			INSERT INTO #Data (  [Hour] , 
							   srecommend, 
							   bettype, 
							   CustId ,
							   BetCount ,
							   TotalBetsRM ,
							   TotalWinsRM , 
							   TotalRefundRM ,
							   CompanyTurnoverRM , 
							   CompanyGrossIncomeRM , 
							   CompanyCommRM,
							   ExtraPT							   
								)
		
			SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

					COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
									
					- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

					- SUM(scomm * actualrate) AS CompanyCommRM,
					
					- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT
						
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			
			WHERE b.WinlostDate = @WLDate
				AND EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
				AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
				AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
				AND ( @Site = 'ALL'
					  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END, 
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
					
			OPTION(RECOMPILE)	
		END

		DELETE d
		FROM #Data d INNER JOIN #tmpContributionBettype b ON d.bettype = b.bettype
		WHERE d.bettype IN (SELECT Bettype FROM #tmpSportBetType)
		
		IF EXISTS(SELECT 1 FROM #tmpContributionBettype)
		BEGIN
			INSERT INTO #Data (  [Hour] ,
							   srecommend, 
							   bettype,  
							   CustId ,
							   BetCount ,
							   TotalBetsRM ,
							   TotalWinsRM , 
							   TotalRefundRM ,
							   CompanyTurnoverRM , 
							   CompanyGrossIncomeRM , 
							   CompanyCommRM,
							   ExtraPT								   
								)
		
			SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], srecommend, b.gameID,
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

					0 AS BetCount, 

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

					SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

					SUM((CASE WHEN b.statusID IN (103) THEN 0 
							WHEN b.tpositiontaking = 1 THEN 0
							ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
									
					- SUM((b.ContributionStake3rd + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

					- SUM(scomm *actualrate) AS CompanyCommRM,
					
					- SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
								ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT			
					
			FROM  dbo.BettransRNG b WITH (NOLOCK)
			WHERE b.WinlostDate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND b.gameID IN (SELECT Bettype FROM #tmpContributionBettype)
				AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
				AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
				AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
				AND ( @Site = 'ALL'
					  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
					)
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
						ELSE  DATEPART(HOUR, b.transdate) END, 
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
					
			OPTION(RECOMPILE)	
		END

		---1b. By bettype for Casino Product
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   RealTurnoverRM,
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT				   
							)
	
		SELECT   CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], srecommend, b.gameID,
					
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,	
						
				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverRM,	
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT			
				
		FROM  dbo.BettransLC b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.GameId IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY   CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END, 
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID
					
		OPTION(RECOMPILE)	

	---- Lucky 3 
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT							   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 --kickoff at 23PM and settled on the next day then convert to 0 AM 
					ELSE  DATEPART(HOUR, m.kickofftime) 
				END AS [Hour],	srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT		
				
		FROM  dbo.Bettrans b WITH (NOLOCK)
			INNER JOIN dbo.match m WITH (NOLOCK) ON b.matchid = m.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 26)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets			
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 --kickoff at 23PM and settled on the next day then convert to 0 AM 
					ELSE  DATEPART(HOUR, m.kickofftime)  END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
				
	---- NumberGame 
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT						   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 --kickoff at 23PM and settled on the next day then convert to 0 AM 
					ELSE  DATEPART(HOUR, m.kickofftime) 
				END AS [Hour],	srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT						
				
		FROM  dbo.Bettrans b WITH (NOLOCK)	
			INNER JOIN dbo.match m WITH (NOLOCK) ON b.matchid = m.matchid		
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM #tmpLeagueID l WHERE m.leagueid = l.LeagueID AND l.Bettype = b.bettype)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 --kickoff at 23PM and settled on the next day then convert to 0 AM 
					ELSE  DATEPART(HOUR, m.kickofftime) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
				
	---- Live Casino 
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT						   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 --bet at 23PM then convert to 0 AM 
					ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour], srecommend, b.bettype,	
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT
						
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 --bet at 23PM then convert to 0 AM 
					ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END,srecommend, b.bettype
		OPTION(RECOMPILE)
				
	---- VirtualSport (Soccer)
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT						   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 --bet at 23PM then convert to 0 AM 
					ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour],	srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT
						
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND Eventtype = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmpSporttype sp ON sp.Sporttype = m.sporttype WHERE m.matchid = b.matchid)			
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 --bet at 23PM then convert to 0 AM 
					ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)

	----  VirtualSport (HR) 
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT					   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
					THEN 0 --bet at 23PM then convert to 0 AM 
				ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour], srecommend, b.bettype,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm * actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT
							
		FROM  dbo.Bettrans b WITH (NOLOCK)
		WHERE b.WinlostDate = @WLDate
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND Eventtype = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS (SELECT 1 From VSRaceInfo r WITH (NOLOCK) INNER JOIN #tmpSporttype sp ON sp.Sporttype = r.sporttype WHERE r.EventID = b.matchid)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				 OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
				ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
				
		--VirtualSports 2
		CREATE TABLE #tmp_bettransm (refno BIGINT)
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM,
						   ExtraPT				   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour],	srecommend, b.bettype,
				
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm * actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT				
				
		FROM  dbo.Bettrans b WITH (NOLOCK)			
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EventType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS(SELECT 1 FROM dbo.match m WITH (NOLOCK) 
									INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype 
								WHERE m.matchid = b.matchid)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
				
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype
					
		INSERT INTO #Data (  [Hour] ,  
						   srecommend, 
						   bettype,
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM, 
						   ExtraPT				   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour],	srecommend, b.bettype,
				
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 
						WHEN b.tpositiontaking = 1 THEN 0
						ELSE (1 - b.tpositiontaking - CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm * actualrate) AS CompanyCommRM,
				
				- SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPT								
				
		FROM  dbo.Bettrans b WITH (NOLOCK)			
		WHERE b.WinlostDate = @WLDate
			AND b.bettype in (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EventType = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND EXISTS(SELECT 1 FROM #tmp_bettransm bm WHERE bm.refno = b.refno)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId) OR @currency = '-1') 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR EXISTS(SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend)
				)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.bettype
		OPTION(RECOMPILE)
		
	--Update Real Turnover
	CREATE TABLE #tmpNetStakeBettype (Bettype INT)
	INSERT INTO #tmpNetStakeBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 13
	
	UPDATE #Data
	SET RealTurnoverRM = CompanyTurnoverRM
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
			 
	CREATE TABLE #DimHour(
		[Hour] [tinyint],
		[Description] [varchar](50)
		)
		
	INSERT INTO #DimHour([Hour], [Description])
	SELECT [Hour], [Description]
	FROM DBDW.[bodb_Account].[dbo].[DimHour]
		
	IF @Currency = '-1'  
	BEGIN 		
		INSERT INTO #Result ([Hour], NoOfPlayers, BetCount,	Currency, TotalBets, TotalWins, GamePayout, TotalRefund, 
							CompanyTurnover, RealTurnover, CompanyGrossIncome, CompanyComm, ExtraPT)							
		SELECT  [Hour], 
				COUNT(DISTINCT CustID) AS NoOfPlayers, 
				SUM(BetCount) AS BetCount ,
				'RM' Currency,
				SUM(TotalBetsRM) AS TotalBets, 
				SUM(TotalWinsRM) AS TotalWins,
				CASE WHEN SUM(ISNULL(TotalBetsRM,0)) = 0 THEN NULL ELSE SUM(TotalWinsRM)/SUM(TotalBetsRM) END AS GamePayout,
				SUM(TotalRefundRM) AS TotalRefund,
				SUM(CompanyTurnoverRM) AS CompanyTurnover,
				SUM(RealTurnoverRM) AS RealTurnover,
				SUM(CompanyGrossIncomeRM) AS CompanyGrossIncome,
				SUM(CompanyCommRM) AS CompanyComm,
				SUM(b.ExtraPT) ExtraPT
		FROM	#Data b
		GROUP BY [Hour] 
		HAVING (@TotalBetType = 0
				OR (@TotalBetType = 1 AND SUM(TotalBetsRM) >= @TotalBetValue) 
				OR (@TotalBetType = -1 AND SUM(TotalBetsRM) <= @TotalBetValue)
				)
			AND (@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND SUM(TotalBetsRM - TotalWinsRM) >= @GameIncomeValue) 
				OR (@GameIncomeType = -1 AND SUM(TotalBetsRM - TotalWinsRM) <= @GameIncomeValue)
				)  						      
	END 			

	SELECT
		a.Description AS ReportBy, 
		NoOfPlayers, 
		BetCount, 
		Currency,
		TotalBets, 
		TotalWins, 
		TotalRefund, 
		CompanyTurnover AS HouseTurnover, 
		RealTurnover, 
		CompanyGrossIncome AS HouseGrossIncome, 
		CompanyComm AS HouseComm,
		ExtraPT 
	FROM  #DimHour a LEFT JOIN #Result b ON a.[Hour]=b.[Hour]
	ORDER BY a.Hour
	
	DROP TABLE #DimHour
	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #Temp_MemIDs
	DROP TABLE #tmpBetType
	DROP TABLE #tmpDevice
	DROP TABLE #tmpLeagueId
	DROP TABLE #tmpProductID
	DROP TABLE #tmpHouseProduct
	DROP TABLE #tmpSite
	DROP TABLE #tmpSiteSuper
	DROP TABLE #tmpSporttype
	DROP TABLE #tmp_bettransm
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	DROP TABLE #tmpCurrency
	DROP TABLE #tmpContributionBettype
	DROP TABLE #tmpSportBetType
	DROP TABLE #tmpNetStakeBettype	
	DROP TABLE #tmpNoBetCountBettype

END 


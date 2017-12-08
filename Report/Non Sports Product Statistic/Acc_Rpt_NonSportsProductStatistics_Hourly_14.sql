USE bodb02
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_NonSportsProductStatistics_Hourly_14    Script Date: 8/30/2017 2:50:44 PM ******/

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Hourly_14]
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
	@UsernameDrillDown	BIT = 0

AS
/*
	Created: 20170612@Cherry
	Task :	Non Sports Product Statistic - Hourly Report [#Redmine: 71923]
	DB:		DBACC/bodb02
	Original: Acc_Rpt_NonSportsProductStatistics_Daily
	Revisions:	
		- 20170927@Cherry: Integrate Lucky 3 (#83101)
		- 20171006@Cherry: Add filter of Number Game Bettype (#83101)
		- 20171024@Cherry: Remove GamePayout (#85103)
		- 20171208@Cherry: Add param @UsernameDrillDown (#87888)

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
			 - @UsernameDrillDown = 1 if drilldown from Member
				
	Query exam: 

	EXEC Acc_Rpt_NonSportsProductStatistics_Hourly_14 @WinlostDate = '2016-10-03' ,
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
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm
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
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm

			RETURN
		END
	END

	DECLARE @WLDate DATETIME , @IsMBC BIT, @IsSite BIT
	SELECT @WLDate = @WinlostDate

	CREATE TABLE #Data (   [Hour] tinyint,  
						   CustId INT,
						   BetCount INT,
						   TotalBetsRM MONEY,
						   TotalWinsRM MONEY, 
						   TotalRefundRM MONEY,
						   CompanyTurnoverRM MONEY, 
						   CompanyGrossIncomeRM MONEY, 
						   CompanyCommRM MONEY
						   )
						   
	CREATE TABLE #Result ( [Hour] tinyint,  
						   NoOfPlayers INT, 
						   BetCount INT, 
						   Currency VARCHAR(50),
						   TotalBets MONEY, 
						   TotalWins MONEY, 
						   GamePayout MONEY,
						   TotalRefund MONEY, 
						   CompanyTurnover MONEY, 
						   CompanyGrossIncome MONEY, 
						   CompanyComm MONEY
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
	CREATE TABLE #tmpGameTableId (
        GameTableID INT
    )
	CREATE TABLE #tmpAllDepSuper (
        Srecommend INT
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

	IF @Sporttype <> ''
    BEGIN
		INSERT INTO #tmpSporttype (Sporttype)
		SELECT val FROM [dbo].strSplit(@Sporttype, ',')
	END
		
	IF @GameTableID <> ''
    BEGIN
		INSERT INTO #tmpGameTableId (GameTableID)
		SELECT val FROM [dbo].strSplit(@GameTableID, ',')
	END

	IF @Device <> ''
    BEGIN
		INSERT INTO #tmpDevice (Betfrom)
		SELECT val FROM [dbo].strSplit(@Device, ',')
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

	DELETE	s
	FROM	#SportBettype s
	WHERE	s.ProductID NOT IN (3, 5, 27)   ---- NumberGame , Virtual Sports, Virtual Sports 2
			AND NOT EXISTS (SELECT Bettype FROM #tmpBetType b WHERE b.Bettype = s.Bettype)

	INSERT INTO #NonSportSetting (ProductID, Bettype, WalletType)
	SELECT ProductID, Bettype, WalletType
	FROM DBDW.bodb_Account.dbo.NonSportSetting
	WHERE WalletType = 'SingleWallet'
	
	DELETE s
	FROM	#SportBettype s LEFT JOIN #NonSportSetting t ON s.ProductID = t.ProductID AND s.Bettype = t.Bettype 
	WHERE t.Bettype IS NULL

	--- End Sport Bettype Matrix------

	------Get Site
	SELECT @IsMBC = 0
	SELECT @IsSite = 0

	IF @Site <> 'ALL'
	BEGIN 

		INSERT INTO #tmpSite (Site)
		SELECT RTRIM(LTRIM(val)) FROM [dbo].strSplit(@Site, ',')
		
		----Specific Site
		IF EXISTS (SELECT 1 FROM #tmpSite WHERE Site NOT IN ('MBC Group'))
		BEGIN 
			SELECT @IsSite = 1

			INSERT INTO #tmpSiteSuper (Srecommend)
			SELECT	f.custid 
			FROM	#tmpSite s
			CROSS APPLY f_DepSuper_1(s.Site) f		 
		END


		-- If 'MBC Group' : Credit Site only, so get the Srecommend of Deposit to exclude later  	
		IF EXISTS (SELECT 1 FROM #tmpSite WHERE Site IN ('MBC Group'))					
		BEGIN 

			SELECT @IsMBC = 1   

			INSERT INTO #tmpAllDepSuper (Srecommend)
			SELECT custid FROM f_DepSuper_1('ALL')
			
			IF @IsSite = 1
			BEGIN 				
				DELETE A
				FROM  #tmpAllDepSuper A
				INNER JOIN #tmpSiteSuper S
					ON A.Srecommend = S.Srecommend
			END 			
		END
					
	END	 

 
	---------------------------------------------- 
	---1. By bettype for normal Product
		INSERT INTO #Data ( [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 					   
							   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END AS [Hour],					
				
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN b.StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5,27,26)   --- NumberGame, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Lucky 3
			AND s.RefTable IN (0,3)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
		 

		---1b. By bettype for Casino Product
		INSERT INTO #Data (  [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 								   
							)
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.BettransRNG14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.GameId 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5,27,26)   --- NumberGame, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Lucky 3
			AND s.RefTable = 1
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END, 
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END

		 

		---1b. By bettype for Casino Product
		INSERT INTO #Data (  [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 						   
							)
	
		SELECT   CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END AS [Hour], 
					
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.BettransLC14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.GameId 
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID NOT IN (3,4,5,27,26)   --- NumberGame, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Lucky 3 
			AND s.RefTable = 2
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY   CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0
					ELSE  DATEPART(HOUR, b.transdate) END, 
					CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END

	----2. NumberGame & Live Casino & VirtualSport (Soccer) & Lucky 3 
		INSERT INTO #Data (  [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 							   
					   )
	
		SELECT  CASE WHEN s.ProductID IN (3, 26) THEN	--Number Game, Lucky 3
					CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 --kickoff at 23PM and settled on the next day then convert to 0 AM 
					ELSE  DATEPART(HOUR, m.kickofftime) 
					END 
				ELSE	--Casino, Virtual Sports and Keno
					CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 --bet at 23PM then convert to 0 AM 
					ELSE  DATEPART(HOUR, b.transdate) 
					END
				END AS [Hour],	
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s ON s.Bettype = b.bettype 
			INNER JOIN Match14 m WITH (NOLOCK) ON m.MatchId = b.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID IN (3,4,5,26) --- NumberGame, SLI-Live Casino, VirtualSport, Lucky 3
			AND s.Eventtype = 1
			AND (	s.ProductID = 26
				OR	(
						(EXISTS (SELECT 1 From #tmpLeagueId l WHERE l.LeagueId = m.leagueid AND l.Bettype = b.bettype) AND s.ProductID = 3)
						OR (@LeagueId = '' AND s.ProductID = 3)
					)
				OR (
						(EXISTS (SELECT 1 From #tmpGameTableId g WHERE g.GameTableID = m.leagueid) AND s.ProductID = 4)
						OR (@GameTableId = '' AND s.ProductID = 4)
					)
				OR (
						(EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = m.sporttype) AND s.ProductID = 5)
						OR (@Sporttype = '' AND s.ProductID = 5)
					)
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN s.ProductID IN (3, 26) THEN	
					CASE WHEN DATEDIFF(dd, m.kickofftime, b.winlostdate) = 1 and DATEPART(HOUR, m.kickofftime) = 23 
						THEN 0 
					ELSE  DATEPART(HOUR, m.kickofftime) 
					END 
				ELSE	--Casino, Virtual Sports and Keno
					CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
						THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) 
					END
				END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END

	----3.  VirtualSport (HR) 
		INSERT INTO #Data (  [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 						   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 
					THEN 0 --bet at 23PM then convert to 0 AM 
				ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour],
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s 
				ON s.Bettype = b.bettype 
			INNER JOIN VSRaceInfo r WITH (NOLOCK) 
				ON r.EventId = b.matchid
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID = 5 --- VirtualSport (HR)
			AND s.Eventtype = 3
			AND (	
					EXISTS (SELECT 1 From #tmpSporttype sp WHERE sp.Sporttype = r.sporttype)
					OR @Sporttype = ''
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
				ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
			 
		--VirtualSports 2
		INSERT INTO #Data (  [Hour] ,  
						   CustId ,
						   BetCount ,
						   TotalBetsRM ,
						   TotalWinsRM , 
						   TotalRefundRM ,
						   CompanyTurnoverRM , 
						   CompanyGrossIncomeRM , 
						   CompanyCommRM 							   
					   )
	
		SELECT  CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) 
				END AS [Hour],	
				
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,

				COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, 

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsRM,

				SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundRM,

				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE (1- b.tpositiontaking) * b.stake END) * actualrate) AS CompanyTurnoverRM,		
								
				- SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeRM,

				- SUM(scomm *actualrate) AS CompanyCommRM
				
		FROM  dbo.Bettrans14 b WITH (NOLOCK)
			INNER JOIN #SportBettype s ON s.Bettype = b.bettype 			
		WHERE b.WinlostDate = @WLDate
			AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
			AND s.ProductID = 27
			AND ((b.bettype <> 2799 AND b.matchid >= 0 AND EXISTS(SELECT 1 FROM dbo.match14 m WITH (NOLOCK) 
														INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype 
											WHERE m.matchid = b.matchid))
				OR (b.bettype = 2799 AND b.matchid = 2799 AND EXISTS(SELECT 1 FROM dbo.bettransm14 bm WITH(NOLOCK)
														INNER JOIN dbo.match14 m WITH(NOLOCK) ON bm.matchid = m.matchid 
														INNER JOIN #tmpSporttype st ON m.sporttype = st.Sporttype 
												WHERE bm.refno = b.refno))	
				)
			AND ((b.Currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
			AND (b.currency = @currency OR @currency IN (0,-1)) 			
			AND (EXISTS (SELECT 1 From #Temp_MemIDs m WHERE m.CustID = b.custId) OR @Username = '')
			AND (EXISTS (SELECT 1 From #tmpDevice f WHERE f.betfrom = b.betfrom) OR @Device = '')
			AND ( @Site = 'ALL'
				  OR (EXISTS (SELECT 1 From #tmpSiteSuper s WHERE s.srecommend = b.srecommend) AND @IsSite = 1)
				  OR (NOT EXISTS (SELECT 1 From #tmpAllDepSuper d WHERE d.srecommend = b.srecommend) AND @IsMBC = 1)
			)
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
			)
		GROUP BY CASE WHEN DATEDIFF(dd, b.transdate, b.winlostdate) = 1 and DATEPART(HOUR, b.transdate) = 23 THEN 0 
					ELSE  DATEPART(HOUR, b.transdate) END,
				CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END
	
	CREATE TABLE #DimHour(
		[Hour] [tinyint],
		[Description] [varchar](50)
		)
		
	INSERT INTO #DimHour([Hour], [Description])
	SELECT [Hour], [Description]
	FROM DBDW.[bodb_Account].[dbo].[DimHour]
		
	IF @Currency = -1  
	BEGIN 		
		INSERT INTO #Result ([Hour], NoOfPlayers, BetCount,	Currency, TotalBets, TotalWins, GamePayout, TotalRefund, CompanyTurnover, CompanyGrossIncome, CompanyComm)							
		SELECT  [Hour], 
				COUNT(DISTINCT CustID) AS NoOfPlayers, 
				SUM(BetCount) AS BetCount ,
				'RM' Currency,
				SUM(TotalBetsRM) AS TotalBets, 
				SUM(TotalWinsRM) AS TotalWins,
				CASE WHEN SUM(ISNULL(TotalBetsRM,0)) = 0 THEN NULL ELSE SUM(TotalWinsRM)/SUM(TotalBetsRM) END AS GamePayout,
				SUM(TotalRefundRM) AS TotalRefund,
				SUM(CompanyTurnoverRM) AS CompanyTurnover,
				SUM(CompanyGrossIncomeRM) AS CompanyGrossIncome,
				SUM(CompanyCommRM) AS CompanyComm
		FROM	#Data
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
		CompanyGrossIncome AS HouseGrossIncome, 
		CompanyComm AS HouseComm
	FROM #DimHour a LEFT JOIN #Result b ON a.[Hour]=b.[Hour]
	ORDER BY a.Hour
	
	DROP TABLE #DimHour
	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #SportBettype
	DROP TABLE #Temp_MemIDs
	DROP TABLE #tmpAllDepSuper
	DROP TABLE #tmpBetType
	DROP TABLE #tmpDevice
	DROP TABLE #tmpGameTableId
	DROP TABLE #tmpLeagueId
	DROP TABLE #tmpProductID
	DROP TABLE #tmpSite
	DROP TABLE #tmpSiteSuper
	DROP TABLE #tmpSporttype


END 

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Hourly_14] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Hourly_14] TO [bodbAdminNet]
GO 

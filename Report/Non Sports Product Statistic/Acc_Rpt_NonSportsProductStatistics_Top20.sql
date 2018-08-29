USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Top20]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@TopType		TINYINT = 0,
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
	@RoleID			TINYINT = 1,
	@SortColumnName	VARCHAR(50) = 'GameIncome'

AS

/*
	Creator: Percy
	Date: 2016-12-02
	DB: DBACC.bodb02
	Task: Risk and Control - Non-Sport Game Statistics Report - Report by Super/Master/Agent/Username

	Revisions:
		- 20170227@Percy: support search multiple username [RedmineID: #71342]
		- 20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		- 20170815@Cherry: support top 20 by super, master, agent, username (#71923)
		- 20171006@Cherry: Add filter of Number Game Bettype (#83101)
		- 20180328@Cherry: Integrate One RNG Jackpot (#89459)
		- 20180808@Cherry: Integrate Poker Games (#97809)

	Param's Explanation:
		- @username: search keyword
		- @TopType:
			0: all
			1: top winner
			2: top loser
		- @Site: List of Company filter
			'ALL'	: All sites (MBC + Licensees)
			'MBC'	: MBC sites only
			'12bet' : Specific Licensee Name 
		- @ProductID: string filter by Product 
		- @BetType: string filter by bettype
		- @LeagueId: string filter by LeagueId (only use for ProductID = 3 - Number Game get LeagueId)  
		- @Sporttype: string filter by Sporttype (only use for ProductID = 5 - Virtual Sports get Sporttype)
		- @GameTableId: filter by specific game table (only use for ProductID = 4 - Live Casino get leagueID)
		- @currency: 
			-1: All convert to RM currency
			 0: All original currencyID
			>0: Filter by original currencyID  
		- @TotalBetType, @GameIncomeType, @HousePTType: 
			 1: >=
			-1: <=
		- @TotalBetValue: Value to compare with SUM(actual_stake)
		- @GameIncomeValue: Value to compare with SUM(winlost-actual_stake)
		- @HousePTValue: Value to compare with 1-tpositiontaking
		- @IsDrillDown: associated link
		- @IsGrandTotal: drilldown grandtotal
		- @RoleID: 1=Username, 2=Agent, 3=Master, 4=Super
		- @SortType: Sort by Column
		1: BetCount, 2: TotalBets, 3: Game Income, 4: Game Payout, 5: Turnover, 6: Gross Income, 7: Comm, 8: Net Income
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CustList VARCHAR(MAX)

	IF CHARINDEX(',', @Username) <> 0
	BEGIN
		EXEC dbo.Acc_CustomerSelCustByUsernameList @Username = @Username, @RoleId = @RoleId, @CustList = @CustList OUTPUT

		IF @CustList IS NULL -- invalid username
		BEGIN
			SELECT TOP 0 *
			FROM (
				SELECT
					NULL AS TopType,
					NULL AS ReportById,
					NULL AS ReportBy,
					NULL AS RoleId,
					NULL AS RoleName,
					NULL AS BetCount,
					NULL AS NoOfPlayers,
					NULL AS CurrencyId,
					NULL AS Currency,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnover,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm,
					NULL AS HousePositionTaking,
					NULL AS SiteName
			) A

			-- GrandTotal
			IF @TopType <> 0 AND @IsDrillDown = 1
			BEGIN
				SELECT
					NULL AS ReportBy,
					NULL AS BetCount,
					NULL AS NoOfPlayers,
					NULL AS CurrencyId,
					NULL AS Currency,
					NULL AS TotalBets,
					NULL AS TotalWins,
					NULL AS TotalRefund,
					NULL AS CompanyTurnover,		
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm
			END

			RETURN
		END
	END

	DECLARE @WLDate DATETIME
	SELECT  @WLDate = @WinlostDate

	CREATE TABLE #tmp_ProductID		(ProductID TINYINT)
	CREATE TABLE #tmp_BetType		(Bettype SMALLINT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT, Bettype INT)
	CREATE TABLE #tmp_SportType		(Sporttype SMALLINT)
	CREATE TABLE #tmp_GameTableID	(GameTableID INT)
	CREATE TABLE #tmp_Devide		(Betfrom NVARCHAR(2))

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

	IF @Device <> ''
	BEGIN
		INSERT INTO #tmp_Devide (Betfrom)
		SELECT val FROM dbo.strSplit(@Device, ',')
	END
	-- End Info from Pars list

	-- Get Sport Bettype Matrix --
	DECLARE @isTest BIT = 0
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype (ProductID TINYINT, Bettype SMALLINT, EvenType TINYINT, RefTable TINYINT)
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.RefTable
	FROM
		dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN #tmp_ProductID p ON s.ProductID = p.ProductID
		INNER JOIN #tmp_BetType b ON s.BetType = b.Bettype

	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.RefTable
	FROM
		dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN #tmp_ProductID p ON s.ProductID = p.ProductID
	WHERE p.ProductID IN (3, 5, 27) -- Number Game, Virtual Sports, Virtual Sports 2

	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_BetType
	-- End Get Sport Bettype Matrix --

	-- Get Site	
	CREATE TABLE #tmp_Site (Site VARCHAR(50))
	CREATE TABLE #tmp_Company (SiteName VARCHAR(50), srecommend INT)
	CREATE TABLE #tmp_MemIDs (CustID INT PRIMARY KEY, roleID TINYINT)

	DECLARE @CID INT, @IsFilterCust BIT
	SELECT  @IsFilterCust = 0
	
	CREATE TABLE #CustUser (CustID INT, roleID TINYINT)
	
	IF @IsDrillDown = 1 AND @TopType = 0
	BEGIN
		SELECT @CID = custid FROM dbo.Customer WITH(NOLOCK) WHERE username = @Username AND roleid = @RoleID
		SELECT @IsFilterCust = 1
	END
	ELSE
	BEGIN
		IF @Username <> ''
		BEGIN
			IF @CustList IS NOT NULL
			BEGIN
				INSERT INTO #CustUser (CustID)
				SELECT val FROM dbo.strSplit(@CustList, ',')
			END
			ELSE
			BEGIN
				INSERT INTO #CustUser (CustID)
				SELECT custid
				FROM dbo.Customer WITH(NOLOCK)
				WHERE username LIKE @Username + '%' AND roleid = @RoleID 

				IF @Username NOT LIKE '%[^0-9]%' AND LEN(@Username) < 10
				BEGIN
				INSERT INTO #CustUser (CustID)
				SELECT cu.custid FROM dbo.Customer cu WITH(NOLOCK) WHERE cu.custid = @Username AND cu.roleid = @RoleID
					AND NOT EXISTS (SELECT 1 FROM #CustUser c WHERE cu.custid = c.custid)
				END
			END

			SELECT @IsFilterCust = 1
		END
	END

	IF @Site <> 'ALL'
	BEGIN
		SELECT @IsFilterCust = 1

		INSERT INTO #tmp_Site (Site)
		SELECT RTRIM(LTRIM(val)) FROM dbo.strSplit(@Site, ',')

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site = 'MBC Group')
		BEGIN
			INSERT INTO #tmp_Company (Srecommend)
			SELECT custid
			FROM Customer c WITH(NOLOCK)
			WHERE NOT EXISTS (SELECT 1 FROM dbo.Dep_CustSuper d WITH(NOLOCK) WHERE c.custid = d.custid)
				AND c.roleid = 4
		END

		IF EXISTS (SELECT 1 FROM #tmp_Site WHERE Site <> 'MBC Group')
		BEGIN
			INSERT INTO #tmp_Company (SiteName, Srecommend)
			SELECT s.Site, c.srecommend
			FROM #tmp_Site s
				INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
				INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
			WHERE c.roleid = 4 AND ss.isDeposit = 1
		END

		IF @Username <> ''
		BEGIN
			IF @IsDrillDown = 0 OR @TopType <> 0
			BEGIN
				IF @RoleID = 1
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.custid = cu.CustID
					WHERE c.roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				IF @RoleID = 2
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.recommend = cu.CustID
					WHERE c.roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID = 3
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.mrecommend = cu.CustID
					WHERE c.roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID = 4
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.srecommend = cu.CustID
					WHERE c.roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
			END
			ELSE -- @IsDrillDown = 1 and @TopType = 0
			BEGIN
				IF @RoleID = 1
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
					WHERE c.custid = @CID AND roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
				END
				ELSE IF @RoleID = 2
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
					WHERE c.recommend = @CID AND roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
				END
				ELSE IF @RoleID = 3
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
					WHERE c.mrecommend = @CID AND roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
				END
				ELSE IF @RoleID = 4
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
					WHERE c.srecommend = @CID AND roleid = 1
						AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
				END
			END
		END
		ELSE -- @Username = ''
		BEGIN
			INSERT INTO #tmp_MemIDs (CustID, roleID)
			SELECT custid, 1
			FROM
				dbo.Customer c WITH (NOLOCK)
			WHERE c.roleid = 1
				AND EXISTS (SELECT 1 FROM #tmp_Company tc WHERE c.srecommend = tc.srecommend)
		END
	END
	ELSE
	BEGIN
		IF @Username <> ''
		BEGIN
			SELECT @IsFilterCust = 1

			IF @IsDrillDown = 0 OR @TopType <> 0
			BEGIN
				IF @RoleID = 1
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.custid = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID = 2
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.recommend = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID = 3
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.mrecommend = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID = 4
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.srecommend = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
			END
			ELSE -- @IsDrillDown = 1
			BEGIN
				IF @RoleID = 1
					BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM dbo.Customer WITH (NOLOCK)
					WHERE custid = @CID AND roleid = 1
				END
				ELSE IF @RoleID = 2
					BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM dbo.Customer WITH (NOLOCK)
					WHERE recommend = @CID AND roleid = 1
				END
				ELSE IF @RoleID = 3
					BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM dbo.Customer WITH (NOLOCK)
					WHERE mrecommend = @CID AND roleid = 1
				END
				ELSE IF @RoleID = 4
					BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT custid, 1
					FROM dbo.Customer WITH (NOLOCK)
					WHERE srecommend = @CID AND roleid = 1
				END
			END
		END
	END

	DROP TABLE #tmp_Site
	DROP TABLE #tmp_Company
	-- End Get Site --

	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans
	(
		srecommend INT,
		mrecommend INT,
		recommend INT,
		custid INT,
		Bettype INT,
		BetCount BIGINT,
		CurrencyID INT,
		TotalBets MONEY,
		TotalBetsBase MONEY,
		TotalWins MONEY,
		TotalWinsBase MONEY,
		CompanyTurnover MONEY,
		CompanyTurnoverBase MONEY,
		CompanyGrossIncome MONEY,
		CompanyGrossIncomeBase MONEY,
		CompanyComm MONEY,
		CompanyCommBase MONEY,
		EvenType INT DEFAULT (-1), Matchid INT DEFAULT (-1), ProductID INT,
		HousePT SMALLMONEY,
		statusID TINYINT
	)

	IF @IsFilterCust = 1 -- has filter custid
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				EvenType, Matchid, ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.bettype,
				CASE WHEN s.ProductID = 33 THEN SUM(b.betid)  -- Poker Games
					 ELSE COUNT(b.transid) END AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
						ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,
				SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
						 ELSE (1- b.tpositiontaking) * b.stake * actualrate END) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.EvenType, b.matchid, s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT, 
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM  dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			WHERE b.winlostdate = @WLDate
				AND b.matchid >= 0
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable IN (0, 3)
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
				AND b.bettype <> 2799 
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
			
			--Mix Parlay Virtual Sport 2
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				EvenType, Matchid, ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.bettype,
				COUNT(b.transid) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.EvenType, b.matchid, s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM  dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			WHERE b.winlostdate = @WLDate
				AND b.matchid = 2799
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable IN (0, 3)
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
				AND b.Bettype = 2799
				AND EXISTS (SELECT 1 FROM dbo.bettransm bm WITH (NOLOCK)
									INNER JOIN dbo.match m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno)			
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
			
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(CASE WHEN b.gameID NOT IN (2198, 2398, 2998) THEN b.transid ELSE NULL END) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM(CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
						ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END) AS CompanyGrossIncome,
				SUM((CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
						  ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.ProductID,
				SUM(CASE WHEN b.gameID IN (2198, 2398, 2998) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM dbo.bettransRnG b WITH (NOLOCK)
				INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				INNER JOIN #SportBettype s ON s.Bettype = b.gameID
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable = 1		
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END
		
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(b.transid) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM dbo.bettransLC b WITH (NOLOCK)
				INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				INNER JOIN #SportBettype s ON s.Bettype = b.gameID
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable = 2
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END
	END
	ELSE -- non filter custid
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				EvenType, matchid, ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.bettype,
				CASE WHEN s.ProductID = 33 THEN SUM(b.betid)  -- Poker Games
					 ELSE COUNT(b.transid) END AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
						 ELSE (1- b.tpositiontaking) * b.stake END) AS CompanyTurnover,
				SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
						 ELSE (1- b.tpositiontaking) * b.stake * actualrate END) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.EvenType, b.matchid, s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM  dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND b.matchid >= 0
				AND s.RefTable IN (0, 3)
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
				AND b.bettype <> 2799
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
			
			--Mix Parlay Virtual Sport 2
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				EvenType, matchid, ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.bettype,
				COUNT(b.transid) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.EvenType, b.matchid, s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM  dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND b.matchid = 2799	
				AND s.RefTable IN (0, 3)
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
				AND b.bettype = 2799
				AND EXISTS (SELECT 1 FROM dbo.bettransm bm WITH (NOLOCK)
									INNER JOIN dbo.match m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno)				
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
			
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(CASE WHEN b.gameID NOT IN (2198, 2398, 2998) THEN b.transid ELSE NULL END) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM(CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
						 ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END) AS CompanyGrossIncome,
				SUM((CASE WHEN b.gameID IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
						  ELSE winlost - actual_stake + awinlost + mwinlost + swinlost END) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.ProductID,
				SUM(CASE WHEN b.gameID IN (2198, 2398, 2998) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM dbo.bettransRnG b WITH (NOLOCK)
				INNER JOIN #SportBettype s ON s.Bettype = b.gameID
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable = 1		
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
				Bettype,
				BetCount,
				CurrencyID,
				TotalBets,
				TotalBetsBase,
				TotalWins,
				TotalWinsBase,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				ProductID,
				HousePT,
				statusID
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(b.transid) AS BetCount,
				b.currency,
				SUM(actual_stake) AS TotalBets,
				SUM(actual_stake * actualrate) AS TotalBetsBase,
				SUM(winlost) AS TotalWins,
				SUM(winlost * actualrate) AS TotalWinsBase,
				SUM((1- b.tpositiontaking) * b.stake) AS CompanyTurnover,
				SUM((1- b.tpositiontaking) * b.stake * actualrate) AS CompanyTurnoverBase,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)) AS CompanyGrossIncome,
				SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * actualrate) AS CompanyGrossIncomeBase,
				SUM(scomm) AS CompanyComm,
				SUM(scomm *actualrate) AS CompanyCommBase,
				s.ProductID,
				SUM(1 - b.tpositiontaking) AS HousePT,
				CASE WHEN statusID = 103 THEN 103 ELSE 112 END AS statusID
			FROM dbo.bettransLC b WITH (NOLOCK)
				INNER JOIN #SportBettype s ON s.Bettype = b.gameID
			WHERE b.winlostdate = @WLDate
				AND b.statusID IN (111, 112, 113, 103) -- won/lose/draw/refund tickets
				AND s.RefTable = 2		
				AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
				AND (b.currency = @Currency OR @Currency IN (0, -1))
				AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END
	END

	CREATE NONCLUSTERED INDEX IX_ProductID_SMAU ON #tmp_bettrans (ProductID) INCLUDE (srecommend, mrecommend, recommend, custid)

	-- Get data
	CREATE TABLE #Data
	( 
		srecommend INT,
		mrecommend INT,
		recommend INT,
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		ProductID TINYINT,
		TotalBets MONEY,
		TotalBetsBase MONEY,
		TotalWins MONEY,
		TotalWinsBase MONEY,
		CompanyTurnover MONEY,
		CompanyTurnoverBase MONEY,
		CompanyGrossIncome MONEY,
		CompanyGrossIncomeBase MONEY,
		CompanyComm MONEY,
		CompanyCommBase MONEY,
		HousePT SMALLMONEY,
		statusID TINYINT
	)
	--- Check condition 
	IF EXISTS (SELECT TOP 1 1 FROM #tmp_bettrans WHERE ProductID NOT IN (3, 4, 5, 27)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2
	BEGIN		
		INSERT INTO #Data
		(
			srecommend,
			mrecommend,
			recommend,
			custid,
			BetCount,
			CurrencyID,
			ProductID,
			TotalBets,
			TotalBetsBase,
			TotalWins,
			TotalWinsBase,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			statusID
		)
		SELECT
			srecommend,
			mrecommend,
			recommend,
			custid,
			SUM(BetCount) AS BetCount,
			CurrencyID,
			ProductID,
			SUM(TotalBets) AS TotalBets,
			SUM(TotalBetsBase) AS TotalBetsBase,
			SUM(TotalWins) AS TotalWins,
			SUM(TotalWinsBase) AS TotalWinsBase,
			SUM(CompanyTurnover) AS CompanyTurnover,
			SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
			- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
			- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
			- SUM(CompanyComm) AS CompanyComm,
			- SUM(CompanyCommBase) AS CompanyCommBase,
			SUM(HousePT) AS HousePT,
			statusID
		FROM  #tmp_bettrans
		WHERE ProductID NOT IN (3, 4, 5, 27)
		GROUP BY srecommend, mrecommend, recommend, custid, CurrencyID, ProductID, statusID
	END

	IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID IN (3, 4, 5)) -- NG, SLI-Live Casino, Virtual Sports
	BEGIN		
		INSERT INTO #Data
		(
			srecommend,
			mrecommend,
			recommend,
			custid,
			BetCount,
			CurrencyID,
			ProductID,
			TotalBets,
			TotalBetsBase,
			TotalWins,
			TotalWinsBase,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			statusID
		)
		SELECT
			srecommend,
			mrecommend,
			recommend,
			custid,
			SUM(BetCount) AS BetCount,
			CurrencyID,
			ProductID,
			SUM(TotalBets) AS TotalBets,
			SUM(TotalBetsBase) AS TotalBetsBase,
			SUM(TotalWins) AS TotalWins,
			SUM(TotalWinsBase) AS TotalWinsBase,
			SUM(CompanyTurnover) AS CompanyTurnover,
			SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
			- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
			- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
			- SUM(CompanyComm) AS CompanyComm,
			- SUM(CompanyCommBase) AS CompanyCommBase,
			SUM(HousePT) AS HousePT,
			statusID
		FROM  #tmp_bettrans b
			INNER JOIN dbo.match m WITH (NOLOCK) ON m.matchid = b.matchid
		WHERE ProductID IN (3, 4, 5) AND b.EvenType = 1
			AND (
				(b.ProductID = 3 AND (@LeagueId = '' OR (EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = m.leagueid AND l.Bettype = b.Bettype)))) OR
				(b.ProductID = 4 AND (@GameTableId = '' OR (EXISTS (SELECT 1 FROM #tmp_GameTableID g WHERE g.GameTableID = m.leagueid)))) OR
				(b.ProductID = 5 AND (@Sporttype = '' OR (EXISTS (SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = m.sporttype))))
			)
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.CurrencyID, b.ProductID, statusID

		-- HR
		INSERT INTO #Data
		(
			srecommend,
			mrecommend,
			recommend,
			custid,
			BetCount,
			CurrencyID,
			ProductID,
			TotalBets,
			TotalBetsBase,
			TotalWins,
			TotalWinsBase,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			statusID
		)
		SELECT
			srecommend,
			mrecommend,
			recommend,
			custid,
			SUM(BetCount) AS BetCount,
			CurrencyID,
			ProductID,
			SUM(TotalBets) AS TotalBets,
			SUM(TotalBetsBase) AS TotalBetsBase,
			SUM(TotalWins) AS TotalWins,
			SUM(TotalWinsBase) AS TotalWinsBase,
			SUM(CompanyTurnover) AS CompanyTurnover,
			SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
			- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
			- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
			- SUM(CompanyComm) AS CompanyComm,
			- SUM(CompanyCommBase) AS CompanyCommBase,
			SUM(HousePT) AS HousePT,
			statusID
		FROM  #tmp_bettrans b
			INNER JOIN dbo.VSRaceInfo r WITH (NOLOCK) ON r.EventID = b.matchid
		WHERE b.ProductID = 5 AND b.EvenType = 3
			AND (@Sporttype = '' OR (EXISTS(SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = r.SportType)))			  
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.CurrencyID, b.ProductID, statusID
	END
	
	IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID = 27)
	BEGIN
		-- Virtual Sports 2
		INSERT INTO #Data
		(
			srecommend,
			mrecommend,
			recommend,
			custid,
			BetCount,
			CurrencyID,
			ProductID,
			TotalBets,
			TotalBetsBase,
			TotalWins,
			TotalWinsBase,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			statusID
		)
		SELECT
			srecommend,
			mrecommend,
			recommend,
			custid,
			SUM(BetCount) AS BetCount,
			CurrencyID,
			ProductID,
			SUM(TotalBets) AS TotalBets,
			SUM(TotalBetsBase) AS TotalBetsBase,
			SUM(TotalWins) AS TotalWins,
			SUM(TotalWinsBase) AS TotalWinsBase,
			SUM(CompanyTurnover) AS CompanyTurnover,
			SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
			- SUM(CompanyGrossIncome) AS CompanyGrossIncome,
			- SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
			- SUM(CompanyComm) AS CompanyComm,
			- SUM(CompanyCommBase) AS CompanyCommBase,
			SUM(HousePT) AS HousePT,
			statusID
		FROM  #tmp_bettrans b
		WHERE b.ProductID = 27
			AND (b.EvenType = 0 OR
				(EXISTS (SELECT 1 FROM dbo.match m WITH (NOLOCK)
								INNER JOIN #tmp_SportType st ON m.Sporttype = st.sporttype
						 WHERE b.Matchid = m.matchid))
			)	
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.CurrencyID, b.ProductID, statusID
	END

	CREATE TABLE #tmp_Result
	( 
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		ProductID TINYINT,
		TotalBets MONEY,
		TotalWins MONEY,
		TotalRefund MONEY,
		CompanyTurnover MONEY,
		CompanyGrossIncome MONEY,
		CompanyComm MONEY,
		TotalBetsBase MONEY,
		TotalWinsBase MONEY,
		TotalRefundBase MONEY,
		CompanyTurnoverBase MONEY,
		CompanyGrossIncomeBase MONEY,
		CompanyCommBase MONEY,
		HousePT SMALLMONEY,
		GamePayout MONEY,
		CompanyNetIncome MONEY, 
		GameIncome MONEY
	)	
	
	IF @RoleID IN (1,2,3,4) -- member (username) / agent / master / super
	BEGIN
		IF @IsDrillDown = 1 AND @TopType = 0
		BEGIN
			SELECT @RoleID = @RoleID - 1
		END

		IF @RoleID = 1
			CREATE NONCLUSTERED INDEX IX_custid ON #Data (custId)
		ELSE IF @RoleID = 2
			CREATE NONCLUSTERED INDEX IX_recommend ON #Data (recommend)
		ELSE IF @RoleID = 3
			CREATE NONCLUSTERED INDEX IX_mrecommend ON #Data (mrecommend)
		ELSE
			CREATE NONCLUSTERED INDEX IX_srecommend ON #Data (srecommend)

		IF @Currency = -1
		BEGIN
			;WITH Result AS (
				SELECT
					CASE @roleID
						WHEN 1 THEN custid
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						WHEN 4 THEN srecommend
						END AS custid,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE BetCount END) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalBetsBase END) AS TotalBets,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalWinsBase END) AS TotalWins,
					SUM(CASE statusID WHEN 112 THEN 0 ELSE TotalBetsBase END) AS TotalRefund,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyTurnoverBase END) AS CompanyTurnover,		
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyGrossIncomeBase END) AS CompanyGrossIncome,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyCommBase END) AS CompanyComm,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalBetsBase END)  AS TotalBetsBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalWinsBase END) AS TotalWinsBase,
					SUM(CASE statusID WHEN 112 THEN 0 ELSE TotalBetsBase END) AS TotalRefundBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyTurnoverBase END) AS CompanyTurnoverBase,		
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyGrossIncomeBase END) AS CompanyGrossIncomeBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyCommBase END) AS CompanyCommBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE HousePT END) AS HousePT
				FROM #Data
				GROUP BY CASE @roleID
						WHEN 1 THEN custid
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						WHEN 4 THEN srecommend
						END, CurrencyID, ProductID
			)
			INSERT INTO #tmp_Result
			(
				custid,
				BetCount,
				CurrencyID,
				ProductID,
				TotalBets,
				TotalWins,
				TotalRefund,
				CompanyTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT
			)
			SELECT
				custid,
				BetCount,
				CurrencyID,
				ProductID,
				TotalBets,
				TotalWins,
				TotalRefund,
				CompanyTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT
			FROM Result
		END
		ELSE
		BEGIN
			;WITH Result AS (
				SELECT
					CASE @roleID
						WHEN 1 THEN custid
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						WHEN 4 THEN srecommend
						END AS custid,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE BetCount END) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalBets END) AS TotalBets,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalWins END) AS TotalWins,
					SUM(CASE statusID WHEN 112 THEN 0 ELSE TotalBets END) AS TotalRefund,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyTurnover END) AS CompanyTurnover,		
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyGrossIncome END) AS CompanyGrossIncome,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyComm END) AS CompanyComm,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalBetsBase END)  AS TotalBetsBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE TotalWinsBase END) AS TotalWinsBase,
					SUM(CASE statusID WHEN 112 THEN 0 ELSE TotalBetsBase END) AS TotalRefundBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyTurnoverBase END) AS CompanyTurnoverBase,		
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyGrossIncomeBase END) AS CompanyGrossIncomeBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE CompanyCommBase END) AS CompanyCommBase,
					SUM(CASE statusID WHEN 103 THEN 0 ELSE HousePT END) AS HousePT
				FROM #Data
				GROUP BY CASE @roleID
						WHEN 1 THEN custid
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						WHEN 4 THEN srecommend
						END, CurrencyID, ProductID
			)
			INSERT INTO #tmp_Result
			(
				custid,
				BetCount,
				CurrencyID,
				ProductID,
				TotalBets,
				TotalWins,
				TotalRefund,
				CompanyTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT
			)
			SELECT
				custid,
				BetCount,
				CurrencyID,
				ProductID,
				TotalBets,
				TotalWins,
				TotalRefund,
				CompanyTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT
			FROM Result
		END
	END
	
	UPDATE #tmp_Result
	SET GamePayout = CASE WHEN TotalBets = 0 THEN 0 ELSE TotalWins/TotalBets END,
		CompanyNetIncome = CompanyGrossIncome + CompanyComm,
		GameIncome = TotalBets - TotalWins

	CREATE TABLE #tmp_Result2
	( 
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		TotalBets MONEY,
		TotalWins MONEY,
		TotalRefund MONEY,
		CompanyTurnover MONEY,
		CompanyGrossIncome MONEY,
		CompanyComm MONEY,
		TotalBetsBase MONEY,
		TotalWinsBase MONEY,
		TotalRefundBase MONEY,
		CompanyTurnoverBase MONEY,
		CompanyGrossIncomeBase MONEY,
		CompanyCommBase MONEY,
		HousePT SMALLMONEY,
		GamePayout MONEY,
		CompanyNetIncome MONEY, 
		GameIncome MONEY
	)

	INSERT INTO #tmp_Result2
	(
		custid,
		BetCount,
		CurrencyID,
		TotalBets,
		TotalWins,
		TotalRefund,
		CompanyTurnover,
		CompanyGrossIncome,
		CompanyComm,
		TotalBetsBase,
		TotalWinsBase,
		TotalRefundBase,
		CompanyTurnoverBase,
		CompanyGrossIncomeBase,
		CompanyCommBase,
		HousePT,
		GamePayout,
		CompanyNetIncome, 
		GameIncome 
	)
	SELECT
		custid,
		SUM(BetCount) AS BetCount,
		CurrencyID,
		SUM(TotalBets) AS TotalBets,
		SUM(TotalWins) AS TotalWins,
		SUM(TotalRefund) AS TotalRefund,
		SUM(CompanyTurnover) AS CompanyTurnover,
		SUM(CompanyGrossIncome) AS CompanyGrossIncome,
		SUM(CompanyComm) AS CompanyComm,
		SUM(TotalBetsBase) AS TotalBetsBase,
		SUM(TotalWinsBase) AS TotalWinsBase,
		SUM(TotalRefundBase) AS TotalRefundBase,
		SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
		SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
		SUM(CompanyCommBase) AS CompanyCommBase,
		AVG(CASE WHEN ProductID = 33 THEN 1  -- Poker Games 
				 WHEN BetCount = 0 THEN NULL ELSE HousePT/BetCount END) AS HousePT,
		SUM(GamePayout) GamePayout,
		SUM(CompanyNetIncome) CompanyNetIncome, 
		SUM(GameIncome) GameIncome
	FROM #tmp_Result
	GROUP BY custid, CurrencyID
	HAVING
		(
			@TotalBetType = 0
			OR (@TotalBetType = 1 AND SUM(TotalBets) >= @TotalBetValue) 
			OR (@TotalBetType = -1 AND SUM(TotalBets) <= @TotalBetValue)
		)
		AND
		(
			@GameIncomeType = 0
			OR (@GameIncomeType = 1 AND SUM(TotalBets - TotalWins) >= @GameIncomeValue) 
			OR (@GameIncomeType = -1 AND SUM(TotalBets - TotalWins) <= @GameIncomeValue)
		)

	DECLARE @TotalRefundCust BIGINT
	SELECT  @TotalRefundCust = COUNT(DISTINCT custid)
	FROM #tmp_Result
	GROUP BY custid
	HAVING
		(
			SUM(TotalBets) = 0
			AND SUM(TotalWins) = 0
			AND SUM(CompanyTurnover) = 0
			AND SUM(CompanyGrossIncome) = 0
			AND SUM(CompanyComm) = 0
		)
	SELECT  @TotalRefundCust = ISNULL(@TotalRefundCust, 0)

	CREATE TABLE #Result
	( 
		TopType TINYINT,
		RowNum BIGINT,
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		TotalBets MONEY,
		TotalWins MONEY,
		TotalRefund MONEY,
		CompanyTurnover MONEY,
		CompanyGrossIncome MONEY,
		CompanyComm MONEY,
		TotalBetsBase MONEY,
		TotalWinsBase MONEY,
		TotalRefundBase MONEY,
		CompanyTurnoverBase MONEY,
		CompanyGrossIncomeBase MONEY,
		CompanyCommBase MONEY,
		HousePT SMALLMONEY
	)

	-- Detail	
	BEGIN		
		;WITH Result_1 AS (
			SELECT
				custid,
				SUM(BetCount) AS BetCount,
				CurrencyID,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalRefund) AS TotalRefund,
				SUM(CompanyTurnover) AS CompanyTurnover,		
				SUM(CompanyGrossIncome) AS CompanyGrossIncome,
				SUM(CompanyComm) AS CompanyComm,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWinsBase) AS TotalWinsBase,
				SUM(TotalRefundBase) AS TotalRefundBase,
				SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,		
				SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
				SUM(CompanyCommBase) AS CompanyCommBase,
				AVG(HousePT) AS HousePT,
				SUM(GamePayout) GamePayout,
				SUM(CompanyNetIncome) CompanyNetIncome, 
				SUM(GameIncome) GameIncome
			FROM #tmp_Result2
			GROUP BY custid, CurrencyID
		), Result AS (
			SELECT *,
				CASE WHEN @SortColumnName = 'BetCount' THEN RANK() OVER(ORDER BY BetCount DESC) 
				WHEN @SortColumnName = 'TotalBets' THEN RANK() OVER(ORDER BY TotalBets DESC)
				WHEN @SortColumnName = 'TotalWins' THEN RANK() OVER(ORDER BY TotalWins DESC)
				WHEN @SortColumnName = 'TotalRefund' THEN RANK() OVER(ORDER BY TotalRefund DESC)
				WHEN @SortColumnName = 'GameIncome' THEN RANK() OVER(ORDER BY GameIncome)
				WHEN @SortColumnName = 'GamePayout' THEN RANK() OVER(ORDER BY GamePayout DESC)
				WHEN @SortColumnName = 'HouseTurnOver' THEN RANK() OVER(ORDER BY CompanyTurnOver DESC)
				WHEN @SortColumnName = 'HouseGrossIncome' THEN RANK() OVER(ORDER BY CompanyGrossIncome DESC)
				WHEN @SortColumnName = 'HouseComm' THEN RANK() OVER(ORDER BY CompanyComm)
				WHEN @SortColumnName = 'HouseNetIncome' THEN RANK() OVER(ORDER BY CompanyNetIncome DESC)
				WHEN @SortColumnName = 'HousePositionTaking' THEN RANK() OVER(ORDER BY HousePT DESC)
				END AS RowNum1,
				CASE WHEN @SortColumnName = 'BetCount' THEN RANK() OVER(ORDER BY BetCount) 
				WHEN @SortColumnName = 'TotalBets' THEN RANK() OVER(ORDER BY TotalBets)
				WHEN @SortColumnName = 'TotalWins' THEN RANK() OVER(ORDER BY TotalWins)
				WHEN @SortColumnName = 'TotalRefund' THEN RANK() OVER(ORDER BY TotalRefund)
				WHEN @SortColumnName = 'GameIncome' THEN RANK() OVER(ORDER BY GameIncome DESC)
				WHEN @SortColumnName = 'GamePayout' THEN RANK() OVER(ORDER BY GamePayout)
				WHEN @SortColumnName = 'HouseTurnOver' THEN RANK() OVER(ORDER BY CompanyTurnOver)
				WHEN @SortColumnName = 'HouseGrossIncome' THEN RANK() OVER(ORDER BY CompanyGrossIncome)
				WHEN @SortColumnName = 'HouseComm' THEN RANK() OVER(ORDER BY CompanyComm DESC)
				WHEN @SortColumnName = 'HouseNetIncome' THEN RANK() OVER(ORDER BY CompanyNetIncome)
				WHEN @SortColumnName = 'HousePositionTaking' THEN RANK() OVER(ORDER BY HousePT)
				END AS RowNum2
			FROM Result_1
		)	
		INSERT INTO #Result
		(
			TopType,
			RowNum,
			custid,
			BetCount,
			CurrencyID,
			TotalBets,
			TotalWins,
			TotalRefund,
			CompanyTurnover,
			CompanyGrossIncome,
			CompanyComm,
			TotalBetsBase,
			TotalWinsBase,
			TotalRefundBase,
			CompanyTurnoverBase,
			CompanyGrossIncomeBase,
			CompanyCommBase,
			HousePT
		)
		SELECT
			CASE WHEN RowNum1 <= 20 THEN 1 ELSE 2 END AS TopType,
			CASE WHEN RowNum1 <= 20 THEN RowNum1 ELSE RowNum2 END AS RowNum,
			custid,
			BetCount,
			CurrencyID,
			TotalBets,
			TotalWins,
			TotalRefund,
			CompanyTurnover,
			CompanyGrossIncome,
			CompanyComm,
			TotalBetsBase,
			TotalWinsBase,
			TotalRefundBase,
			CompanyTurnoverBase,
			CompanyGrossIncomeBase,
			CompanyCommBase,
			HousePT
		FROM Result
		WHERE
			((@TopType = 0 OR @TopType = 1) AND RowNum1 <= 20)	
			OR ((@TopType = 0 OR @TopType = 2) AND RowNum2 <= 20)					

		SELECT  @TotalRefundCust = 0
		SELECT  @TotalRefundCust = COUNT(DISTINCT custid)
		FROM #Result
		GROUP BY custid
		HAVING
			(
				SUM(TotalBets) = 0
				AND SUM(TotalWins) = 0
				AND SUM(CompanyTurnover) = 0
				AND SUM(CompanyGrossIncome) = 0
				AND SUM(CompanyComm) = 0
			)
		SELECT  @TotalRefundCust = ISNULL(@TotalRefundCust, 0)

		IF @TopType = 0
		BEGIN
			SELECT
				CASE r.TopType WHEN 1 THEN 'Top 20' ELSE 'Bottom 20' END AS TopType,
				r.custid AS ReportById,
				c.username AS ReportBy,
				c.roleid AS RoleId,
				CASE c.roleid WHEN 1 THEN 'Member' WHEN 2 THEN 'Agent' WHEN 3 THEN 'Master' WHEN 4 THEN 'Super' END AS RoleName,
				r.BetCount,
				e.exchangeid AS CurrencyId,
				e.currency AS Currency,
				r.TotalBets,
				r.TotalWins,
				r.TotalRefund,
				r.CompanyTurnover AS HouseTurnover,
				r.CompanyGrossIncome AS HouseGrossIncome,
				r.CompanyComm AS HouseComm,
				r.HousePT AS HousePositionTaking,
				CASE WHEN c.roleid = 1 THEN a.site ELSE c.site END AS SiteName
			FROM #Result r
				LEFT JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
				LEFT JOIN dbo.Customer c WITH(NOLOCK) ON r.custId = c.custid
				LEFT JOIN dbo.Customer a WITH(NOLOCK) ON a.custid = c.recommend 
			ORDER BY r.TopType, r.RowNum, c.username

			SELECT
				CASE TopType WHEN 1 THEN 'Top 20' ELSE 'Bottom 20' END AS ReportBy,
				TopType AS ReportById,
				SUM(BetCount) AS BetCount,
				@Currency AS CurrencyId,
				'RM' AS Currency,
				SUM(TotalBetsBase) AS TotalBets,
				SUM(TotalWinsBase) AS TotalWins,
				SUM(TotalRefundBase) AS TotalRefund,
				SUM(CompanyTurnoverBase) AS HouseTurnover,
				SUM(CompanyGrossIncomeBase) AS HouseGrossIncome,
				SUM(CompanyCommBase) AS HouseComm
			FROM #Result
			GROUP BY CASE TopType WHEN 1 THEN 'Top 20' ELSE 'Bottom 20' END, TopType
			ORDER BY TopType
		END
		ELSE -- @TopType <> 0	
		BEGIN
			;WITH CTE AS (
				SELECT CurrencyID, COUNT(DISTINCT custId) AS RefundCust
				FROM #Result
				GROUP BY CurrencyID
				HAVING
					(
						SUM(TotalBets) = 0
						AND SUM(TotalWins) = 0
						AND SUM(CompanyTurnover) = 0
						AND SUM(CompanyGrossIncome) = 0
						AND SUM(CompanyComm) = 0
					)
			)
			SELECT
				CASE @TopType WHEN 1 THEN 'Top 20' ELSE 'Bottom 20' END AS ReportBy,
				@TopType AS ReportById,
				BetCount,
				NoOfPlayers - ISNULL(c.RefundCust, 0) AS NoOfPlayers,
				A.CurrencyId,
				Currency,
				TotalBets,
				TotalWins,
				TotalRefund,
				CompanyTurnover AS HouseTurnover,
				CompanyGrossIncome AS HouseGrossIncome, 
				CompanyComm AS HouseComm
			FROM (
				SELECT
					SUM(BetCount) AS BetCount,
					COUNT(DISTINCT custid) AS NoOfPlayers,
					e.exchangeid AS CurrencyId,
					e.currency AS Currency,
					SUM(TotalBets) AS TotalBets,
					SUM(TotalWins) AS TotalWins,
					SUM(TotalRefund) AS TotalRefund,
					SUM(CompanyTurnover) AS CompanyTurnover,
					SUM(CompanyGrossIncome) AS CompanyGrossIncome,
					SUM(CompanyComm) AS CompanyComm
				FROM #Result r
					INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
				GROUP BY e.exchangeid, e.currency
			) A
			LEFT JOIN CTE c ON A.CurrencyID = c.CurrencyID 
				ORDER BY Currency
		END
	END
	
	-- GrandTotal
	IF @TopType <> 0 AND @IsDrillDown = 1
	BEGIN
		SELECT
			'GrandTotal' AS ReportBy,
			SUM(BetCount) AS BetCount,
			COUNT(DISTINCT custid) - @TotalRefundCust AS NoOfPlayers,
			-1 AS CurrencyId,
			'RM' AS Currency,
			SUM(TotalBetsBase) AS TotalBets,
			SUM(TotalWinsBase) AS TotalWins,
			SUM(TotalRefundBase) AS TotalRefund,
			SUM(CompanyTurnoverBase) AS HouseTurnover,		
			SUM(CompanyGrossIncomeBase) AS HouseGrossIncome,
			SUM(CompanyCommBase) AS HouseComm
		FROM #Result
	END

	DROP TABLE #Data
	DROP TABLE #SportBettype
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_Devide
	DROP TABLE #tmp_GameTableID
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_SportType
	DROP TABLE #CustUser
	DROP TABLE #tmp_Result
	DROP TABLE #tmp_Result2
	DROP TABLE #Result
	
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Top20] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Top20] TO [vnteam];
GO
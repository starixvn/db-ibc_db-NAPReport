USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Customer_14]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@RoleID			TINYINT = 1,
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
	Creator: Percy
	Date: 2016-12-02
	DB: DBACC.bodb02
	Task: Risk and Control - Non-Sport Game Statistics Report - Report by Super/Master/Agent/Username

	Revisions:
		- 20170215@Percy: Remove hardcode product to support Fishing World [RedmineID: #71616]
		- 20170227@Percy: support search multiple username [RedmineID: #71342]
		- 20170726@Cherry: Integrate Betradar Virtual Sports (#78495)

	Param's Explanation:
		- @username: search keyword
		- @roleID:
			0: associated customer
			1,2,3,4: super/master/agent/member
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
		- @IsDrillDown: drilldown master/agent/member from super/master/agent
		- @IsGrandTotal: drilldown grandtotal
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CustList VARCHAR(MAX)

	IF  @RoleID <> 0 AND CHARINDEX(',', @Username) <> 0
	BEGIN
		EXEC dbo.Acc_CustomerSelCustByUsernameList @Username = @Username, @RoleId = @RoleId, @CustList = @CustList OUTPUT

		IF @CustList IS NULL -- invalid username
		BEGIN
			SELECT TOP 0 *
			FROM (
				SELECT
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
					NULL AS HousePositionTaking
			) A

			-- Grand Total
			SELECT
				'GrandTotal' AS ReportBy,
				NULL AS BetCount,
				NULL AS NoOfPlayers,
				-1 AS CurrencyId,
				'RM' AS Currency,
				NULL AS TotalBets,
				NULL AS TotalWins,
				NULL AS TotalRefund,
				NULL AS CompanyTurnover,		
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm
		
			RETURN
		END
	END

	DECLARE @WLDate DATETIME
	SELECT  @WLDate = @WinlostDate

	CREATE TABLE #tmp_ProductID		(ProductID TINYINT)
	CREATE TABLE #tmp_BetType		(Bettype SMALLINT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT)
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

	IF @LeagueId <> ''
	BEGIN
		INSERT INTO #tmp_LeagueID (LeagueID)
		SELECT val FROM dbo.strSplit(@LeagueId, ',')
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
	WHERE p.ProductID IN (3, 5, 27) -- Number Game, Virtual Sport (input @bettype = '')

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
	IF @IsDrillDown = 1
	BEGIN
		SELECT @CID = custid FROM dbo.Customer WITH(NOLOCK) WHERE username = @Username AND roleid = @RoleID
		SELECT @IsFilterCust = 1
	END
	ELSE IF @RoleID = 0 -- click associated accounts link
	BEGIN
		INSERT INTO #CustUser (CustID, roleID)
		SELECT custid, roleid FROM dbo.Customer c WITH(NOLOCK)
		WHERE EXISTS (SELECT 1 FROM dbo.strSplit(@Username, ',') u WHERE c.username = u.val)
		
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
				WHERE username LIKE @Username + '%' AND roleid = @RoleId

				IF @Username NOT LIKE '%[^0-9]%' AND LEN(@Username) < 10
				BEGIN
				INSERT INTO #CustUser (CustID)
				SELECT cu.custid FROM dbo.Customer cu WITH(NOLOCK) WHERE cu.custid = @Username AND cu.roleid = @RoleId
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
			IF @IsDrillDown = 0
			BEGIN
				IF @RoleID IN (0,1)
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
				
				IF @RoleID IN (0,2)
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
				
				IF @RoleID IN (0,3)
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
				
				IF @RoleID IN (0,4)
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
			ELSE -- @IsDrillDown = 1
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

			IF @IsDrillDown = 0
			BEGIN
				IF @RoleID IN (0,1)
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.custid = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID IN (0,2)
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.recommend = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID IN (0,3)
				BEGIN
					INSERT INTO #tmp_MemIDs (CustID, roleID)
					SELECT c.custid, 1
					FROM
						dbo.Customer c WITH (NOLOCK)
						INNER JOIN #CustUser cu ON c.mrecommend = cu.CustID
					WHERE c.roleid = 1
						AND NOT EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE c.custId = m.CustID)
				END
				
				IF @RoleID IN (0,4)
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

	-- Select temp data of bettrans14, bettransRnG14, bettransLC14
	CREATE TABLE #tmp_bettrans
	(
		srecommend INT,
		mrecommend INT,
		recommend INT,
		custid INT,
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
		statusID TINYINT,
	)

	IF @IsFilterCust = 1 -- has filter custid
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM  dbo.bettrans14 b WITH (NOLOCK)
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
				AND (s.ProductID <> 27 OR (s.ProductID = 27 AND s.EvenType = 1) 
					OR (EXISTS (SELECT 1 FROM dbo.bettransm14 bm WITH (NOLOCK)
									INNER JOIN dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno))
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM dbo.bettransRnG14 b WITH (NOLOCK)
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
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END
		
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM dbo.bettransLC14 b WITH (NOLOCK)
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
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END
	END
	ELSE -- non filter custid
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM  dbo.bettrans14 b WITH (NOLOCK)
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
				AND (s.ProductID <> 27 OR (s.ProductID = 27 AND s.EvenType = 1) 
					OR (EXISTS (SELECT 1 FROM dbo.bettransm14 bm WITH (NOLOCK)
									INNER JOIN dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno))
				)
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.EvenType, b.matchid, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM dbo.bettransRnG14 b WITH (NOLOCK)
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
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC14
		BEGIN
			INSERT INTO #tmp_bettrans
			(
				srecommend,
				mrecommend,
				recommend,
				custid,
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
			FROM dbo.bettransLC14 b WITH (NOLOCK)
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
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.ProductID, CASE WHEN statusID = 103 THEN 103 ELSE 112 END
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
	IF EXISTS (SELECT TOP 1 1 FROM #tmp_bettrans WHERE ProductID NOT IN (3, 4, 5, 27)) -- NG, SLI-Live Casino, Virtual Sport
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

	IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID IN (3, 4, 5)) -- NG, SLI-Live Casino, Virtual Sport
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
			INNER JOIN dbo.match14 m WITH (NOLOCK) ON m.matchid = b.matchid
		WHERE ProductID IN (3, 4, 5) AND b.EvenType = 1
			AND (
				(b.ProductID = 3 AND (@LeagueId = '' OR (EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = m.leagueid)))) OR
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
	
	IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID = 27) -- NG, SLI-Live Casino, Virtual Sport
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
		WHERE b.ProductID = 27
			AND (b.EvenType = 0 OR
				(EXISTS (SELECT 1 FROM dbo.match14 m WITH (NOLOCK)
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
		HousePT SMALLMONEY
	)

	-- Return Data
	IF @RoleID IN (1,2,3,4) -- member (username) / agent / master / super
	BEGIN
		IF @IsDrillDown = 1 --AND @IsGrandTotal = 0
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
	ELSE -- @roleID = 0 --> click associated accounts link
	BEGIN
		IF @Currency = -1 -- base RM
		BEGIN
			;WITH Result AS (
				SELECT
					c.custid,
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
				FROM #Data d
					INNER JOIN #CustUser c
						ON c.CustID = CASE c.roleID
										WHEN 1 THEN d.custid
										WHEN 2 THEN d.recommend
										WHEN 3 THEN d.mrecommend
										WHEN 4 THEN d.srecommend
										END
				GROUP BY c.custid, CurrencyID, ProductID
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
					c.custid,
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
				FROM #Data d
					INNER JOIN #CustUser c
						ON c.CustID = CASE c.roleID
										WHEN 1 THEN d.custid
										WHEN 2 THEN d.recommend
										WHEN 3 THEN d.mrecommend
										WHEN 4 THEN d.srecommend
										END
				GROUP BY c.custid, CurrencyID, ProductID
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

	CREATE TABLE #Result
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
		HousePT SMALLMONEY
	)

	INSERT INTO #Result
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
		HousePT
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
		AVG(CASE WHEN BetCount = 0 THEN NULL ELSE HousePT/BetCount END) AS HousePT
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

	-- Detail
	IF @IsGrandTotal = 0
	BEGIN
		SELECT
			c.custid AS ReportById,
			c.username AS ReportBy,
			c.roleid AS RoleId,
			CASE c.roleid WHEN 1 THEN 'Member' WHEN 2 THEN 'Agent' WHEN 3 THEN 'Master' WHEN 4 THEN 'Super' END AS RoleName,
			r.BetCount,
			e.exchangeid AS CurrencyId,
			e.currency AS Currency,
			r.TotalBets,
			r.TotalWins,
			r.TotalRefund,
			r.CompanyTurnover,
			r.CompanyGrossIncome,
			r.CompanyComm,
			r.HousePT AS HousePositionTaking
		FROM #Result r
			INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
			INNER JOIN dbo.Customer c WITH(NOLOCK) ON r.custId = c.custid
		ORDER BY c.username
	END
	ELSE IF @RoleID = 0
	BEGIN
		SELECT
			c.custid AS ReportById,
			c.username AS ReportBy,
			c.roleid AS RoleId,
			CASE c.roleid WHEN 1 THEN 'Member' WHEN 2 THEN 'Agent' WHEN 3 THEN 'Master' WHEN 4 THEN 'Super' END AS RoleName,
			r.BetCount,
			e.exchangeid AS CurrencyId,
			e.currency AS Currency,
			r.TotalBetsBase AS TotalBets,
			r.TotalWinsBase AS TotalWins,
			r.TotalRefundBase AS TotalRefund,
			r.CompanyTurnoverBase AS CompanyTurnover,
			r.CompanyGrossIncomeBase AS CompanyGrossIncome,
			r.CompanyCommBase AS CompanyComm,
			r.HousePT AS HousePositionTaking
		FROM #Result r
			INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
			INNER JOIN dbo.Customer c WITH(NOLOCK) ON r.custId = c.custid
		ORDER BY c.username
	END
	ELSE
	BEGIN
		SELECT
			SUM(r.BetCount) AS BetCount,
			COUNT(DISTINCT r.custid) - @TotalRefundCust AS NoOfPlayers,
			e.exchangeid AS CurrencyId,
			e.currency AS Currency,
			SUM(r.TotalBets) AS TotalBets,
			SUM(r.TotalWins) AS TotalWins,
			SUM(r.TotalRefund) AS TotalRefund,
			SUM(r.CompanyTurnover) AS CompanyTurnover,
			SUM(r.CompanyGrossIncome) AS CompanyGrossIncome,
			SUM(r.CompanyComm) AS CompanyComm
		FROM #Result r
			INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
		GROUP BY e.exchangeid, e.currency
		ORDER BY e.currency
	END

	-- Total
	SELECT
		'GrandTotal' AS ReportBy,
		SUM(BetCount) AS BetCount,
		COUNT(DISTINCT custid) - @TotalRefundCust AS NoOfPlayers,
		-1 AS CurrencyId,
		'RM' AS Currency,
		SUM(TotalBetsBase)  AS TotalBets,
		SUM(TotalWinsBase) AS TotalWins,
		SUM(TotalRefundBase) AS TotalRefund,
		SUM(CompanyTurnoverBase) AS CompanyTurnover,		
		SUM(CompanyGrossIncomeBase) AS CompanyGrossIncome,
		SUM(CompanyCommBase) AS CompanyComm
	FROM #Result

	DROP TABLE #Data
	DROP TABLE #SportBettype
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_Devide
	DROP TABLE #tmp_GameTableID
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_SportType
	DROP TABLE #CustUser
	DROP TABLE #Result
	DROP TABLE #tmp_Result
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Customer_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_Customer_14] TO [vnteam];
GO
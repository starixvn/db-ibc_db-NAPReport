/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Customer_HousePT_14]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@CustID			INT,
	@BetType		VARCHAR(MAX) = '',
	@LeagueId		VARCHAR(MAX) = '',
	@Sporttype		VARCHAR(MAX) = '',
	@SportBetType	VARCHAR(MAX) = '',
	@Currency		VARCHAR(MAX) = '',
	@Device			VARCHAR(200) = '',
	@TotalBetType	SMALLINT = 0,
	@TotalBetValue  MONEY = NULL,
	@GameIncomeType	SMALLINT = 0,
	@GameIncomeValue MONEY = NULL,
	@HousePTType	SMALLINT = 0,
	@HousePTValue   MONEY = 0,
	@ExcludeTest	BIT = 1,
	@Site			VARCHAR(MAX) = 'All'
AS

/*
	Creator: Percy
	Date: 2016-12-21
	DB: DBACC.bodb02
	Task: Risk and Control - Non-Sport Game Statistics Report - Report by Super/Master/Agent/Username - Drilldown House PT (1-tpositiontaking)

	Revisions:
		20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		20171006@Cherry: Add filter of Number Game Bettype (#83101)
		20180328@Cherry: Integrate One RNG Jackpot (#89459)
		20180808@Cherry: Integrate Poker Games (#97809)
		20181018@Cherry: Integrate NG2 (#102229)
		20190214@Cherry: Integrate Video Poker Games (#108735)
		20200601@Cherry: Add Credit Site and support multiple currency (#135009)
		20200624@Cherry: Archive VSRaceInfo (#136256)
		20200710@Cherry: Integrate Pragmatic Jackpot (#137268)
		20200828@Cherry: Integrate Saba.club Free Bet (#140109)
		20200917@Cherry: Improve performance (#141844)


	Param's Explanation:
		- @ProductID: string filter by Product 
		- @BetType: string filter by bettype
		- @LeagueId: string filter by LeagueId (only use for ProductID = 3 - Number Game get LeagueId)  
		- @Sporttype: string filter by Sporttype (only use for ProductID = 5 - Virtual Sports get Sporttype)
		- @HousePTType: 
			 1: >=
			-1: <=
		- @HousePTValue: Value to compare with 1-tpositiontaking
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @WLDate DATETIME, @CID INT
	SELECT  @WLDate = @WinlostDate, @CID = @CustID

	CREATE TABLE #tmp_ProductID		(ProductID TINYINT)
	CREATE TABLE #tmp_BetType		(Bettype SMALLINT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT, Bettype INT)
	CREATE TABLE #tmp_SportType		(Sporttype SMALLINT)
	CREATE TABLE #tmp_Devide		(Betfrom NVARCHAR(2))
	CREATE TABLE #tmpContributionBettype (Bettype INT)
	CREATE TABLE #tmpSportBetType (Sporttype INT, Bettype INT)

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
	WHERE p.ProductID IN (3, 5, 27, 42) -- Number Game, Virtual Sports, Virtual Sports 2, Saba.club
	
	INSERT INTO #SportBettype (ProductID, Bettype, EvenType, RefTable)
	SELECT s.ProductID, s.BetType, s.EventType, s.RefTable
	FROM bodb02.dbo.SportBettypeMatrix s WITH(NOLOCK) 
		INNER JOIN #tmp_ProductID p ON s.ProductID = p.ProductID
		INNER JOIN #tmp_SportType t ON s.SportType = t.Sporttype 
	WHERE p.ProductID = 23 --NG2
		AND (s.IsTest = 0 OR s.IsTest = @isTest)

	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_BetType
	-- End Get Sport Bettype Matrix --

	-- Get list member
	DECLARE @srecommend INT, @RoleID TINYINT, @recommend INT, @CustSite VARCHAR(10)
	SELECT  @srecommend = srecommend, @recommend = recommend, @RoleID = roleid, @CustSite = site FROM dbo.Customer WITH(NOLOCK) WHERE custid = @CID

	IF NOT EXISTS (SELECT 1 FROM dbo.Dep_CustSuper WITH(NOLOCK) WHERE custid = @srecommend) -- Credit - MBC Group
	BEGIN
		SELECT @CustSite = 'MBC Group'
	END
	ELSE IF @RoleID = 1
	BEGIN
		SELECT @CustSite = site FROM dbo.Customer WITH(NOLOCK) WHERE custid = @recommend
	END

	CREATE TABLE #tmp_MemIDs (CustID INT)
	
	IF @Site <> 'All'
	BEGIN
		IF ',' + @Site + ',' NOT LIKE '%,' + @CustSite + ',%'
			SELECT @CID = -1
	END
	
	-- End Get list member
	
	-- Select temp data of bettrans
	CREATE TABLE #tmp_bettrans
	(
		BetCount BIGINT,
		TotalBets MONEY, TotalBetsBase MONEY,
		TotalWins MONEY, TotalWinsBase MONEY,
		EvenType INT DEFAULT (-1), Matchid INT DEFAULT (-1), ProductID INT, Bettype INT,
		HousePT SMALLMONEY,
		RowNum INT
	)
	
	-- Get data
	CREATE TABLE #Data
	( 
		BetCount BIGINT,
		TotalBets MONEY, TotalBetsBase MONEY,
		TotalWins MONEY, TotalWinsBase MONEY,
		ProductID INT,
		HousePT SMALLMONEY,
		RowNum INT
	)

	IF @CID <> -1
	BEGIN
		IF @RoleID = 1
		BEGIN
			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					EvenType, Matchid, ProductID, Bettype,
					HousePT, RowNum
				)
				SELECT
					CASE WHEN s.ProductID = 33 THEN SUM(b.betid)  -- Poker Games
						 ELSE COUNT(b.transid) END AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.EvenType, b.matchid, s.ProductID, b.bettype,
					SUM(1 - b.tpositiontaking) AS HousePT,
					COUNT(b.transid) AS RowNum
				FROM  dbo.bettrans14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.bettype
				WHERE b.winlostdate = @WLDate
					AND b.custid = @CID
					AND b.matchid >= 0
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable IN (0, 3)
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
					AND b.bettype <> 2799
				GROUP BY s.EvenType, b.matchid, s.ProductID, b.bettype
				
				OPTION(RECOMPILE)
				
				--Mix Parlay Virtual Sport 2
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					EvenType, Matchid, ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(b.transid) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.EvenType, b.matchid, s.ProductID, b.bettype,
					SUM(1 - b.tpositiontaking) AS HousePT
				FROM  dbo.bettrans14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.bettype
				WHERE b.winlostdate = @WLDate
					AND b.custid = @CID
					AND b.matchid = 2799
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable IN (0, 3)
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
					AND b.bettype = 2799
					AND EXISTS (SELECT 1 FROM dbo.bettransm14 bm WITH (NOLOCK)
									INNER JOIN dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno)					
				GROUP BY s.EvenType, b.matchid, s.ProductID, b.bettype 
				
				OPTION(RECOMPILE)
			END

			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(CASE WHEN bt.Bettype IS NOT NULL THEN NULL ELSE b.transid END) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(CASE WHEN bt.Bettype IS NOT NULL THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT
				FROM dbo.bettransRnG14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
					LEFT JOIN #tmpContributionBettype bt ON bt.Bettype = b.gameID
				WHERE b.winlostdate = @WLDate
					AND b.custid = @CID
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 1
					AND s.ProductID <> 42
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
				
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(CASE WHEN bt.Bettype IS NOT NULL THEN NULL ELSE b.transid END) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(CASE WHEN bt.Bettype IS NOT NULL THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT
				FROM dbo.bettransRnG14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
					LEFT JOIN #tmpContributionBettype bt ON bt.Bettype = b.gameID
				WHERE b.winlostdate = @WLDate
					AND b.custid = @CID
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 1
					AND s.ProductID = 42
					AND EXISTS(SELECT 1 FROM #tmpSportBetType s where b.productid = s.Sporttype and b.gameid = s.Bettype)
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
			END
		
			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(b.transid) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(1 - b.tpositiontaking) AS HousePT
				FROM dbo.bettransLC14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
				WHERE b.winlostdate = @WLDate
					AND b.custid = @CID
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 2
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.currency, s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
			END
		END
		ELSE -- roleID > 1
		BEGIN
			INSERT INTO #tmp_MemIDs (CustID)
			SELECT CustID
			FROM dbo.custInfo WITH(NOLOCK)
			WHERE roleid = 1 AND srecommend = @srecommend
				AND CASE @RoleID
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						ELSE @CID END = @CID

			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable IN (0, 3)) -- bettrans
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					EvenType, matchid, ProductID, Bettype,
					HousePT, RowNum
				)
				SELECT
					CASE WHEN s.ProductID = 33 THEN SUM(b.betid)  -- Poker Games
						 ELSE COUNT(b.transid) END AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.EvenType, b.matchid, s.ProductID, b.bettype,
					SUM(1 - b.tpositiontaking) AS HousePT,
					COUNT(b.transid) AS RowNum
				FROM  dbo.bettrans14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.bettype
					INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				WHERE b.winlostdate = @WLDate
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND b.matchid >= 0
					AND s.RefTable IN (0, 3)
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
					AND (s.ProductID <> 27 OR (s.ProductID = 27 AND s.EvenType = 1) 
						OR (EXISTS (SELECT 1 FROM dbo.bettransm bm WITH (NOLOCK)
									INNER JOIN dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid 
									INNER JOIN #tmp_SportType st ON m.sporttype = st.Sporttype
								WHERE bm.refno = b.refno))
					)
				GROUP BY s.EvenType, b.matchid, s.ProductID, b.bettype 
				
				OPTION(RECOMPILE)
			END

			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 1) -- bettransRnG
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(CASE WHEN bt.Bettype IS NOT NULL THEN NULL ELSE b.transid END) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(CASE WHEN bt.Bettype IS NOT NULL THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT
				FROM dbo.bettransRnG14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
					INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
					LEFT JOIN #tmpContributionBettype bt ON bt.Bettype = b.gameID
				WHERE b.winlostdate = @WLDate
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 1
					AND s.ProductID <> 42
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
				
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(CASE WHEN bt.Bettype IS NOT NULL THEN NULL ELSE b.transid END) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(CASE WHEN bt.Bettype IS NOT NULL THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT
				FROM dbo.bettransRnG14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
					INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
					LEFT JOIN #tmpContributionBettype bt ON bt.Bettype = b.gameID
				WHERE b.winlostdate = @WLDate
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 1
					AND s.ProductID = 42
					AND EXISTS(SELECT 1 FROM #tmpSportBetType s where b.productid = s.Sporttype and b.gameid = s.Bettype)
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
			END

			IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE RefTable = 2) -- bettransLC
			BEGIN
				INSERT INTO #tmp_bettrans
				(
					BetCount,
					TotalBets, TotalBetsBase,
					TotalWins, TotalWinsBase,
					ProductID, Bettype,
					HousePT
				)
				SELECT
					COUNT(b.transid) AS BetCount,
					SUM(actual_stake) AS TotalBets,
					SUM(actual_stake * actualrate) AS TotalBetsBase,
					SUM(winlost) AS TotalWins,
					SUM(winlost * actualrate) AS TotalWinsBase,
					s.ProductID, b.gameID,
					SUM(1 - b.tpositiontaking) AS HousePT
				FROM dbo.bettransLC14 b WITH (NOLOCK)
					INNER JOIN #SportBettype s ON s.Bettype = b.gameID
					INNER JOIN #tmp_MemIDs m ON b.custid = m.CustID
				WHERE b.winlostdate = @WLDate
					AND b.statusID IN (111, 112, 113) -- won/lose/draw tickets
					AND s.RefTable = 2
					AND ((b.currency <> 20 AND @ExcludeTest = 1) OR @ExcludeTest = 0)
					AND (EXISTS (SELECT 1 FROM #tmp_Devide d WHERE d.Betfrom = b.betfrom) OR @Device = '')
					AND (
						@HousePTType = 0
						OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) -- 1-tpositiontaking <= @HousePTValue
						OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) -- 1-tpositiontaking >= @HousePTValue
					)
				GROUP BY s.ProductID, b.gameID 
				
				OPTION(RECOMPILE)
			END
		END
	
		--- Check condition 
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Poker Games
		BEGIN		
			INSERT INTO #Data
			(
				BetCount,
				TotalBets, TotalBetsBase,
				TotalWins, TotalWinsBase,
				ProductID,
				HousePT,
				RowNum
			)
			SELECT
				SUM(BetCount) AS BetCount,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,
				ProductID,
				SUM(HousePT) AS HousePT,
				SUM(RowNum) AS RowNum
			FROM  #tmp_bettrans
			WHERE ProductID NOT IN (3, 4, 5, 27, 33)
			GROUP BY ProductID
		END
		
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID = 33) -- Poker Games
		BEGIN		
			INSERT INTO #Data
			(
				BetCount,
				TotalBets, TotalBetsBase,
				TotalWins, TotalWinsBase,
				ProductID,
				HousePT,
				RowNum
			)
			SELECT
				SUM(BetCount) AS BetCount,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,
				b.ProductID,
				SUM(HousePT) AS HousePT,
				SUM(CASE WHEN s.RefTable = 0 THEN RowNum ELSE BetCount END) AS RowNum
			FROM  #tmp_bettrans b
				INNER JOIN #SportBettype s ON b.Bettype = s.Bettype				
			WHERE b.ProductID = 33
			GROUP BY b.ProductID
		END

		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID IN (3, 4, 5)) -- NG, SLI-Live Casino, Virtual Sport
		BEGIN		
			INSERT INTO #Data
			(
				BetCount,
				TotalBets, TotalBetsBase,
				TotalWins, TotalWinsBase,
				ProductID,
				HousePT
			)
			SELECT
				SUM(BetCount) AS BetCount,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,
				ProductID,
				SUM(HousePT) AS HousePT
			FROM  #tmp_bettrans b
				INNER JOIN dbo.match14 m WITH (NOLOCK) ON m.matchid = b.matchid
			WHERE ProductID IN (3, 4, 5) AND b.EvenType = 1
				AND (
					(b.ProductID = 3 AND (@LeagueId = '' OR (EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = m.leagueid AND l.Bettype = b.Bettype)))) OR
					(b.ProductID = 5 AND (@Sporttype = '' OR (EXISTS (SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = m.sporttype))))
				)
			GROUP BY ProductID

			-- HR
			INSERT INTO #Data
			(
				BetCount,
				TotalBets, TotalBetsBase,
				TotalWins, TotalWinsBase,
				ProductID,
				HousePT
			)
			SELECT
				SUM(BetCount) AS BetCount,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,
				ProductID,
				SUM(HousePT) AS HousePT
			FROM  #tmp_bettrans b
				INNER JOIN dbo.VSRaceInfo14 r WITH (NOLOCK) ON r.EventID = b.matchid
			WHERE b.ProductID = 5 AND b.EvenType = 3
				AND (@Sporttype = '' OR (EXISTS(SELECT 1 FROM #tmp_SportType st WHERE st.Sporttype = r.SportType)))			  
			GROUP BY b.ProductID
		END
		
		IF EXISTS (SELECT TOP 1 1 FROM #SportBettype WHERE ProductID = 27) -- Virtual Sports 2
		BEGIN		
			INSERT INTO #Data
			(
				BetCount,
				TotalBets, TotalBetsBase,
				TotalWins, TotalWinsBase,
				ProductID,
				HousePT
			)
			SELECT
				SUM(BetCount) AS BetCount,
				SUM(TotalBets) AS TotalBets,
				SUM(TotalBetsBase) AS TotalBetsBase,
				SUM(TotalWins) AS TotalWins,
				SUM(TotalWinsBase) AS TotalWinsBase,
				ProductID,
				SUM(HousePT) AS HousePT
			FROM  #tmp_bettrans b
			WHERE b.ProductID = 27
				AND (b.EvenType = 0 OR
					(EXISTS (SELECT 1 FROM dbo.match14 m WITH (NOLOCK)
									INNER JOIN #tmp_SportType st ON m.Sporttype = st.sporttype
							 WHERE b.Matchid = m.matchid))
				)	
			GROUP BY b.ProductID
		END
			
	END

	-- Return Data
	DECLARE @TotalBets MONEY, @TotalWins MONEY
	
	IF @TotalBetType <> 0 OR @GameIncomeType <> 0
	BEGIN
		IF @Currency = '-1'
			SELECT @TotalBets = SUM(TotalBetsBase), @TotalWins = SUM(TotalWinsBase) FROM #Data
		ELSE
			SELECT @TotalBets = SUM(TotalBets), @TotalWins = SUM(TotalWins) FROM #Data
		
		IF 
			(
				@TotalBetType = 0
				OR (@TotalBetType = 1 AND @TotalBets >= @TotalBetValue)
				OR (@TotalBetType =- 1 AND @TotalBets <= @TotalBetValue)
			)
			AND
			(
				@GameIncomeType = 0
				OR (@GameIncomeType = 1 AND @TotalBets - @TotalWins >= @GameIncomeValue)
				OR (@GameIncomeType =- 1 AND @TotalBets - @TotalWins <= @GameIncomeValue)
			)
		BEGIN
			;WITH CTE AS (
				SELECT
					SUM(BetCount) AS BetCount,
					ProductID,
					SUM(HousePT) AS HousePT,
					SUM(RowNum) AS RowNum
				FROM #Data
				GROUP BY ProductID
			)
			SELECT
				p.ProductName AS Product,
				CASE WHEN c.ProductID = 33 THEN HousePT/RowNum  -- Poker Games
					 WHEN BetCount = 0 THEN NULL
					 ELSE HousePT/BetCount END AS HousePositionTaking
			FROM CTE c
				INNER JOIN dbo.Products p WITH(NOLOCK) ON c.ProductID = p.ProductID
			ORDER BY p.ProductName
		END
	END
	ELSE
	BEGIN
		;WITH CTE AS (
			SELECT
				SUM(BetCount) AS BetCount,
				ProductID,
				SUM(HousePT) AS HousePT,
				SUM(RowNum) AS RowNum
			FROM #Data
			GROUP BY ProductID
		)
		SELECT
			p.ProductName AS Product,
			CASE WHEN c.ProductID = 33 THEN HousePT/RowNum  -- Poker Games
				 WHEN BetCount = 0 THEN NULL
				 ELSE HousePT/BetCount END AS HousePositionTaking
		FROM CTE c
			INNER JOIN dbo.Products p WITH(NOLOCK) ON c.ProductID = p.ProductID
		ORDER BY p.ProductName
	END

	DROP TABLE #Data
	DROP TABLE #SportBettype
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_Devide
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_SportType
	DROP TABLE #tmpContributionBettype		
	DROP TABLE #tmpSportBetType
END

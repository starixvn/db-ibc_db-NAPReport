/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_Customer]
	@WinlostDate	DATETIME,
	@ProductId		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = NULL,
	@RoleID			TINYINT = 1,
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
	@IsGrandTotal	BIT = 0
	
AS

/*
	Creator: Percy
	Date: 2016-12-02
	DB: DBACC.bodb02
	Task: Risk and Control - Non-Sport Game Statistics Report - Report by Super/Master/Agent/Username

	Revisions:
		20170215@Percy: Remove hardcode product to support Fishing World [RedmineID: #71616]
		20170227@Percy: support search multiple username [RedmineID: #71342]
		20170726@Cherry: Integrate Betradar Virtual Sports (#78495)
		20170815@Cherry: Non-Sport Statistics Phase 5 (#71923)
		20171002@Cherry: Modify Associated Accounts Code Logic (#84002)
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
		20200415@Cherry: Exclude dummy accounts (#132492)
		20200601@Cherry: Add Credit Site and support multiple currency (#135009)
		20200710@Cherry: Integrate Pragmatic Jackpot (#137268)
		20200828@Cherry: Integrate Saba.club Free Bet (#140109)
		20200917@Cherry: Improve performance (#141844)
		20200922@Cherry: Improve performance (#142096)
		20200928@Cherry: Hot fix (#142436)
		20201210@Cherry: Add Real Turnover (#146137)
		20201224@Cherry: Integrate Happy 5 Linked Games (#146537)
		20210120@Cherry: Integrate Saba Jackpot (#148293)	

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
		- @currency: 
			-1: All convert to RM currency
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
					NULL AS RealTurnover,
					NULL AS CompanyGrossIncome,
					NULL AS CompanyComm,
					NULL AS HousePositionTaking,
					NULL AS SiteName,
					NULL AS ExtraPT
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
				NULL AS RealTurnover,		
				NULL AS CompanyGrossIncome,
				NULL AS CompanyComm,
				NULL AS ExtraPT
			RETURN
		END
	END

	DECLARE @WLDate SMALLDATETIME
	SELECT  @WLDate = CAST(@WinlostDate AS SMALLDATETIME)

	CREATE TABLE #tmp_ProductID		(ProductID TINYINT)
	CREATE TABLE #tmp_BetType		(Bettype SMALLINT)
	CREATE TABLE #tmp_LeagueID		(LeagueID INT, Bettype INT)
	CREATE TABLE #tmp_SportType		(Sporttype SMALLINT)
	CREATE TABLE #tmp_Device		(Betfrom NVARCHAR(2))
	CREATE TABLE #tmpCurrency (CurrencyId INT)
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
			INSERT INTO #tmp_LeagueID(LeagueID, Bettype) VALUES (@league, @bettypeid)
			SET @start = @charindex1 +1
			SET @charindex1 = charindex(@splitter1, @LeagueID, @start)          
		END
	END
	
	IF @SportBetType <> '' AND EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 42)
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
	
	IF @Currency <> '-1'
    BEGIN
		INSERT INTO #tmpCurrency (CurrencyId)
		SELECT val FROM [dbo].strSplit(@Currency, ',')
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

		INSERT INTO #tmp_Company (SiteName, Srecommend)
		SELECT s.Site, c.srecommend
		FROM #tmp_Site s
			INNER JOIN dbo.Site ss WITH (NOLOCK) ON s.Site = ss.site
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON ss.Site = c.site
		WHERE c.roleid = 4

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
	
	CREATE CLUSTERED INDEX IX_SportBettype ON #SportBettype (ProductID, Bettype, EvenType, RefTable)  
	CREATE CLUSTERED INDEX IX_SportType ON #tmp_SportType (Sporttype)    
	CREATE CLUSTERED INDEX IX_LeagueID ON #tmp_LeagueID (LeagueID, Bettype)

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
					AND a.ProductId IN (SELECT ProductID FROM #tmp_ProductID)
               GROUP BY ProductID,
                        SuperId  

	-- Select temp data of bettrans, bettransRnG, bettransLC
	CREATE TABLE #tmp_bettrans
	(
		srecommend INT,
		mrecommend INT,
		recommend INT,
		custid INT,
		Bettype INT,
		BetCount BIGINT,
		CurrencyID INT,
		TotalBets DECIMAL(19,4),
		TotalBetsBase DECIMAL(19,4),
		TotalWins DECIMAL(19,4),
		TotalWinsBase DECIMAL(19,4),
		TotalRefund DECIMAL(19,4), 
		TotalRefundBase DECIMAL(19,4),
		CompanyTurnover DECIMAL(19,4),
		CompanyTurnoverBase DECIMAL(19,4),
		RealTurnover DECIMAL(19,4),
		RealTurnoverBase DECIMAL(19,4),
		CompanyGrossIncome DECIMAL(19,4),
		CompanyGrossIncomeBase DECIMAL(19,4),
		CompanyComm DECIMAL(19,4),
		CompanyCommBase DECIMAL(19,4),
		HousePT DECIMAL(19,4),
		ExtraPT DECIMAL(19,8),
		ExtraPTBase DECIMAL(19,8),
		RowNum INT
	)

	-- ProductID NOT IN (3, 4, 5, 27, 33)) -- NG, SLI-Live Casino, Virtual Sports, Virtual Sports 2, Poker Games
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			RealTurnover,
			RealTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE RefTable IN (0, 3) AND ProductID NOT IN (3, 4, 5, 27, 33))
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		
		OPTION(RECOMPILE)
		
		INSERT INTO #tmpContributionBettype (Bettype)
		SELECT Bettype
		FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
		WHERE BettypeGroupID = 10
		
		DELETE #tmpContributionBettype
		WHERE bettype NOT IN (SELECT bettype FROM #SportBettype) 

		DELETE #SportBettype
		WHERE bettype IN (SELECT bettype FROM #tmpContributionBettype)
	
		IF EXISTS(SELECT 1 FROM #SportBettype WHERE ProductID <> 42)
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
				TotalRefund ,
				TotalRefundBase ,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
				b.currency CurrencyID,
				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
			FROM dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate				
				AND (b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND ProductID <> 42)
					OR EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
				AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
				AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
				AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)			
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency
			
			OPTION(RECOMPILE)
		END
		
		IF (EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 42) AND (SELECT COUNT(1) FROM #tmp_ProductID) = 1)
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
				TotalRefund ,
				TotalRefundBase ,
				CompanyTurnover,
				CompanyTurnoverBase,
				CompanyGrossIncome,
				CompanyGrossIncomeBase,
				CompanyComm,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
			)
			SELECT
				b.srecommend,
				b.mrecommend,
				b.recommend,
				b.custid,
				b.gameID,
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
				b.currency CurrencyID,
				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
				SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
				SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
				SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
						ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
				COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
			FROM dbo.bettransRnG b WITH (NOLOCK)
			WHERE b.winlostdate = @WLDate				
				AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 1 AND ProductID = 42)
				AND EXISTS(SELECT 1 FROM #tmpSportBetType s WHERE b.productid = s.Sporttype and b.gameid = s.Bettype)
				AND b.statusID IN (111, 112, 113, 103) 
				AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
				AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
				AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
				AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
				AND (
					@HousePTType = 0
					OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
					OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
				)			
			GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency
			
			OPTION(RECOMPILE)
		END
		
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.gameID,
			0 AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(scomm * actualrate) AS CompanyCommBase,
			0 AS HousePT,
			SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraWL,
			SUM((b.ContributionStake3rd + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraWLBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM dbo.bettransRnG b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.gameID IN (SELECT Bettype FROM #tmpContributionBettype) 
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency
		
		OPTION(RECOMPILE)
		
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			RealTurnover,
			RealTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.gameID,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(scomm * actualrate) AS CompanyCommBase,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM dbo.bettransLC b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.gameID IN (SELECT Bettype FROM #SportBettype WHERE RefTable = 2)
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.gameID, b.currency
		
		OPTION(RECOMPILE)
		
	END
	
	-- Poker Games
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 33)
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			SUM(CASE WHEN b.statusID IN (111, 112, 113) THEN b.betid ELSE 0 END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,
			SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,
			SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,
			0 AS CompanyTurnover,
			0 AS CompanyTurnoverBase,
			SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,
			SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,
			SUM(scomm) AS CompanyComm,
			SUM(scomm * actualrate) AS CompanyCommBase,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM(ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) ExtraPT,
			SUM((ISNULL(b.transid2, 0) * 1.0 / 10000 * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) - b.oddsspread * ISNULL(c.ExtraComm,0)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
			LEFT JOIN #ExtraComm c ON b.srecommend = c.SuperID AND c.ProductID = 33 
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 33 AND RefTable = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Number Game
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 3)
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (EXISTS (SELECT 1 FROM Match m WITH (NOLOCK) INNER JOIN #tmp_LeagueID l ON m.leagueid = l.LeagueID WHERE m.matchid = b.matchid AND l.Bettype = b.bettype)
				OR EXISTS (SELECT 1 FROM #tmp_LeagueID l WHERE l.LeagueID = 168 AND l.Bettype = b.bettype)
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Live Casino
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 4)
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 4)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sports
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 5)
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT matchid FROM dbo.match WITH (NOLOCK)
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
		
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 5 AND EvenType = 3)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND (@Sporttype = '' OR
				b.matchid IN (SELECT EventId FROM VSRaceInfo WITH (NOLOCK) 
								WHERE sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))				
				)
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
	END
	
	-- Virtual Sports 2
	CREATE TABLE #tmp_bettransm (refno BIGINT)
	IF EXISTS (SELECT 1 FROM #tmp_ProductID WHERE ProductID = 27)  
	BEGIN
		INSERT INTO #tmp_bettransm (refno)
		SELECT DISTINCT bm.refno FROM dbo.bettransm bm WITH(NOLOCK)
					INNER JOIN dbo.match m WITH(NOLOCK) ON bm.matchid = m.matchid 
					INNER JOIN #tmp_Sporttype st ON m.sporttype = st.Sporttype
					
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
							ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 1)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.matchid IN (SELECT m.matchid FROM dbo.match m WITH (NOLOCK) 
								WHERE m.sporttype IN (SELECT Sporttype FROM #tmp_Sporttype))	
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
		
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
			TotalRefund ,
			TotalRefundBase ,
			CompanyTurnover,
			CompanyTurnoverBase,
			CompanyGrossIncome,
			CompanyGrossIncomeBase,
			CompanyComm,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase,
			RowNum
		)
		SELECT
			b.srecommend,
			b.mrecommend,
			b.recommend,
			b.custid,
			b.bettype,
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS BetCount,
			b.currency CurrencyID,
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,
			SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate) AS TotalBetsBase,
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
			SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE 1 - b.tpositiontaking END) AS HousePT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,
			SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0
					ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase,							
			COUNT(CASE WHEN b.statusID IN (111, 112, 113) THEN b.transid ELSE NULL END) AS RowNum			
		FROM  dbo.bettrans b WITH (NOLOCK)
		WHERE b.winlostdate = @WLDate				
			AND b.bettype IN (SELECT Bettype FROM #SportBettype WHERE ProductID = 27 AND EvenType = 0)
			AND b.ruben = 1
			AND b.statusID IN (111, 112, 113, 103) 
			AND b.refno IN (SELECT refno FROM #tmp_bettransm)		
			AND (@ExcludeTest = 0 OR (b.currency <> 20 AND @ExcludeTest = 1))
			AND (@Currency = '-1' OR EXISTS (SELECT 1 From #tmpCurrency c WHERE b.currency = c.CurrencyId))	
			AND (@IsFilterCust = 0 OR EXISTS (SELECT 1 FROM #tmp_MemIDs m WHERE m.CustID = b.custid))
			AND (@Device = '' OR EXISTS (SELECT 1 FROM #tmp_Device d WHERE d.Betfrom = b.betfrom))
			AND (
				@HousePTType = 0
				OR (@HousePTType = -1 AND b.tpositiontaking >= 1-@HousePTValue) 
				OR (@HousePTType = 1 AND b.tpositiontaking <= 1-@HousePTValue) 
			)			
		GROUP BY b.srecommend, b.mrecommend, b.recommend, b.custid, b.bettype, b.currency
		OPTION(RECOMPILE)
	END
	
	--Update Real Turnover
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
		TotalBets DECIMAL(19,4),
		TotalBetsBase DECIMAL(19,4),
		TotalWins DECIMAL(19,4),
		TotalWinsBase DECIMAL(19,4),
		TotalRefund DECIMAL(19,4),
		TotalRefundBase DECIMAL(19,4),
		CompanyTurnover DECIMAL(19,4),
		CompanyTurnoverBase DECIMAL(19,4),
		RealTurnover DECIMAL(19,4),
		RealTurnoverBase DECIMAL(19,4),
		CompanyGrossIncome DECIMAL(19,4),
		CompanyGrossIncomeBase DECIMAL(19,4),
		CompanyComm DECIMAL(19,4),
		CompanyCommBase DECIMAL(19,4),
		HousePT DECIMAL(19,4),
		ExtraPT DECIMAL(19,8),
		ExtraPTBase DECIMAL(19,8),
		RowNum INT
	)
	
	INSERT INTO #Data 
		(srecommend,
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
		TotalRefund,
		TotalRefundBase,
		CompanyTurnover,
		CompanyTurnoverBase,
		RealTurnover,
		RealTurnoverBase,
		CompanyGrossIncome,
		CompanyGrossIncomeBase,
		CompanyComm,
		CompanyCommBase,
		HousePT,
		ExtraPT,
		ExtraPTBase,
		RowNum)
	SELECT
		b.srecommend,
		b.mrecommend,
		b.recommend,
		b.custid,
		SUM(BetCount),
		b.CurrencyID,
		s.ProductID,
		SUM(TotalBets),
		SUM(TotalBetsBase),
		SUM(TotalWins),
		SUM(TotalWinsBase),
		SUM(TotalRefund),
		SUM(TotalRefundBase),
		SUM(CompanyTurnover),
		SUM(CompanyTurnoverBase),
		SUM(RealTurnover),
		SUM(RealTurnoverBase),
		- SUM(CompanyGrossIncome),
		- SUM(CompanyGrossIncomeBase),
		- SUM(CompanyComm),
		- SUM(CompanyCommBase),
		SUM(HousePT),
		- SUM(b.ExtraPT),
		- SUM(b.ExtraPTBase),
		SUM(RowNum)
	FROM #tmp_bettrans b
		INNER JOIN dbo.customer a WITH(NOLOCK) ON b.recommend = a.custid
		INNER JOIN (SELECT DISTINCT Bettype, ProductID
					FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)) s ON b.Bettype = s.Bettype
	WHERE a.username not like '%acc%'
	GROUP BY s.ProductID, b.custid, b.CurrencyID, b.srecommend, b.mrecommend, b.recommend	
	
	CREATE TABLE #tmp_Result
	( 
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		ProductID TINYINT,
		TotalBets DECIMAL(19,4),
		TotalWins DECIMAL(19,4),
		TotalRefund DECIMAL(19,4),
		CompanyTurnover DECIMAL(19,4),
		RealTurnover DECIMAL(19,4),
		CompanyGrossIncome DECIMAL(19,4),
		CompanyComm DECIMAL(19,4),
		TotalBetsBase DECIMAL(19,4),
		TotalWinsBase DECIMAL(19,4),
		TotalRefundBase DECIMAL(19,4),
		CompanyTurnoverBase DECIMAL(19,4),
		RealTurnoverBase DECIMAL(19,4),
		CompanyGrossIncomeBase DECIMAL(19,4),
		CompanyCommBase DECIMAL(19,4),
		HousePT DECIMAL(19,4),
		ExtraPT DECIMAL(19,8),
		ExtraPTBase DECIMAL(19,8),
		RowNum INT
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

		IF @Currency = '-1'
		BEGIN
			;WITH Result AS (
				SELECT
					CASE @roleID
						WHEN 1 THEN custid
						WHEN 2 THEN recommend
						WHEN 3 THEN mrecommend
						WHEN 4 THEN srecommend
						END AS custid,
					SUM(BetCount) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(TotalBetsBase) AS TotalBets,
					SUM(TotalWinsBase) AS TotalWins,
					SUM(TotalRefundBase) AS TotalRefund,
					SUM(CompanyTurnoverBase) AS CompanyTurnover,	
					SUM(RealTurnoverBase) AS RealTurnover,	
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncome,
					SUM(CompanyCommBase) AS CompanyComm,
					SUM(TotalBetsBase)  AS TotalBetsBase,
					SUM(TotalWinsBase) AS TotalWinsBase,
					SUM(TotalRefundBase) AS TotalRefundBase,
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
					SUM(RealTurnoverBase) AS RealTurnoverBase,			
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
					SUM(CompanyCommBase) AS CompanyCommBase,
					SUM(HousePT) AS HousePT,
					SUM(ExtraPTBase) ExtraPT,
					SUM(ExtraPTBase) ExtraPTBase,
					SUM(RowNum) AS RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum 
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
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
					SUM(BetCount) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(TotalBets) AS TotalBets,
					SUM(TotalWins) AS TotalWins,
					SUM(TotalRefund) AS TotalRefund,
					SUM(CompanyTurnover) AS CompanyTurnover,	
					SUM(RealTurnover) AS RealTurnover,	
					SUM(CompanyGrossIncome) AS CompanyGrossIncome,
					SUM(CompanyComm) AS CompanyComm,
					SUM(TotalBetsBase)  AS TotalBetsBase,
					SUM(TotalWinsBase) AS TotalWinsBase,
					SUM(TotalRefundBase) AS TotalRefundBase,
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
					SUM(RealTurnoverBase) AS RealTurnoverBase,		
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
					SUM(CompanyCommBase) AS CompanyCommBase,
					SUM(HousePT) AS HousePT,
					SUM(ExtraPT) ExtraPT,
					SUM(ExtraPTBase) ExtraPTBase,
					SUM(RowNum) AS RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
			FROM Result
		END
	END
	ELSE -- @roleID = 0 --> click associated accounts link
	BEGIN
		IF @Currency = '-1' -- base RM
		BEGIN
			;WITH Result AS (
				SELECT
					c.custid,
					SUM(BetCount) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(TotalBetsBase) AS TotalBets,
					SUM(TotalWinsBase) AS TotalWins,
					SUM(TotalRefundBase) AS TotalRefund,
					SUM(CompanyTurnoverBase) AS CompanyTurnover,	
					SUM(RealTurnoverBase) AS RealTurnover,		
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncome,
					SUM(CompanyCommBase) AS CompanyComm,
					SUM(TotalBetsBase)  AS TotalBetsBase,
					SUM(TotalWinsBase) AS TotalWinsBase,
					SUM(TotalRefundBase) AS TotalRefundBase,
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,	
					SUM(CompanyTurnoverBase) AS RealTurnoverBase,	
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
					SUM(CompanyCommBase) AS CompanyCommBase,
					SUM(HousePT) AS HousePT,
					SUM(ExtraPTBase) ExtraPT,
					SUM(ExtraPTBase) ExtraPTBase,
					SUM(RowNum) AS RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
			FROM Result
		END
		ELSE
		BEGIN
			;WITH Result AS (
				SELECT
					c.custid,
					SUM(BetCount) AS BetCount,
					CurrencyID,
					ProductID,
					SUM(TotalBets) AS TotalBets,
					SUM(TotalWins) AS TotalWins,
					SUM(TotalRefund) AS TotalRefund,
					SUM(CompanyTurnover) AS CompanyTurnover,	
					SUM(RealTurnover) AS RealTurnover,		
					SUM(CompanyGrossIncome) AS CompanyGrossIncome,
					SUM(CompanyComm) AS CompanyComm,
					SUM(TotalBetsBase)  AS TotalBetsBase,
					SUM(TotalWinsBase) AS TotalWinsBase,
					SUM(TotalRefundBase) AS TotalRefundBase,
					SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,	
					SUM(RealTurnoverBase) AS RealTurnoverBase,		
					SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
					SUM(CompanyCommBase) AS CompanyCommBase,
					SUM(HousePT) AS HousePT,
					SUM(ExtraPT) ExtraPT,
					SUM(ExtraPTBase) ExtraPTBase,
					SUM(RowNum) AS RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
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
				RealTurnover,
				CompanyGrossIncome,
				CompanyComm,
				TotalBetsBase,
				TotalWinsBase,
				TotalRefundBase,
				CompanyTurnoverBase,
				RealTurnoverBase,
				CompanyGrossIncomeBase,
				CompanyCommBase,
				HousePT,
				ExtraPT,
				ExtraPTBase,
				RowNum
			FROM Result
		END
	END

	CREATE TABLE #Result
	( 
		custid BIGINT,
		BetCount INT,
		CurrencyID INT,
		TotalBets DECIMAL(19,4),
		TotalWins DECIMAL(19,4),
		TotalRefund DECIMAL(19,4),
		CompanyTurnover DECIMAL(19,4),
		RealTurnover DECIMAL(19,4),
		CompanyGrossIncome DECIMAL(19,4),
		CompanyComm DECIMAL(19,4),
		TotalBetsBase DECIMAL(19,4),
		TotalWinsBase DECIMAL(19,4),
		TotalRefundBase DECIMAL(19,4),
		CompanyTurnoverBase DECIMAL(19,4),
		RealTurnoverBase DECIMAL(19,4),
		CompanyGrossIncomeBase DECIMAL(19,4),
		CompanyCommBase DECIMAL(19,4),
		HousePT DECIMAL(19,4),
		ExtraPT DECIMAL(19,8),
		ExtraPTBase DECIMAL(19,8)
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
		RealTurnover,
		CompanyGrossIncome,
		CompanyComm,
		TotalBetsBase,
		TotalWinsBase,
		TotalRefundBase,
		CompanyTurnoverBase,
		RealTurnoverBase,
		CompanyGrossIncomeBase,
		CompanyCommBase,
		HousePT,
		ExtraPT,
		ExtraPTBase
	)
	SELECT
		custid,
		SUM(BetCount) AS BetCount,
		CurrencyID,
		SUM(TotalBets) AS TotalBets,
		SUM(TotalWins) AS TotalWins,
		SUM(TotalRefund) AS TotalRefund,
		SUM(CompanyTurnover) AS CompanyTurnover,
		SUM(RealTurnover) AS RealTurnover,
		SUM(CompanyGrossIncome) AS CompanyGrossIncome,
		SUM(CompanyComm) AS CompanyComm,
		SUM(TotalBetsBase) AS TotalBetsBase,
		SUM(TotalWinsBase) AS TotalWinsBase,
		SUM(TotalRefundBase) AS TotalRefundBase,
		SUM(CompanyTurnoverBase) AS CompanyTurnoverBase,
		SUM(RealTurnoverBase) AS RealTurnoverBase,
		SUM(CompanyGrossIncomeBase) AS CompanyGrossIncomeBase,
		SUM(CompanyCommBase) AS CompanyCommBase,
		AVG(CASE WHEN ProductID = 33 THEN HousePT/RowNum --Poker Games
				 WHEN BetCount = 0 THEN NULL 
				 ELSE HousePT/BetCount END) AS HousePT,
		SUM(ExtraPT) ExtraPT,
		SUM(ExtraPTBase) ExtraPTBase	 		 
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

	IF @RoleID = 0 --Click Associated Accounts
	BEGIN
		INSERT INTO #Result
		(
			custid,
			BetCount,
			CurrencyID,
			TotalBets,
			TotalWins,
			TotalRefund,
			CompanyTurnover,
			RealTurnover,
			CompanyGrossIncome,
			CompanyComm,
			TotalBetsBase,
			TotalWinsBase,
			TotalRefundBase,
			CompanyTurnoverBase,
			RealTurnoverBase,
			CompanyGrossIncomeBase,
			CompanyCommBase,
			HousePT,
			ExtraPT,
			ExtraPTBase
		)
		SELECT
			c.CustID,
			0 BetCount,
			cust.currency,
			0 TotalBets,
			0 TotalWins,
			0 TotalRefund,
			0 CompanyTurnover,
			0 RealTurnover,
			0 CompanyGrossIncome,
			0 CompanyComm,
			0 TotalBetsBase,
			0 TotalWinsBase,
			0 TotalRefundBase,
			0 CompanyTurnoverBase,
			0 RealTurnoverBase,
			0 CompanyGrossIncomeBase,
			0 CompanyCommBase,
			0 HousePT,
			0 ExtraPT,
			0 ExtraPTBase
		FROM #CustUser c
			LEFT JOIN #Result d ON c.CustID = d.custid 
			INNER JOIN dbo.Customer cust WITH(NOLOCK) ON c.CustID = cust.custid 
		WHERE d.custid IS NULL
	END

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
			r.CompanyTurnover AS HouseTurnover,
			r.RealTurnover AS RealTurnover,
			r.CompanyGrossIncome AS HouseGrossIncome,
			r.CompanyComm AS HouseComm,
			r.HousePT AS HousePositionTaking,
			CASE WHEN c.roleid = 1 THEN a.site ELSE c.site END AS SiteName,
			r.ExtraPT 
		FROM #Result r
			INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
			LEFT JOIN dbo.Customer c WITH(NOLOCK) ON r.custId = c.custid
			LEFT JOIN dbo.Customer a WITH(NOLOCK) ON a.custid = c.recommend 
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
			r.CompanyTurnoverBase AS HouseTurnover,
			r.RealTurnoverBase AS RealTurnover,
			r.CompanyGrossIncomeBase AS HouseGrossIncome,
			r.CompanyCommBase AS HouseComm,
			r.HousePT AS HousePositionTaking,
			CASE WHEN c.roleid = 1 THEN a.site ELSE c.site END AS SiteName,
			r.ExtraPTBase ExtraPT
		FROM #Result r
			INNER JOIN dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.exchangeid
			LEFT JOIN dbo.Customer c WITH(NOLOCK) ON r.custId = c.custid
			LEFT JOIN dbo.Customer a WITH(NOLOCK) ON a.custid = c.recommend 
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
			SUM(r.CompanyTurnover) AS HouseTurnover,
			SUM(r.RealTurnover) AS RealTurnover,
			SUM(r.CompanyGrossIncome) AS HouseGrossIncome,
			SUM(r.CompanyComm) AS HouseComm,
			SUM(r.ExtraPT) ExtraPT
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
		SUM(CompanyTurnoverBase) AS HouseTurnover,	
		SUM(RealTurnoverBase) AS RealTurnover,		
		SUM(CompanyGrossIncomeBase) AS HouseGrossIncome,
		SUM(CompanyCommBase) AS HouseComm,
		SUM(ExtraPTBase) ExtraPT
	FROM #Result

	DROP TABLE #Data
	DROP TABLE #SportBettype
	DROP TABLE #tmp_ProductID
	DROP TABLE #tmp_bettrans
	DROP TABLE #tmp_Device
	DROP TABLE #tmp_LeagueID
	DROP TABLE #tmp_MemIDs
	DROP TABLE #tmp_SportType
	DROP TABLE #CustUser
	DROP TABLE #Result
	DROP TABLE #tmp_Result
	DROP TABLE #tmp_bettransm
	DROP TABLE #Device
	DROP TABLE #ExtraComm
	DROP TABLE #tmpCurrency
	DROP TABLE #tmpContributionBettype	
	DROP TABLE #tmpSportBetType
	DROP TABLE #tmpNetStakeBettype	
	DROP TABLE #tmpNoBetCountBettype

END

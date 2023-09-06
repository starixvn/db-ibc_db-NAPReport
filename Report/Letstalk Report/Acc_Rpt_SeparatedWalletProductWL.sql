/*<info serverAlias="DBLIC-bodb_3rdProduct" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SeparatedWalletProductWL
	@WinlostDate DATE
	,@ProductID INT
	,@DataMode VARCHAR(50) = ''
AS
/*
	Created: Roy@20230829
	Task: Get WL Product By Date
	DB: DBACC.bodb02

	Revisions:
		20230829@Roy: Letstalk Reports - Support to show Exchange Product statistics every 2 hours for today (#181348)

	Param's Explanation:
		@ProductID: Exchange(31), AG Casino(11)
		@DataMode: reutrn ResultSet based on this value, default BLANK
					- Letstalk34
					- Letstalk36
	Example:
		EXEC bodb02.dbo.Acc_Rpt_SeparatedWalletProductWL
			@WinlostDate = '2022-06-29'
			,@ProductID = 31
			,@DataMode = 'Letstalk34'
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @PartyList VARCHAR(MAX)
		,@WLDate DATETIME
		,@DummyBetType INT
		,@DummyMatchID INT
	
	IF @ProductID = 31 --Exchange(31)
	BEGIN
		SELECT @WLDate = @WinlostDate
			,@DummyBetType = BetType --8000
			,@DummyMatchID = SportType --221
		FROM bodb02.dbo.SportBetTypeMatrix WITH (NOLOCK)
		WHERE ProductID = @ProductID
	END
	
	CREATE TABLE #tmpLicByProduct (
		LicenseeID INT
		,LicenseeName VARCHAR(50)
		,CurrencyID INT
		,Recommend INT
	)

	CREATE TABLE #tmpRawData (
		WinlostDate DATE
		,CustID INT
		,CurrencyID INT
		,BetType SMALLINT
		,Stake MONEY
		,Actual_Stake MONEY
		,Winlost MONEY
		,PlayerComm MONEY DEFAULT(0)
		,Comm MONEY DEFAULT(0)
	)

	CREATE TABLE #tmpChargeRate (
		ChargeID INT
		,LicenseeID INT
		,Rate MONEY
	)

	CREATE TABLE #tmpChargeRateByCurr (
		ChargeID INT
		,CurrencyID INT
		,Rate MONEY
	)
	--------------------------------------------------
	INSERT INTO #tmpLicByProduct (
		LicenseeID
		,LicenseeName
		,CurrencyID
		,Recommend
	)
	SELECT DISTINCT l.LicenseeID
		,l.LicenseeName
		,c.Currency
		,c.CustID
	FROM bodb02.dbo.Products AS p WITH (NOLOCK)
		INNER JOIN bodb_Licensee.dbo.Product3rd AS prd WITH (NOLOCK) ON p.ProductPrefix = prd.ProductPrefix
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd AS lprd WITH (NOLOCK) ON lprd.ProductID = prd.ProductID
		INNER JOIN bodb_licensee.dbo.Licensees AS l WITH (NOLOCK) ON l.LicenseeID = lprd.LicenseeID
		INNER JOIN bodb_licensee.dbo.f_SelLicenseeCust(0) AS c ON c.LicenseeID = l.LicenseeID
	WHERE p.ProductID = @ProductID
	
	;WITH CTE_Party AS (
		SELECT DISTINCT FromParty AS PartyId
		FROM bodb_licensee.dbo.OAS_ChargeInfo AS c WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.Product3rd AS prd WITH (NOLOCK) ON c.ProductID = prd.ProductID
			INNER JOIN bodb02.dbo.Products AS p WITH (NOLOCK) ON prd.ProductPrefix = p.ProductPrefix
		WHERE p.ProductID = @ProductID
	)
	SELECT @PartyList = COALESCE(@PartyList + ',' + CONVERT(VARCHAR, PartyId), CONVERT(VARCHAR, PartyId))
	FROM CTE_Party
	
	INSERT INTO #tmpChargeRate (
		ChargeID
		,LicenseeID
		,Rate
	)
	SELECT DISTINCT ChargeID
		,LicenseeID
		,DI_Rate
	FROM (
		SELECT ChargeID
			,LicenseeID
			,DI_Rate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyList, CONVERT(VARCHAR, @WLDate, 23), CONVERT(VARCHAR, @WLDate, 23), 'BX', 'OA', 1)
		WHERE DI_Rate > 0
			AND ChargeType IN (1, 12)
		
		UNION
		
		SELECT ChargeID
			,LicenseeID
			,DI_Rate
		FROM bodb_licensee.dbo.LA_f_GetChargeInfoWithTrialTime(@PartyList, CONVERT(VARCHAR, @WLDate, 23), CONVERT(VARCHAR, @WLDate, 23), 'BX', 'OA', 1)
		WHERE DI_Rate > 0
			AND ChargeType IN (1, 12)
	) AS t
	
	INSERT INTO #tmpChargeRateByCurr (
		ChargeID
		,CurrencyID
		,Rate
	)
	SELECT DISTINCT rbc.ChargeID
		,rbc.CurrencyID
		,rbc.Rate
	FROM bodb_Licensee.dbo.LA_ChargeRateByCurrency AS rbc WITH (NOLOCK)
		INNER JOIN #tmpChargeRate AS r ON rbc.ChargeID = r.ChargeID
	
	INSERT INTO #tmpRawData (
		WinlostDate
		,CustID
		,CurrencyID
		,BetType
		,Stake
		,Actual_stake
		,Winlost
		,PlayerComm
		,Comm
	)
	SELECT CONVERT(DATE, b.SettledDate) AS WinlostDate
		,b.CustID
		,b.Currency
		,@DummyBetType AS BetType
		,SUM(b.stakeTotal / b.ExVirtualRate) AS Stake
		,SUM(b.stakeTotal / b.ExVirtualRate) AS Actual_stake
		,SUM((b.marketTotal + b.stakeTotal) / b.ExVirtualRate) AS Winlost
		,SUM(b.Commission / b.ExVirtualRate) AS PlayerComm
		,SUM((b.agentCommission + b.Commission) / b.ExVirtualRate) AS Comm
	FROM bodb_3rdProduct.dbo.Sum_winloss_Exchange AS b WITH (NOLOCK, FORCESEEK)
	WHERE b.SettledDate >= @WLDate
		AND b.SettledDate < DATEADD(DD,1,@WLDate)
		AND b.currency <> 20
	GROUP BY CONVERT(DATE, b.SettledDate)
		,b.CustID
		,b.Currency
	
	CREATE CLUSTERED INDEX tmpRawData ON #tmpRawData (CustID, CurrencyID)
	
	/*
		reutrn ResultSet based on @DataMode
	*/
	IF @DataMode = 'Letstalk34'
	BEGIN
		;WITH CTE AS (
			SELECT d.WinlostDate
				,d.CurrencyID
				,d.BetType
				,l.LicenseeID
				,SUM(d.Stake) AS Stake
				,SUM(d.Actual_stake) AS Actual_stake
				,SUM(d.Winlost) AS Winlost
				,SUM(d.Comm) AS SComm
			FROM #tmpRawData AS d
				INNER JOIN bodb02.dbo.vw_Customer AS c WITH (NOLOCK) ON d.CustID = c.CustID AND c.roleid = 1
				INNER JOIN #tmpLicByProduct AS l ON c.Recommend = l.Recommend AND d.CurrencyID = l.CurrencyID
			GROUP BY d.WinlostDate
				,d.CurrencyID
				,d.BetType
				,l.LicenseeID
		)
		SELECT d.WinlostDate
			,d.BetType
			,CASE WHEN Winlost - Actual_stake > 0 THEN 112
				WHEN Winlost - Actual_stake < 0 THEN 113
				ELSE 111
				END AS StatusID
			,d.CurrencyID
			,ex.ActualRate
			,ex.ActualRate AS Virtualrate
			,CONVERT(SMALLMONEY,0) AS EPos
			,1 - ISNULL(rc.Rate, r.Rate) AS TPos
			,d.Stake
			,d.Actual_Stake
			,d.Winlost
			,- (d.Winlost - d.Actual_stake) * (1 - ISNULL(rc.Rate, r.Rate)) AS AWinlost
			,CONVERT(MONEY,0) AS MWinlost
			,CONVERT(MONEY,0) AS SWinlost
			,d.SComm
		FROM CTE AS d
			INNER JOIN bodb02.dbo.ExchangeDailyOanda AS ex WITH (NOLOCK) ON ex.ExchangeDate = CONVERT(SMALLDATETIME,d.WinlostDate) AND ex.ExchangeId = d.CurrencyID
			INNER JOIN #tmpChargeRate AS r ON d.LicenseeID = r.LicenseeID
			LEFT JOIN #tmpChargeRateByCurr AS rc ON r.ChargeID = rc.ChargeID AND d.CurrencyID = rc.CurrencyID
	END
	ELSE IF @DataMode = 'Letstalk36'
	BEGIN
		;WITH CTE AS (
			SELECT d.WinlostDate
				,d.CurrencyID
				,c.SRecommend
				,d.BetType
				,l.LicenseeID
				,SUM(d.Stake) AS Stake
				,SUM(d.Actual_stake) AS Actual_stake
				,SUM(d.Winlost) AS Winlost
				,SUM(d.Comm) AS Comm
				,SUM(d.PlayerComm) AS PlayerComm
			FROM #tmpRawData AS d
				INNER JOIN bodb02.dbo.vw_Customer AS c WITH (NOLOCK) ON d.CustID = c.CustID AND c.roleid = 1
				INNER JOIN #tmpLicByProduct AS l ON c.Recommend = l.Recommend AND d.CurrencyID = l.CurrencyID
			GROUP BY d.WinlostDate
				,d.CurrencyID
				,c.SRecommend
				,d.BetType
				,l.LicenseeID
		)
		SELECT d.WinlostDate
			,CONVERT(BIT,0) AS LiveIndicator
			,CONVERT(BIT,0) AS IsBA
			,@ProductID AS ProductID
			,@DummyMatchID AS SportType
			,d.BetType
			,CASE WHEN Winlost - Actual_stake > 0 THEN 'WON'
				WHEN Winlost - Actual_stake < 0 THEN 'LOSE'
				ELSE 'DRAW'
				END AS Status
			,d.SRecommend
			,d.CurrencyID
			,d.Stake
			,d.Actual_Stake
			,d.Winlost
			,- (d.Winlost - d.Actual_stake) * (1 - ISNULL(rc.Rate, r.Rate)) AS AWinlost
			,CONVERT(MONEY,0) AS MWinlost
			,CONVERT(MONEY,0) AS SWinlost
			,d.PlayerComm
			,d.Comm
		FROM CTE AS d
			INNER JOIN #tmpChargeRate AS r ON d.LicenseeID = r.LicenseeID
			LEFT JOIN #tmpChargeRateByCurr AS rc ON r.ChargeID = rc.ChargeID AND d.CurrencyID = rc.CurrencyID
	END
	ELSE --default
	BEGIN
		;WITH CTE AS (
			SELECT d.WinlostDate
				,d.BetType
				,l.LicenseeID
				,l.LicenseeName
				,c.Recommend
				,c.SRecommend
				,d.CurrencyID
				,SUM(d.Stake) AS Stake
				,SUM(d.Actual_stake) AS Actual_stake
				,SUM(d.Winlost) AS Winlost
				,SUM(d.Comm) AS Comm
				,SUM(d.PlayerComm) AS PlayerComm
			FROM #tmpRawData AS d
				INNER JOIN bodb02.dbo.vw_Customer AS c WITH (NOLOCK) ON d.CustID = c.CustID AND c.roleid = 1
				INNER JOIN #tmpLicByProduct AS l ON c.Recommend = l.Recommend AND d.CurrencyID = l.CurrencyID
			GROUP BY d.WinlostDate
				,c.SRecommend
				,d.BetType
				,l.LicenseeID
				,l.LicenseeName
				,c.Recommend
				,c.SRecommend
				,d.CurrencyID
		)
		SELECT d.WinlostDate
			,ISNULL(@DummyMatchID, 0) AS MatchID
			,CONVERT(BIT,0) AS LiveIndicator
			,CONVERT(BIT,0) AS IsBA
			,d.BetType
			,CASE WHEN Winlost - Actual_stake > 0 THEN 112
				WHEN Winlost - Actual_stake < 0 THEN 113
				ELSE 111
				END AS StatusID
			,CASE WHEN Winlost - Actual_stake > 0 THEN 'WON'
				WHEN Winlost - Actual_stake < 0 THEN 'LOSE'
				ELSE 'DRAW'
				END AS Status
			,d.LicenseeName AS Site
			,d.Recommend
			,d.SRecommend
			,d.CurrencyID
			,ex.ActualRate
			,ex.ActualRate AS Virtualrate
			,1 - ISNULL(rc.Rate, r.Rate) AS APos
			,CONVERT(SMALLMONEY,0) AS EPos
			,1 - ISNULL(rc.Rate, r.Rate) AS TPos
			,d.Stake
			,d.Actual_Stake
			,d.Winlost
			,- (d.Winlost - d.Actual_stake) * (1 - ISNULL(rc.Rate, r.Rate)) AS AWinlost
			,CONVERT(MONEY,0) AS MWinlost
			,CONVERT(MONEY,0) AS SWinlost
			,d.PlayerComm
			,d.Comm
			,d.Comm AS SComm
		FROM CTE AS d
			INNER JOIN bodb02.dbo.ExchangeDailyOanda AS ex WITH (NOLOCK) ON ex.ExchangeDate = CONVERT(SMALLDATETIME,d.WinlostDate) AND ex.ExchangeId = d.CurrencyID
			INNER JOIN #tmpChargeRate AS r ON d.LicenseeID = r.LicenseeID
			LEFT JOIN #tmpChargeRateByCurr AS rc ON r.ChargeID = rc.ChargeID AND d.CurrencyID = rc.CurrencyID
	END
	
	DROP TABLE #tmpLicByProduct
	DROP TABLE #tmpRawData
	DROP TABLE #tmpChargeRate
	DROP TABLE #tmpChargeRateByCurr
END

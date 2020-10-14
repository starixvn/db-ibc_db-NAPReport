/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MemberWL]
	@FromDate		DATE
	,@ToDate		DATE
	,@ProductIds	VARCHAR(MAX)
	,@SubProducts	VARCHAR(MAX) = ''
	,@DepositType	TINYINT = 2
AS

/*
	Created: 20200901@Percy
	DB: DBWH-bodb_Account
	Task: House Net Income - Get data from DW

	Revisions:
		- 20200901@Percy: Initialize SP [RedmineID: #140677]

	Param's Explanation:
		@DepositType:
			. 0 = Credit
			. 1 = Deposit
			. 2 = All (Credit + Deposit)
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	SELECT @SubProducts = ISNULL(',' + @SubProducts + ',', '')

	-- Mapping site
	DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
	INSERT INTO @tmpSite (LicenseeId, SiteName)
	SELECT LicenseeId, RTRIM(LTRIM(LicenseeName))
	FROM DBLIC.bodb_licensee.dbo.Licensees WITH (NOLOCK)
	WHERE (@DepositType = 2 OR IsDeposit = @DepositType)

	UPDATE s
	SET s.SiteId_DW = t.SiteId
	FROM @tmpSite s
		INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))

	-- Bettype list
	DECLARE @tmpBetType TABLE (ProductId INT, BetType INT, BettypeGroup INT DEFAULT (-1))
	INSERT INTO @tmpBetType (ProductId, BetType)
	SELECT DISTINCT
		CASE
			WHEN bettype BETWEEN 8101 AND 8200 THEN -2
			WHEN bettype = 4298 THEN -3
			WHEN bettype BETWEEN 801 AND 899 THEN -4
			WHEN bettype = 38 THEN -5
			ELSE ProductId
			END
		,BetType
	FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE ',' + @ProductIds + ',' LIKE '%,' + CONVERT(VARCHAR(5), ProductId) + ',%'
		AND BetType NOT IN (901, 902, 903, 904, 911, 912, 18000, 1700, 1706, 1800, 8000)
		AND (
			ProductId NOT IN (1, 3, 32)
			OR
			(
				ProductId = 1
				AND (
					bettype BETWEEN 801 AND 899
					OR bettype = 38
				)
			)
			OR
			(
				ProductId = 3
				AND (
					@SubProducts LIKE '%,NG,%' AND bettype NOT BETWEEN 8101 AND 8200
					OR @SubProducts LIKE '%,H5,%' AND bettype BETWEEN 8101 AND 8200
				)
			)
			OR
			(
				ProductId = 32
				AND BetType NOT IN (4299, 4300)
				AND (
					@SubProducts LIKE '%,PP,%' AND bettype <> 4298
					OR @SubProducts LIKE '%,PP-JP,%' AND bettype = 4298
				)
			)
	)

	IF @SubProducts LIKE '%,PP-JP,%'
		INSERT INTO @tmpBetType (ProductId, BetType)
		VALUES (-3, 4297)

	IF ',' + @ProductIds + ',' LIKE '%,-1,%' -- BT (Bettrade)
		INSERT INTO @tmpBetType (ProductId, BetType)
		VALUES (-1, 903), (-1, 904)

	UPDATE @tmpBetType
	SET BetTypeGroup = 1
	WHERE ProductId = 22 -- VB (Macau Games)
		AND BetType IN (SELECT BetType FROM bodb_Account.dbo.BettypeGroup WITH (NOLOCK) WHERE BettypeGroupID = 11)

	UPDATE @tmpBetType
	SET BettypeGroup = Bettype
	WHERE ProductId = 34 -- CC (Card Club)
		AND Bettype IN (1902, 1903, 1904, 1905)

	UPDATE @tmpBetType
	SET BettypeGroup = 1
	WHERE ProductId = 39 -- SAG (SA Gaming)
		AND Bettype = 3007

	-- Get data
	CREATE TABLE #__MemberWL (rptDate DATE, LicenseeId INT, CurrencyId INT, ProductId INT, SporttypeGroup INT, BettypeGroup INT, MemberWL MONEY, HouseWL MONEY, AComm MONEY, HouseContribution MONEY, FullContribution MONEY)
	INSERT INTO #__MemberWL (rptDate, LicenseeId, CurrencyId, ProductId, SporttypeGroup, BettypeGroup, MemberWL, HouseWL, AComm, HouseContribution, FullContribution)
	SELECT b.rptDate, s.LicenseeId, b.CurrencyId, bt.ProductId, -1, bt.BetTypeGroup
		,SUM(CASE
				WHEN b.BetType IN (4297) THEN 0
				WHEN b.BetType IN (903, 904, 913, 914) THEN b.WinlossP + b.WinlossA
				WHEN bt.ProductId = -4 THEN b.WinlossP + b.WinLossA + b.WinLossS + b.WinLossM + b.CommissionS
				WHEN bt.ProductId = -5 THEN b.WinlossP + b.CommissionS
				ELSE b.WinlossP
				END) AS MemberWL
		,SUM(CASE WHEN b.bettype = 4297 THEN 0 ELSE b.WinlossIBC + b.CommissionS END) AS HouseWL
		,0 AS AComm
		,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC ELSE 0 END) AS HouseContribution
		,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
	FROM bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN @tmpBetType bt ON b.BetType = bt.BetType
		INNER JOIN @tmpSite s ON b.SiteId = s.SiteId_DW
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyId <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
	GROUP BY b.rptDate, s.LicenseeId, b.CurrencyId, bt.ProductId, bt.BetTypeGroup
	OPTION (RECOMPILE)

	SELECT rptDate, LicenseeId, CurrencyId, ProductId, SporttypeGroup, BettypeGroup, MemberWL, HouseWL, AComm, HouseContribution, FullContribution
	FROM #__MemberWL

	DROP TABLE #__MemberWL
END
GO

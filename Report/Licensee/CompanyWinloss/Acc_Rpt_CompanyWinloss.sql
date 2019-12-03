/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinloss
	  @FromDate SMALLDATETIME
	, @ToDate SMALLDATETIME
	, @LicenseeId INT
	, @CurrencyId TINYINT = 0
	, @ProductPrefix VARCHAR(10) = ''
	, @MoveBetsDay SMALLDATETIME
	
AS
/*	Creator: 20150612@Patrick
	Task : Get company win loss
	DB: DBEXT/bodb02

	Param's Explanation:
		@ProductId default value is 0 it mean get all products
		@CurrencyId default value is 0 it mean get all currencies
		
	Revisions:
		- 20150630@Patrick: Remove the UUS line
		- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
		- 20160119@Patrick: Support BetTrade
		- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
		- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20160919@Robert: Licensee / Company Win Loss: Missing data of Bettrade when generating report for All Products [RedmineID: #64312]
		- 20160909@Robert: Offer Colossus Bets for Cash Model (#63144)
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
		- 20160323@Percy: Refactor code aplly new products [RedmineID: #73328]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	DECLARE @FromDateTmp DATE, @ToDateTmp DATE, @LicenseeName VARCHAR(50)
	SELECT  @FromDateTmp = @FromDate, @ToDateTmp = @ToDate

	SELECT  @ProductPrefix = ISNULL(@ProductPrefix, '')

	DECLARE @ProductId INT
	SELECT  @ProductId = ProductId FROM dbo.Products WITH(NOLOCK) WHERE ProductPrefix = @ProductPrefix
	
	DECLARE @SAgWinLoss TABLE (CustId INT, CompanyWL MONEY) 
	DECLARE @Super AS TABLE (custid INT, currency TINYINT)
	DECLARE @BetTypeList TABLE(BetType SMALLINT)
	DECLARE @SportTypeList TABLE(SportType SMALLINT, IsBA BIT DEFAULT (0))

	DECLARE @ExcludeBettype TABLE (bettype SMALLINT)
	INSERT INTO @ExcludeBettype (bettype)
	VALUES (901), (902), (911), (912) -- always exclude

	IF @ProductPrefix <> '' -- get detail product not in bettrade, Cash Out
	BEGIN
		INSERT INTO @ExcludeBettype(bettype)
		VALUES (903), (904), (913), (914)
	END

	SELECT @LicenseeName = LicenseeName
	FROM bodb_Licensee.dbo.Licensees (NOLOCK) WHERE LicenseeID = @LicenseeID

	IF @ProductPrefix IN ('SB', 'BA') -- sportbook
    BEGIN
		INSERT INTO @SportTypeList(SportType)
		VALUES (0)

		IF @ProductPrefix = 'BA'
		BEGIN
			UPDATE @SportTypeList
			SET IsBA = 1
			WHERE SportType = 0
		END

		INSERT INTO @BetTypeList(BetType)
		SELECT DISTINCT BetType
		FROM dbo.f_SportBettypeMatrix_Sel(1, 0, 0, 2, '', '', @isTest)
		WHERE BetType NOT BETWEEN 901 AND 904
    END
	ELSE IF @ProductPrefix = 'BT' -- bettrade
	BEGIN
	   INSERT INTO @BetTypeList(BetType)
	   VALUES (903), (904) -- don't include 901, 902
    END
	ELSE
	BEGIN
		INSERT INTO @SportTypeList(SportType)
		SELECT DISTINCT SportType
		FROM dbo.SportBettypeMatrix WITH(NOLOCK)
		WHERE ProductID = @ProductId

		INSERT INTO @BetTypeList(BetType)
		SELECT DISTINCT BetType
		FROM dbo.f_SportBettypeMatrix_Sel(@ProductId, 0, 0, 2, '', '', @isTest)
		WHERE BetType NOT IN (911, 912) -- for Cash Out
	END
	
	INSERT INTO @Super(custid, currency)
	SELECT DISTINCT CustID, currency
	FROM bodb_Licensee.dbo.f_SelDepCustSuper(@LicenseeName)
	WHERE ((@CurrencyId = 0) OR (@CurrencyId <> 0 AND currency = @CurrencyId)) AND currency <> 20
		
	IF @ToDate > @MoveBetsDay
	BEGIN
		IF @ProductPrefix = '' -- get all products
		BEGIN
			INSERT INTO @SAgWinLoss(CustId, CompanyWL)
			SELECT b.srecommend
				, - SUM(ISNULL(swinlost, 0) + ISNULL(mwinlost, 0) + ISNULL(awinlost, 0) + ISNULL(winlost, 0) - ISNULL(actual_stake, 0) + ISNULL(scomm, 0))
			FROM dbo.bettrans b WITH (NOLOCK, INDEX = IX_srecommend)
				INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency = s.currency
			WHERE b.winlostdate BETWEEN @FromDateTmp AND @ToDateTmp
				AND b.bettype < 19999
				AND NOT EXISTS (SELECT 1 FROM @ExcludeBettype e WHERE b.bettype = e.bettype)
				AND b.statusid IN (111, 112, 113)
			GROUP BY b.srecommend
		END
		ELSE
		BEGIN
			INSERT INTO @SAgWinLoss(CustId, CompanyWL)
			SELECT b.srecommend
				, - SUM(ISNULL(swinlost, 0) + ISNULL(mwinlost, 0) + ISNULL(awinlost, 0) + ISNULL(winlost, 0) - ISNULL(actual_stake, 0) + ISNULL(scomm, 0))
			FROM dbo.bettrans b WITH (NOLOCK, INDEX = IX_srecommend)
				INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency = s.currency
			WHERE b.winlostdate BETWEEN @FromDateTmp AND @ToDateTmp
				AND EXISTS (SELECT 1 FROM @BetTypeList bt WHERE b.bettype = bt.bettype)
				AND b.statusid IN (111, 112, 113)
				AND (
					@ProductPrefix NOT IN ('SB', 'BA')
					OR (@ProductPrefix = 'SB' AND b.apositiontaking <> 0)
					OR (@ProductPrefix = 'BA' AND b.apositiontaking = 0)
				)
			GROUP BY b.srecommend
		END
	END

	IF @FromDateTmp <= @MoveBetsDay 
	BEGIN
		IF @ToDateTmp >= @MoveBetsDay
			SET @ToDateTmp = @MoveBetsDay

		IF @ProductPrefix = '' -- get all product
		BEGIN
			INSERT INTO @SAgWinLoss(custid, CompanyWL)
			SELECT b.srecommend
				, - SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS Company
			FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH (NOLOCK)
				INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency = s.currency
			WHERE b.winlostdate BETWEEN @FromDateTmp AND @ToDateTmp
				AND b.RoleId = 4
				AND b.BetType < 19999
				AND b.statusid IN (111, 112, 113, 114, 115)
				AND NOT EXISTS (SELECT 1 FROM @ExcludeBettype e WHERE b.bettype = e.bettype)
			GROUP BY b.srecommend
		END
		ELSE
		BEGIN
			IF @ProductPrefix IN ('BT', 'CO')
			BEGIN
				INSERT INTO @SAgWinLoss(custid, CompanyWL)
				SELECT b.srecommend
					, - SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS Company
				FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH (NOLOCK)
					INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency = s.currency
				WHERE b.winlostdate BETWEEN @FromDateTmp AND @ToDateTmp
					AND b.RoleId = 4
					AND EXISTS (SELECT 1 FROM @BetTypeList bt WHERE b.bettype = bt.BetType)
					AND b.statusid IN (111, 112, 113, 114, 115)
				GROUP BY b.srecommend
			END
			ELSE
			BEGIN
				INSERT INTO @SAgWinLoss(custid, CompanyWL)
				SELECT b.srecommend
					, - SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS Company
				FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH (NOLOCK)
					INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency = s.currency
					INNER JOIN @SportTypeList bt ON b.SportType = bt.SportType AND b.IsBA = bt.IsBA
				WHERE b.winlostdate BETWEEN @FromDateTmp AND @ToDateTmp
					AND b.RoleId = 4
					AND b.statusid IN (111, 112, 113, 114, 115)
					AND NOT EXISTS (SELECT 1 FROM @ExcludeBettype e WHERE b.bettype = e.BetType)
				GROUP BY b.srecommend
			END
		END
	END

	--show result
	SELECT ROW_NUMBER() OVER(ORDER BY UserName) AS RowId
		, UserName, SUM(CompanyWL) AS CompanyWL--, c.custid
	FROM @SAgWinLoss tmp
		INNER JOIN dbo.Customer c WITH(NOLOCK) ON tmp.CustId = c.custid
	WHERE roleid = 4
	GROUP BY UserName
END

GO
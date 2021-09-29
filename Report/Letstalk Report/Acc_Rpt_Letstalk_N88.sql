/*<info serverAlias="DBN88-bodb_N88" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_N88
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Letstalk_N88]
	@FromDate	DATE
	,@ToDate	DATE
	,@TimeZone	INT = -4
AS

/*
	Created: 20200827@Percy
	DB: DBN88-bodb_N88
	Task: NAP Report - Letstalk - Novacash Performance

	Revisions:
		- 20200827@Percy: Initialize SP [RedmineID: #138339]
		- 20210923@Percy: Change data source [RedmineID: #162087]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = DATEADD(DAY, -1, @FromDate), @TDate = DATEADD(DAY, 1, @ToDate)

	DECLARE @FromDateTimeGMT DATETIME, @ToDateTimeGMT DATETIME -- convert to data time zone: GMT+0
	SELECT  @FromDateTimeGMT = DATEADD(HOUR, -@TimeZone, CONVERT(DATETIME, @FromDate))
			,@ToDateTimeGMT = DATEADD(DAY, 1, DATEADD(HOUR, -@TimeZone, CONVERT(DATETIME, @ToDate))) -- include time

	-- 1. Member Information
	BEGIN
		-- Active Members
		DECLARE @ActiveMembers TABLE (SiteId INT, Currency INT, ActiveMembers INT)
		INSERT INTO @ActiveMembers (SiteId, Currency, ActiveMembers)
		SELECT c.SiteId, c.CurrencyId, COUNT(1)
		FROM (
			SELECT CustId
			FROM dbo.N88_SumWinloss WITH (NOLOCK)
			WHERE TransTime >= @FromDateTimeGMT AND TransTime < @ToDateTimeGMT
			GROUP BY CustId
		) r
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON r.CustId = c.CustId
		WHERE c.IsTest = 0
		GROUP BY c.SiteId, c.CurrencyId

		-- Deposit Members
		DECLARE @DepositMembers TABLE (SiteId INT, Currency INT, DepositMembers INT, FirstDepositTrans INT, DepositTrans INT)
		INSERT INTO @DepositMembers (SiteId, Currency, DepositMembers, FirstDepositTrans, DepositTrans)
		SELECT c.SiteId, c.CurrencyId, COUNT(1), SUM(FirstDepositTrans), SUM(DepositTrans)
		FROM (
			SELECT CustId, COUNT(CASE WHEN FirstDeposit = 1 THEN 1 ELSE NULL END) AS FirstDepositTrans, COUNT(1) AS DepositTrans
			FROM dbo.DepositInfo WITH (NOLOCK)
			WHERE WinlostDate BETWEEN @FDate AND @TDate
				AND CreateTime >= @FromDateTimeGMT AND CreateTime < @ToDateTimeGMT
				AND Status = 3 -- Approved
			GROUP BY CustId
		) d
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON d.CustId = c.CustId
		WHERE c.IsTest = 0
		GROUP BY c.SiteId, c.CurrencyId

		-- Return data
		SELECT s.LicenseeName, e.Currency, r.ActiveMembers, r.DepositMembers, r.FirstDepositTrans, r.DepositTrans
		FROM (
			SELECT
				ISNULL(a.SiteId, d.SiteId)		AS SiteId
				,ISNULL(a.Currency, d.Currency)	AS Currency
				,ISNULL(a.ActiveMembers, 0)		AS ActiveMembers
				,ISNULL(d.DepositMembers, 0)	AS DepositMembers
				,ISNULL(d.FirstDepositTrans, 0) AS FirstDepositTrans
				,ISNULL(d.DepositTrans, 0)		AS DepositTrans
			FROM @ActiveMembers a
				FULL OUTER JOIN @DepositMembers d ON a.Currency = d.Currency AND a.SiteId = d.SiteId
		) r
			INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON r.Currency = e.ExchangeId
			INNER JOIN dbo.ServerInfo s WITH (NOLOCK) ON r.SiteId = s.SiteId
	END

	-- 2. Winloss performance
	BEGIN
		CREATE TABLE #Exchange (FromDate DATE, ToDate DATE, ExchangeId INT, Rate FLOAT)
		INSERT INTO #Exchange (FromDate, ToDate, ExchangeId, Rate)
		SELECT FromDate, ToDate, ExchangeId, Rate FROM bodb02.dbo.Lrf_f_GetExchangeRate(@FromDate, @ToDate, 'MYR', '')

		;WITH CTE_tmpData AS (
			SELECT CONVERT(DATE, DATEADD(HOUR, -4, r.SettledTime)) AS ExchangeDate, r.Currency, r.SiteId, r.GameType, SUM(r.BetCount) AS BetCount, SUM(r.ValidBet) AS ValidBet, SUM(r.Winloss) AS Winloss
			FROM dbo.N88_SumWinloss r WITH (NOLOCK)
			WHERE r.SettledTime >= @FromDateTimeGMT AND r.SettledTime < @ToDateTimeGMT
				AND r.StatusId IN (1, 2, 4, 6)
				AND r.GameType <> 1 -- Exclude OW Sports
				AND EXISTS (SELECT 1 FROM dbo.Customer c WITH (NOLOCK) WHERE r.CustId = c.CustId AND c.IsTest = 0)
			GROUP BY CONVERT(DATE, DATEADD(HOUR, -4, r.SettledTime)), r.Currency, r.SiteId, r.GameType
		)
		SELECT s.LicenseeName, g.TypeName AS Product, BetCount, ValidBet AS Turnover, Winloss
			,ValidBet AS CoTurnover, -Winloss AS CoIncome
			, CASE WHEN ValidBet = 0 THEN 0 ELSE -Winloss/ValidBet END AS CoMargin
		FROM (
			SELECT r.SiteId, r.GameType, SUM(r.BetCount) AS BetCount, SUM(r.ValidBet * e.Rate) AS ValidBet, SUM(r.Winloss * e.Rate) AS Winloss
			FROM CTE_tmpData r
				INNER JOIN #Exchange e ON r.ExchangeDate BETWEEN e.FromDate AND e.ToDate AND r.Currency = e.ExchangeId
			GROUP BY r.SiteId, r.GameType
		) r
			INNER JOIN dbo.TpGameType g WITH (NOLOCK) ON r.GameType = g.Type
			INNER JOIN dbo.ServerInfo s WITH (NOLOCK) ON r.SiteId = s.SiteId
	END

	DROP TABLE #Exchange
END
GO
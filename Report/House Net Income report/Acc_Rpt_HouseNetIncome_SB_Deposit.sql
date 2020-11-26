/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SB_Deposit]
	@FromDate	DATE
   ,@ToDate		DATE
AS

/*  
	Created: Victor
	Date: 2016-05-23
    Task: House month-to-date Net Income report
    DB: DBEXT-bodb02
   
    Revisions:
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20161024@Harper - #65699: HAIFA - Apply new charge rate discount for HNI report
		- 20171206@Harper - Update Pay To MuayThai amount due to include Parlay data [RedmineID: #83193]		
		- 20180131@Harper - Fix Daily HAIFA data [#RedmineID: 90263]
		- 20180518@Harper - Hot Fix Daily HAIFA data [#RedmineID: 95399]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20190308@Robert: 109770 - House Net Income - Change formula for MTD values and add old month data into a new sheet
		- 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		- 20200203@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200113@Ned.Le: DHWL Letstalk Reports - Break SB into Soccer, OS and Parlay (#126634)
		- 20200202@Robert: #126634 DHWL - break OS into Basketball, E-sports, Tennis and Other Sports
		- 20200720@Percy: Separate Saba Sports [RedmineID: #137822]
		- 20200529@Ned.Le: Letstalk Reports - Saba - Treat Saba Futsal as Saba Soccer (#142264)
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
		- 20201026@Percy: Offer Odds Spread Adjustment for Sportsbook [RedmineID: #111275]
		- 20201120@Percy: Apply group min fee [RedmineID: #135865]

	EXEC Acc_Rpt_HouseNetIncome_SB_Deposit '2017-12-01', '2017-12-31'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate

	DECLARE @Discount_PartyIds VARCHAR(MAX)

	-- Get licensee charge rate
	BEGIN
		-- All licensees
		CREATE TABLE #AllLicensees (LicenseeId INT, PartyId INT, ParentId INT)
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
		SELECT OldRefId, PartyId, ParentId
		FROM (
			SELECT ci.FromParty AS PartyId, ci.ToParty AS ParentId, p.OldRefId
				,ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
			FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
				INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
				INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
				INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
			WHERE ci.ChargeType = 1
				AND p.PartyType = 1
				AND pd.IsDeposit = 1
				AND ci.ToParty IN (1, 9, 11, 98)
		) r
		WHERE RowNum = 1

		-- Licensees by product
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT, ParentId INT)
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		SELECT DISTINCT p.OldRefId, p.PartyId, ci.ToParty
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
		WHERE p.PartyType = 1
			AND pd.IsDeposit = 1
			AND ci.ToParty IN (1, 9, 11, 98)
			AND ci.ProductId IN (0, 3)
			AND (
				(ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
			)

		-- Get charge rate
		DECLARE @PartyIDs VARCHAR(1000)
		SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees
		
		CREATE TABLE #PartyChargeInfo
		(
			ChargeId		INT
			,PartyId		INT
			,LicenseeId		INT
			,ParentId		INT
			,Product3rdId	INT
			,Rate			MONEY
			,FromDate		DATE
			,ToDate			DATE
			,Bettype		INT
			,ChargeType		INT
		)
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
		SELECT ci.ChargeId, ci.PartyId, ci.LicenseeId, p.ParentId, ci.ProductId, ci.DI_Rate, ci.FromDate, ci.ToDate, ISNULL(sbr.Bettype, ci.Bettype), ci.ChargeType
		FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, 'SB,BA', 'OA', 1) ci
			INNER JOIN #Licensees p ON ci.PartyId = p.PartyId
			LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE ci.ChargeType = 1
			AND ci.DI_Rate > 0

		CREATE TABLE #PartyCharge3rdInfo
		(
			LicenseeId		INT
			,Product3rdId	INT
			,ChargeType		INT
			,Rate			MONEY
			,FromDate		DATE
			,ToDate			DATE
		)

		-- Licensee to 3rd
		INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
		SELECT DISTINCT p.LicenseeId, ci.ProductId, ci.ChargeType, ci.DI_Rate, ci.FromDate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'SB,BA', 'OA') ci
			INNER JOIN #PartyChargeInfo p ON p.PartyId = ci.PartyId AND ci.ProductId = p.Product3rdId
		WHERE ci.ChargeType = 1

		-- OW to 3rd
		INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
		SELECT DISTINCT p.LicenseeId, ci.ProductId, ci.ChargeType, ci.DI_Rate, ci.FromDate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (@FDate, @TDate, 'SB,BA', 'OA') ci
			INNER JOIN #PartyChargeInfo p ON p.ParentId = ci.PartyId AND ci.ProductId = p.Product3rdId
		WHERE ci.ChargeType = 1
			AND NOT EXISTS (SELECT 1 FROM #PartyCharge3rdInfo rd WHERE p.LicenseeId = rd.LicenseeId AND ci.ProductId = rd.Product3rdId)

		-- For Metric Gaming
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, LicenseeId, ParentId, Product3rdId, Rate, FromDate, ToDate, Bettype, ChargeType)
		SELECT ChargeId, PartyId, LicenseeId, ParentId, -4, Rate, FromDate, ToDate, -1, ChargeType
		FROM #PartyChargeInfo
		WHERE Product3rdId = 0

		INSERT INTO #PartyCharge3rdInfo (LicenseeId, Product3rdId, ChargeType, Rate, FromDate, ToDate)
		SELECT LicenseeId, -4, ChargeType, Rate, FromDate, ToDate
		FROM #PartyCharge3rdInfo
		WHERE Product3rdId = 0

		DROP TABLE #Licensees
	END

	-- Get exchange rate
	BEGIN
		CREATE TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
		INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData
		(
			rptDate				DATE
			,LicenseeId			INT
			,CurrencyId			INT
			,ProductId			INT
			,SportTypeGroup		INT
			,BetTypeGroup		INT
			,MemberWL			MONEY DEFAULT(0)
			,HouseWL			MONEY DEFAULT(0) -- Odds Spread Adjustment
			,AComm				MONEY DEFAULT(0)
			,HouseContribution	MONEY DEFAULT(0) -- not use (due to using core sp)
			,FullContribution	MONEY DEFAULT(0) -- not use (due to using core sp)
		)

		-- Mapping site
		CREATE TABLE #__tempSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO #__tempSite (SiteId_DW, SiteName)
		SELECT SiteId, RTRIM(LTRIM(Site)) FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE IsDeposit = 1
			
		UPDATE s
		SET s.LicenseeId = l.LicenseeId
		FROM #__tempSite s
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(l.LicenseeName))
			
		-- Saba League
		CREATE TABLE #__SabaLeague (LeagueId INT, LeagueGroupId INT)
		INSERT INTO #__SabaLeague (LeagueId, LeagueGroupId)
		SELECT LeagueId, LeagueGroupId FROM dbo.League WITH (NOLOCK) WHERE sporttype IN (1, 2, 50) AND LeagueGroupId IN (42, 74, 108)

		CREATE TABLE #__tempSB (rptDate DATE, SiteId INT, CurrencyId INT, ProductId INT, LeagueId INT, Sporttype INT, MemberWL MONEY, AWL MONEY, AComm MONEY)
		INSERT INTO #__tempSB (rptDate, SiteId, CurrencyId, ProductId, LeagueId, Sporttype, MemberWL, AWL, AComm)
		SELECT f.rptDate, f.SiteId, f.CurrencyId, f.ProductId, f.LeagueId
			,CASE
				WHEN f.BetType IN (9, 29) THEN -2 -- Parlay
				WHEN f.SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
				ELSE 99 -- Other Sports
				END AS Sporttype
			,SUM(f.MemberWinloss) AS MemberWL
			,SUM(CASE WHEN f.bettype = 999 THEN f.AgentWinloss ELSE 0 END) AS AWL -- Odds Spread Adjustment
			,SUM(f.AgentComm) AS AComm
		FROM DBWH.bodb_Account.dbo.FactLADailyWinloss f WITH (NOLOCK)
		WHERE f.rptDate BETWEEN @FDate AND @TDate
			AND f.SiteId NOT IN(-2, -4)
			AND f.ProductId IN (10001, 10004)
			AND f.Bettype NOT IN (901, 902, 903, 904)
			AND f.CurrencyId <> 20
			AND f.TicketStatus NOT IN(-1, 18, 9, 10, 14)
		GROUP BY f.rptDate, f.SiteId, f.CurrencyId, f.ProductId, f.LeagueId
			,CASE
				WHEN f.BetType IN (9, 29) THEN -2 -- Parlay
				WHEN f.SportType IN (1, 2, 5, 43, 50) THEN SportType -- Soccer, Basketball, Tennis, E-Sports
				ELSE 99 -- Other Sports
				END
		OPTION (RECOMPILE)

		INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SporttypeGroup, BettypeGroup, MemberWL, HouseWL, AComm)
		SELECT t.rptDate, s.LicenseeId, t.CurrencyId
			,CASE
				WHEN t.ProductId = 10001 THEN 0 -- SB
				ELSE 3 -- BA
				END AS ProductId
			,CASE
				WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
				WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -4 -- Saba Basketball
				WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -5 -- Saba Cricket
				WHEN t.SportType IN (-2, 1, 2, 5, 43) THEN t.SportType
				ELSE 99
				END AS SporttypeGroup
			,-1 AS BettypeGroup
			,SUM(t.MemberWL) AS MemberWL
			,SUM(t.AWL) AS HouseWL -- Odds Spread Adjustment
			,SUM(t.AComm) AS AComm
		FROM #__tempSB t
			INNER JOIN #__tempSite s ON t.SiteId = s.SiteId_DW
			LEFT JOIN #__SabaLeague l ON t.LeagueId = l.LeagueId
		GROUP BY t.rptDate, s.LicenseeId, t.CurrencyId
			,CASE
				WHEN t.ProductId = 10001 THEN 0 -- SB
				ELSE 3 -- BA
				END
			,CASE
				WHEN l.LeagueGroupId IN (42, 74, 108) AND t.SportType = 1 THEN -3 -- Saba Soccer
				WHEN l.LeagueGroupId IN (42) AND t.SportType = 2 THEN -4 -- Saba Basketball
				WHEN l.LeagueGroupId IN (42) AND t.SportType = 50 THEN -5 -- Saba Cricket
				WHEN t.SportType IN (-2, 1, 2, 5, 43) THEN t.SportType
				ELSE 99
				END

		DROP TABLE #__SabaLeague
		DROP TABLE #__tempSB
		DROP TABLE #__tempSite

		-- Get data Metric Gaming, Bet Builder (input ProductId = 1 return Metric Gaming = -4, Bet Builder = -5)
		INSERT INTO #__tempData (rptDate, LicenseeId, CurrencyId, ProductId, SportTypeGroup, BetTypeGroup, MemberWL, HouseWL, AComm, HouseContribution, FullContribution)
		EXEC DBWH.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MemberWL
			@FromDate		= @FDate
			,@ToDate		= @TDate
			,@ProductIds	= 1
			,@SubProducts	= ''
			,@DepositType	= 1
		
		CREATE TABLE #__tempResult
		(
			rptDate				DATETIME
			,PartyId			INT
			,Product3rdId		INT
			,SporttypeGroup		INT
			,MemberWL			MONEY
			,PayToSupplier		MONEY
			,AmountToCompany	MONEY
			,AComm				MONEY
			,IsApplyMinFee		BIT DEFAULT (1)
		)
		INSERT INTO #__tempResult (rptDate, PartyId, Product3rdId, SporttypeGroup, MemberWL, PayToSupplier, AmountToCompany, AComm)
		SELECT t.rptDate, l.PartyId, t.ProductId, t.SporttypeGroup
			,SUM(t.MemberWL * ISNULL(oa.Rate, 0))
			,SUM(t.MemberWL * ISNULL(oa.Rate, 0) * CASE WHEN t.ProductId = -4 THEN -1 * ISNULL(lc.Rate, p.Rate) WHEN t.ProductId = -5 THEN 0.04 ELSE ISNULL(rd.Rate, 0) END)
			,SUM((-t.MemberWL * ISNULL(lc.Rate, p.Rate) - t.HouseWL) * ISNULL(oa.Rate, 0))
			,SUM(t.AComm * ISNULL(oa.Rate, 0))
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON l.LicenseeId = t.LicenseeId
			LEFT JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND p.Product3rdId = t.ProductId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					AND (p.Bettype = -1 OR p.Bettype = t.BetTypeGroup)
			LEFT JOIN #PartyCharge3rdInfo rd ON rd.LicenseeId = l.LicenseeId AND rd.Product3rdId = t.ProductId AND t.rptDate BETWEEN rd.FromDate AND rd.ToDate
			LEFT JOIN #ExchangeOANDA oa ON t.rptDate = oa.ExchangeDate AND t.CurrencyId = oa.ExchangeId
			LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
		WHERE
		(
			(t.ProductId IN (0, 3, -4) AND p.PartyId IS NOT NULL)
			OR (t.ProductId NOT IN (0, 3, -4))
		)
		GROUP BY t.rptDate, l.PartyId, t.ProductId, t.SporttypeGroup

		DROP TABLE #__tempData
		DROP TABLE #AllLicensees
		DROP TABLE #PartyCharge3rdInfo

		CREATE CLUSTERED INDEX CIX_Product3rdId ON #__tempResult (Product3rdId, rptDate)

		-- PayToSupplier of Metric Gaming, Muay Thai, Bet Builder
		CREATE TABLE #__PayToSupplierSB (GroupId TINYINT, rptDate DATE, PaytoSupplier MONEY) -- GroupId: 1 = Metric Gaming, 2 = Muay Thai, 3 = Bet Builder
		
		;WITH CTE_Metric AS (
			SELECT ci.Rate
				,CASE WHEN @FDate >= ci.FromDate THEN @FDate ELSE ci.FromDate END AS FromDate
				,CASE WHEN @TDate <= ci.ToDate THEN @TDate ELSE ci.ToDate END AS ToDate
				,ci.MinAmount * oa.Rate AS MinAmount
				,ci.MaxAmount * oa.Rate AS MaxAmount
			FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
				INNER JOIN #ExchangeOANDA oa ON ci.BaseCurrencyId = oa.ExchangeId AND oa.ExchangeDate = @TDate
			WHERE ci.ProductId = 0
				AND ci.FromParty = 1
				AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming
				AND (
					ci.FromDate BETWEEN @FDate AND @TDate
					OR ci.ToDate BETWEEN @FDate AND @TDate
					OR ci.FromDate < @FDate
					AND @TDate < ci.ToDate
				)
		)
		INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
		SELECT CASE WHEN r.Product3rdId = -5 THEN 3 ELSE 2 END
			,r.rptDate
			,CASE
				WHEN r.Product3rdId = -5 THEN r.PaytoSupplier
				WHEN (r.PayToSupplier < 0 AND m.MinAmount = 0) OR r.PayToSupplier >= m.MinAmount
					THEN CASE WHEN r.PayToSupplier > m.MaxAmount THEN -(m.MaxAmount - m.MinAmount) ELSE -(r.PayToSupplier - m.MinAmount) END * m.Rate
				ELSE 0
				END
		FROM #__tempResult r
			LEFT JOIN CTE_Metric m ON r.rptDate BETWEEN m.FromDate AND m.ToDate AND r.Product3rdId = -4
		WHERE r.Product3rdId IN (-4, -5)

		-- Muay Thai
		INSERT INTO #__PayToSupplierSB (GroupId, rptDate, PaytoSupplier)
		SELECT 1, b.rptDate
			,SUM((ISNULL(b.AdjustedCustomerWL * 0.03, 0) - ISNULL(b.AdjustedCommShare, 0)) * ISNULL(oa.Rate, 0))
		FROM bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
			INNER JOIN #PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #ExchangeOANDA oa ON oa.ExchangeDate = b.rptDate AND oa.ExchangeId = b.CurrencyId
		WHERE b.rptDate BETWEEN @FDate AND @TDate
			AND b.CurrencyId <> 20
			AND b.StatusId IN (111, 112, 113)
			AND b.customercategory NOT IN (27, 28)
			AND b.SiteId < 1000
			AND b.SportType = 44
			AND p.Product3rdId = 0
		GROUP BY b.rptdate
	END

	-- Licensee Min Fee
	BEGIN
		DECLARE @FirstDate		DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FDate), 0)
		DECLARE @LastDate		DATETIME = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FirstDate))
		DECLARE @DaysInMonth	INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

		DECLARE @MinFee TABLE
		(
			FeeTypeId			TINYINT -- 1: normal, 2: waive
			,GroupMinFeeId		SMALLINT
			,PartyId			INT
			,IsPrimary			BIT
			,Product3rdId		INT
			,CurrencyId         INT
			,FromDate			DATE
			,ToDate				DATE
			,IndividualMinFee   MONEY -- Setting min fee
			,ProrateMinFee		MONEY
			,WaivedFee			MONEY
			,LicenseeFee		MONEY
			,ActualFee			MONEY
		)
		INSERT INTO @MinFee
		(
			FeeTypeId
			,GroupMinFeeId
			,PartyId
			,IsPrimary
			,Product3rdId
			,CurrencyId
			,IndividualMinFee
			,FromDate
			,ToDate
		)
		SELECT
			FeeTypeId
			,-PartyId AS GroupMinFeeId
			,PartyId
			,0 AS IsPrimary
			,ProductId
			,CurrencyId
			,FeeAmount
			,CASE WHEN @FDate > FromDate THEN @FDate ELSE FromDate END AS FromDate
			,CASE WHEN @TDate < ToDate THEN @TDate ELSE ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_MinFee WITH (NOLOCK)
		WHERE FeeTypeId IN (1, 2)
			AND ProductId IN (SELECT p.Product3rdId FROM #PartyChargeInfo p)
			AND FromDate <= @LastDate AND ToDate >= @FirstDate

		;WITH CTE_GroupMinFee AS (
			SELECT TOP (1) WITH TIES a.PartyId, h.GroupMinFeeId, a.IsPrimary
			FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
			WHERE @FDate BETWEEN h.FromDate AND h.ToDate
			ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)
		)
		UPDATE m
		SET m.GroupMinFeeId = g.GroupMinFeeId, m.IsPrimary = g.IsPrimary, m.IndividualMinFee = 0
		FROM @MinFee m
			INNER JOIN CTE_GroupMinFee g ON m.PartyId = g.PartyId

		UPDATE m
		SET m.IndividualMinFee = m.IndividualMinFee * e.Rate
		FROM @MinFee m
			INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = @TDate AND m.CurrencyId = e.ExchangeId
		WHERE m.GroupMinFeeId < 0

		UPDATE t
		SET t.IsApplyMinFee = 0
		FROM #__tempResult t
			INNER JOIN @MinFee m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
				AND t.PartyId = m.PartyId
				AND t.Product3rdId = m.Product3rdId
		WHERE m.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = (
					(
						SELECT TOP 1 m2.IndividualMinFee
						FROM @MinFee m2
						WHERE m2.FeeTypeId = 1
							AND m1.PartyId = m2.PartyId
							AND m1.Product3rdId = m2.Product3rdId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
			,m1.WaivedFee = ISNULL(
					(
						SELECT SUM(r.AmountToCompany)
						FROM #__tempResult r
						WHERE m1.PartyId = r.PartyId
							AND m1.Product3rdId = r.Product3rdId
							AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
					), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = ROUND(
								(m1.IndividualMinFee / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
								- ISNULL((
									SELECT SUM(m2.ProrateMinFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2
										AND m1.PartyId = m2.PartyId
										AND m1.Product3rdId = m2.Product3rdId
									), 0)
								, 2)
			,m1.WaivedFee = ISNULL((
									SELECT SUM(m2.WaivedFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2
										AND m1.PartyId = m2.PartyId
										AND m1.Product3rdId = m2.Product3rdId
									HAVING SUM(m2.WaivedFee) > 0
								), 0)
			,m1.LicenseeFee = ISNULL((
									SELECT SUM(r.AmountToCompany)
									FROM #__tempResult r
									WHERE m1.PartyId = r.PartyId
										AND m1.Product3rdId = r.Product3rdId
										AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
										AND r.IsApplyMinFee = 1
								), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 1

		DELETE @MinFee WHERE FeeTypeId = 2

		UPDATE @MinFee
		SET ActualFee = CASE
							WHEN LicenseeFee < 0 THEN 0
							WHEN LicenseeFee < ProrateMinFee THEN ProrateMinFee
							ELSE LicenseeFee END + WaivedFee

		-- Group min fee
		DECLARE @GroupMinFee TABLE
		(
			GroupMinFeeId	INT
			,Product3rdId	INT
			,GroupMinFee	MONEY DEFAULT(0)
			,HouseWL		MONEY DEFAULT(0)
			,LicenseeFee	MONEY DEFAULT(0)
			,Rebate			MONEY DEFAULT(0)
			,Discount		MONEY DEFAULT(0)
		)
		INSERT INTO @GroupMinFee (GroupMinFeeId, Product3rdId, GroupMinFee)
		SELECT TOP(1) WITH TIES mfd.GroupMinFeeID, ProductId, mfd.MinimumFee * e.Rate AS TotalMinFee
		FROM bodb_Licensee.dbo.LA_GroupMinFeeDetail mfd WITH (NOLOCK)
			INNER JOIN #ExchangeOANDA e ON e.ExchangeId = mfd.CurrencyId AND e.ExchangeDate = @TDate
		WHERE @FDate BETWEEN mfd.FromDate AND mfd.ToDate
		ORDER BY ROW_NUMBER() OVER(PARTITION BY mfd.GroupMinFeeId ORDER BY mfd.ToDate DESC)

		-- HouseWL
		UPDATE g
		SET g.HouseWL = ISNULL(m.HouseWL, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(m.LicenseeFee) AS HouseWL
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.Product3rdId = m.Product3rdId
					AND m.LicenseeFee > 0
			) m
		
		-- Include left over min fee into primary licensees
		UPDATE m
		SET m.ActualFee = CASE WHEN m.LicenseeFee < 0 THEN 0 ELSE m.LicenseeFee END + (g.GroupMinFee - g.HouseWL)
		FROM @MinFee m
			INNER JOIN @GroupMinFee g ON g.GroupMinFeeId = m.GroupMinFeeId AND g.Product3rdId = m.Product3rdId
		WHERE g.HouseWL < g.GroupMinFee
			AND m.IsPrimary = 1

		-- Licensee Fee & Licensee Min Fee
		UPDATE g
		SET g.LicenseeFee = ISNULL(m.ActualFee, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(m.ActualFee) AS ActualFee
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.Product3rdId = m.Product3rdId
			) m

		-- Rebate & Discount
		DECLARE @DiscountGroupHeader TABLE (DiscountGroupId SMALLINT, PartyId INT)
		INSERT INTO @DiscountGroupHeader (DiscountGroupId, PartyId)
		SELECT DiscountGroupId, PartyId
		FROM (
			SELECT dh.DiscountGroupId, da.PartyId
				,ROW_NUMBER() OVER(PARTITION BY da.PartyId ORDER BY dh.ToDate DESC) AS RN
			FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dh WITH (NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
			WHERE dh.FromDate <= @TDate AND dh.ToDate >= @FDate
		) d
		WHERE RN = 1

		DECLARE @DiscountGroup TABLE (PartyId INT)
		INSERT INTO @DiscountGroup (PartyId)
		SELECT dh.PartyId
		FROM @DiscountGroupHeader dh
			INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
	
		;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM @DiscountGroup)
		SELECT @Discount_PartyIds = COALESCE(@Discount_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

		DECLARE @DiscountData TABLE
		(
			PartyId				INT
			,Product3rdId		INT
			,Winloss			MONEY
			,Fee				MONEY
			,NegativeFee		MONEY
			,Minfee				MONEY
			,IsChargedByMinFee	BIT
			,Discount			MONEY
			,DiscountRate		MONEY
			,DiscountRemark		NVARCHAR(MAX)
			,Rebate				MONEY
			,RebateRate			MONEY
			,RebateRemark		VARCHAR(MAX)

		)
		INSERT INTO @DiscountData
		(
			PartyId
			,Product3rdId
			,Winloss
			,Fee
			,NegativeFee
			,Minfee
			,IsChargedByMinFee
			,Discount
			,DiscountRate
			,DiscountRemark
			,Rebate
			,RebateRate
			,RebateRemark
		)
		EXEC bodb_licensee.dbo.LA_AmountToCompanySel
			@FromDate		= @FDate
			,@ToDate		= @TDate
			,@PartyIds		= @Discount_PartyIds
			,@ProductCodes	= 'SB,BA'
			,@BaseCurrency	= 'MYR'
			,@CurrencyId	= 0

		DECLARE @tmpResult TABLE
		(
			PartyId			INT
			,Product3rdId	INT
			,GroupMinFeeId	INT
			,IsPrimaryFee	BIT DEFAULT(0)
			,LicenseeWL		MONEY DEFAULT(0)
			,HouseIncome	MONEY DEFAULT(0)
			,AComm			MONEY DEFAULT(0)
			,LicenseeMinFee MONEY DEFAULT(0)
			,LicenseeFee	MONEY DEFAULT(0)
			,Rebate			MONEY DEFAULT(0)
			,Discount		MONEY DEFAULT(0)
			,ActualWLFee	MONEY DEFAULT(0)
		)
		;WITH CTE_Result AS (
			SELECT PartyId, Product3rdId
				,LicenseeWL		= SUM(CASE WHEN SporttypeGroup = 150 THEN 0 ELSE -MemberWL END)
				,HouseIncome	= SUM(AmountToCompany)
				,AComm			= SUM(AComm)
			FROM #__tempResult
			GROUP BY PartyId, Product3rdId
		)
		INSERT INTO @tmpResult (PartyId, Product3rdId, GroupMinFeeId, LicenseeWL, HouseIncome, AComm)
		SELECT p.PartyId, p.Product3rdId
			,ISNULL(m.GroupMinFeeId, -r.PartyId)
			,ISNULL(r.LicenseeWL, 0)
			,ISNULL(r.HouseIncome, 0)
			,ISNULL(r.AComm, 0)
		FROM #PartyChargeInfo p
			LEFT JOIN CTE_Result r ON p.PartyId = r.PartyId AND p.Product3rdId = r.Product3rdId
			LEFT JOIN @MinFee m ON p.PartyId = m.PartyId AND p.Product3rdId = m.Product3rdId

		DELETE @tmpResult WHERE GroupMinFeeId IS NULL

		UPDATE s
		SET s.IsPrimaryFee		= m.IsPrimary
			,s.HouseIncome		= m.LicenseeFee
			,s.LicenseeMinFee	= CASE
									WHEN m.LicenseeFee = m.ActualFee THEN 0
									ELSE m.ActualFee END
			,s.LicenseeFee		= CASE
									WHEN m.LicenseeFee = m.ActualFee THEN m.ActualFee
									ELSE 0 END
			,s.Rebate			= ISNULL(d.Rebate, 0)
			,s.Discount			= ISNULL(d.Discount, 0)
		FROM @tmpResult s
			INNER JOIN @MinFee m ON m.PartyId = s.PartyId AND m.Product3rdId = s.Product3rdId
			LEFT JOIN @DiscountData d ON d.PartyId = s.PartyId AND d.Product3rdId = s.Product3rdId

		UPDATE g
		SET g.Rebate = ISNULL(d.Rebate, 0), g.Discount = ISNULL(d.Discount, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(s.Rebate) AS Rebate, SUM(s.Discount) AS Discount
				FROM @tmpResult s
				WHERE s.GroupMinFeeId = g.GroupMinFeeId AND s.Product3rdId = g.Product3rdId
			) d

		UPDATE s
		SET s.LicenseeFee = CASE
								WHEN s.Discount = 0 THEN 0
								ELSE s.LicenseeFee + (g.GroupMinFee - (g.LicenseeFee - g.Discount)) END
			,s.LicenseeMinFee = CASE
								WHEN s.Discount <> 0 THEN 0
								ELSE s.LicenseeMinFee + (g.GroupMinFee - (g.LicenseeFee - g.Discount)) END
		FROM @tmpResult s
			INNER JOIN @GroupMinFee g ON s.GroupMinFeeId = g.GroupMinFeeId
		WHERE s.GroupMinFeeId > 0
			AND (g.LicenseeFee - g.Discount) < g.GroupMinFee
			AND s.IsPrimaryFee = 1

		UPDATE r
		SET r.HouseIncome = CASE WHEN r.HouseIncome > 0 OR r.Product3rdId = 3 THEN r.HouseIncome ELSE 0 END
			,r.LicenseeFee = CASE
						WHEN r.Product3rdId = 42 THEN CASE WHEN r.LicenseeWL > 0 THEN r.LicenseeFee ELSE 0 END
						WHEN r.LicenseeFee > 0 THEN r.LicenseeFee ELSE 0 END
		FROM @tmpResult r
		WHERE
			r.Product3rdId <> 0
			OR r.PartyId NOT IN (
				SELECT p.PartyId FROM bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)
				WHERE p.PartyName IN ('9wickets', '9Wsports')
			)
	END

	DROP TABLE #PartyChargeInfo
	DROP TABLE #ExchangeOANDA

	-- Calculate result
	DECLARE @Products TABLE (OrderId INT, SporttypeGroup INT, ProductCode VARCHAR(500))
	INSERT INTO @Products (OrderId, SporttypeGroup, ProductCode)
	SELECT 1, 1, 'Soccer' AS ProductCode
	UNION ALL SELECT 2, -3, 'SabaSoccer'
	UNION ALL SELECT 3, 2, 'Basketball'
	UNION ALL SELECT 4, -4, 'SabaBasketball'
	UNION ALL SELECT 5, 5, 'Tennis'
	UNION ALL SELECT 6, 43, 'E-Sports'
	UNION ALL SELECT 7, 99, 'OS'
	UNION ALL SELECT 8, -5, 'SabaCricket'
	UNION ALL SELECT 9, -2, 'Parlay'

	DECLARE @BAComm MONEY, @BAWinloss MONEY
    SELECT  @BAComm = -SUM(AComm), @BAWinloss = SUM(HouseIncome) FROM @tmpResult WHERE Product3rdId = 3
	SELECT  @BAComm = ISNULL(@BAComm, 0), @BAWinloss = ISNULL(@BAWinloss, 0)

	UPDATE #__tempResult SET Product3rdId = 0 WHERE Product3rdId = 3

	CREATE TABLE #Result
	(
		Id INT IDENTITY(1, 1)
		,OrderId INT
		,rptDate VARCHAR(10)
		,ProductCode VARCHAR(50)
		,HouseIncome MONEY
		,MinFee MONEY
		,Discount MONEY
		,BAComm MONEY
		,PaytoMuayThai MONEY
		,PaytoMetricGaming MONEY
		,PayToBetBuilder MONEY
	)
	INSERT INTO #Result
	(
		OrderId
		,rptDate
		,ProductCode
		,HouseIncome
		,MinFee
		,Discount
		,BAComm
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
	)
	SELECT p.OrderId, 'FullRange', p.ProductCode
		,HouseIncome = SUM(CASE WHEN p.SporttypeGroup = 1 THEN ISNULL(r.LicenseeFee, 0) ELSE 0 END)
		,MinFee = SUM(CASE WHEN p.SporttypeGroup = 1 THEN ISNULL(r.LicenseeMinFee, 0) ELSE 0 END)
		,Discount = 0
		,BAComm = 0
		,PaytoMuayThai = 0
		,PaytoMetricGaming = 0
		,PayToBetBuilder = 0
	FROM @Products p
		LEFT JOIN @tmpResult r ON r.Product3rdId = 0
	GROUP BY p.OrderId, p.ProductCode
	
	UPDATE #Result SET HouseIncome = HouseIncome + @BAWinloss, BAComm = @BAComm WHERE ProductCode = 'Soccer'

	-- Detail daily
	;WITH CTE_rptDate AS
	(
		SELECT CONVERT(DATETIME, @FDate) AS rptDate
		UNION ALL
		SELECT DATEADD(DAY, 1, rptDate)
		FROM CTE_rptDate
		WHERE rptDate < @TDate
	)
	INSERT INTO #Result
	(
		OrderId
		,rptDate
		,ProductCode
		,HouseIncome
		,MinFee
		,Discount
		,BAComm
		,PaytoMuayThai
		,PaytoMetricGaming
		,PayToBetBuilder
	)
	SELECT p.OrderId
		,CONVERT(VARCHAR(2), r.rptDate, 106) AS rptDate
		,p.ProductCode
		,SUM(ISNULL(t.AmountToCompany, 0))
		,0 AS MinFee
		,0
		,SUM(ISNULL(-t.AComm, 0))
		,0
		,0
		,0
	FROM CTE_rptDate r
		CROSS JOIN @Products p
		LEFT JOIN #__tempResult t ON r.rptDate = t.rptDate AND t.SporttypeGroup = p.SporttypeGroup
	GROUP BY p.OrderId, CONVERT(VARCHAR(2), r.rptDate, 106), p.ProductCode
	ORDER BY OrderId, rptDate
	OPTION (MAXRECURSION 0)

	;WITH CTE_PayToSB AS (
		SELECT
			CONVERT(VARCHAR(2), rptDate, 106) AS rptDate
			,CASE WHEN GroupId = 1 THEN 'OS' ELSE 'Soccer' END AS ProductCode
			,SUM(CASE WHEN GroupId = 1 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PaytoMuayThai
			,SUM(CASE WHEN GroupId = 2 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PaytoMetricGaming
			,SUM(CASE WHEN GroupId = 3 THEN ISNULL(PaytoSupplier, 0) ELSE 0 END) AS PayToBetBuilder
		FROM #__PayToSupplierSB
		GROUP BY
			CONVERT(VARCHAR(2), rptDate, 106)
			,CASE WHEN GroupId = 1 THEN 'OS' ELSE 'Soccer' END
	)
	UPDATE r
	SET r.PaytoMuayThai = p.PaytoMuayThai
		,r.PaytoMetricGaming = p.PaytoMetricGaming
		,r.PayToBetBuilder = CASE WHEN r.rptDate = 'FullRange' AND p.PayToBetBuilder > 0 THEN 0 ELSE p.PayToBetBuilder END
	FROM #Result r
		INNER JOIN (
			SELECT CONVERT(VARCHAR(10), 'FullRange') AS rptDate
				,ProductCode
				,SUM(PaytoMuayThai) AS PaytoMuayThai
				,SUM(PaytoMetricGaming) AS PaytoMetricGaming
				,SUM(PayToBetBuilder) AS PayToBetBuilder
			FROM CTE_PayToSB
			GROUP BY ProductCode
			
			UNION ALL
			SELECT rptDate, ProductCode, PaytoMuayThai, PaytoMetricGaming, PayToBetBuilder FROM CTE_PayToSB
		) p ON r.rptDate = p.rptDate AND r.ProductCode = p.ProductCode
	WHERE r.ProductCode IN ('OS', 'Soccer')

	DROP TABLE #__PayToSupplierSB
	DROP TABLE #__tempResult

	-- Update result
	UPDATE #Result
	SET PaytoMuayThai		= CASE WHEN ProductCode <> 'OS' THEN NULL ELSE PaytoMuayThai END
		,PaytoMetricGaming	= CASE WHEN ProductCode <> 'Soccer' THEN NULL ELSE PaytoMetricGaming END
		,PayToBetBuilder	= CASE WHEN ProductCode <> 'Soccer' THEN NULL ELSE PayToBetBuilder END

	DECLARE @DateList VARCHAR(2000), @ReturnColumns VARCHAR(2000)
	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + rptDate + ']' FROM #Result WHERE ProductCode = 'Soccer' ORDER BY Id

	SELECT @ReturnColumns = 'ProductCode,[Order],Figure,' + @DateList

    /* End region*/
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(MAX)
	SELECT  @SQL =	'SELECT ' + @ReturnColumns + CHAR(13) +
					'FROM	(
								SELECT OrderId, ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value
								FROM #Result
									CROSS APPLY (
												  SELECT 1, ''House Income''			, HouseIncome		WHERE HouseIncome IS NOT NULL
										UNION ALL SELECT 2, ''Licensing Minimum Fee''	, MinFee			WHERE MinFee IS NOT NULL
										UNION ALL SELECT 4, ''Rebate & Discount''		, Discount			WHERE Discount IS NOT NULL
										UNION ALL SELECT 5, ''BA Commission''			, BAComm			WHERE BAComm IS NOT NULL
										UNION ALL SELECT 6, ''Pay to Muay Thai''		, PaytoMuayThai		WHERE PaytoMuayThai IS NOT NULL
										UNION ALL SELECT 7, ''Pay to Metric Gaming''	, PaytoMetricGaming WHERE PaytoMetricGaming IS NOT NULL
										UNION ALL SELECT 8, ''Pay to Bet Genius''		, PayToBetBuilder	WHERE PayToBetBuilder IS NOT NULL
									) c ([Order], Figure, value)
							) a
							PIVOT
							(
								MAX(value)
								FOR [RptDate] IN (' + @DateList + ')
							) p
							ORDER BY [Order], OrderId'
	EXEC(@SQL)

	DROP TABLE #Result
END
GO
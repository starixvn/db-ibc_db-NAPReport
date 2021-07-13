/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Reconciliation]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*
	Created: 20210129@Percy
	DB: DBWH-bodb_dwrs
	Task: Auto mail - Licensee Sportsbook Data
	
	Revisions:
		- 20210129@Percy: Initiliaze SP [RedmineID: #148805]
		- 20210708@Danny: Handle JV parties (#158191)
*/

BEGIN
	SET NOCOUNT ON

	IF @FromDate > @ToDate OR DATEDIFF(MONTH, @FromDate, @ToDate) <> 0
		RETURN

	DECLARE
		@FDate DATE, @TDate DATE, @LastDay DATE
		,@FromExDate SMALLDATETIME, @ToExDate SMALLDATETIME, @ExDate SMALLDATETIME
		,@f_date VARCHAR(10), @t_date VARCHAR(10), @SQL VARCHAR(MAX) -- use for dynamic query
		,@FromDateByBatch DATE, @ToDateByBatch DATE

	SELECT
		@FDate = @FromDate
		,@TDate = @ToDate
		,@FromExDate = @FromDate, @ToExDate = @ToDate
		,@f_date = CONVERT(VARCHAR(10), @FromDate, 120)
		,@t_date = CONVERT(VARCHAR(10), @ToDate, 120)
		
	DECLARE @PartyIds VARCHAR(MAX), @Discount_PartyIds VARCHAR(MAX)

	-- Get Exchange
	BEGIN
		-- Daily System Rate
		CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
		INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, Currency, Rate
		FROM bodb_Account.dbo.tbl_Currency_Daily WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN @FromExDate AND @ToExDate

		-- Oanda Rate
		DECLARE @ExchangeOANDA TABLE (ExchangeId INT, Rate FLOAT, CNY FLOAT, USD FLOAT)
		SELECT  @ExDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
		SELECT  @LastDay = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
		
		IF @ExDate > @LastDay
			SELECT @ExDate = @LastDay

		INSERT INTO @ExchangeOANDA (ExchangeId, Rate, CNY, USD)
		SELECT ExchangeId, MYR, CNY, USD FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK) WHERE ExchangeDate = @ExDate
	END

	-- Get Deposit Licensees
	BEGIN
		-- All Deposit Licensees
		CREATE TABLE #AllLicensees (LicenseeId INT, PartyId INT, ParentId INT, SiteId_DW INT)
		INSERT INTO #AllLicensees (LicenseeId, PartyId, ParentId)
		SELECT LicenseeId, PartyId, ParentId
		FROM OPENQUERY (DBLIC, 'SELECT OldRefId AS LicenseeId, FromParty AS PartyId, ToParty AS ParentId
								FROM (
									SELECT p.OldRefId, ci.FromParty, ci.ToParty, ROW_NUMBER() OVER(PARTITION BY ci.FromParty ORDER BY ci.FromDate DESC) AS RowNum
									FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
										INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
										INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
										INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
									WHERE ci.ChargeType = 1 AND p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98)
								) r
								WHERE RowNum = 1')

		-- Deposit Licensees have setting
		CREATE TABLE #Licensees (LicenseeId INT, PartyId INT, ParentId INT)
		SELECT @SQL = ' SELECT LicenseeId, PartyId, ParentId
						FROM OPENQUERY (DBLIC, '' 
							SELECT DISTINCT p.OldRefId AS LicenseeId, ci.FromParty AS PartyId, ci.ToParty AS ParentId
							FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
								INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
								INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
								INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
							WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND ci.ToParty IN (1, 9, 11, 98)
								AND ci.ProductId = 0
								AND ci.FromDate <= ''''' + @t_date + ''''' AND ci.ToDate >= ''''' + @f_date + ''''''')'
		INSERT INTO #Licensees (LicenseeId, PartyId, ParentId)
		EXEC (@SQL)
	END

	-- Get charge rate
	BEGIN
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM #Licensees

		CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, FromDate DATE, ToDate DATE, Rate FLOAT, Bettype INT, ChargeType INT)
		SELECT @SQL = '	SELECT ChargeId, PartyId, FromDate, ToDate, Rate, Bettype, ChargeType
						FROM OPENQUERY (DBLIC, ''
							SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate, ISNULL(sbr.Bettype, ci.Bettype) AS Bettype, ci.ChargeType
							FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
								LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
							WHERE ci.DI_Rate > 0
								AND ci.ChargeType = 1
								AND ci.ProductId = 0'')'
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, FromDate, ToDate, Rate, Bettype, ChargeType)
		EXEC (@SQL)

		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)
		SELECT @SQL = '	SELECT ChargeId, CurrencyId, Rate
						FROM OPENQUERY(DBLIC, ''SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
												FROM bodb_licensee.dbo.LA_f_ChargeInfo (''''' + @PartyIds + ''''', ''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''', 1) ci
													INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
												WHERE ci.ChargeType = 1 AND ci.DI_Rate > 0'')'
		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)
		EXEC (@SQL)

		DECLARE @PartyCharge3rd TABLE (PartyId INT, ChargeType INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		SELECT @SQL = '	SELECT PartyId, ChargeType, FromDate, ToDate, Rate
						FROM OPENQUERY (DBLIC, ''SELECT DISTINCT PartyId, ChargeType, FromDate, ToDate, CASE WHEN ProductId = 10 THEN 0 ELSE DI_Rate END AS Rate
												 FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd (''''' + @f_date + ''''', ''''' + @t_date + ''''', ''''SB'''', ''''OA'''')
												 WHERE DI_Rate > 0
													AND (
														ChargeType = 1
														OR (ChargeType IN (9, 10, 12) AND ProductId = 11) -- GD
													)'')'
		INSERT INTO @PartyCharge3rd (PartyId, ChargeType, FromDate, ToDate, Rate)
		EXEC (@SQL)

		CREATE TABLE #PartyCharge3rdInfo (ChargeType INT, PartyId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #PartyChargeInfo p ON p.PartyId = p3.PartyId

		INSERT INTO #PartyCharge3rdInfo (ChargeType, PartyId, FromDate, ToDate, Rate)
		SELECT p3.ChargeType, p.PartyId, p3.FromDate, p3.ToDate, p3.Rate
		FROM @PartyCharge3rd p3
			INNER JOIN #AllLicensees l ON p3.PartyId = l.ParentId
			INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId
		WHERE NOT EXISTS (SELECT 1 FROM #PartyCharge3rdInfo rd WHERE p.PartyId = rd.PartyId)
	END

	-- Get mapping site
	BEGIN
		CREATE TABLE #__tmpSite (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO #__tmpSite (LicenseeId, SiteName)
		SELECT LicenseeId, RTRIM(LTRIM(LicenseeName)) FROM DBLIC.bodb_licensee.dbo.Licensees WITH (NOLOCK) WHERE IsDeposit = 1

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM #__tmpSite s
			INNER JOIN bodb_Account.dbo.tbl_Site t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))

		UPDATE l
		SET l.SiteId_DW = s.SiteId_DW
		FROM #AllLicensees l
			INNER JOIN #__tmpSite s ON l.LicenseeId = s.LicenseeId
	END

	-- Get data
	BEGIN
		CREATE TABLE #__tempData (rptDate DATE, SiteId_DW INT, CurrencyId INT, MemberWL MONEY, AgentWL MONEY, AgentComm MONEY, OddsSpreadAdj MONEY)
		CREATE CLUSTERED INDEX CIX_tempData ON #__tempData (SiteId_DW, rptDate)

		SELECT @FromDateByBatch = @FDate

		WHILE @FromDateByBatch <= @TDate
		BEGIN
			SELECT @ToDateByBatch = DATEADD(DAY, 15, @FromDateByBatch)

			IF @ToDateByBatch > @TDate
				SET @ToDateByBatch = @TDate
		
			INSERT INTO #__tempData (rptDate, SiteId_DW, CurrencyId, MemberWL, AgentWL, AgentComm, OddsSpreadAdj)
			SELECT rptDate, SiteId, CurrencyId
				,SUM(MemberWinloss) AS MemberWL
				,SUM(AgentWinloss)	AS AgentWL
				,SUM(AgentComm)		AS AgentComm
				,SUM(CASE WHEN bettype = 999 THEN AgentWinloss ELSE 0 END) AS OddsSpreadAdj
			FROM bodb_Account.dbo.FactLADailyWinloss WITH (NOLOCK)
			WHERE rptDate BETWEEN @FromDateByBatch AND @ToDateByBatch
				AND SiteId IN (SELECT SiteId_DW FROM #__tmpSite)
				AND ProductId = 10001 -- SB only (not include BA)
				AND Bettype NOT IN (901, 902, 903, 904)
				AND CurrencyId <> 20
				AND TicketStatus NOT IN (-1, 18, 9, 10, 14)
			GROUP BY rptDate, SiteId, CurrencyId
			OPTION (RECOMPILE)

			SELECT @FromDateByBatch = DATEADD(DAY, 1, @ToDateByBatch)
		END

		-- Process data
		CREATE TABLE #__tempResult (
			rptDate DATETIME
			,PartyId INT
			-- SystemRate
			,MemberWL_e MONEY
			,AgentWL_e MONEY
			,AgentComm_e MONEY
			,HouseWL_e MONEY
			,HouseIncome_e MONEY
			-- Oanda Rate
			,MemberWL_oa MONEY
			,AgentWL_oa MONEY
			,AgentComm_oa MONEY
			,HouseWL_oa MONEY
			,HouseIncome_oa MONEY

			, IsApplyMinFee BIT DEFAULT (1)
		)
		CREATE CLUSTERED INDEX CIX_tempResult ON #__tempResult (PartyId, rptDate)

		INSERT INTO #__tempResult (rptDate, PartyId, MemberWL_e, AgentWL_e, AgentComm_e, HouseWL_e, HouseIncome_e, MemberWL_oa, AgentWL_oa, AgentComm_oa, HouseWL_oa, HouseIncome_oa)
		SELECT t.rptDate, l.PartyId
			,MemberWL_e		= SUM(t.MemberWL * e.Rate)
			,AgentWL_e		= SUM(t.AgentWL * e.Rate)
			,AgentComm_e	= SUM(t.AgentComm * e.Rate)
			,HouseWL_e		= SUM(-(t.MemberWL + t.AgentWL + t.AgentComm) * e.Rate)
			,HouseIncome_e	= SUM(((- t.MemberWL - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - t.OddsSpreadAdj) * e.Rate)
			,MemberWL_oa	= SUM(t.MemberWL * oa.Rate)
			,AgentWL_oa		= SUM(t.AgentWL * oa.Rate)
			,AgentComm_oa	= SUM(t.AgentComm * oa.Rate)
			,HouseWL_oa		= SUM(-(t.MemberWL + t.AgentWL + t.AgentComm) * oa.Rate)
			,HouseIncome_oa = SUM(((- t.MemberWL - t.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - t.OddsSpreadAdj) * oa.Rate)
		FROM #__tempData t
			INNER JOIN #AllLicensees l ON t.SiteId_DW = l.SiteId_DW
			INNER JOIN #PartyChargeInfo p ON p.PartyId = l.PartyId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId AND t.CurrencyId = lc.CurrencyId
			INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
			INNER JOIN @ExchangeOANDA oa ON t.CurrencyId = oa.ExchangeId
		GROUP BY t.rptDate, l.PartyId
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
			,CurrencyId         INT
			,FromDate			DATE
			,ToDate				DATE
			
			,IndividualMinFee_e		MONEY -- Setting min fee
			,ProrateMinFee_e		MONEY
			,WaivedFee_e			MONEY
			,LicenseeFee_e			MONEY
			,ActualFee_e			MONEY

			,IndividualMinFee_oa	MONEY -- Setting min fee
			,ProrateMinFee_oa		MONEY
			,WaivedFee_oa			MONEY
			,LicenseeFee_oa			MONEY
			,ActualFee_oa			MONEY
		)
		INSERT INTO @MinFee
		(
			FeeTypeId
			,GroupMinFeeId
			,PartyId
			,IsPrimary
			,CurrencyId
			,IndividualMinFee_e
			,IndividualMinFee_oa
			,FromDate
			,ToDate
		)
		SELECT
			FeeTypeId
			,-PartyId AS GroupMinFeeId
			,PartyId
			,0 AS IsPrimary
			,CurrencyId
			,FeeAmount
			,FeeAmount
			,CASE WHEN @FDate > FromDate THEN @FDate ELSE FromDate END AS FromDate
			,CASE WHEN @TDate < ToDate THEN @TDate ELSE ToDate END AS ToDate
		FROM DBLIC.bodb_licensee.dbo.LA_MinFee WITH (NOLOCK)
		WHERE FeeTypeId IN (1, 2)
			AND FromDate <= @LastDate AND ToDate >= @FirstDate
			AND ProductId = 0

		DECLARE @GroupMinFeeSetting TABLE (PartyId INT, GroupMinFeeId SMALLINT, IsPrimary BIT)
		SELECT @SQL = '	SELECT PartyId, GroupMinFeeId, IsPrimary
						FROM OPENQUERY (DBLIC, ''	SELECT TOP (1) WITH TIES a.PartyId, h.GroupMinFeeId, a.IsPrimary
													FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
														INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
													WHERE ''''' + @f_date + ''''' BETWEEN h.FromDate AND h.ToDate
													ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)'')'
		INSERT INTO @GroupMinFeeSetting (PartyId, GroupMinFeeId, IsPrimary)
		EXEC (@SQL)

		UPDATE m
		SET m.GroupMinFeeId = g.GroupMinFeeId, m.IsPrimary = g.IsPrimary, m.IndividualMinFee_e = 0, m.IndividualMinFee_oa = 0
		FROM @MinFee m
			INNER JOIN @GroupMinFeeSetting g ON m.PartyId = g.PartyId

		UPDATE m
		SET m.IndividualMinFee_e = m.IndividualMinFee_e * e.Rate, m.IndividualMinFee_oa = m.IndividualMinFee_oa * oa.Rate
		FROM @MinFee m
			INNER JOIN #Exchange e ON m.CurrencyId = e.ExchangeId AND e.ExchangeDate = @TDate
			INNER JOIN @ExchangeOANDA oa ON m.CurrencyId = oa.ExchangeId
		WHERE m.GroupMinFeeId < 0

		UPDATE t
		SET t.IsApplyMinFee = 0
		FROM #__tempResult t
			INNER JOIN @MinFee m ON t.PartyId = m.PartyId AND t.rptDate BETWEEN m.FromDate AND m.ToDate
		WHERE m.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee_e = (
					(
						SELECT TOP 1 m2.IndividualMinFee_e
						FROM @MinFee m2
						WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
			,m1.WaivedFee_e = ISNULL(
					(
						SELECT SUM(r.HouseIncome_e)
						FROM #__tempResult r
						WHERE m1.PartyId = r.PartyId AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
					), 0)
			,m1.ProrateMinFee_oa = (
					(
						SELECT TOP 1 m2.IndividualMinFee_oa
						FROM @MinFee m2
						WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
			,m1.WaivedFee_oa = ISNULL(
					(
						SELECT SUM(r.HouseIncome_oa)
						FROM #__tempResult r
						WHERE m1.PartyId = r.PartyId AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
					), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee_e = ROUND(
								(m1.IndividualMinFee_e / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
								- ISNULL((
									SELECT SUM(m2.ProrateMinFee_e)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
									), 0)
								, 2)
			,m1.WaivedFee_e = ISNULL((
									SELECT SUM(m2.WaivedFee_e)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
									HAVING SUM(m2.WaivedFee_e) > 0
								), 0)
			,m1.LicenseeFee_e = ISNULL((
									SELECT SUM(r.HouseIncome_e)
									FROM #__tempResult r
									WHERE m1.PartyId = r.PartyId AND r.IsApplyMinFee = 1 AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
								), 0)
			,m1.ProrateMinFee_oa = ROUND(
								(m1.IndividualMinFee_oa / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
								- ISNULL((
									SELECT SUM(m2.ProrateMinFee_oa)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
									), 0)
								, 2)
			,m1.WaivedFee_oa = ISNULL((
									SELECT SUM(m2.WaivedFee_oa)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
									HAVING SUM(m2.WaivedFee_e) > 0
								), 0)
			,m1.LicenseeFee_oa = ISNULL((
									SELECT SUM(r.HouseIncome_oa)
									FROM #__tempResult r
									WHERE m1.PartyId = r.PartyId AND r.IsApplyMinFee = 1 AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
								), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 1

		DELETE @MinFee WHERE FeeTypeId = 2

		UPDATE @MinFee
		SET ActualFee_e = CASE
							WHEN LicenseeFee_e < ProrateMinFee_e THEN ProrateMinFee_e
							ELSE LicenseeFee_e END + WaivedFee_e
			,ActualFee_oa = CASE
							WHEN LicenseeFee_oa < ProrateMinFee_oa THEN ProrateMinFee_oa
							ELSE LicenseeFee_oa END + WaivedFee_oa

		-- Group min fee
		DECLARE @GroupMinFee TABLE
		(
			GroupMinFeeId	INT
			,CurrencyId		INT
			,Rebate			MONEY DEFAULT(0)
			,Discount		MONEY DEFAULT(0)
			
			,GroupMinFee_e	MONEY DEFAULT(0)
			,HouseWL_e		MONEY DEFAULT(0)
			,LicenseeFee_e	MONEY DEFAULT(0)

			,GroupMinFee_oa	MONEY DEFAULT(0)
			,HouseWL_oa		MONEY DEFAULT(0)
			,LicenseeFee_oa	MONEY DEFAULT(0)
		)
		INSERT INTO @GroupMinFee (GroupMinFeeId, CurrencyId, GroupMinFee_e, GroupMinFee_oa)
		SELECT TOP(1) WITH TIES GroupMinFeeID, CurrencyId, MinimumFee, MinimumFee
		FROM DBLIC.bodb_Licensee.dbo.LA_GroupMinFeeDetail WITH (NOLOCK)
		WHERE @FDate BETWEEN FromDate AND ToDate
			AND ProductId = 0
		ORDER BY ROW_NUMBER() OVER(PARTITION BY GroupMinFeeId ORDER BY ToDate DESC)

		UPDATE g
		SET g.GroupMinFee_e = g.GroupMinFee_e * e.Rate, g.GroupMinFee_oa = g.GroupMinFee_oa * oa.Rate
		FROM @GroupMinFee g
			INNER JOIN #Exchange e ON e.ExchangeId = g.CurrencyId AND e.ExchangeDate = @TDate
			INNER JOIN @ExchangeOANDA oa ON oa.ExchangeId = g.CurrencyId

		-- HouseWL
		UPDATE g
		SET g.HouseWL_e = ISNULL(m.HouseWL_e, 0), g.HouseWL_oa = ISNULL(m.HouseWL_oa, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(CASE WHEN m.LicenseeFee_e > 0 THEN m.LicenseeFee_e ELSE 0 END + m.WaivedFee_e) AS HouseWL_e
					,SUM(CASE WHEN m.LicenseeFee_oa > 0 THEN m.LicenseeFee_oa ELSE 0 END + m.WaivedFee_oa) AS HouseWL_oa
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId 
			) m
		
		-- Include left over min fee into primary licensees
		UPDATE m
		SET m.ActualFee_e = CASE
								WHEN g.HouseWL_e >= g.GroupMinFee_e THEN ActualFee_e
								WHEN m.LicenseeFee_e < 0 THEN g.GroupMinFee_e - g.HouseWL_e
								ELSE m.LicenseeFee_e + g.GroupMinFee_e - g.HouseWL_e END
			,m.ActualFee_oa = CASE
								WHEN g.HouseWL_oa >= g.GroupMinFee_oa THEN ActualFee_oa
								WHEN m.LicenseeFee_oa < 0 THEN g.GroupMinFee_oa - g.HouseWL_oa
								ELSE m.LicenseeFee_oa + g.GroupMinFee_oa - g.HouseWL_oa END
		FROM @MinFee m
			INNER JOIN @GroupMinFee g ON g.GroupMinFeeId = m.GroupMinFeeId
		WHERE m.IsPrimary = 1

		-- Licensee Fee & Licensee Min Fee
		UPDATE g
		SET g.LicenseeFee_e = ISNULL(m.ActualFee_e, 0), g.LicenseeFee_oa = ISNULL(m.ActualFee_oa, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(m.ActualFee_e) AS ActualFee_e, SUM(m.ActualFee_oa) AS ActualFee_oa
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId
			) m

		-- Rebate & Discount
		DECLARE @DiscountGroup TABLE (PartyId INT)
		SELECT @SQL = 'SELECT PartyId
						FROM OPENQUERY (DBLIC, ''	SELECT TOP(1) WITH TIES da.PartyId
													FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dh WITH (NOLOCK)
														INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
														INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
													WHERE dh.FromDate <= ''''' + @t_date + ''''' AND dh.ToDate >= ''''' + @f_date + '''''
														AND dp.ProductId = 0
													ORDER BY ROW_NUMBER() OVER(PARTITION BY da.PartyId ORDER BY dh.ToDate DESC)'')'
		INSERT INTO @DiscountGroup (PartyId)
		EXEC (@SQL)

		;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM @DiscountGroup)
		SELECT @Discount_PartyIds = COALESCE(@Discount_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

		DECLARE @DiscountData TABLE
		(
			PartyId				INT
			,ProductId			INT
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
			,ProductId
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
		EXEC DBLIC.bodb_licensee.dbo.LA_AmountToCompanySel
			@FromDate		= @FDate
			,@ToDate		= @TDate
			,@PartyIds		= @Discount_PartyIds
			,@ProductCodes	= 'SB'
			,@BaseCurrency	= 'MYR'
			,@CurrencyId	= 0

		DECLARE @tmpResult TABLE
		(
			PartyId			INT
			,GroupMinFeeId	INT
			,IsPrimaryFee	BIT DEFAULT(0)
			,Rebate				MONEY DEFAULT(0)
			,RebateRate			MONEY DEFAULT(0)
			,Discount			MONEY DEFAULT(0)
			,DiscountRate		MONEY DEFAULT(0)
			-- System Rate
			,LicenseeWL_e		MONEY DEFAULT(0)
			,HouseWL_e			MONEY DEFAULT(0)
			,HouseIncome_e		MONEY DEFAULT(0)
			,LicenseeMinFee_e	MONEY DEFAULT(0)
			,LicenseeFee_e		MONEY DEFAULT(0)
			,ActualWLFee_e		MONEY DEFAULT(0)
			-- Oanda Rate
			,LicenseeWL_oa		MONEY DEFAULT(0)
			,HouseWL_oa			MONEY DEFAULT(0)
			,HouseIncome_oa		MONEY DEFAULT(0)
			,LicenseeMinFee_oa	MONEY DEFAULT(0)
			,LicenseeFee_oa		MONEY DEFAULT(0)
			,ActualWLFee_oa		MONEY DEFAULT(0)
		)
		;WITH CTE_tempResult AS (
			SELECT PartyId
				,LicenseeWL_e	= SUM(-MemberWL_e)
				,HouseWL_e		= SUM(HouseWL_e)
				,HouseIncome_e	= SUM(HouseIncome_e)
				,LicenseeWL_oa	= SUM(-MemberWL_oa)
				,HouseWL_oa		= SUM(HouseWL_oa)
				,HouseIncome_oa	= SUM(HouseIncome_oa)
			FROM #__tempResult
			GROUP BY PartyId
		), CTE_Result AS (
			SELECT
				PartyId			= ISNULL(t.PartyId, m.PartyId)
				,GroupMinFeeId	= ISNULL(m.GroupMinFeeId, -t.PartyId)
				,LicenseeWL_e	= ISNULL(t.LicenseeWL_e, 0)
				,HouseWL_e		= ISNULL(t.HouseWL_e, 0)
				,HouseIncome_e	= ISNULL(t.HouseIncome_e, 0)
				,LicenseeWL_oa	= ISNULL(t.LicenseeWL_oa, 0)
				,HouseWL_oa		= ISNULL(t.HouseWL_oa, 0)
				,HouseIncome_oa = ISNULL(t.HouseIncome_oa, 0)
			FROM CTE_tempResult t
				FULL OUTER JOIN @MinFee m ON t.PartyId = m.PartyId
		)
		INSERT INTO @tmpResult (PartyId, GroupMinFeeId, LicenseeWL_e, HouseWL_e, HouseIncome_e, LicenseeWL_oa, HouseWL_oa, HouseIncome_oa)
		SELECT r.PartyId, r.GroupMinFeeId, r.LicenseeWL_e, r.HouseWL_e, r.HouseIncome_e, r.LicenseeWL_oa, r.HouseWL_oa, r.HouseIncome_oa
		FROM CTE_Result r
			INNER JOIN (SELECT DISTINCT PartyId FROM #PartyChargeInfo) p ON p.PartyId = r.PartyId

		DELETE @tmpResult WHERE GroupMinFeeId IS NULL

		UPDATE s
		SET s.IsPrimaryFee		= m.IsPrimary
			,s.Rebate			= ISNULL(d.Rebate, 0)
			,s.RebateRate		= ISNULL(d.RebateRate, 0)
			,s.Discount			= ISNULL(d.Discount, 0)
			,s.DiscountRate		= ISNULL(d.DiscountRate, 0)
			,s.LicenseeMinFee_e		= CASE
										WHEN m.PartyId IS NULL THEN 0
										WHEN m.LicenseeFee_e + m.WaivedFee_e = m.ActualFee_e THEN 0
										ELSE m.ActualFee_e END
			,s.LicenseeFee_e		= CASE
										WHEN m.PartyId IS NULL THEN s.HouseIncome_e
										WHEN m.LicenseeFee_e + m.WaivedFee_e = m.ActualFee_e THEN m.ActualFee_e
										ELSE 0 END
			,s.LicenseeMinFee_oa	= CASE
										WHEN m.PartyId IS NULL THEN 0
										WHEN m.LicenseeFee_oa + m.WaivedFee_oa = m.ActualFee_oa THEN 0
										ELSE m.ActualFee_oa END
			,s.LicenseeFee_oa		= CASE
										WHEN m.PartyId IS NULL THEN s.HouseIncome_oa
										WHEN m.LicenseeFee_oa + m.WaivedFee_oa = m.ActualFee_oa THEN m.ActualFee_oa
										ELSE 0 END
		FROM @tmpResult s
			LEFT JOIN @MinFee m ON m.PartyId = s.PartyId
			LEFT JOIN @DiscountData d ON d.PartyId = s.PartyId

		UPDATE g
		SET g.Rebate = ISNULL(d.Rebate, 0), g.Discount = ISNULL(d.Discount, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(s.Rebate) AS Rebate, SUM(s.Discount) AS Discount
				FROM @tmpResult s
				WHERE s.GroupMinFeeId = g.GroupMinFeeId
			) d

		UPDATE s
		SET s.LicenseeFee_e		= CASE
									WHEN s.Discount = 0 THEN 0
									ELSE s.LicenseeFee_e + (g.GroupMinFee_e - (g.LicenseeFee_e - g.Discount)) END
			,s.LicenseeMinFee_e = CASE
									WHEN s.Discount <> 0 THEN 0
									ELSE s.LicenseeMinFee_e + (g.GroupMinFee_e - (g.LicenseeFee_e - g.Discount)) END
		FROM @tmpResult s
			INNER JOIN @GroupMinFee g ON s.GroupMinFeeId = g.GroupMinFeeId
		WHERE s.GroupMinFeeId > 0
			AND (g.LicenseeFee_e - g.Discount) < g.GroupMinFee_e
			AND s.IsPrimaryFee = 1

		UPDATE s
		SET s.LicenseeFee_oa	= CASE
									WHEN s.Discount = 0 THEN 0
									ELSE s.LicenseeFee_oa + (g.GroupMinFee_oa - (g.LicenseeFee_oa - g.Discount)) END
			,s.LicenseeMinFee_oa = CASE
									WHEN s.Discount <> 0 THEN 0
									ELSE s.LicenseeMinFee_oa + (g.GroupMinFee_oa - (g.LicenseeFee_oa - g.Discount)) END
		FROM @tmpResult s
			INNER JOIN @GroupMinFee g ON s.GroupMinFeeId = g.GroupMinFeeId
		WHERE s.GroupMinFeeId > 0
			AND (g.LicenseeFee_oa - g.Discount) < g.GroupMinFee_oa
			AND s.IsPrimaryFee = 1

		UPDATE r
		SET r.LicenseeFee_e = CASE WHEN r.LicenseeFee_e > 0 THEN r.LicenseeFee_e ELSE 0 END
			,r.LicenseeFee_oa = CASE WHEN r.LicenseeFee_oa > 0 THEN r.LicenseeFee_oa ELSE 0 END
		FROM @tmpResult r
		WHERE r.PartyId NOT IN (
					SELECT p.PartyId FROM DBLIC.bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)
					WHERE p.PartyName IN ('9wickets', '9Wsports', '9w')
				)

		UPDATE @tmpResult
		SET ActualWLFee_e = ISNULL(LicenseeMinFee_e, 0) + ISNULL(LicenseeFee_e, 0)
			,ActualWLFee_oa = ISNULL(LicenseeMinFee_oa, 0) + ISNULL(LicenseeFee_oa, 0)
	END

	DELETE r
	FROM @tmpResult r
		LEFT JOIN #PartyChargeInfo p ON r.PartyId = p.PartyId
	WHERE p.PartyId IS NULL

	-- Get Licensee House PT
	DECLARE @Sites VARCHAR(MAX), @SiteCurrencies VARCHAR(MAX)
	SET @Sites = CONVERT(VARCHAR(MAX), (
		SELECT
			s.SiteId	AS '@SiteId'
			,l.PartyId	AS '@PartyId'
			,s.SiteName	AS '@SiteName'
		FROM #AllLicensees l
			INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
			INNER JOIN #PartyChargeInfo p ON l.PartyId = p.PartyId
		FOR XML PATH('r'), TYPE, ROOT('root')
	))

	SET @SiteCurrencies = CONVERT(VARCHAR(MAX), (
		SELECT
			s.SiteId		AS '@SiteId'
			,l.PartyId		AS '@PartyId'
			,s.SiteName		AS '@SiteName'
			,lc.CurrencyId	AS '@CurrencyId'
		FROM #AllLicensees l
			INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
			INNER JOIN #PartyChargeInfo p ON l.PartyId = p.PartyId
			INNER JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId
		FOR XML PATH('r'), TYPE, ROOT('root')
	))

	CREATE TABLE #__HousePT (PartyId INT, CurrencyId INT, HousePT FLOAT)
	INSERT INTO #__HousePT (PartyId, CurrencyId, HousePT)
	EXEC DBACC.bodb02.dbo.Acc_Licensee_HousePT @Sites = @Sites, @SiteCurrencies = @SiteCurrencies

	-- Return Data
	CREATE TABLE #__Result (OrderId TINYINT, PartyId INT, Product VARCHAR(10), SiteName VARCHAR(50)
		,MemberWL_SysRate MONEY, MemberWL_OaRate MONEY, LicenseeWL_SysRate MONEY, LicenseeWL_OaRate MONEY
		,HousePT VARCHAR(200), HouseWL_SysRate MONEY, HouseWL_OaRate MONEY
		,ChargeRate VARCHAR(200), GrossLicenseeFee_SysRate MONEY, GrossLicenseeFee_OaRate MONEY
		,LicenseeMinFee_SysRate MONEY, LicenseeMinFee_OaRate MONEY, LicenseeFee_SysRate MONEY, LicenseeFee_OaRate MONEY
		,LicenseeFeeAfterMinFee_SysRate MONEY, LicenseeFeeAfterMinFee_OaRate MONEY
		,RebateRate FLOAT, Rebate MONEY, DiscountRate FLOAT, Discount MONEY, RebateDiscount MONEY
		,ActualLicenseeFee_SysRate MONEY, ActualLicenseeFee_OaRate MONEY)

	INSERT INTO #__Result (OrderId, PartyId, Product, SiteName
		,MemberWL_SysRate, MemberWL_OaRate, LicenseeWL_SysRate, LicenseeWL_OaRate
		,HousePT, HouseWL_SysRate, HouseWL_OaRate
		,ChargeRate, GrossLicenseeFee_SysRate, GrossLicenseeFee_OaRate
		,LicenseeMinFee_SysRate, LicenseeMinFee_OaRate, LicenseeFee_SysRate, LicenseeFee_OaRate
		,LicenseeFeeAfterMinFee_SysRate, LicenseeFeeAfterMinFee_OaRate
		,RebateRate, Rebate, DiscountRate, Discount, RebateDiscount
		,ActualLicenseeFee_SysRate, ActualLicenseeFee_OaRate)
	SELECT
		1 AS OrderId
		,0 AS PartyId
		,'SB Total'	AS Product
		,''			AS SiteName
		,-SUM(ISNULL(tr.LicenseeWL_e, 0))	AS MemberWL_SysRate
		,-SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS MemberWL_OaRate
		,SUM(ISNULL(tr.LicenseeWL_e, 0))	AS LicenseeWL_SysRate
		,SUM(ISNULL(tr.LicenseeWL_oa, 0))	AS LicenseeWL_OaRate
		,NULL	AS HousePT
		,SUM(ISNULL(tr.HouseWL_e, 0))		AS HouseWL_SysRate
		,SUM(ISNULL(tr.HouseWL_oa, 0))		AS HouseWL_OaRate
		,NULL	AS ChargeRate
		,SUM(ISNULL(tr.HouseIncome_e, 0))		AS GrossLicenseeFee_SysRate
		,SUM(ISNULL(tr.HouseIncome_oa, 0))		AS GrossLicenseeFee_OaRate
		,SUM(ISNULL(tr.LicenseeMinFee_e, 0))	AS LicenseeMinFee_SysRate
		,SUM(ISNULL(tr.LicenseeMinFee_oa, 0))	AS LicenseeMinFee_OaRate
		,SUM(ISNULL(tr.LicenseeFee_e, 0))		AS LicenseeFee_SysRate
		,SUM(ISNULL(tr.LicenseeFee_oa, 0))		AS LicenseeFee_OaRate
		,SUM(ISNULL(tr.ActualWLFee_e, 0))		AS LicenseeFeeAfterMinFee_SysRate
		,SUM(ISNULL(tr.ActualWLFee_oa, 0))		AS LicenseeFeeAfterMinFee_OaRate
		,NULL							AS RebateRate
		,SUM(ISNULL(tr.Rebate, 0))		AS Rebate
		,NULL							AS DiscountRate
		,SUM(ISNULL(tr.Discount, 0))	AS Discount
		,SUM(ISNULL(tr.Rebate, 0) + ISNULL(tr.Discount, 0)) AS RebateDiscount
		,SUM(ISNULL(tr.ActualWLFee_e, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0))	AS ActualLicenseeFee_SysRate
		,SUM(ISNULL(tr.ActualWLFee_oa, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0))	AS ActualLicenseeFee_OaRate
	FROM @tmpResult tr

	UNION ALL
	SELECT
		2 AS OrderId
		,tr.PartyId
		,'SB' AS Product
		,s.SiteName
		,-ISNULL(tr.LicenseeWL_e, 0)	AS MemberWL_SysRate
		,-ISNULL(tr.LicenseeWL_oa, 0)	AS MemberWL_OaRate
		,ISNULL(tr.LicenseeWL_e, 0)		AS LicenseeWL_SysRate
		,ISNULL(tr.LicenseeWL_oa, 0)	AS LicenseeWL_OaRate
		,''	AS HousePT
		,ISNULL(tr.HouseWL_e, 0)		AS HouseWL_SysRate
		,ISNULL(tr.HouseWL_oa, 0)		AS HouseWL_OaRate
		,''	AS ChargeRate
		,ISNULL(tr.HouseIncome_e, 0)	AS GrossLicenseeFee_SysRate
		,ISNULL(tr.HouseIncome_oa, 0)	AS GrossLicenseeFee_OaRate
		,ISNULL(tr.LicenseeMinFee_e, 0)		AS LicenseeMinFee_SysRate
		,ISNULL(tr.LicenseeMinFee_oa, 0)	AS LicenseeMinFee_OaRate
		,ISNULL(tr.LicenseeFee_e, 0)		AS LicenseeFee_SysRate
		,ISNULL(tr.LicenseeFee_oa, 0)		AS LicenseeFee_OaRate
		,ISNULL(tr.ActualWLFee_e, 0)		AS LicenseeFeeAfterMinFee_SysRate
		,ISNULL(tr.ActualWLFee_oa, 0)		AS LicenseeFeeAfterMinFee_OaRate
		,ISNULL(tr.RebateRate, 0)	AS RebateRate
		,ISNULL(tr.Rebate, 0)		AS Rebate
		,ISNULL(tr.DiscountRate, 0) AS DiscountRate
		,ISNULL(tr.Discount, 0)		AS Discount
		,ISNULL(tr.Rebate, 0) + ISNULL(tr.Discount, 0) AS RebateDiscount
		,ISNULL(tr.ActualWLFee_e, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0) AS ActualLicenseeFee_SysRate
		,ISNULL(tr.ActualWLFee_oa, 0) - ISNULL(tr.Discount, 0) - ISNULL(tr.Rebate, 0) AS ActualLicenseeFee_OaRate
	FROM @tmpResult tr
		INNER JOIN #AllLicensees l ON tr.PartyId = l.PartyId
		INNER JOIN DBLIC.bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON l.LicenseeId = s.SiteId
	WHERE ISNULL(tr.LicenseeWL_e, 0) <> 0 OR ISNULL(tr.ActualWLFee_e, 0) <> 0

	;WITH CTE_ChargeRate AS (
		SELECT PartyId, Rate = ISNULL(CurrencyCode + ': ', '') + CONVERT(VARCHAR(5), ROUND(Rate, 3))
		FROM (
		SELECT DISTINCT PartyId, Rate, CONVERT(VARCHAR(3), NULL) AS CurrencyCode FROM #PartyChargeInfo
		UNION ALL
		SELECT DISTINCT p.PartyId, lc.Rate, CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END
		FROM #PartyChargeInfo p
			INNER JOIN #PartyChargeByCurrencyInfo lc ON p.ChargeId = lc.ChargeId
			INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON lc.CurrencyId = e.ExchangeId
		) t
	), CTE_ChargeRateByCurrency AS (
		SELECT p1.PartyId, ChargeRate = STUFF((
            SELECT ' | ' + p2.Rate
            FROM CTE_ChargeRate p2 WHERE p1.PartyId = p2.PartyId ORDER BY p2.Rate
            FOR XML PATH('')
            ), 1, 3, '')
		FROM CTE_ChargeRate p1
		GROUP BY p1.PartyId
	)
	UPDATE r
	SET r.ChargeRate = c.ChargeRate
	FROM #__Result r
		INNER JOIN CTE_ChargeRateByCurrency c ON r.PartyId = c.PartyId
	WHERE r.Product = 'SB'

	;WITH CTE_HousePT AS (
		SELECT h.PartyId, Rate = ISNULL(CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END + ': ', '') + CONVERT(VARCHAR(5), ROUND(h.HousePT, 3))
		FROM #__HousePT h
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
	), CTE_HousePTByCurrency AS (
		SELECT p1.PartyId, HousePT = STUFF((
            SELECT ' | ' + p2.Rate
            FROM CTE_HousePT p2 WHERE p1.PartyId = p2.PartyId ORDER BY p2.Rate
            FOR XML PATH('')
            ), 1, 3, '')
		FROM CTE_HousePT p1
		GROUP BY p1.PartyId
	)
	UPDATE r
	SET r.HousePT = c.HousePT
	FROM #__Result r
		INNER JOIN CTE_HousePTByCurrency c ON r.PartyId = c.PartyId
	WHERE r.Product = 'SB'

	SELECT Product, SiteName
		,MemberWL_SysRate, MemberWL_OaRate, LicenseeWL_SysRate, LicenseeWL_OaRate
		,HousePT, HouseWL_SysRate, HouseWL_OaRate
		,ChargeRate, GrossLicenseeFee_SysRate, GrossLicenseeFee_OaRate
		,LicenseeMinFee_SysRate, LicenseeMinFee_OaRate, LicenseeFee_SysRate, LicenseeFee_OaRate
		,LicenseeFeeAfterMinFee_SysRate, LicenseeFeeAfterMinFee_OaRate
		,RebateRate, Rebate, DiscountRate, Discount, RebateDiscount
		,ActualLicenseeFee_SysRate, ActualLicenseeFee_OaRate
	FROM #__Result
	ORDER BY OrderId, SiteName

	DROP TABLE #__HousePT
	DROP TABLE #__Result
	DROP TABLE #__tempData
	DROP TABLE #__tempResult
	DROP TABLE #__tmpSite
	DROP TABLE #AllLicensees
	DROP TABLE #Exchange
	DROP TABLE #Licensees
	DROP TABLE #PartyCharge3rdInfo
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #PartyChargeInfo
END
GO
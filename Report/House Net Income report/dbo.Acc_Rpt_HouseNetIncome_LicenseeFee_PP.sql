/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_LicenseeFee_PP
	@FromDate   DATE
   ,@ToDate     DATE
AS

/*  
	Created: 20200715@Percy
    Task: House month-to-date Net Income report for PP
    DB: DBEXT-bodb02
   
    Revisions:
	   - 20200715@Percy: Integrate PP Jackpot [RedmineID: #137280]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Active licensees
	DECLARE @tmpParty TABLE(PartyID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, IsDeposit)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID AND map.SystemID = 2
	WHERE p.PartyType = 1
		AND ci.ProductId = 32
		AND (
			ci.FromDate BETWEEN @FDate AND @TDate
			OR ci.ToDate BETWEEN @FDate AND @TDate
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate)
		)

	DECLARE @PartyIDs VARCHAR(1000)
	SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
	FROM @tmpParty
	WHERE IsDeposit = 1
	-- End region

	-- Region: Get exchange rate info
	CREATE TABLE #tmp__Exchange (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #tmp__Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH(NOLOCK)
	WHERE ExchangeDate BETWEEN @FDate AND @TDate
	-- End region

	-- Region: Party charge info*/
	DECLARE @PartyChargeInfo TABLE
	(
		ChargeId	INT
		,PartyId	INT
		,LicenseeId	INT
		,IsDeposit	BIT
		,Rate		MONEY
		,FromDate	SMALLDATETIME
		,ToDate		SMALLDATETIME
		,Bettype	INT
		,ChargeType TINYINT
	)
	INSERT INTO @PartyChargeInfo
	(
		ChargeId
		,PartyId
		,LicenseeId
		,IsDeposit
		,Rate
		,Fromdate
		,Todate
		,Bettype
		,ChargeType
	)
	SELECT
		ci.ChargeId
		,ci.PartyID
		,ci.LicenseeID
		,ci.isDeposit
		,ci.DI_Rate
		,ci.Fromdate
		,ci.ToDate
		,ISNULL(sbr.Bettype, ci.Bettype)
		,ci.ChargeType
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, 'PP', 'OA', 1) ci
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.BettypeRef = ci.Bettype
	WHERE DI_Rate > 0
		AND ProductId <> 1 /*exclude RB*/
	-- End region
	
	-- Region: MinfeeGroup Date range
	DECLARE @Month			TINYINT = MONTH(@FDate)
	DECLARE @FirstDate		DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FDate), 0)
	DECLARE @LastDate		DATETIME = DATEADD(dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FDate) + 1, 0))
	DECLARE @DaysInMonth	INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @PartyGroup TABLE (PartyGroupId INT, PartyId INT)
	INSERT INTO @PartyGroup (PartyGroupId, PartyId)
	SELECT PartyGroupId, PartyId
	FROM bodb_licensee.dbo.LA_PartyGroupAssignment WITH (NOLOCK)
	WHERE PartyGroupId IN
		(
			SELECT p1.PartyGroupId
			FROM bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH (NOLOCK)
			WHERE p1.PartyId IN (SELECT PartyId FROM @tmpParty)
		)

	DECLARE @MinFeeGroup TABLE
	(
		FeeType				TINYINT
		,PartyId            INT
		,ProductId          INT
		,CurrencyId         INT
		,FeeAmount          MONEY
		,FromDate           DATETIME
		,ToDate             DATETIME
		,MinFeeProrate      MONEY
		,WaivedAmount       MONEY
		,TotalAmount        MONEY
		,MinFeeAmount       MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO @MinFeeGroup
	(
		FeeType
		,PartyId
		,ProductId
		,CurrencyId
		,FeeAmount
		,FromDate
		,ToDate
	)
	SELECT
		mf.FeeTypeId
		,mf.PartyId
		,mf.ProductId
		,mf.CurrencyId
		,mf.FeeAmount
		,CASE WHEN @FDate >= mf.FromDate THEN @FDate ELSE mf.FromDate END AS FromDate
		,CASE WHEN @TDate < mf.ToDate THEN @TDate ELSE mf.ToDate END AS ToDate
	FROM bodb_licensee.dbo.LA_MinFee mf WITH (NOLOCK)
	WHERE		(
					mf.FeeTypeId = 1
					OR mf.FeeTypeId = 2 
					AND EXISTS (SELECT	PartyId
								FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
								WHERE	m.FeeTypeId = 1
										AND m.PartyId = mf.PartyId
										AND m.ProductId = mf.ProductId
										AND (
												(m.FromDate BETWEEN @FirstDate AND @LastDate)
												OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
												OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
											)
								)
				)
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND (	
						(mf.FromDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)	
					)					
		
		
	 
	
	UPDATE m
	SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
		INNER JOIN #tmp__Exchange e ON e.ExchangeDate = @TDate AND m.CurrencyId = e.ExchangeID
	-- End region

	CREATE TABLE #__Site (SiteID_DW INT, LicenseeID INT, SiteName VARCHAR(20))
	INSERT INTO #__Site (SiteID_DW, SiteName)
	SELECT SiteID, RTRIM(LTRIM(Site)) SiteName
	FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK) WHERE isDeposit = 1

	UPDATE s
	SET s.LicenseeID = l.LicenseeID
	FROM #__Site s
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON s.SiteName  = RTRIM(LTRIM(l.LicenseeName))

	CREATE TABLE #__Bettype (BetType INT)
	INSERT INTO #__Bettype (BetType)
	SELECT DISTINCT s.BetType FROM bodb02.dbo.SportBettypeMatrix s WITH (NOLOCK)
	WHERE s.ProductID = 32 AND s.Bettype NOT IN (4298, 4299, 4300)

	CREATE TABLE #__tempDataDW
	(
		rptDate					DATE
		,LicenseeID				INT
		,CurrencyID				INT
		,LicenseeWL				MONEY
		,LicenseeComm			MONEY
		,LicenseeContribution	MONEY
		,FullContribution		MONEY
	)

	INSERT INTO #__tempDataDW (rptDate, LicenseeID, CurrencyID, LicenseeWL, LicenseeComm, LicenseeContribution, FullContribution)
	SELECT b.rptDate, s.LicenseeID, b.CurrencyID
		,SUM(CASE WHEN b.bettype = 4297 THEN 0 ELSE -b.WinlossP END) AS LicenseeWL
		,SUM(CASE WHEN b.bettype = 4297 THEN 0 ELSE b.CommissionA END) AS LicenseeComm
		,SUM(CASE WHEN b.bettype = 4297 THEN -b.WinlossA ELSE 0 END) AS LicenseeContribution
		,SUM(CASE WHEN b.bettype = 4297 THEN b.WinlossIBC-b.WinlossS-b.WinlossM-b.WinlossA ELSE 0 END) AS FullContribution
	FROM DBWH.bodb_Account.dbo.FactSiteWinloss b WITH (NOLOCK)
		INNER JOIN #__Site s ON b.SiteID = s.SiteID_DW
		INNER JOIN #__Bettype bt ON b.BetType = bt.BetType
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
	GROUP BY b.rptDate, s.LicenseeID, b.CurrencyID

	CREATE TABLE #tmp__Data
	(
		PartyId            INT
		,rptDate            DATETIME
		,CurrencyId         INT
		,WinLoss            MONEY
		,AComm              MONEY
		,ProductId          TINYINT
		,AmountToCompany	MONEY
		,IsApplyMinFee		BIT
	)
	INSERT INTO #tmp__Data
	(
		PartyId
		,rptDate
		,CurrencyId
		,WinLoss
		,AComm
		,AmountToCompany
		,IsApplyMinFee
	)
	SELECT
		p.PartyId
		,b.rptDate
		,b.CurrencyID
		,SUM(-LicenseeWL * e.Rate) AS WinLoss
		,SUM(b.LicenseeComm * e.Rate) AS AComm
		,SUM(((b.LicenseeWL - b.LicenseeContribution) * ISNULL(lc.Rate, p.Rate) - (b.FullContribution - b.LicenseeContribution)) * e.Rate) AS AmountToCompany
		,1 AS IsApplyMinFee
	FROM #__tempDataDW b
		INNER JOIN #tmp__Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		INNER JOIN @PartyChargeInfo p ON p.LicenseeId = b.LicenseeId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID AND b.CurrencyId = lc.CurrencyID
	GROUP BY
		p.PartyId
		,b.rptDate
		,b.CurrencyID

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #tmp__Data (PartyId)
	
	-- Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency
	UPDATE t
	SET t.IsApplyMinFee = 0
	FROM #tmp__Data t
		INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate AND t.ProductId = m.ProductId AND t.PartyId = m.PartyId
	WHERE m.FeeType = 2

	-- Region: Check min fee group
	UPDATE amf
	SET amf.MinFeeProrate = (
			    (
				   SELECT TOP 1 mfg.FeeAmount
				   FROM @MinFeeGroup AS mfg
				   WHERE mfg.FeeType = 1
					    AND mfg.PartyId = amf.PartyId
					    AND mfg.ProductId = amf.ProductId
			    ) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
	FROM @MinFeeGroup amf
	WHERE FeeType = 2

	UPDATE amf
	SET amf.WaivedAmount = ISNULL(
			    (
				   SELECT SUM(td.AmountToCompany)
				   FROM #tmp__Data td
				   WHERE amf.PartyId = td.PartyId
					    AND amf.ProductId = td.ProductId
					    AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
			    ), 0)
	FROM @MinFeeGroup amf
	WHERE amf.FeeType = 2

	UPDATE amf
	SET amf.MinFeeProrate = ROUND((amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) - ISNULL(
			    (
				   SELECT SUM(f.MinFeeProrate)
				   FROM @MinFeeGroup AS f
				   WHERE f.FeeType = 2
					    AND amf.PartyId = f.PartyId
					    AND amf.ProductId = f.ProductId
			    ), 0), 2)
			  , amf.WaivedAmount = ISNULL(
			    (
				   SELECT CASE
						    WHEN SUM(f.WaivedAmount) < 0
						    THEN 0
						    ELSE SUM(f.WaivedAmount)
						END
				   FROM @MinFeeGroup AS f
				   WHERE f.FeeType = 2
					    AND amf.PartyId = f.PartyId
					    AND amf.ProductId = f.ProductId
			    ), 0)
			  , amf.MinFeeAmount = ISNULL(
			    (
				   SELECT SUM(td.AmountToCompany)
				   FROM #tmp__Data AS td
				   WHERE amf.PartyId = td.PartyId
					    AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
					    AND td.IsApplyMinFee = 1
					    AND amf.ProductId = td.ProductId
			    ), 0)
	FROM @MinFeeGroup amf
	WHERE amf.FeeType = 1

	UPDATE amf
	SET amf.TotalAmount = amf.MinFeeAmount + amf.WaivedAmount
	FROM @MinFeeGroup amf
	WHERE amf.FeeType = 1

	DECLARE @TotalMinFees TABLE
	(
		PartyGroupId        INT
		,ProductId          INT
		,TotalMinFee        MONEY
		,TotalMinFeeAmount  MONEY
	)
	INSERT INTO @TotalMinFees
	(
		PartyGroupId
		,ProductId
		,TotalMinFee
		,TotalMinFeeAmount
	)
	SELECT
		pg.PartyGroupId
		,mf.ProductId
		,SUM(mf.MinFeeProrate)
		,SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END)
	FROM @MinFeeGroup mf
		INNER JOIN @PartyGroup AS pg ON mf.PartyId = pg.PartyId
	WHERE mf.FeeType = 1
	GROUP BY
		pg.PartyGroupId
		,mf.ProductId

	UPDATE amf
	SET amf.AmountToCompany = CASE
									WHEN t.TotalMinFeeAmount < t.TotalMinFee
										AND amf.MinFeeAmount < amf.MinFeeProrate
									THEN amf.MinFeeProrate + amf.WaivedAmount
									ELSE amf.TotalAmount
								 END
	FROM @MinFeeGroup amf
		INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
		INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId AND t.PartyGroupId = pg.PartyGroupId
	WHERE amf.FeeType = 1

	UPDATE amf
	SET amf.AmountToCompany = CASE
									WHEN amf.MinFeeAmount < amf.MinFeeProrate
									THEN amf.MinFeeProrate + amf.WaivedAmount
									ELSE amf.TotalAmount
								 END
	FROM @MinFeeGroup amf
	WHERE amf.FeeType = 1 AND amf.AmountToCompany IS NULL

	-- sum by products
	CREATE TABLE #tmp__SumByProducts
	(
		PartyId            INT
		,WinLoss            MONEY
		,AComm              MONEY
		,MinFeeApplied      MONEY
		,WLFeeApplied       MONEY
		,AmountToCompany	MONEY
	)
	INSERT INTO #tmp__SumByProducts
	(
		PartyId
		,WinLoss
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	)
	SELECT
		PartyId
		,SUM(WinLoss) AS WinLoss
		,SUM(AComm) AS AComm
		,0
		,SUM(AmountToCompany) AS WLFeeApplied
		,SUM(AmountToCompany) AS AmountToCompany
	FROM #tmp__Data
	GROUP BY
		PartyId
		,ProductId
		,CASE
			WHEN MONTH(rptDate) = MONTH(@FDate)
			THEN 1
			ELSE 0
		END

	INSERT INTO #tmp__SumByProducts
	(
		PartyId
		,WinLoss
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	)
	SELECT
		mf.PartyId
		,0 AS Winloss
		,0 AS AComm
		,0 AS MinFeeApplied
		,0 AS WLFeeApplied
		,0 AS AmountToCompany
	FROM @MinFeeGroup AS mf
		INNER JOIN @tmpParty AS p ON p.PartyID = mf.PartyId
	WHERE mf.PartyId NOT IN (SELECT PartyId FROM #tmp__Data)
		AND mf.FeeType = 1

	UPDATE s
	SET AmountToCompany = m.AmountToCompany
		,MinFeeApplied = CASE WHEN m.AmountToCompany = m.TotalAmount THEN 0 ELSE m.MinFeeProrate END
		,WLFeeApplied = CASE WHEN m.AmountToCompany = m.TotalAmount THEN m.TotalAmount ELSE m.WaivedAmount END
	FROM #tmp__SumByProducts s
		INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId
	WHERE m.FeeType = 1

	UPDATE #tmp__SumByProducts
	SET WLFeeApplied = CASE WHEN WLFeeApplied > 0 THEN WLFeeApplied ELSE 0 END
		,AmountToCompany = CASE WHEN AmountToCompany > 0 THEN AmountToCompany ELSE 0 END

	SELECT
		PartyId
		,32 AS ProductId
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	FROM #tmp__SumByProducts

	DROP TABLE #__tempDataDW
	DROP TABLE #tmp__Data
	DROP TABLE #tmp__Exchange
	DROP TABLE #tmp__SumByProducts
	DROP TABLE #__Site
	DROP TABLE #__Bettype
END
GO
/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_LicenseeFee
	@FromDate   DATE
   ,@ToDate     DATE
   ,@Products   VARCHAR(100)
   ,@SubProduct	VARCHAR(100) = ''
AS

/*  
	Created: Victor  
	Date: 2016-06-24  
    Task: House month-to-date Net Income report
    DB: DBEXT-bodb02
   
    Revisions:
	   - 20181113@Robert: DHWL Email/Letstalk/Margin Chart - Integrate Bidme & Sicbo[#104145]
	   - 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
	   - 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
	   - 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
	   - 20200403@Percy: Change name of tmp table to prevent duplicate name with main SP [RedmineID: #131755]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductList TABLE (ProductID INT, ProductCode VARCHAR(10))
	INSERT INTO @ProductList(ProductID, ProductCode)
	SELECT CASE WHEN pl.val = 'SB' THEN 0 ELSE p.ProductId END AS ProductID, p.ProductPrefix
	FROM dbo.Lrf_f_StringSplit (@Products, ',') pl
		LEFT JOIN bodb_licensee.dbo.Product3rd p WITH (NOLOCK) ON p.ProductPrefix = pl.val

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
		AND ci.ProductId IN (SELECT ProductID FROM @ProductList)
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
		,ProductID	INT
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
		,ProductID
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
		,ci.ProductID
		,ci.DI_Rate
		,ci.Fromdate
		,ci.ToDate
		,ISNULL(sbr.Bettype, ci.Bettype)
		,ci.ChargeType
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FDate, @TDate, @Products, 'OA', 1) ci
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
	WHERE
		(
			mf.FeeTypeId = 1
			OR
			(
				mf.FeeTypeId = 2
				AND EXISTS
					(
					SELECT PartyId
					FROM bodb_licensee.dbo.LA_MinFee m WITH (NOLOCK)
					WHERE m.FeeTypeId = 1
							AND m.PartyId = mf.PartyId
							AND m.ProductId = mf.ProductId
							AND
							(
								m.FromDate BETWEEN @FirstDate AND @LastDate
								OR m.ToDate BETWEEN @FirstDate AND @LastDate
								OR m.FromDate < @FirstDate
								AND @LastDate < m.ToDate
							)
					))
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND
				(
					mf.FromDate BETWEEN @FirstDate AND @LastDate
					OR mf.ToDate BETWEEN @FirstDate AND @LastDate
					OR mf.FromDate < @FirstDate
					AND @LastDate < mf.ToDate
				)
		)
	
	UPDATE m
	SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
		INNER JOIN #tmp__Exchange e ON e.ExchangeDate = @TDate AND m.CurrencyId = e.ExchangeID
	-- End region

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
		,ProductId
		,AmountToCompany
		,IsApplyMinFee
	)
	SELECT
		p.PartyId
		,b.rptDate
		,b.CurrencyID
		,SUM(ISNULL(b.MemberWL, 0) * e.Rate) AS WinLoss
		,SUM(ISNULL(b.CommissionA, 0) * e.Rate) AS AComm
		,p.ProductId
		,SUM(-ISNULL(b.MemberWL, 0) * ISNULL(lc.Rate, p.Rate) * e.Rate) AS AmountToCompany
		,1 AS IsApplyMinFee
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #tmp__Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		INNER JOIN @PartyChargeInfo p ON b.ProductId = p.ProductID AND p.LicenseeId = b.SiteId AND b.rptDate BETWEEN p.FromDate AND p.ToDate AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		LEFT JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency lc WITH (NOLOCK) ON p.ChargeId = lc.ChargeID AND b.CurrencyId = lc.CurrencyID
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.CurrencyID <> 20
		AND b.customercategory NOT IN(27, 28)
		AND b.Bettype NOT IN(901, 902, 903, 904, 4300)
		AND b.StatusId NOT IN(-1, 103) /* Exclude Reject , Void, Refund*/
		AND
		(
			(
				p.ChargeType = 12
				AND b.Bettype = 1706
			)
			OR 
			(
				p.ChargeType <> 12
				AND b.Bettype = CASE WHEN @Products = 'NG' AND @SubProduct = 'H5' THEN 8101 ELSE -1 END
			)
		)
	GROUP BY
		p.PartyId
		,b.rptDate
		,b.CurrencyID
		,p.ProductId

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #tmp__Data (PartyId, ProductId)
	
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
		,ProductId          INT
	)
	INSERT INTO #tmp__SumByProducts
	(
		PartyId
		,ProductId
		,WinLoss
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	)
	SELECT
		PartyId
		,ProductId
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
		,ProductId
		,WinLoss
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	)
	SELECT
		mf.PartyId
		,ProductID
		,0 AS Winloss
		,0 AS AComm
		,0 AS MinFeeApplied
		,0 AS WLFeeApplied
		,0 AS AmountToCompany
	FROM @MinFeeGroup AS mf
		INNER JOIN @tmpParty AS p ON p.PartyID = mf.PartyId
	WHERE mf.PartyId NOT IN (SELECT PartyId FROM #tmp__Data WHERE ProductId = mf.ProductId)
		AND mf.FeeType = 1

	UPDATE s
	SET AmountToCompany = m.AmountToCompany
		,MinFeeApplied = CASE WHEN m.AmountToCompany = m.TotalAmount THEN 0 ELSE m.MinFeeProrate END
		,WLFeeApplied = CASE WHEN m.AmountToCompany = m.TotalAmount THEN m.TotalAmount ELSE m.WaivedAmount END
	FROM #tmp__SumByProducts s
		INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
	WHERE m.FeeType = 1

	UPDATE #tmp__SumByProducts
	SET WLFeeApplied = CASE WHEN WLFeeApplied > 0 THEN WLFeeApplied ELSE 0 END
		,AmountToCompany = CASE WHEN AmountToCompany > 0 OR ProductId = 3 THEN AmountToCompany ELSE 0 END

	SELECT
		PartyId
		,ProductId
		,AComm
		,MinFeeApplied
		,WLFeeApplied
		,AmountToCompany
	FROM #tmp__SumByProducts

	DROP TABLE #tmp__Data
	DROP TABLE #tmp__Exchange
	DROP TABLE #tmp__SumByProducts
END
GO
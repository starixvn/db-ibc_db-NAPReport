/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit]
	@FromDate	DATE,
	@ToDate		DATE,
	@ProductList VARCHAR(MAX) = ''
AS  
/*  	
	Created:		20180126@Harper 
	Description:	HDWL Letstalk - Implement Chart of NonSport product margin    
    DB:				DBWH/bodb_dwrs  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of NonSport product margin [#RedmineID: 89632]
		- 20180806@Harper - DHWL Margin Chart - Create new message notification to NSD group based on Product List [#RedmineID: 98611]
		- 20180813@Harper - DHWL Non-sports Margin Chart - Integrate OneRNG Jackpot & Pragmatic [#RedmineID: 97562]
		- 20180912@Harper - DHWL Non-sports Margin Chart - Integrate Pocker Games [#RedmineID: 100426]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]		

	Param's Explanation:   
		- @ProductList: '' - default value when get all product
						'GD,AB,AGC,MGCLC,MGCRNG,CS,VB,PP,NG,VS,KN,LT,FW,VS2,CB' - if group is NSD Group

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_NonSport_Credit '2018-05-01', '2018-05-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	DECLARE @Credit VARCHAR(MAX) = 'KN,LT,VB,VS,VS2,NG,CS,NG2,AB,FW,GD,LK3,CB,PP,PG'	
		
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange			(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	CREATE	TABLE #tmpProduct		(ProductPrefix VARCHAR(20))

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	-- Get Product List
	
	IF LEN(ISNULL(@ProductList, '')) > 0 
	BEGIN
		INSERT INTO #tmpProduct ( ProductPrefix )		
		SELECT val AS ProductPrefix		
		FROM dbo.strSplit(@ProductList, ',')
	END

	CREATE CLUSTERED INDEX [PK_tmp_CurrencyDaily] ON #Exchange( ExchangeDate, ExchangeID )

	DECLARE @OpenQuery NVARCHAR(1000)
	SELECT @OpenQuery = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBEXT, '
						+ N'''SELECT ExchangeDate, ExchangeID, BaseCurrencyRate '
						+ N'FROM bodb02.dbo.LA_f_ExchangeDailySel('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''MYR'''''			
						+ N')'')'
					
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	EXECUTE (@OpenQuery)
	
	-- End region

	CREATE TABLE #FinalResult (
		RptDate		VARCHAR(10),
		HouseWL		MONEY,
		ExtraPT		MONEY,
		PayToSupplier MONEY,
		TurnOver	MONEY
	)

	DECLARE @tmpDate DATE, @DateList VARCHAR(200) = '[FullRange]'
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- KN + LT + MacauGame + VS + VS2: with Exchange Oanda Rate
	CREATE TABLE #PayToSupplierRate (ProductID INT, Rate MONEY)

	INSERT INTO #PayToSupplierRate( ProductID, Rate )
	VALUES  (8, 0.03), (28, 0.03), (22, 0.02), (5, 0.01), (27, 0.01)
			, (3, 0.4), (23, 0.5), (26, 0.4)

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct 
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0,0,0,2,'',@Credit,0) sel
	WHERE ISNULL(@ProductList, '') = ''
		OR EXISTS (SELECT 1 FROM #tmpProduct p WHERE sel.ProductPrefix = p.ProductPrefix) 

	-- House WL
	CREATE TABLE #TmpHouseWL (rptDate DATE, ProductID INT, CurrencyID INT, HouseWL MONEY
								, MemberWL MONEY, MemberWLReal MONEY, MemberWLOANDA MONEY
								, PayToSupplier MONEY, TurnOver MONEY, ExtraPT MONEY, PartnerFee MONEY)
	
	INSERT INTO #TmpHouseWL (rptDate, ProductID, CurrencyID, HouseWL, MemberWL, MemberWLReal, TurnOver, ExtraPT, PartnerFee)
	SELECT 
		b.rptDate,
		sb.ProductID,
		b.CurrencyID,
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE -SUM((b.WinlossIBC + b.CommissionS) * ex.rate) END AS HouseWL, -- Don't need to caculate for CB
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE SUM(b.WinlossP) END AS MemberWL,
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE SUM(b.WinlossP * ex.Rate) END AS MemberWLReal,		
		SUM((CASE WHEN TurnoverIBC = 0 THEN 0  ELSE TurnoverIBC - ExtraTO END ) * ( CASE WHEN VarianceVR > 0 THEN( VarianceVR + 1 ) ELSE 1 END ) * ex.Rate) AS TurnOver,
		CASE WHEN sb.ProductID = 15 THEN 0 ELSE SUM((b.ExtraWL + b.ExtraComm) * ex.Rate) END AS ExtraPT,
		CASE WHEN sb.ProductID = 33 THEN SUM(-b.PartnerFee - PartnerWinloss) ELSE 0 END AS PartnerFee -- Pocker Game
	FROM bodb_Account.dbo.FactSiteWinloss b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID		
		INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 	
		AND b.TicketStatus NOT IN (-1,18,9,10,14)
		AND SiteID IN (SELECT SiteID FROM bodb_Account.dbo.tbl_Site WHERE isDeposit = 0 )-- Credit data only
	GROUP BY b.rptDate, sb.ProductID, b.CurrencyID
	OPTION (RECOMPILE)
	
	-- OANDA Rate: KN + LT + MacauGame + VS + VS2
	UPDATE b
	SET b.PayToSupplier = b.MemberWL * r.Rate * oanda.Rate
	FROM #TmpHouseWL b
		INNER JOIN #ExchangeOANDA oanda ON b.rptDate = oanda.ExchangeDate AND b.CurrencyId = oanda.ExchangeID
		INNER JOIN #PayToSupplierRate r ON b.ProductID = r.ProductID
	WHERE b.ProductID IN (5, 8, 22, 27, 28) -- Need caculate based on oanda rate

	-- OANDA Rate: PG
	UPDATE b
	SET b.PayToSupplier = b.PartnerFee * oanda.Rate
	FROM #TmpHouseWL b
		INNER JOIN #ExchangeOANDA oanda ON b.rptDate = oanda.ExchangeDate AND b.CurrencyId = oanda.ExchangeID		
	WHERE b.ProductID IN (33) -- Need caculate based on oanda rate
	
	-- NG, NG2, LK3
	UPDATE b
	SET b.PayToSupplier = - (b.HouseWL + ExtraPT) * r.Rate
	FROM #TmpHouseWL b		
		INNER JOIN #PayToSupplierRate r ON b.ProductID = r.ProductID
	WHERE b.ProductID IN (3, 23, 26)

	-- PayToSupplier for PP Product	
	CREATE TABLE #ChargeInfo3rd (ProductID INT, Rate MONEY, FromDate SMALLDATETIME, ToDate SMALLDATETIME, MinAmount MONEY, MaxAmount MONEY, BaseCurrencyId INT)
	
	DECLARE @OpenQueryCharge NVARCHAR(1000)
	SELECT @OpenQueryCharge = N'SELECT * ' 
						+ N'FROM OPENQUERY(DBLIC, '
						+ N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
						+ N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
						+ CAST(@FDate AS NVARCHAR(50)) + ''''''
						+ N','''''
						+ CAST(@TDate AS NVARCHAR(50)) + ''''''
						+ N',''''PP'''''
						+ N',''''OA'''''	
						+ N') ci '
						+ N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
						+ N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
						+ N''')'
					
	INSERT INTO #ChargeInfo3rd(ProductID, Rate, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrencyId)
	EXECUTE (@OpenQueryCharge)
	
	UPDATE ci
	SET MinAmount = MinAmount * ex.Rate,
		MaxAmount = MaxAmount * ex.Rate
	FROM #ChargeInfo3rd ci
		INNER JOIN #ExchangeOANDA ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @TDate	
	
	-- PayToSupplier
	; WITH WLAmount AS
	(
		SELECT CONVERT(VARCHAR(2), RptDate, 106) rptDate,
			rptDate FullDate, SUM(- MemberWL * oanda.Rate) AS MemberWL
		FROM #TmpHouseWL b
			INNER JOIN #ExchangeOANDA oanda ON b.rptDate = oanda.ExchangeDate AND b.CurrencyId = oanda.ExchangeID
		WHERE b.ProductID = 32
		GROUP BY CONVERT(VARCHAR(2), RptDate, 106), rptDate
	),
	PayToSupplier AS
	(
		SELECT wl.*, ci.MinAmount, ci.MaxAmount, ci.Rate, 
			CASE 
				WHEN (MemberWL < 0 AND ci.MinAmount = 0) OR (MemberWL >= ci.MinAmount) THEN 
					CASE 
						WHEN MemberWL > MaxAmount THEN ci.MaxAmount - ci.MinAmount
						ELSE MemberWL - ci.MinAmount
					END
				ELSE 0
			END * ci.Rate AS AmtByRange
		FROM WLAmount wl
			INNER JOIN #ChargeInfo3rd ci ON wl.FullDate BETWEEN ci.FromDate AND ci.ToDate
	),
	AmtByDate AS
	(
		SELECT m.rptDate, SUM(AmtByRange) AS AmtByDate	
		FROM PayToSupplier m
		GROUP BY m.rptDate
	)	
	UPDATE r
	SET r.PayToSupplier = - AmtByDate
	FROM AmtByDate m
		INNER JOIN #FinalResult r ON r.RptDate = m.rptDate			
	-- END: Pay To Supplier for PP product
	
	-- Final Return
	;WITH totalcte AS (
						SELECT rptDate
							, SUM(ISNULL(HouseWL, 0))		AS HouseWL
							, SUM(ISNULL(ExtraPT, 0))		AS ExtraPT
							, SUM(ISNULL(TurnOver, 0))		AS TurnOver
							, SUM(ISNULL(PayToSupplier, 0)) AS PayToSupplier
						FROM #TmpHouseWL
						GROUP BY rptDate
					)
	UPDATE f
	SET HouseWL = f.HouseWL + wl.HouseWL,
		ExtraPT = f.ExtraPT + wl.ExtraPT,
		TurnOver = f.TurnOver + wl.TurnOver,
		PayToSupplier = f.PayToSupplier + wl.PayToSupplier
	FROM #FinalResult f
		INNER JOIN totalcte wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate
			
	-- FullRange amount
	INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, PayToSupplier, TurnOver)
	SELECT 'FullRange', 0, 0, 0, 0		

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''NonSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 2, ''Extra PT'', ExtraPT' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 8, ''Turn Over'', TurnOver' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''NonSport'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	-- Drop tmp table
	DROP TABLE #SportBettypeMatrix
	DROP TABLE #TmpHouseWL
	DROP TABLE #Exchange
	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
	DROP TABLE #tmpProduct
	DROP TABLE #PayToSupplierRate
	DROP TABLE #ChargeInfo3rd
END
GO

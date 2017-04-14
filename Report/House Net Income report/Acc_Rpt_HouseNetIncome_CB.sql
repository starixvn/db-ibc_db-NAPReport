USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CB]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  
	Created:	20161226@Harper  
    Task :		House month-to-date Net Income report for Colossus Bets
    DB:			DBEXT/bodb02  
   
    Revisions:  
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_CB '20161001', '20161030'
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- Exchange to Actutal Rate
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	
	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')

	-- Commission Share & Cash in share charge rate
	/*DECLARE @CBShareRate AS TABLE (
		Rate			MONEY,
		MinAmount		MONEY,
		MaxAmount		MONEY,
		MinAmountEx		MONEY,
		MaxAmountEx		MONEY,
		BaseCurrencyID	SMALLINT,
		TypeID			SMALLINT,
		FromDate		DATE,
		ToDate			DATE
	)

	INSERT INTO @CBShareRate
	        ( Rate ,
	          MinAmount ,
	          MaxAmount ,	          
	          BaseCurrencyID ,
	          TypeID ,
	          FromDate ,
	          ToDate
	        )
	SELECT ci.Rate, ci.MinAmount, ci.MaxAmount, ci.BaseCurrencyId, ci.ChargeType,
		CASE WHEN @FDate <= ci.FromDate THEN ci.FromDate ELSE @FDate END,
		CASE WHEN @TDate >= ci.ToDate THEN ci.ToDate ELSE @TDate END
	FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	WHERE ci.FromParty = 1 AND ci.ProductID = 15 -- ColossusBet
		AND ci.ChargeType IN (6, 7) -- charge rate of tunrover and Commission
		AND (@FromDate BETWEEN ci.FromDate AND ci.ToDate 
			OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
			OR ci.FromDate BETWEEN @FDate AND @TDate
			OR ci.ToDate BETWEEN @FDate AND @TDate) 
	*/

	-- Get active Licensees
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT, LicenseeID INT)

	INSERT INTO @tmpParty ( PartyID, IsDeposit, LicenseeID )	
	SELECT DISTINCT p.PartyID, pd.IsDeposit,
		CASE 
			WHEN ISNULL(pd.IsDeposit, 0) = 1 
			THEN p.OldRefID 
			ELSE lb.LabelID 
		END AS LicenseeID
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID AND map.SystemID = 2 -- LA
		LEFT JOIN bodb_licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE p.PartyType = 1 -- Licensee
		AND ci.ProductID = 15 -- CB			
		AND ((ci.FromDate BETWEEN @FDate AND @TDate) 
			OR (ci.ToDate BETWEEN @FDate AND @TDate)
			OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))	
	
	-- Get temp data
	CREATE TABLE #TempDataCB (		
		PartyID			INT,
		rptDate			DATETIME,
		CurrencyID		INT,
		TurnOver		MONEY,		
		CashInAmount	MONEY,
		IsDeposit		BIT
	)

	INSERT INTO #TempDataCB
	        ( 
	          PartyID ,
	          rptDate ,
	          CurrencyID ,
	          TurnOver ,	         
	          CashInAmount,
			  IsDeposit
	        )
	SELECT p.PartyId,
		b.rptDate,
		b.CurrencyID,				
		SUM(b.Turnover * e.Rate) Turnover,		
		SUM(ISNULL(b.BuyBackAmount,0) * e.Rate) CashInAmount,
		p.IsDeposit
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID
		INNER JOIN #ExchangeOANDA e ON b.CurrencyId = e.ExchangeID AND b.rptDate = e.ExchangeDate
	WHERE b.rptDate BETWEEN @FDate AND @TDate
		AND b.ProductID = 15		
		AND b.CurrencyId <> 20
		AND b.CustomerCategory NOT IN (27, 28)
		AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject, Void, Refund
	GROUP BY p.PartyID, b.rptDate, b.CurrencyId, p.IsDeposit
	
	-- Final Result
	CREATE TABLE #ResultByDate (
		RptDate				DATETIME,
		Commission			MONEY,
		CashInShare			MONEY,
		TurnOver			MONEY,
		CashInAmount		MONEY,
		IsDeposit			BIT	
	)

	INSERT INTO #ResultByDate
	        ( RptDate ,	          
	          TurnOver ,
	          CashInAmount,
			  IsDeposit
	        )
	SELECT rptDate, 
		SUM (TurnOver) AS TurnOver,
		SUM (CashInAmount) AS CashInAmount,
		IsDeposit
	FROM #TempDataCB
	GROUP BY rptDate, IsDeposit
	
	UPDATE f
	SET f.Commission = f.TurnOver * CASE WHEN IsDeposit = 0 THEN 0.062 ELSE 0.0405 END,
		f.CashInShare = f.CashInAmount * CASE WHEN IsDeposit = 0 THEN 0.225 ELSE 0.15 END		
	FROM #ResultByDate f
		
	-- Collect data
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		LicenseeWL			MONEY,
		PayToSupplier		MONEY
	)

	INSERT INTO #FinalResult (rptDate, LicenseeWL, PayToSupplier)
	SELECT 'FullRange', SUM(r.Commission + r.CashInShare), 0
	FROM #ResultByDate r
	
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, LicenseeWL, PayToSupplier)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 
			(SELECT ISNULL(SUM(Commission + CashInShare), 0) FROM #ResultByDate WHERE rptDate = @tmpDate), -- LicenseeWL
			0 

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 
	-- End region

	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''CB'', 1, ''House Income'', LicenseeWL' + CHAR(13) +
							') c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	DROP TABLE #ExchangeOANDA
	DROP TABLE #TempDataCB
	DROP TABLE #ResultByDate
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_CB] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_CB] TO [vnteam]
GO
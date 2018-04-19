/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet,dwrs" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Credit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Other Sport[#RedmineID: 89632]
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport '2017-12-01', '2017-12-31'
  
*/  
BEGIN  
	SET NOCOUNT ON  

	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	CREATE	TABLE #ExchangeOANDA	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	INSERT INTO #ExchangeOANDA(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FDate, @TDate, 'MYR')
	-- End region		

	-- Region: Handle data of Soccer
	CREATE TABLE #FinalResult (
		RptDate				VARCHAR(10),
		HouseWL				MONEY,
		ExtraPT				MONEY,
		TurnOver			MONEY,
		ExtraTO				MONEY,
		PayToMuayThai		MONEY,
	)

	-- Date list to draw chart
	DECLARE @tmpDate DATE, @DateList VARCHAR(200)
	SELECT @tmpDate = @FDate

	WHILE @tmpDate <= @TDate
	BEGIN
		INSERT INTO #FinalResult (RptDate, HouseWL, ExtraPT, TurnOver, ExtraTO, PayToMuayThai)
		SELECT CONVERT(VARCHAR(2), @tmpDate, 106), 0, 0, 0, 0, 0

		SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate)
	END

	SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']' FROM #FinalResult 

	-- Sport - Bettype Matrix
	CREATE TABLE #SportBettypeMatrix (ProductID INT, Bettype INT, EventType INT, SubProduct VARCHAR(500))

	INSERT INTO #SportBettypeMatrix (ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID, BetType, EventType, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','SB',0) WHERE SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')

	-- Daily Extra PT
	;WITH ExtraPT AS
	(
		SELECT b.rptDate, SUM(b.ExtraWLAfterComm_RM) AS ExtraPT, SUM(b.ExtraTO_RM) AS ExtraTO
		FROM bodb_account.dbo.rptExtraPTBySite b WITH (NOLOCK)
			INNER JOIN #SportBettypeMatrix sb ON sb.Bettype = b.bettype
		WHERE	rptdate BETWEEN @FDate AND @TDate 
				AND sb.ProductID = 1
				AND b.statusid <> 14
		GROUP BY b.rptDate
	)
	UPDATE f
	SET f.ExtraPT = e.ExtraPT,
		f.ExtraTO = e.ExtraTO
	FROM #FinalResult f
		INNER JOIN ExtraPT e ON CONVERT(VARCHAR(2), e.rptDate, 106) = f.RptDate

	-- House WL of Other Sport
	CREATE TABLE #TmpHouseWL (rptDate DATE, HouseWL MONEY, TurnOver MONEY)
	INSERT INTO #TmpHouseWL (rptDate, HouseWL, TurnOver)
	SELECT 
		b.rptDate,
		ISNULL(-SUM(CASE WHEN b.SiteID NOT IN (-2, -4)THEN (winlossP + winlossS + winlossM + winlossA + commissionS) ELSE 0 END * ex.rate), 0) HouseWL,
		ISNULL(SUM(b.TurnoverIBC * ex.Rate), 0) TurnOver
	FROM bodb_Account.dbo.mcSiteDaily b WITH(NOLOCK)
		INNER JOIN #exchange ex ON b.rptdate = ex.exchangedate AND b.currencyid = ex.ExchangeID	
	WHERE 
		b.rptDate BETWEEN @FDate AND @TDate 
		AND b.status <> 14	
		AND EXISTS( 
					SELECT TOP 1 1
					FROM #SportBettypeMatrix AS sb
					WHERE sb.BetType = b.BetType				                     
						AND sb.ProductID = 1							
						AND sb.EventType IN( 1, 2, 4 )
					)       
		AND EXISTS( 
            SELECT TOP 1 1
            FROM bodb_Account.dbo.League l  WITH(NOLOCK)
            WHERE b.LeagueId = l.LeagueId
				AND l.sportid > 1)
	GROUP BY b.rptDate	
	OPTION (RECOMPILE)
	
	UPDATE f
	SET HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0),
		f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0) - ISNULL(f.ExtraTO, 0)
	FROM #FinalResult f
		INNER JOIN #TmpHouseWL wl ON CONVERT(VARCHAR(2), wl.rptDate, 106) = f.RptDate		


	---------------------------------------------------- Pay to Muay Thai -------------------------------------------------------
	-- Region: Get Party list, including credit licensees	
	DECLARE @tmpParty TABLE (PartyID INT, IsDeposit BIT)
	INSERT INTO @tmpParty (PartyID, IsDeposit)
	SELECT DISTINCT ci.FromParty, pd.IsDeposit
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
	WHERE	p.PartyType = 1
			AND ci.ProductId = 0 -- SB
			AND ((ci.FromDate BETWEEN @FDate AND @TDate)
				OR (ci.ToDate BETWEEN @FDate AND @TDate)
				OR (ci.FromDate < @FDate AND @TDate < ci.ToDate))

	DECLARE @PartyIDs VARCHAR(1000)	
	SELECT	@PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId) FROM @tmpParty

	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			IsDeposit	BIT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)
	
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
	FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)	
	-- End Region: Get Party list, including credit licensees		

	DECLARE @MuayThaiData TABLE (rptDate DATE, AmtDueMuayThai MONEY)
	DECLARE @ShareRate MONEY = 0.03
	DECLARE @CutOfDate		SMALLDATETIME,
			@TmpFromDate	SMALLDATETIME,
			@TmpToDate		SMALLDATETIME 

	SELECT @CutOfDate = '2017-09-30' -- New formula when caculate muaythai ticket be applied	

	IF @FDate < @CutOfDate -- Old Data: incase when handle script by hand for regen past email
	BEGIN
		INSERT INTO @MuayThaiData
		SELECT	b.rptDate,
				SUM(ISNULL(b.WLShare * e.Rate, 0) + ISNULL(b.CommShare * e.Rate, 0)) AmtDueMuayThai
		FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
												AND b.SiteID = p.LicenseeId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.rptDate AND e.ExchangeID = b.CurrencyId
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND (b.CurrencyID <> 20)
				AND b.StatusId BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.SportType = 44 -- Muay Thai
		GROUP BY b.rptdate
	END
	ELSE
	BEGIN
		INSERT INTO @MuayThaiData
		SELECT	b.rptDate,
				SUM(ISNULL(b.AdjustedCustomerWL * e.Rate * (-@ShareRate), 0) + ISNULL(b.AdjustedCommShare * e.Rate, 0)) AmtDueMuayThai
		FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
												AND b.SiteID = p.LicenseeId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				INNER JOIN #ExchangeOANDA e ON e.ExchangeDate = b.rptDate AND e.ExchangeID = b.CurrencyId
		WHERE	b.rptDate BETWEEN @FDate AND @TDate
				AND (b.CurrencyID <> 20)
				AND b.StatusId BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.SportType = 44 -- Muay Thai
		GROUP BY b.rptdate
	END	

	-- Update daily amount
	UPDATE r
	SET PayToMuayThai = -d.AmtDueMuayThai
	FROM #FinalResult r
		INNER JOIN @MuayThaiData d ON r.RptDate = CONVERT(VARCHAR(2), d.RptDate, 106)	
		
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''SB'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 3, ''Extra PT'', ExtraPT' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 8, ''Turn Over'', TurnOver' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''SB'', 6, ''Pay to Muay Thai'', PayToMuayThai) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
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
	DROP TABLE #FinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport] TO [dwrs]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport] TO vnteam
GO
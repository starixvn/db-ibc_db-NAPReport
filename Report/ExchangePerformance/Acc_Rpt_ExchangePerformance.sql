USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_ExchangePerformance]
	  @FromDate		DATE
	, @ToDate		DATE
	, @LicenseeId	VARCHAR(MAX) = ''
	, @SportType	VARCHAR(MAX) = ''
AS

/*
	Created: 20180529@Cherry
	Description: Nap Report - Exchange Performance
	DB: DBEXT.bodb02 
	Revisions: 
		- 20180529@Cherry: Nap Report - Exchange Performance report [RedmineID: #93582]

	Param's Explanation:  
 
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @PartyList VARCHAR(4000), @FDate DATE, @TDate DATE

	CREATE TABLE #tmpResult (LicenseeName VARCHAR(50), 
							 MemberCount INT, 
							 BetCount INT, 
							 TurnOver MONEY,
							 MemberWinLoss MONEY, 
							 MemberCommission MONEY,
							 LicenseeWinLoss MONEY, 
							 LicenseeCommission MONEY,
							 PayToSupplier MONEY)
	
	CREATE TABLE #tmpSport (SportID INT)
    
    CREATE TABLE #tmpLicensee (LicenseeId INT, LicenseeName VARCHAR(50))
    
    CREATE TABLE #tmpWinLostDate (WinLostDate DATE, StartWLDate DATETIME, EndWLDate DATETIME)
    
    CREATE TABLE #ChargeRate (PartyId INT, LicenseeId INT, ParentID INT, Rate MONEY, FromDate DATE, ToDate DATE)
    
    CREATE TABLE #ChargeRate3rd (LicenseeId INT, Rate MONEY, FromDate DATE, ToDate DATE)
    
    CREATE TABLE #tmpPartyList (PartyID INT, PartyName VARCHAR(200), BrandName VARCHAR(200), ParentID INT)
    
    CREATE TABLE #TicketData (	SettledDate		DATE,
								Custid			INT,	
								SiteID			INT,							
								CurrencyID		INT,
								UserID			VARCHAR(20),
								EventID			INT,
								MarketID		VARCHAR(50),							
								Turnover		MONEY,							
								Winlost			MONEY,	
								WinLostA		MONEY,					
								BetCount		INT,
								CommissionP		MONEY,
								CommissionA		MONEY,
								EventTypeName   Nvarchar(50), 
								EventType 		SMALLINT
							 )
							
	CREATE TABLE #DetailData (	UserID			VARCHAR(20),
								EventID			INT,
								MarketID		VARCHAR(50),					
								BetCount		INT,
								EventTypeName   NVARCHAR(50),
								EventType 		SMALLINT
							 )	
    
    CREATE TABLE #tmpWinlost(	Winlostdate DATE,
								SiteId INT,
								Sporttype SMALLINT,
								Custid INT,								
								Currency INT,
								Turnover MONEY,								
								Winlost MONEY,
								WinLostA MONEY,
								CommissionP MONEY,
								CommissionA MONEY,
								BetCount INT )		
								
	-- Region: Get Exchange
	CREATE	TABLE #ExchangeOANDA (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	
	INSERT INTO #ExchangeOANDA (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, ActualRate
	FROM bodb02.dbo.ExchangeDailyOanda
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate 
	-- End Region						)
    
    INSERT INTO #tmpSport (SportID)
	SELECT val
	FROM dbo.strSplit(@SportType, ',')
	
	INSERT INTO #tmpLicensee (LicenseeId, LicenseeName)
	SELECT s.val, l.LicenseeName
	FROM [dbo].strSplit(@LicenseeId, ',') s
		INNER JOIN bodb_Licensee.dbo.Licensees l ON s.val = l.LicenseeID		
	
	INSERT INTO #tmpWinLostDate (WinLostDate, StartWLDate, EndWLDate)
	SELECT DISTINCT WinlostDate, WinlostDate, DATEADD(Day, 1, WinlostDate)
	FROM bodb_3rdProduct.dbo.Product3rd_SummarizedDateHistory WITH (NOLOCK)
	WHERE WinlostDate >= @FromDate AND WinlostDate <= @ToDate 
		AND SumToThirdPartyDate IS NULL

	INSERT INTO #tmpPartyList
	EXECUTE bodb_licensee.dbo.LA_PartyListSel 

	SELECT @PartyList = COALESCE(@PartyList + ',' + CAST(FromParty AS VARCHAR), CAST(FromParty AS VARCHAR))
	FROM (
		SELECT c.FromParty
		FROM bodb_licensee.dbo.OAS_ChargeInfo c WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) ON c.FromParty = p.PartyID
			INNER JOIN #tmpLicensee l ON p.OldRefID = l.LicenseeId 
		WHERE ProductId = 31
		GROUP BY FromParty
	)tmp
	
	-- Get charge rate	
	INSERT INTO #ChargeRate(PartyId, LicenseeId, ParentID, Rate, FromDate, ToDate)
	SELECT ci.PartyId, LicenseeId, p.ParentID, DI_Rate, FromDate, ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyList, @FromDate, @ToDate, 'BX', 'OA', 1) ci
		INNER JOIN #tmpPartyList p ON ci.PartyID = p.PartyID	
	WHERE DI_Rate > 0 AND ChargeType = 1

	-- Get more charge rate for trial time
	INSERT INTO #ChargeRate(PartyId, LicenseeId, ParentID, Rate, FromDate, ToDate)
	SELECT ci.PartyId, LicenseeId, p.ParentID, DI_Rate, FromDate, ToDate
	FROM bodb_licensee.dbo.LA_f_GetChargeInfoWithTrialTime(@PartyList, @FromDate, @ToDate, 'BX', 'OA', 1) ci
		INNER JOIN #tmpPartyList p ON ci.PartyID = p.PartyID	
	WHERE DI_Rate > 0 AND ChargeType = 1
	
	-- Get charge rate for 3rd
	INSERT INTO #ChargeRate3rd(LicenseeId, Rate, FromDate, ToDate)	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'BX', 'OA') ci	
			INNER JOIN #ChargeRate p ON (CASE WHEN ci.IsParent = 1 THEN p.ParentID ELSE p.PartyId END) = ci.PartyID	
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
	)

	-- Get data has not been moved to sum table yet(yesterday and today)
	IF EXISTS (SELECT 1 FROM #tmpWinLostDate)
	BEGIN		
		SELECT @FDate = MIN(WinLostDate), @TDate = MAX(WinLostDate)
		FROM #tmpWinLostDate
	
		INSERT INTO #TicketData (SettledDate, Custid, SiteID, CurrencyID, UserID, EventID, MarketID
									, Turnover, Winlost, CommissionP, CommissionA)
		SELECT b.settledDate, b.CustID, ISNULL(site.SiteID,-1) as SiteId, b.Currency, b.userId, b.eventID, b.marketID
			, SUM(ISNULL(b.stakeTotal,0) * 1/b.ExVirtualRate) Turnover, SUM(ISNULL(b.marketTotal,0) * 1/b.ExVirtualRate) Winlost
			, SUM(ISNULL(b.commission,0) * 1/b.ExVirtualRate) CommissionP, SUM(ISNULL(b.agentCommission,0) * 1/b.ExVirtualRate) CommissionA			
		FROM bodb_3rdProduct.dbo.Sum_winloss_Exchange b WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON c.Custid = b.CustID AND c.roleid = 1
			INNER JOIN bodb02.dbo.customer ag WITH (NOLOCK) ON c.recommend = ag.custid AND ag.roleid = 2
			INNER JOIN bodb02.dbo.Site ibcsite WITH (NOLOCK) ON ag.site=ibcsite.site
			INNER JOIN bodb_licensee.dbo.view_site_list [site] WITH (NOLOCK) ON ibcsite.siteid=site.IbcSiteID
		WHERE CONVERT(DATE, b.settledDate) BETWEEN @FDate AND @TDate
			AND b.Currency <> 20
			AND EXISTS (SELECT 1 FROM #tmpLicensee l WHERE l.LicenseeId = [site].SiteID)
		GROUP BY b.settledDate, b.CustID, ISNULL(site.SiteID,-1), b.currency, b.ExVirtualRate, b.userId, b.eventID, b.marketID

		INSERT INTO #DetailData
			( UserID ,
			EventID ,
			MarketID ,
			BetCount, 
			EventType, 
			EventTypeName )			
		SELECT d.userId, 
			d.eventID, 
			d.marketID,
			COUNT(*) AS Betcount,
			d.eventType, 
			d.EventTypeName
		FROM bodb_3rdProduct.dbo.Bettrans_Exchange d WITH (NOLOCK)
			INNER JOIN #tmpSport s ON d.eventType = s.SportID
			INNER JOIN #TicketData b ON d.userId = b.userId AND d.eventID = b.eventID AND d.marketID = b.marketID
		WHERE d.betstatus = 'Settled'				
		GROUP BY d.userId, d.eventID, d.marketID, d.eventType, d.EventTypeName
		
		UPDATE b
		SET b.BetCount = ISNULL(d.BetCount, 0),
			b.EventType = ISNULL(d.eventType,-1),
			b.EventTypeName = ISNULL(d.EventTypeName, 'Invalid')
		FROM #TicketData b
			INNER JOIN #DetailData d ON d.userId = b.userId AND d.eventID = b.eventID AND d.marketID = b.marketID
			
		DELETE #TicketData WHERE EventType = -1
		
		UPDATE b
		SET b.WinLostA = - (ISNULL(Winlost, 0)) * (1 - ISNULL(r.Rate, 0))
		FROM #TicketData b
			INNER JOIN #ChargeRate r ON b.SiteID = r.LicenseeId
		WHERE b.SettledDate BETWEEN r.FromDate AND r.ToDate

		DELETE #TicketData 
			WHERE ISNULL(Turnover,0) = 0 AND ISNULL(Winlost,0) = 0 AND ISNULL(WinLostA,0) = 0 AND ISNULL(CommissionP,0) = 0 AND ISNULL(CommissionA,0) = 0 
				  AND ISNULL(BetCount,0) = 0 AND ISNULL(eventType,-1) = -1 AND ISNULL(EventTypeName, 'Invalid') = 'Invalid'
				  
		INSERT INTO #tmpWinlost 
			(Winlostdate, 
			SiteId,
			Sporttype,
			Custid, 			
			Currency,
			Turnover,			
			Winlost,
			WinLostA,
			CommissionP,
			CommissionA,
			BetCount)
		SELECT SettledDate, 
			SiteID,
			EventType,
			Custid, 			 
			CurrencyID, 
			SUM(ISNULL(turnover, 0)) Turnover, 
			SUM(ISNULL(Winlost, 0)) Winlost, 
			SUM(ISNULL(WinLostA, 0)) WinLostA,			
			SUM(ISNULL(CommissionP, 0)) CommissionP, 
			SUM(ISNULL(CommissionA, 0)) CommissionA, 
			SUM(ISNULL(BetCount, 0)) BetCount
		FROM #TicketData d	
		GROUP BY SettledDate, SiteID, EventType, Custid, CurrencyID		
	END
	-- #EndRegion: Get data has not been moved to sum table yet(yesterday and today)

	-- #Region: Handle Data	from Sum Table
	BEGIN
		
		INSERT INTO #tmpWinlost 
			(Winlostdate, 
			SiteId,
			Sporttype,
			Custid, 			
			Currency,
			Turnover,			
			Winlost,
			WinLostA,
			CommissionP,
			CommissionA,
			BetCount)
		SELECT Winlostdate, 
			SiteID,
			Sporttype,
			Custid, 			 
			Currency, 
			SUM(ISNULL(Turnover, 0)) Turnover, 
			SUM(ISNULL(Winlost, 0)) Winlost, 
			SUM(ISNULL(WinLostA, 0)) WinLostA,			
			SUM(ISNULL(CommissionP, 0)) CommissionP, 
			SUM(ISNULL(CommissionA, 0)) CommissionA, 
			SUM(ISNULL(BetCount, 0)) BetCount
		FROM bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty_Performance b WITH (NOLOCK)
		WHERE Winlostdate BETWEEN @FromDate AND @ToDate 
			AND b.ProductId = 31 
			AND NOT EXISTS (SELECT 1 FROM #tmpWinLostDate r WHERE b.Winlostdate = r.WinLostDate)		
			AND EXISTS (SELECT 1 FROM #tmpSport s WHERE b.Sporttype	= s.SportID)	
			AND EXISTS (SELECT 1 FROM #tmpLicensee l WHERE b.SiteId = l.LicenseeId)
		GROUP BY Winlostdate, SiteID, Sporttype, Custid, Currency
				
	END
	-- #EndRegion: Handle Data	from Sum Table
	
	INSERT INTO #tmpResult
			(LicenseeName, 
			MemberCount, 
			BetCount, 
			TurnOver,
			MemberWinLoss,
			MemberCommission,
			LicenseeWinLoss,
			LicenseeCommission,
			PayToSupplier)
	SELECT  l.LicenseeName,
			COUNT(DISTINCT Custid) MemberCount,
			SUM(BetCount) BetCount,
			SUM(Turnover * e.Rate) Turnover,
			SUM(Winlost * e.Rate) MemberWinloss,
			SUM(CommissionP * e.Rate) MemberCommission,
			SUM(WinLostA * e.Rate) LicenseeWinloss,
			SUM(CommissionA * e.Rate) LicenseeCommission,
			SUM(CASE WHEN c.Rate IS NULL THEN 0 ELSE -(Winlost * c.Rate + CommissionP + CommissionA) * e.Rate END) PayToSupplier
	FROM #tmpWinlost t
		INNER JOIN #tmpLicensee l ON t.SiteId = l.LicenseeId		
		INNER JOIN #ExchangeOANDA e ON t.Currency = e.ExchangeID AND t.Winlostdate = e.ExchangeDate	
		LEFT JOIN #ChargeRate3rd c ON t.SiteId = c.LicenseeId AND t.Winlostdate BETWEEN c.FromDate AND c.ToDate
	GROUP BY LicenseeName
		
	-- #Region: Return data
	SELECT  LicenseeName, 
			MemberCount, 
			BetCount, 
			TurnOver,
			MemberWinLoss,
			MemberCommission,
			MemberWinLoss + MemberCommission AS MemberTotal,
			LicenseeWinLoss,
			LicenseeCommission,
			LicenseeWinLoss + LicenseeCommission AS LicenseeTotal,
			-(MemberWinLoss + LicenseeWinLoss) AS CompanyWinLoss,
			-(MemberCommission + LicenseeCommission) AS CompanyCommission,
			PayToSupplier,
			-(MemberWinLoss + LicenseeWinLoss + MemberCommission + LicenseeCommission + PayToSupplier) AS CompanyNetIncome
	FROM #tmpResult 
	
	-- #EndRegion: Return data		
	
	DROP TABLE #tmpResult
	DROP TABLE #tmpSport
	DROP TABLE #tmpLicensee
	DROP TABLE #tmpWinLostDate
	DROP TABLE #ChargeRate
	DROP TABLE #ChargeRate3rd
	DROP TABLE #tmpPartyList
	DROP TABLE #TicketData
	DROP TABLE #DetailData
	DROP TABLE #tmpWinlost
	DROP TABLE #ExchangeOANDA

END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_ExchangePerformance] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_ExchangePerformance] TO [vnteam];
GO	
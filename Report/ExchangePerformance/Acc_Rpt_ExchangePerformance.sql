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
    
    CREATE TABLE #ChargeRate (PartyId INT, LicenseeId INT, ParentID INT, Rate MONEY, FromDate DATE, ToDate DATE)
    
    CREATE TABLE #ChargeRate3rd (LicenseeId INT, Rate MONEY, FromDate DATE, ToDate DATE)
    
    CREATE TABLE #tmpPartyList (PartyID INT, PartyName VARCHAR(200), BrandName VARCHAR(200), ParentID INT)       
    
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
	CREATE	TABLE #ExchangeRate (ExchangeDate DATE, ExchangeID INT, Rate FLOAT)	
	
	INSERT INTO #ExchangeRate (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, ActualRate
	FROM bodb02.dbo.ExchangeDailyOanda WITH (NOLOCK)
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate 
	-- End Region						)
    
    INSERT INTO #tmpSport (SportID)
	SELECT val
	FROM dbo.strSplit(@SportType, ',')
	
	INSERT INTO #tmpLicensee (LicenseeId, LicenseeName)
	SELECT s.val, l.LicenseeName
	FROM [dbo].strSplit(@LicenseeId, ',') s
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (NOLOCK) ON s.val = l.LicenseeID		

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

	-- Handle Data	from Sum Table
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
			AND EXISTS (SELECT 1 FROM #tmpSport s WHERE b.Sporttype	= s.SportID)	
			AND EXISTS (SELECT 1 FROM #tmpLicensee l WHERE b.SiteId = l.LicenseeId)
		GROUP BY Winlostdate, SiteID, Sporttype, Custid, Currency
				
	END
	-- #End of Handle Data	from Sum Table
	
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
		INNER JOIN #ExchangeRate e ON t.Currency = e.ExchangeID AND t.Winlostdate = e.ExchangeDate	
		LEFT JOIN #ChargeRate3rd c ON t.SiteId = c.LicenseeId AND t.Winlostdate BETWEEN c.FromDate AND c.ToDate
	GROUP BY LicenseeName
		
	-- Return data
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
	-- #End of Return data		
	
	DROP TABLE #tmpResult
	DROP TABLE #tmpSport
	DROP TABLE #tmpLicensee
	DROP TABLE #ChargeRate
	DROP TABLE #ChargeRate3rd
	DROP TABLE #tmpPartyList
	DROP TABLE #tmpWinlost
	DROP TABLE #ExchangeRate

END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_ExchangePerformance] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_ExchangePerformance] TO [vnteam];
GO	
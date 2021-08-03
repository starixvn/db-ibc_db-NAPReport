/*<info serverAlias="DBEXT-bodb02" isFunction="0" executers="bodbAdminNet" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_rptDepWinlost_ThirdParty_Bettrans]
	 @WinLostDate	SMALLDATETIME
AS
/*   
	Created: 20210413@Danny
	Task: Summary Exchange data and insert into rptDepWinlost_ThirdParty
	DB: DBEXT-bodb02
	
	Revisions:	
		- 20210413@Danny: Initialize SP [RedmineID: #151993]

	Param's Explanation:

	EXEC dbo.Acc_Rpt_rptDepWinlost_ThirdParty_Bettrans '2021-05-12'
*/  
BEGIN
SET NOCOUNT ON


	
	DECLARE @ProductId INT = 31, @PartyList VARCHAR(4000), @i SMALLINT = 1, @WLDate DATE

	SELECT @WLDate = @WinLostDate

	CREATE TABLE #ChargeRate (PartyId INT, LicenseeId INT, ProductId INT, Rate MONEY, FromDate DATE, ToDate DATE)
		
	-- #Region: Get charge rate to caculate WinLostA
	DECLARE @fdate DATE, @tDate DATE
	SELECT @fdate = @WinLostDate, @tDate = @WinLostDate

	SELECT @PartyList = COALESCE(@PartyList + ',' + CAST(FromParty AS VARCHAR), CAST(FromParty AS VARCHAR))
	FROM (
		SELECT FromParty
		FROM bodb_licensee.dbo.OAS_ChargeInfo WITH(NOLOCK)
		WHERE ProductId = @ProductId
		GROUP BY FromParty
	)tmp

	-- Get charge rate	
	INSERT INTO #ChargeRate(PartyId, LicenseeId, ProductId, Rate, FromDate, ToDate)
	SELECT PartyId, LicenseeId, ProductId, DI_Rate, FromDate, ToDate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyList, @fdate, @tDate, 'BX', 'OA', 1)
	WHERE DI_Rate > 0 AND ChargeType = 1

	-- Get more charge rate for trial time
	INSERT INTO #ChargeRate(PartyId, LicenseeId, ProductId, Rate, FromDate, ToDate)
	SELECT PartyId, LicenseeId, ProductId, DI_Rate, FromDate, ToDate
	FROM bodb_licensee.dbo.LA_f_GetChargeInfoWithTrialTime(@PartyList, @fdate, @tDate, 'BX', 'OA', 1)
	WHERE DI_Rate > 0 AND ChargeType = 1
	
	-- #EndRegion: Get charge rate to caculate WinLostA
	
	CREATE TABLE #TicketData (	Custid			INT,	
								SiteID			INT,							
								CurrencyID		INT,
								ExVirtualRate	FLOAT,
								UserID			VARCHAR(20),
								EventID			INT,
								MarketID		VARCHAR(50),							
								Turnover		MONEY,							
								Winlost			MONEY,	
								WinLostA		MONEY,
								DrawTO			MONEY,	
								DrawBetCount	INT,						
								BetCount		INT,
								ValidBetAmount	MONEY,
								CommissionP		MONEY,
								CommissionA		MONEY,
								EventTypeName   Nvarchar(50), 
								EventType 		INT
							)
							
	CREATE TABLE #DetailData (	
								UserID			VARCHAR(20),
								EventID			INT,
								MarketID		VARCHAR(50),
								DrawTO			MONEY,	
								DrawBetCount	INT,						
								BetCount		INT,
								Lay				MONEY,
								Back			MONEY,
								EventTypeName   Nvarchar(50),
								EventType 		INT
							)
	

	BEGIN 
		INSERT INTO #TicketData (custid, SiteID, CurrencyID, ExVirtualRate, UserID, EventID, MarketID
									, Turnover, Winlost, CommissionP, CommissionA)
		SELECT b.CustID, ISNULL(site.SiteID,-1) as SiteId, b.Currency, b.ExVirtualRate, b.userId, b.eventID, b.marketID
			, SUM(ISNULL(b.stakeTotal,0) * 1/b.ExVirtualRate), SUM(ISNULL(b.marketTotal,0) * 1/b.ExVirtualRate)
			, SUM(ISNULL(b.commission,0) * 1/b.ExVirtualRate), SUM(ISNULL(b.agentCommission,0) * 1/b.ExVirtualRate)				
		FROM bodb_3rdproduct.dbo.Sum_winloss_Exchange b WITH (NOLOCK)
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON c.Custid = b.CustID AND c.roleid = 1
			LEFT JOIN bodb02.dbo.customer ag WITH (NOLOCK) ON c.recommend = ag.custid AND ag.roleid = 2
			LEFT JOIN bodb02.dbo.Site ibcsite WITH (NOLOCK) ON ag.site=ibcsite.site
			LEFT JOIN bodb_licensee.dbo.view_site_list [site] WITH (NOLOCK) ON ibcsite.siteid=site.IbcSiteID
		WHERE CONVERT(DATE, b.settledDate) = @WLDate
		GROUP BY b.CustID, ISNULL(site.SiteID,-1), b.currency, b.ExVirtualRate, b.userId, b.eventID, b.marketID

		INSERT INTO #DetailData( UserID ,EventID ,MarketID ,BetCount  ,DrawBetCount ,DrawTO ,Lay ,Back, eventType, EventTypeName )			
		SELECT d.userId, d.eventID, d.marketID
			, COUNT(*) AS Betcount
			, SUM(CASE WHEN d.profitLoss = 0 THEN 1 ELSE 0 END) AS DrawBetCount
			, SUM(CASE WHEN d.profitLoss = 0 THEN (d.matchStake * 1/b.ExVirtualRate) ELSE 0 END) AS DrawTO
			, SUM(CASE WHEN d.matchType = 'Lay' THEN (d.matchStake * 1/b.ExVirtualRate) ELSE 0 END) AS Lay
			, SUM(CASE WHEN d.matchType = 'Back' THEN (d.matchStake * 1/b.ExVirtualRate) ELSE 0 END) AS Back
			, d.eventType, d.EventTypeName
		FROM bodb_3rdproduct.dbo.Bettrans_Exchange d WITH (NOLOCK)
			INNER JOIN #TicketData b ON d.userId = b.userId AND d.eventID = b.eventID AND d.marketID = b.marketID
		WHERE d.betstatus = 'Settled'				
		GROUP BY d.userId, d.eventID, d.marketID, d.eventType, d.EventTypeName
			
		UPDATE b
		SET b.BetCount = ISNULL(d.BetCount, 0),
			b.DrawBetCount = ISNULL(d.DrawBetCount, 0),
			b.DrawTO = ISNULL(d.DrawTO, 0),
			b.ValidBetAmount = ABS(ISNULL(d.Lay, 0) - ISNULL(d.Back, 0)),
			b.eventType = ISNULL(d.eventType,-1),
			b.EventTypeName = ISNULL(d.EventTypeName, 'Invalid')
		FROM #TicketData b
			LEFT JOIN #DetailData d ON d.userId = b.userId AND d.eventID = b.eventID AND d.marketID = b.marketID
				
		UPDATE b
		SET b.WinLostA = - (ISNULL(Winlost, 0)) * (1 - ISNULL(r.Rate, 0))
		FROM #TicketData b
			INNER JOIN #ChargeRate r ON b.SiteID = r.LicenseeId
		WHERE @WLDate BETWEEN r.FromDate AND r.ToDate
			
		--- Delete unused data because of bettrans_exchange does not has data , but Sum_winloss_Exchange still has data with 0 ( case void or refund) 
		DELETE #TicketData 
		WHERE ISNULL(Turnover,0) = 0 AND ISNULL(Winlost,0) = 0 AND ISNULL(WinLostA,0) = 0 AND ISNULL(CommissionP,0) = 0 AND ISNULL(CommissionA,0) = 0 
				AND ISNULL(BetCount,0) = 0 AND ISNULL(DrawBetCount,0) = 0 AND ISNULL(DrawTO,0) = 0 AND ISNULL(ValidBetAmount,0) = 0		  
				AND ISNULL(eventType,-1) = -1 AND ISNULL(EventTypeName, 'Invalid') = 'Invalid'
			
		
	
		SELECT  @WinLostDate rptDate, 
				custid custid, 
				@ProductId ProductId, 
				CurrencyID CurrencyId, 
				SUM(ISNULL(Winlost, 0)) Winlost, 	
				SUM(ISNULL(WinLostA, 0)) GrossWL, 
				SUM(ISNULL(turnover, 0)) Turnover, 
				SUM(ISNULL(BetCount, 0)) BetCount,
				SUM(ISNULL(CommissionP, 0)) PlayerComm, 
				SUM(ISNULL(CommissionA, 0)) AgentComm, 
				SUM(ISNULL(ValidBetAmount, 0)) ValidBetAmount		
		FROM #TicketData
		WHERE CurrencyID <> 20
		GROUP BY Custid, CurrencyID

	END 

	DROP TABLE #TicketData
	DROP TABLE #DetailData
	DROP TABLE #ChargeRate
END



/*<info serverAlias="DBEXT-bodb02" isFunction="0" executers="wsv_nap" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[Acc_Rpt_rptBettingByProduct_Bettrans]
	@WinLostDate SMALLDATETIME
AS
/*
	Created: 20210413@Danny
	Task: Gen data for licensee bettrans staging
	DB: DBEXT-bodb02

	Revisions:
		- 20210413@Danny: Initialize SP [RedmineID: #151993]
		- 20210914@Danny: Edit CB Winloss (#159045)
		- 20231027@Danny: Change LicenseeID detection formulary of deposit licensee [#183209]
		- 20230414@Danny: New Commercial Terms for 12B (#186505)
        - 20230817@Ned.Le: Remove currency test
		- 20240403@Danny: AGC product integrate JP, Contribution, Promotion  (#200523)
		- 20240328@Danny: Incorporate Yolo And remove unsupported products (#201590)

	Exec [Acc_Rpt_rptBettingByProduct_Bettrans] '2021-05-12'

*/

BEGIN
	SET NOCOUNT ON
	--- rptBettingByProduct
	CREATE TABLE #rpt_BettingByProduct(
		[rptDate] [datetime],
		[SiteID] [int],
		[ProductID] [tinyint],
		[Bettype] [int],
		[CurrencyId] [int],
		[StatusId] [smallint],
		[CustomerCategory] [int],
		[MemberWL] [money],
		[Turnover] [money],
		[BetCount] [int],
		[CommissionA] [money],
		[CommissionP] [money],
		[BuyBackAmount] [money],
		[ValidBetAmount] [money],
		HouseContribution  [money],
		FullContribution   [money]
	)

	-- Collect data of 3rd party products (API source) -- ProductID 10, 31
	CREATE TABLE #tmpData (
		rptDate			DATE,
		CustID			INT,
		ProductID		INT,
		CurrencyId		INT,
		Winlost			MONEY,
		Turnover		MONEY,
		BetCount		INT,
		PlayerComm		MONEY,
		AgentComm		MONEY,
		ValidBetAmount	MONEY,
		GrossWL			MONEY,
		Bettype			SMALLINT,
		JpContribution	MONEY)

		---- ProductID = 31
		INSERT INTO #tmpData (
				rptDate,
				CustID,
				ProductID,
				CurrencyId,
				Winlost,
				GrossWL,
				Turnover,
				BetCount,
				PlayerComm,
				AgentComm,
				ValidBetAmount)
		EXEC bodb02.dbo.Acc_Rpt_rptDepWinlost_ThirdParty_Bettrans @winlostdate = @WinLostDate
		

		---- ProductID = 11	
		INSERT INTO #tmpData (
				rptDate,
				CustID,
				ProductID,
				CurrencyId,
				Winlost,
				Turnover,
				BetCount,
				PlayerComm,
				Bettype,
				JpContribution)
		EXEC bodb02.dbo.Acc_Rpt_rptDepWinlost_AGCasino_Bettrans @winlostdate = @WinLostDate

		INSERT INTO #rpt_BettingByProduct
			([rptDate]
			,[SiteID]
			,[ProductID]
			,[Bettype]
			,[CurrencyId]
			,[StatusId]
			,[CustomerCategory]
			,[MemberWL]
			,[Turnover]
			,[CommissionA]
			,[CommissionP]
			,[BuyBackAmount]
			,[HouseContribution]
			,[FullContribution]
			)
		SELECT td.rptDate
			, ISNULL(site.SiteID,-1) AS SiteId
			, td.productId
			, ISNULL(td.Bettype, -1) AS bettype
			, td.CurrencyId
			, CASE 
				WHEN td.Winlost > 0 THEN 112
				WHEN td.Winlost < 0 THEN 113
				ELSE 111
			  END AS StatusId
			, -1 AS CustomerCategory
			, SUM(ISNULL(td.Winlost,0)) AS MemberWL
			, SUM(ISNULL(td.Turnover,0)) AS Turnover
			, SUM(ISNULL(td.AgentComm,0)) AS CommissionA
			, SUM(ISNULL(td.PlayerComm,0)) AS CommissionP
			, 0 AS BuyBackAmount
			, 0 AS [HouseContribution]
			, SUM(ISNULL(td.JpContribution,0)) AS FullContribution
		
		FROM #tmpData td WITH (NOLOCK)
			LEFT JOIN bodb02.dbo.Customer AS c WITH (NOLOCK) ON c.Custid = td.CustID AND c.roleid = 1
			LEFT JOIN bodb02.dbo.customer AS ag WITH (NOLOCK) ON c.recommend = ag.custid AND ag.roleid = 2
			LEFT JOIN bodb02.dbo.Site AS ibcsite WITH (NOLOCK) ON ag.site = ibcsite.site
			LEFT JOIN bodb_Licensee.dbo.view_site_list AS [site] WITH (NOLOCK) ON ibcsite.SiteID = site.IbcSiteID
		GROUP BY rptDate
			, ISNULL(site.SiteID,-1)
			, ISNULL(td.Bettype, -1)
			, td.productId
			, td.CurrencyId
			, CASE 
				WHEN td.Winlost > 0 THEN 112
				WHEN td.Winlost < 0 THEN 113
				ELSE 111
			  END

	--- Final result
	SELECT	rptDate, 
			LicenseeId = SiteId, 
			CurrencyId, 
			Product3rdId = ProductId
			,BetTypeGroup	= Bettype
			,ValidBetAmount	= SUM(CASE WHEN ProductId = 11 AND bettype = -1 THEN ValidBetAmount ELSE 0 END)
			,MemberWL		= SUM(CASE WHEN ProductId = 15 THEN Turnover * 0.0405 + BuyBackAmount * 0.15 ELSE MemberWL END)
			,Comm			= SUM(CASE WHEN ProductId = 31 THEN CommissionP + CommissionA ELSE 0 END)
			,LicenseeWL		= -SUM(MemberWL)
			,LicenseeTO		= SUM(Turnover)
			,ExchangePlayerComm	= SUM(CASE WHEN ProductId = 31 THEN CommissionP ELSE 0 END)
			,HouseContribution = 0
		    ,FullContribution = SUM(FullContribution)
	FROM #rpt_BettingByProduct WITH (NOLOCK)
	WHERE ProductId IN (10, 31)
		AND CurrencyId <> 20
		AND CustomerCategory NOT IN (27, 28)
		AND StatusId NOT IN (-1, 101, 102, 103)
		AND (SiteId <= 1000 OR SiteID >= 50000) -- Deposit only
	GROUP BY rptDate, SiteId, CurrencyId, ProductId, Bettype

	DROP TABLE #tmpData
	DROP TABLE #rpt_BettingByProduct

END

GO
/*<info serverAlias="DBEXT-bodb02" isFunction="0" executers="bodbAdminNet" isNested="1"></info>*/
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
		Bettype			SMALLINT)
	
	---- Get data rpt_Betting  -- ProductID 15
	CREATE TABLE #rpt_Betting(
			[rptDate] [datetime] NOT NULL,
			[SiteID] [int] NOT NULL,
			[Bettype] [smallint] NOT NULL,
			[CurrencyID] [int] NOT NULL,
			[Status] [smallint] NOT NULL,
			[Turnover] [money] NULL,
			[WinLoss] [money] NULL,
			[CommissionP] [money] NULL,
			[CommissionA] [money] NULL,
			[CustomerCategory] [smallint] NULL,
			[BuyBackAmount] [money] NULL,
			[oddsspread] [money] NULL
	)
	INSERT INTO #rpt_Betting (rptDate,SiteID,Bettype,CurrencyID,Status,Turnover,WinLoss,CommissionP,CommissionA,CustomerCategory,BuyBackAmount,oddsspread)
	SELECT  b.winlostdate AS  rptDate,
			ISNULL(s.SiteID, -1) AS siteid,
			b.bettype AS bettype,
			b.currency AS CurrencyID,
			b.statusID  AS statusid,
			SUM(ABS(b.stake)) AS Turnover,
			SUM(b.winlost - b.actual_stake) AS winloss,
			SUM(b.playercomm) AS commissionP,
			SUM(b.comm) AS commissionA,
			CASE
				WHEN b.recommend = 52466 THEN 27 -- 8RM
				WHEN b.recommend = 5707545 THEN 28 -- BARM
				ELSE -1
			END AS customercategory,
			SUM(ISNULL(bm.CashInAmount,0)) AS BuyBackAmount,
			SUM(ISNULL(b.oddsspread,0)) AS oddsspread
	FROM bodb02.dbo.bettrans b (NOLOCK)
	OUTER APPLY (
			SELECT SUM(CASE WHEN bm.bettype = 18002 THEN bm.oddsspread ELSE 0 END) AS CashInAmount
			FROM bodb02.dbo.bettransm bm WITH (NOLOCK)
			WHERE b.refno = bm.refno
				AND bm.bettype BETWEEN 18000 AND 18006
		) bm
	LEFT JOIN bodb02.dbo.customer ag WITH (NOLOCK) ON b.recommend = ag.custid AND ag.roleid = 2
	LEFT JOIN bodb_Licensee.dbo.view_site_list s WITH (NOLOCK) ON s.SiteName = ag.site
	WHERE  b.bettype IN (18000, 1801, 1802, 1803, 1804, 8000, 8001)
		AND b.winlostdate =  @WinLostDate
		AND b.custid > 0
		AND b.recommend > 0
		AND b.statusid NOT IN (0, 101, 102, 121) -- exclude waiting, reject, void ticket (statusID = 1)
	GROUP BY b.winlostdate, ISNULL(s.SiteID, -1)
		,b.bettype
		,b.currency
		,b.statusid
		,CASE
				WHEN b.recommend = 52466 THEN 27 -- 8RM
				WHEN b.recommend = 5707545 THEN 28 -- BARM
				ELSE -1
		END

	--- ProductID = 15
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
			,[ValidBetAmount]

			)
		SELECT
			b.rptDate
			,b.SiteID
			,15 AS ProductID
			,b.Bettype AS Bettype
			,b.CurrencyID
			,b.Status AS StatusId
			,ISNULL([CustomerCategory],-1)
			,SUM(ISNULL(b.WinLoss, 0)) [MemberWL]
			,SUM(ISNULL([Turnover], 0)) [Turnover]
			,SUM(ISNULL([CommissionA], 0)) [CommissionA]
			,SUM(ISNULL([CommissionP], 0)) [CommissionP]
			,SUM(ISNULL([BuyBackAmount], 0)) [BuyBackAmount]
			,SUM(ISNULL([oddsspread], 0)) [ValidBetAmount]

		FROM #rpt_Betting b WITH (NOLOCK)
		WHERE b.Status IN (111,112,113,114,115,101,102,103)
			AND b.CurrencyID <> 20
			AND Bettype = 18000
		GROUP BY b.rptDate
			,b.SiteID
			,b.Bettype
			,b.CurrencyID
			,b.Status
			,ISNULL(b.CustomerCategory,-1)

	
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
		

		---- ProductID = 10	
		INSERT INTO #tmpData (
				rptDate,
				CustID,
				ProductID,
				CurrencyId,
				Winlost,
				Turnover,
				BetCount,
				PlayerComm)
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
			,BetTypeGroup	= CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END
			,ValidBetAmount	= SUM(CASE WHEN ProductId = 11 AND bettype = -1 THEN ValidBetAmount ELSE 0 END)
			,MemberWL		= SUM(CASE WHEN ProductId = 15 THEN Turnover * 0.0405 + BuyBackAmount * 0.15 ELSE MemberWL END)
			,Comm			= SUM(CASE WHEN ProductId = 31 THEN CommissionP + CommissionA ELSE 0 END)
			,LicenseeWL		= -SUM(MemberWL)
			,LicenseeTO		= SUM(Turnover)
	FROM #rpt_BettingByProduct WITH (NOLOCK)
	WHERE ProductId IN (10, 11, 15, 31)
		AND CurrencyId <> 20
		AND CustomerCategory NOT IN (27, 28)
		AND StatusId NOT IN (-1, 101, 102, 103)
		AND SiteId < 1000 -- Deposit only
	GROUP BY rptDate, SiteId, CurrencyId, ProductId, CASE WHEN bettype = 1706 THEN 1706 ELSE -1 END

	DROP TABLE #tmpData
	DROP TABLE #rpt_BettingByProduct
	DROP TABLE #rpt_Betting

END

GO
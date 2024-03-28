/*<info serverAlias="DBACC-bodb02" isFunction="0" executers="bodbAdminNet" isNested="1"></info>*/
ALTER PROCEDURE [dbo].Acc_rpt_ThirdPartyWL_ExtraGMT_Bettrans
	@Winlostdate SMALLDATETIME,
	@DepositType TINYINT = 2
AS
/*
	 Created: 20210420@Danny
	 Task: Generate data for MicroGaming Casino
	 DB: DBACC-bodb02
	 Revisions: 
		- 20210413@Danny: Initialize SP [RedmineID: #151993]
		- 20211102@Danny: SG integrate JP, Contribution (#166684)
		- 20220325@Danny: Incorporate FGG (#170522)
		- 20231027@Danny: Change LicenseeID detection formulary of deposit licensee [#183209]
		- 20230522@Danny: Incorporate YeeBet (#186481)
        - 20230817@Ned.Le: Remove currency test
		- 20240305@Danny: Incorporate UU Slots (#192594)
		- 20240328@Danny: Incorporate Yolo (#201590)

	 Param's Explanation:

	 exec Acc_rpt_ThirdPartyWL_ExtraGMT_Bettrans @Winlostdate = '2021-05-12', @DepositType = 2 
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate SMALLDATETIME 
	DECLARE @TDate SMALLDATETIME

	SELECT @FDate = DATEADD(DAY, -1, @Winlostdate), @TDate = DATEADD(DAY, 1, @Winlostdate)
	
	CREATE TABLE #rpt_ThirdPartyWL_ExtraGMT(
				[RptDate] [date] NOT NULL,
				[RptDate3rd] [date] NOT NULL,
				[SiteId] [int] NOT NULL,
				[BetTypeId] [int] NOT NULL,
				[CurrencyId] [int] NULL,
				[StatusId] [int] NOT NULL,
				[Winloss] [money] NOT NULL,
				[ProgressiveContribution] [money] NOT NULL,
				[ValidBetAmount] [money] NULL
				)
	
	DECLARE @RnGBettypeList TABLE(Bettype INT)
	INSERT INTO @RnGBettypeList(Bettype)
	SELECT bettype FROM OPENQUERY (DBLIC, 'SELECT	DISTINCT bettype FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,''FW,PP,CC,SG,JK,CG,MGRNG,JIG,L22,UUSL,YOL'') la')

	DECLARE @LCBettypeList TABLE(Bettype INT)
	INSERT INTO @LCBettypeList(Bettype)
	SELECT bettype FROM OPENQUERY (DBLIC, 'SELECT	DISTINCT bettype FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,''AB,SXG,SAG,WM,PPL,FGGL,YB'') la')


	INSERT INTO #rpt_ThirdPartyWL_ExtraGMT(	RptDate,RptDate3rd ,SiteId,BetTypeId,CurrencyId,StatusId,Winloss,ProgressiveContribution,ValidBetAmount)
	SELECT CAST(b.winlostdate AS DATE)	AS Rptdate,
			CAST(b.Transdate3rd AS DATE)	AS RptDate3rd
		, ISNULL(site.SiteID, -1) AS siteid
		, b.gameID	 AS BetTypeId		
		, b.currency
		, b.statusID
		, SUM(winlost - actual_stake) AS Winloss		
		, SUM(CASE WHEN b.gameID IN (4297, 4599) THEN ContributionStake3rd ELSE 0 END) AS ProgressiveContribution -- Full Contribution(PP-4297)
		, 0 AS ValidBetAmount
	FROM bodb02.dbo.bettransRnG b WITH (NOLOCK)
		LEFT JOIN DBTXN.bodb02.dbo.PayoutTrans p ON b.transid = p.RefNo
		LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
		LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
		LEFT JOIN bodb_licensee.dbo.view_site_list [site] (NOLOCK) ON s.siteid = site.IbcSiteID			
	WHERE b.winlostdate  BETWEEN @FDate AND  @TDate
		AND b.Transdate3rd >= @Winlostdate AND b.Transdate3rd < @TDate
		AND b.statusID NOT IN (0, 1, 101, 102, 121)
		AND b.gameID IN (SELECT x.Bettype FROM @RnGBettypeList x)
        AND b.currency <> 20
	GROUP BY CAST(b.winlostdate AS DATE), 
			CAST(b.Transdate3rd AS DATE), 
			ISNULL(site.SiteID, -1), 
			b.gameID, 
			b.currency, 
			b.statusID

	UNION

	SELECT CAST(b.winlostdate AS DATE)	AS Rptdate,
		  CAST(b.Transdate3rd AS DATE) AS RptDate3rd
		, ISNULL(site.SiteID, -1) AS siteid
		, b.gameID AS BetTypeId		
		, b.currency
		, b.statusID
		, SUM(winlost - actual_stake) AS Winloss		
		, 0 AS ProgressiveContribution
		, SUM(ISNULL(b.NetStake, 0)) AS ValidBetAmount
	FROM bodb02.dbo.bettransLC b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
		LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
		LEFT JOIN bodb_licensee.dbo.view_site_list  [site] (NOLOCK) ON s.siteid = site.IbcSiteID			
	WHERE 
		b.winlostdate  BETWEEN @FDate AND  @TDate
		AND b.Transdate3rd >= @Winlostdate AND b.Transdate3rd < @TDate 
		AND b.statusID NOT IN (0, 1, 101, 102, 121)
		AND b.gameID IN (SELECT x.Bettype FROM @LCBettypeList x)
        AND b.currency <> 20
	GROUP BY CAST(b.winlostdate AS DATE), 
			CAST(b.Transdate3rd AS DATE), 
			ISNULL(site.SiteID, -1),
			b.gameID, 
			b.currency, 
			b.statusID	


	SELECT RptDate3rd, SiteId, BetTypeId, CurrencyId, SUM(Winloss) Winloss, SUM(ValidBetAmount) ValidBetAmount, SUM(ProgressiveContribution) ProgressiveContribution
	FROM #rpt_ThirdPartyWL_ExtraGMT WITH (NOLOCK)
	WHERE CurrencyID <> 20
		AND StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		AND (
			@DepositType = 2
			OR (@DepositType = 0 AND ((SiteId > 1000 OR SiteId < 50000) OR SiteID = 509))
			OR (@DepositType = 1 AND ((SiteId <= 1000 OR SiteId >= 50000) AND SiteID <> 509))
		)
	GROUP BY RptDate3rd, SiteId, BetTypeId, CurrencyId
		

	DROP TABLE #rpt_ThirdPartyWL_ExtraGMT

END

    

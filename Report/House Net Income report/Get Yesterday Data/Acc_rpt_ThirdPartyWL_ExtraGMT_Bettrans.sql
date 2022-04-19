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
		AND (b.gameID BETWEEN 1011 AND 1020 -- FW
			OR b.gameID BETWEEN 4101 AND 4300 -- PP
			OR b.gameID BETWEEN 6701 AND 7000 -- PP
			OR b.gameID BETWEEN 1901 AND 1999 -- CC
			OR b.gameID BETWEEN 4301 AND 4600 -- SG
			OR b.gameID BETWEEN 6401 AND 6700 -- JK
			OR  b.gameID BETWEEN 7301 AND 7600 -- CG
		)
	GROUP BY CAST(b.winlostdate AS DATE), 
			CAST(b.Transdate3rd AS DATE), 
			ISNULL(site.SiteID, -1), 
			b.gameID, 
			b.currency, 
			b.statusID

	UNION

	SELECT CAST(b.winlostdate AS DATE)	AS Rptdate,
		 CASE WHEN b.gameID BETWEEN 5701 AND 5704 THEN CAST(b.winlostdate AS DATE) ELSE CAST(b.Transdate3rd AS DATE) END AS RptDate3rd
		, ISNULL(site.SiteID, -1) AS siteid
		, CASE WHEN b.gameID BETWEEN 5701 AND 5704 THEN -59 ELSE b.gameID END AS BetTypeId		
		, b.currency
		, b.statusID
		, SUM(winlost - actual_stake) AS Winloss		
		, 0 AS ProgressiveContribution
		, SUM(ISNULL(b.NetStake, 0)) AS ValidBetAmount
	FROM bodb02.dbo.bettransLC b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
		LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
		LEFT JOIN bodb_licensee.dbo.view_site_list  [site] (NOLOCK) ON s.siteid = site.IbcSiteID			
	WHERE (
			(	b.winlostdate  BETWEEN @FDate AND  @TDate
				AND b.Transdate3rd >= @Winlostdate AND b.Transdate3rd < @TDate AND  b.gameID NOT BETWEEN 5701 AND 5704
			)
			OR
			(
				b.winlostdate = @Winlostdate AND  b.gameID BETWEEN 5701 AND 5704 -- GDG
			)
		)
		AND b.statusID NOT IN (0, 1, 101, 102, 121)
		AND (
				b.gameID BETWEEN 2401 AND 2499 -- AllBet
			OR  b.gameID BETWEEN 3101 AND 3150 -- SXG
			OR  b.gameID BETWEEN 3001 AND 3099 -- SAG
			OR  b.gameID BETWEEN 3401 AND 3499 -- WM
			OR  b.gameID BETWEEN 3701 AND 3799 -- PPL
			OR  b.gameID BETWEEN 5701 AND 5704 -- GDG
			OR  b.gameID BETWEEN 8201 AND 8299 -- FGG
			) 
	GROUP BY CAST(b.winlostdate AS DATE), 
			CASE WHEN b.gameID BETWEEN 5701 AND 5704 THEN CAST(b.winlostdate AS DATE) ELSE CAST(b.Transdate3rd AS DATE) END, 
			ISNULL(site.SiteID, -1), CASE WHEN b.gameID BETWEEN 5701 AND 5704 THEN -59 ELSE b.gameID END
		, b.currency, b.statusID	


	SELECT RptDate3rd, SiteId, BetTypeId, CurrencyId, SUM(Winloss) Winloss, SUM(ValidBetAmount) ValidBetAmount, SUM(ProgressiveContribution) ProgressiveContribution
	FROM #rpt_ThirdPartyWL_ExtraGMT WITH (NOLOCK)
	WHERE CurrencyID <> 20
		AND StatusId NOT IN(-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		AND (
			@DepositType = 2
			OR (@DepositType = 0 AND (SiteId > 1000 OR SiteID = 509))
			OR (@DepositType = 1 AND (SiteId < 1000 AND SiteID <> 509))
		)
	GROUP BY RptDate3rd, SiteId, BetTypeId, CurrencyId
		

	DROP TABLE #rpt_ThirdPartyWL_ExtraGMT

END

    

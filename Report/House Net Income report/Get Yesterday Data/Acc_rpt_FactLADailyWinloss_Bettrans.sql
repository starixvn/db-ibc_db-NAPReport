/*<info serverAlias="DBACC-bodb02" isFunction="0" executers="wsv_nap" isNested="1"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_FactLADailyWinloss_Bettrans
	@winlostdate SMALLDATETIME
AS
/*
	Created: 20210413@Danny
	Task: Gen data for licensee bettrans staging
	DB: DBACC.bodb02

	Revisions:
		- 20210413@Danny: Initialize SP [RedmineID: #151993]
		- 20220211@Danny: Email/Letstalk Reports - Incorporate Saba Basketball Soccer PinGoal (#168373)
		- 20220310@Danny: get SB bettype dynamically (#169768)
		- 20221206@Danny: Incorporate Saba E-Sports PinGoal (#181261)
		- 20230821@Danny: Integrate Parlay Boost Bonus (#192894)
		- 20240416@Danny: Integrate Saba Coins Wallet (#203365)
		- 20240605@Danny: Letstalk reports - Integrate the Saba Kabaddi (#204927)
		- 20240920@Danny: Email/Letstalk - Odds Boost Voucher (#210559)
		- 20241126@Danny: exclude NovaCasino site (#213501)
		- 20250508@Aries: HNI - Saba Soccer Pingoal Marble Product [Redmine:#225685]

	Exec Acc_Rpt_FactLADailyWinloss_Bettrans '2021-05-19'

*/
BEGIN
	SET NOCOUNT ON
--Get Bettype List
	DECLARE @Bettype_SB_BA TABLE (bettype SMALLINT)
	INSERT INTO @Bettype_SB_BA(bettype)
	SELECT DISTINCT  bettype FROM bodb02.dbo.SportBettypeMatrix WIHT(NOLOCK)
	WHERE productID = 1 AND bettype NOT IN (901,902,903,904) 

	DECLARE @DWH_SabaCoins_SiteID INT
	

	-- #tmpDW_tblsite
	CREATE TABLE #tmpDW_tblsite (
		[siteid] [int] NOT NULL,
		[site] [varchar](20) NOT NULL,
		[isDeposit] [bit] NULL
	)

	INSERT INTO #tmpDW_tblsite (siteid, site, isDeposit)
	SELECT siteid, site, isDeposit
	FROM OPENQUERY(DBWH, 'SELECT si_dw.siteid, si_dw.site, si_dw.isDeposit FROM bodb_Account.dbo.tbl_Site si_dw WITH (NOLOCK)')
	CREATE CLUSTERED INDEX CIX_tmpDW_tblsite ON #tmpDW_tblsite(site)


	SELECT @DWH_SabaCoins_SiteID = siteid
	FROM #tmpDW_tblsite
	WHERE site = 'SabaCoins'

	-- #tmpGameEvent
	CREATE TABLE #tmpGameEvent(
		MatchID 	INT NOT NULL,
		EventType 	TINYINT NOT NULL,
		EventDate	SMALLDATETIME,
		LeagueID 	INT,
		sporttype 	SMALLINT,
		LeagueGroupId INT
	)	
	
	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, sporttype, LeagueGroupId)
	SELECT m.matchid					MatchID,
		   1							EventType,
		   m.eventdate					EventDate,
		   m.leagueid					LeagueID,
		   l.sporttype					sporttype,
		   l.LeagueGroupId				LeagueGroupId
	FROM bodb02.dbo.match m WITH (NOLOCK)
		 LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON m.leagueid = l.leagueid
	WHERE m.eventdate = @winlostdate

	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, sporttype, LeagueGroupId)
	SELECT o.orid						MatchID,
		   2							EventType,
		   o.eventdate					EventDate,
		   o.leagueid					LeagueID,
		   l.sporttype					SportID,
		   l.LeagueGroupId				LeagueGroupId
	FROM bodb02.dbo.outright o WITH (NOLOCK)
		 LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
	WHERE o.eventdate = @winlostdate

	CREATE CLUSTERED INDEX CIX_tmpGameEvent ON #tmpGameEvent(MatchID, EventType)


	CREATE TABLE #tmpDW_BettypeGroup (
    [BettypeGroupID] [smallint] NOT NULL,
    [Bettype]        [int]      NOT NULL
    )

    INSERT INTO #tmpDW_BettypeGroup (BettypeGroupID, Bettype)
    SELECT t.BettypeGroupID, t.Bettype
    FROM DBWH.bodb_Account.dbo.BettypeGroup t WITH (NOLOCK) WHERE BettypeGroupID = 19

	SELECT
			b.winlostdate rptDate,
			ISNULL(si_oltp.siteid,-1) SiteId,
			b.currency CurrencyId,
			CASE WHEN BA.transid IS NOT NULL THEN 3 ELSE 0 END productID,
			CASE
				WHEN b.bettype = 29 THEN -10 --Parlay
				WHEN tmp.LeagueGroupId IN (42, 74, 108) AND tmp.SportType = 1 THEN -3 -- Saba Soccer
				WHEN tmp.LeagueGroupId IN (113,252) AND tmp.SportType = 1 THEN -14 -- Saba Soccer PinGoal
				WHEN tmp.LeagueGroupId = 122 AND tmp.SportType = 2 THEN -15 --Saba Bas PGoal
				WHEN tmp.LeagueGroupId IN (42) AND tmp.SportType = 2 THEN -5 -- Saba Basketball
				WHEN tmp.LeagueGroupId IN (151) AND tmp.SportType = 43 THEN -16 --Saba E-S PGoal
				WHEN tmp.LeagueGroupId IN (42) AND tmp.SportType IN (47,50) THEN -17 -- Saba Cri & Kab
				WHEN tmp.LeagueGroupId IN (42,74,108,113,122,151,252) THEN -18 --Saba OS
				WHEN tmp.Sporttype = 1 THEN -2 -- Soccer
				WHEN tmp.Sporttype = 2 THEN -4 -- Basketball
				WHEN tmp.Sporttype = 5 THEN -6 -- Tennis
				WHEN tmp.Sporttype = 43 THEN -7 -- E-Sports
				WHEN tmp.SportType IN (47,50)  THEN -8  --Cri & Kab
				ELSE -9 -- OS
			END AliasProductId,
			SUM(CASE WHEN si_oltp.siteid = @DWH_SabaCoins_SiteID THEN 0 ELSE b.winlost-b.actual_stake END) MemberWL,
			SUM(CASE WHEN tb.BettypeGroupID = 19 THEN b.awinlost ELSE 0 END)  OddsSpreadAdj,
			SUM(CASE WHEN BA.transid IS NOT NULL THEN b.comm ELSE 0 END) Comm,
			-SUM(CASE WHEN BA.transid IS NULL AND si_oltp.siteid <> @DWH_SabaCoins_SiteID THEN b.winlost-b.actual_stake ELSE 0 END) LicenseeWL,
			SUM(CASE WHEN BA.transid IS NULL  AND si_oltp.siteid <> @DWH_SabaCoins_SiteID THEN
				 CASE WHEN b.statusID = 111 THEN 0 
					 ELSE b.stake * CASE WHEN b.modds IN (-0.25, 0.25)  AND b.statusID IN (112, 113,252)  THEN 0.5 ELSE 1 END
					
				 END ELSE 0 END) AS LicenseeTO,
			SUM(CASE WHEN b.bettype = 29 AND b.statusID = 112 AND b.oddsspread =2 THEN TRY_CAST(TRY_CAST(ExtraInfo AS XML).value('(/p1/@bba)[1]',  'VARCHAR(50)') AS DECIMAL(19, 6)) ELSE 0 END) FullParlayBoostBonus,
		    SUM(CASE WHEN b.bettype = 29 AND b.statusID = 112 AND b.oddsspread =2 THEN TRY_CAST(TRY_CAST(ExtraInfo AS XML).value('(/p1/@bba)[1]',  'VARCHAR(50)') AS DECIMAL(19, 6)) * TRY_CAST(TRY_CAST(ExtraInfo AS XML).value('(/p1/@lbbs)[1]', 'VARCHAR(50)') AS DECIMAL(19, 6)) ELSE 0 END) AgentParlayBoostBonusSharing,
			SUM(CASE WHEN si_oltp.siteid = @DWH_SabaCoins_SiteID THEN -(b.winlost-b.actual_stake) ELSE 0 END) SabaCoinPerf
	FROM bodb02.dbo.bettrans b (NOLOCK)
	INNER JOIN  bodb02.dbo.Dep_CustSuper d (NOLOCK) ON  b.srecommend = d.custid
	INNER JOIN  @Bettype_SB_BA bt ON b.bettype = bt.bettype
	LEFT JOIN	bodb_licensee.dbo.LicenseeBATransaction_active  BA WITH(NOLOCK) ON  b.transid = BA.TransID
	LEFT JOIN	#tmpGameEvent tmp ON b.matchid = tmp.MatchID AND tmp.EventType = CASE WHEN b.bettype = 10 THEN 2 ELSE 1 END
	LEFT JOIN	#tmpDW_tblsite si_oltp WITH (NOLOCK) ON d.site = si_oltp.site
	LEFT JOIN	#tmpDW_BettypeGroup tb ON b.bettype = tb.Bettype
	WHERE b.winlostdate = @winlostdate
		  AND b.statusID IN (111, 112, 113,252)
		  AND d.[site] NOT IN ('Saba789','Seal888','NovaCasino') -- Remove Saba789
		  AND b.Currency <> 20
	GROUP BY	b.winlostdate, 
				b.currency,
				CASE WHEN BA.transid IS NOT NULL THEN 3 ELSE 0 END,
				ISNULL(si_oltp.siteid,-1),
				CASE
					WHEN b.bettype = 29 THEN -10 --Parlay
					WHEN tmp.LeagueGroupId IN (42, 74, 108) AND tmp.SportType = 1 THEN -3 -- Saba Soccer
					WHEN tmp.LeagueGroupId IN (113,252) AND tmp.SportType = 1 THEN -14 -- Saba Soccer PinGoal
					WHEN tmp.LeagueGroupId = 122 AND tmp.SportType = 2 THEN -15 --Saba Bas PGoal
					WHEN tmp.LeagueGroupId IN (42) AND tmp.SportType = 2 THEN -5 -- Saba Basketball
					WHEN tmp.LeagueGroupId IN (151) AND tmp.SportType = 43 THEN -16 --Saba E-S PGoal
					WHEN tmp.LeagueGroupId IN (42) AND tmp.SportType IN (47,50) THEN -17 -- Saba Cri & Kab
					WHEN tmp.LeagueGroupId IN (42,74,108,113,122,151,252) THEN -18 --Saba OS
					WHEN tmp.Sporttype = 1 THEN -2 -- Soccer
					WHEN tmp.Sporttype = 2 THEN -4 -- Basketball
					WHEN tmp.Sporttype = 5 THEN -6 -- Tennis
					WHEN tmp.Sporttype = 43 THEN -7 -- E-Sports
					WHEN tmp.SportType IN (47,50)  THEN -8  --Cri & Kab
					ELSE -9 -- OS
				END
	
	---- DROP TEMP TABLE
	DROP TABLE #tmpDW_tblsite
	DROP TABLE #tmpGameEvent
	DROP TABLE #tmpDW_BettypeGroup

END
/*<info serverAlias="DBACC-bodb02" executers="dwrs" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_Credit_Bettrans @winlostdate DATE,
                                                           @bettypeList VARCHAR(MAX)
    
AS

/*
    Creator: Ned.Le  
    Date: 2021-03-22
    Task: Get yesterday data from bettrans|bettransLC|bettransRNG for HNI report
    DB: DBACC.bodb02
    
    Revisions:  
        20210331@Ned.Le: Email/Letstalk Reports - Change Data Source to retrieve yesterday data from DW into Bettrans table (#151993)
        20220310@Ned.Le: Email/Letstalk Reports - Include 8RM/BARM into Bet Count, member turnover, member win loss, Margin except House Income (#169768)
        20230817@Ned.Le: Remove currency test
        20240123@Ned.Le: Email/Letstalk - Virtual Sports 4 - Edge Gaming (#198628)
        20240206@Ned.Le: AG Casino - Email/Letstalk Reports - Add promotion & Jackpot bet type (#200523)
        20240403@Ned.Le: Fix code to calculate ContributionStake3rd from bettrans
        20240913@Ned.Le: Email/Letstalk - Odds Boost Voucher (#210559)
		20241030@Roy: Email/Letstalk - Integrate VS6 (#212749)
		20241226@Roy: Email/Letstalk - Offer Direct Member for Super and Master (#215045)

    Param's Explanation:
        @winlostdate: The date to get data
        @bettypeList: List of bettypes be used to filter data

    Executes SP:
        EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_Credit_Bettrans @winlostdate = '2021-03-18',
                                                               @bettypeList = '1,3,7,8'
*/

BEGIN

    SET NOCOUNT ON


    ---------------------------------------------------------
    -- CODE LAYOUT                                         --
    ---------------------------------------------------------
    --                                                     --
    -- 1. Prepare meta data                                --
    --                                                     --
    -- 2. Get raw data from bettrans|betransLC|bettransRNG --
    --                                                     --
    -- 3. Cleaning raw data                                --
    --                                                     --
    -- 4. Get final data that can be used for report       --
    --                                                     --
    -- 5. Return final data                                --
    --                                                     --
    -- 6. Drop temp tables                                 --
    --                                                     --
    ---------------------------------------------------------


    --------------------------
    -- 1. Prepare meta data --
    --------------------------

    -- #tmpBettypeList
	CREATE TABLE #tmpBettypeList (Bettype INT)

	INSERT INTO #tmpBettypeList (Bettype)
	SELECT TRY_CONVERT(INT, value) AS Bettype
	FROM STRING_SPLIT(@bettypeList, ',')
	WHERE TRY_CONVERT(INT, value) IS NOT NULL
    CREATE CLUSTERED INDEX CIX_tmpBettypeList ON #tmpBettypeList(Bettype)

    -- #tmpHalfWonLoseBettype
    CREATE TABLE #tmpHalfWonLoseBettype (Bettype INT)

    INSERT INTO #tmpHalfWonLoseBettype (Bettype)
    SELECT DISTINCT BetType
    FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
    WHERE ProductID = 1
          AND BetType NOT IN (29, 38, 901, 902 ,903, 904, 18999)
    
    CREATE CLUSTERED INDEX CIX_tmpHalfWonLoseBettype ON #tmpHalfWonLoseBettype(Bettype)
	
	-- #tmpDW_BettypeSource
    CREATE TABLE #tmpDW_BettypeSource (typeid INT, SourceTable VARCHAR(50))

    INSERT INTO #tmpDW_BettypeSource (typeid, SourceTable)
    SELECT typeid, SourceTable FROM DBWH.bodb_Account.dbo.Bettype WITH(NOLOCK)

    CREATE CLUSTERED INDEX CIX_tmpDW_BettypeSource ON #tmpDW_BettypeSource(typeid)

    DELETE b
    FROM #tmpDW_BettypeSource b
    WHERE b.typeid IN (901 ,902, 911, 912)

    DELETE b
    FROM #tmpDW_BettypeSource b
    WHERE b.typeid NOT IN (SELECT Bettype FROM #tmpBettypeList)

    -- #tmpDW_ProductBettype
    CREATE TABLE #tmpDW_ProductBettype (
        [ProductID] [int]      NOT NULL,
        [Bettype]   [smallint] NOT NULL,
        [EventType] [tinyint]  NULL,
        [sporttype] [smallint] NULL,
    )

    INSERT INTO #tmpDW_ProductBettype (ProductID, Bettype, EventType, sporttype)
    SELECT pb.ProductID, pb.Bettype, pb.EventType, pb.sporttype
    FROM DBWH.bodb_Account.dbo.Product_Bettype pb WITH (NOLOCK)

    CREATE CLUSTERED INDEX CIX_tmpDW_ProductBettype ON #tmpDW_ProductBettype(Bettype, EventType, ProductID)
	
    -- #tmpDW_tblstatus
    CREATE TABLE #tmpDW_tblstatus (
        [statusid] [int]         NOT NULL,
        [status]  [nvarchar](10) NOT NULL,
    )

    INSERT INTO #tmpDW_tblstatus (statusid, status)
    SELECT st.statusid, st.status
    FROM DBWH.bodb_Account.dbo.tbl_Status st WITH (NOLOCK)

    CREATE CLUSTERED INDEX CIX_tmpDW_tblstatus ON #tmpDW_tblstatus(status)

    -- #tmpDW_BettypeGroup
    CREATE TABLE #tmpDW_BettypeGroup (
        [BettypeGroupID] [smallint] NOT NULL,
        [Bettype]        [int]      NOT NULL
    )

    INSERT INTO #tmpDW_BettypeGroup (BettypeGroupID, Bettype)
    SELECT t.BettypeGroupID, t.Bettype
    FROM DBWH.bodb_Account.dbo.BettypeGroup t WITH (NOLOCK)

    CREATE CLUSTERED INDEX CIX_tmpDW_BettypeGroup ON #tmpDW_BettypeGroup(BettypeGroupID, Bettype)

    -- #tmpDW_tblsite
     CREATE TABLE #tmpDW_tblsite (
		SiteID_DW INT
		,Site VARCHAR(10)
	)

    INSERT INTO #tmpDW_tblsite (SiteID_DW, Site)
    SELECT siteid, site
    FROM DBWH.bodb_Account.dbo.tbl_Site WITH (NOLOCK)

    CREATE UNIQUE CLUSTERED INDEX CIX_tmpDW_tblsite ON #tmpDW_tblsite(Site)
	
    -- #tmpOLTP_GameEvent
    CREATE TABLE #tmpOLTP_GameEvent(
        MatchID   INT           NOT NULL,
        EventType TINYINT       NOT NULL,
        EventDate SMALLDATETIME,
        LeagueID  INT,
        SportID   SMALLINT
    )
	
    INSERT INTO #tmpOLTP_GameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
    SELECT m.matchid   MatchID,
           1           EventType,
           m.eventdate EventDate,
           m.leagueid  LeagueID,
           l.sporttype SportID
    FROM bodb02.dbo.match m WITH (NOLOCK)
         LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON m.leagueid = l.leagueid

    INSERT INTO #tmpOLTP_GameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
    SELECT o.orid      MatchID,
           2           EventType,
           o.eventdate EventDate,
           o.leagueid  LeagueID,
           l.sporttype SportID
    FROM bodb02.dbo.outright o WITH (NOLOCK)
         LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid

	/*
		For League3rdId + 1000000000,
		the parent [Acc_Rpt_HouseNetIncome_Credit] use LeagueID to identify [saba sport]
		=> no need exactly League3rdId
		
		(CASE WHEN l3.League3rdId < 1000000000 THEN l3.League3rdId + 1000000000 ELSE l3.League3rdId + 65 END) AS LeagueID
	*/
	INSERT INTO #tmpOLTP_GameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT v.EventID AS MatchID
		,3 AS EventType
		,CAST(v.EventTime AS DATE) AS EventDate
		,v.LeagueID + 1000000000 AS LeagueID
		,l.SportType AS SportID
	FROM bodb02.dbo.VSRaceInfo v WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League3rd l WITH (NOLOCK) ON v.LeagueID = l.League3rdId

	INSERT INTO #tmpOLTP_GameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT m.Match3rdId AS MatchID
		,5 AS EventType
		,m.eventdate AS EventDate
		,m.League3rdId + 1000000000 AS LeagueID
		,l.SportType AS SportID
    FROM bodb02.dbo.Match3rd m WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League3rd l WITH (NOLOCK) ON m.League3rdId = l.League3rdId

    CREATE UNIQUE CLUSTERED INDEX CIX_tmpOLTP_GameEvent ON #tmpOLTP_GameEvent(MatchID, EventType)


    ---------------------------------------------------------
    -- 2. Get raw data from bettrans|betransLC|bettransRNG --
    ---------------------------------------------------------

    -- Create temp table
    CREATE TABLE #tmpbettrans (
        [transid]              [bigint]         NOT NULL,
        [custid]               [int]            NOT NULL,
        [stake]                [money]          NOT NULL,
        [status]               [nvarchar](15)   NULL,
        [winlost]              [money]          NULL,
        [awinlost]             [money]          NULL,
        [mwinlost]             [money]          NULL,
        [tpositiontaking]      [smallmoney]     NULL,
        [betteam]              [nvarchar](10)   NULL,
        [winlostdate]          [DATE]           NULL,
        [actualrate]           [float]          NULL,
        [matchid]              [int]            NULL,
        [recommend]            [int]            NOT NULL,
        [actual_stake]         [money]          NULL,
        [currency]             [tinyint]        NULL,
        [scomm]                [money]          NULL,
        [swinlost]             [money]          NULL,
        [refno]                [bigint]         NULL,
        [virtualrate]          [float]          NULL,
        [bettype]              [int]            NULL,
        [ContributionStake3rd] [decimal](19, 8) NULL,
        [epositiontaking]      [smallmoney]     NULL,
        [NetStake]             [money]          NULL
    )

    -- Get data from bettrans
    INSERT INTO #tmpbettrans WITH (TABLOCK)(
        transid
        ,winlostdate
        ,bettype
        ,custid
        ,betteam
        ,stake
        ,actual_stake
        ,winlost
        ,awinlost
        ,mwinlost
        ,swinlost
        ,scomm
        ,tpositiontaking
        ,matchid
        ,status
        ,actualrate
        ,currency
        ,recommend
        ,refno
        ,virtualrate
        ,ContributionStake3rd
        ,epositiontaking
        ,NetStake
    )
    SELECT
        b.transid
        ,b.winlostdate
        ,b.bettype
        ,b.custid
        ,CASE WHEN b.bettype = 18000 THEN CONVERT(NVARCHAR(10),b.currency2) ELSE b.betteam END AS betteam
        ,b.stake
        ,b.actual_stake
        ,b.winlost
        ,b.awinlost
        ,b.mwinlost + CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN b.swinlost ELSE 0 END AS mwinlost
        ,CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN (winlost - stake) * (1 - tpositiontaking - ISNULL(oddsspread, 0)) ELSE b.swinlost END AS swinlost
        ,b.scomm
        ,CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN 1 - ISNULL(oddsspread, 0) ELSE b.tpositiontaking END AS tpositiontaking
        ,CASE WHEN b.bettype=1003 THEN b.betdaqid ELSE b.matchID END AS matchid        
        ,CASE WHEN h.Bettype IS NOT NULL
                   AND ABS(b.modds) = 0.25
                   AND b.statusID IN (112,113) THEN CONVERT(NVARCHAR(15),'HALF ' + b.[status])
              ELSE CONVERT(NVARCHAR(15), b.[status])
         END AS [status]
        ,b.actualrate
        ,b.currency
        ,b.recommend
        ,b.refno
        ,b.virtualrate
        ,ISNULL(b.betid, 0)/100000000.0 ContributionStake3rd
        ,b.epositiontaking
        ,ISNULL(b.oddsspread,0) NetStake
    FROM bodb02.dbo.bettrans b (NOLOCK)
         LEFT JOIN #tmpHalfWonLoseBettype h ON b.bettype = h.Bettype
    WHERE b.winlostdate = CAST(@winlostdate AS SMALLDATETIME)
          AND b.bettype IN (SELECT typeid FROM #tmpDW_BettypeSource where SourceTable='bettrans')
          AND b.statusID IN (111, 112, 113)
          AND b.currency <> 20
    OPTION (RECOMPILE)

    -- Get data from bettransLC
    INSERT INTO #tmpbettrans WITH (TABLOCK)(
        transid
        ,winlostdate
        ,bettype
        ,custid
        ,betteam
        ,stake
        ,actual_stake
        ,winlost
        ,awinlost
        ,mwinlost
        ,swinlost
        ,scomm
        ,tpositiontaking
        ,matchid
        ,status
        ,actualrate
        ,currency
        ,recommend
        ,refno
        ,virtualrate
        ,ContributionStake3rd
        ,epositiontaking
        ,NetStake
    )
    SELECT
        b.transid
        ,b.winlostdate
        ,b.GameID bettype
        ,b.custid
        ,NULL betteam
        ,b.stake
        ,b.actual_stake
        ,b.winlost
        ,b.awinlost
        ,b.mwinlost
        ,b.swinlost
        ,b.scomm
        ,b.tpositiontaking
        ,b.ProductID matchid
        ,CONVERT(NVARCHAR(15),b.STATUS) status
        ,b.actualrate
        ,b.currency
        ,b.recommend
        ,b.refno
        ,b.virtualrate
        ,NULL ContributionStake3rd
        ,b.epositiontaking
        ,ISNULL(b.NetStake,0) NetStake
    FROM bodb02.dbo.bettransLC b (NOLOCK)
    WHERE b.winlostdate = CAST(@winlostdate AS SMALLDATETIME)
          AND b.gameID IN (SELECT typeid FROM #tmpDW_BettypeSource where SourceTable='bettransLC')
          AND b.StatusID IN (111, 112, 113)
          AND b.currency <> 20
    OPTION (RECOMPILE)

    -- Get data from bettransRNG
    INSERT INTO #tmpbettrans WITH (TABLOCK)(
        transid
        ,winlostdate
        ,bettype
        ,custid
        ,betteam
        ,stake
        ,actual_stake
        ,winlost
        ,awinlost
        ,mwinlost
        ,swinlost
        ,scomm
        ,tpositiontaking
        ,matchid
        ,status
        ,actualrate
        ,currency
        ,recommend
        ,refno
        ,virtualrate
        ,ContributionStake3rd
        ,epositiontaking
        ,NetStake
    )
    SELECT
        b.transid
        ,b.winlostdate
        ,b.GameID bettype
        ,b.custid
        ,NULL betteam
        ,b.stake
        ,b.actual_stake
        ,b.winlost
        ,b.awinlost
        ,b.mwinlost
        ,b.swinlost
        ,b.scomm
        ,b.tpositiontaking
        ,b.ProductID matchid
        ,CONVERT(NVARCHAR(15),b.STATUS) status
        ,b.actualrate
        ,b.currency
        ,b.recommend
        ,b.refno
        ,b.virtualrate
        ,b.ContributionStake3rd
        ,b.epositiontaking
        ,0 NetStake
    FROM bodb02.dbo.bettransRNG b (NOLOCK)
    WHERE b.winlostdate = CAST(@winlostdate AS SMALLDATETIME)
          AND b.gameID IN (SELECT typeid FROM #tmpDW_BettypeSource where SourceTable='bettransRNG')
          AND b.StatusID IN (111, 112, 113)
          AND b.currency <> 20
    OPTION (RECOMPILE)

    CREATE CLUSTERED INDEX CIX_tmpbettrans ON #tmpbettrans(bettype, matchid, CustID)


    --------------------------
    -- 3. Cleaning raw data --
    --------------------------

    -- Clean winlostdate
    -- UPDATE b
    -- SET b.winlostdate = DATEADD(DD, DATEDIFF(DD, 0, b.winlostdate), 0)
    -- FROM #tmpbettrans b WITH (ROWLOCK, UPDLOCK)
    -- WHERE DATEPART(HOUR, b.winlostdate) > 0
          -- OR DATEPART(SECOND, b.winlostdate) > 0
          -- OR DATEPART(MINUTE, b.winlostdate) > 0

    -- Cleaning NG2 (23), Keno(8) and Keno Lottery (28) [matchid = 0]
    UPDATE b
    SET b.matchid = 0
    FROM #tmpbettrans b
         INNER JOIN (SELECT Productid,bettype
                     FROM bodb02.dbo.SportBettypeMatrix mx WITH (NOLOCK)
                     WHERE ProductID IN (8, 23, 28)
                     GROUP BY Productid,bettype) AS td ON b.bettype = td.bettype
    WHERE b.matchid <> 0

    -- Cleaning pary bettype of virtual sport
    CREATE TABLE #tmpbettransm (refno BIGINT, MatchID INT)

    INSERT INTO #tmpbettransm (refno, MatchID)        
    SELECT refno, MIN(matchid) MatchID
    FROM bodb02.dbo.bettransm (NOLOCK)
    WHERE refno IN (SELECT refno
                    FROM bodb02.dbo.bettrans (NOLOCK)
                    WHERE bettype IN (SELECT Bettype FROM #tmpDW_BettypeGroup WHERE BettypeGroupID = 18)
                          AND matchid IN (SELECT Bettype FROM #tmpDW_BettypeGroup WHERE BettypeGroupID = 18)
                          AND winlostdate = CAST(@winlostdate AS SMALLDATETIME))
    GROUP BY refno

    UPDATE b
    SET b.matchid = sm.matchid
    FROM #tmpbettrans b
         LEFT JOIN #tmpbettransm sm ON b.refno = sm.refno
    WHERE b.bettype IN (SELECT Bettype FROM #tmpDW_BettypeGroup WHERE BettypeGroupID = 18)

    DROP TABLE #tmpbettransm
	
	--tmpOLTP_Customer
	CREATE TABLE #tmpOLTP_Customer (CustID INT, SiteID_DW INT)
	INSERT INTO #tmpOLTP_Customer WITH(TABLOCK) (
		CustID
	)
	SELECT CustID
	FROM #tmpbettrans
	GROUP BY CustID
	CREATE UNIQUE CLUSTERED INDEX CIX_tmpOLTP_Customer ON #tmpOLTP_Customer(CustID)
	
	UPDATE cs
	SET cs.SiteID_DW = s.SiteID_DW
	FROM #tmpOLTP_Customer AS cs
		INNER JOIN bodb02.dbo.Customer AS c WITH (NOLOCK) ON cs.CustID = c.CustID
		LEFT JOIN #tmpDW_tblsite AS s ON c.site = s.site
    ---------------------------------------------------
    -- 4. Get final data that can be used for report --
    ---------------------------------------------------

    -- #tmpFactSiteWinloss
    CREATE TABLE #tmpFactSiteWinloss (
        RptDate      DATE,
        SiteID       INT,
        CurrencyID   INT,
        Sporttype    INT,
        Bettype      INT,
        LeagueID     INT,
        TicketStatus INT,
        VarianceVR   DECIMAL (19, 4),
        TurnoverIBC  DECIMAL (19, 4),
        WinlossIBC   DECIMAL (19, 4),
        WinlossP     DECIMAL (19, 4),
        WinlossS     DECIMAL (19, 4),
        WinlossM     DECIMAL (19, 4),
        WinlossA     DECIMAL (19, 4),
        CommissionS  DECIMAL (19, 4),
        ExtraTO      DECIMAL (19, 6),
        ExtraWL      DECIMAL (19, 6),
        ExtraComm    DECIMAL (19, 6),
        NetStake     DECIMAL (19, 4)
    )

    INSERT INTO #tmpFactSiteWinloss WITH (TABLOCK)(RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR,
                                     TurnoverIBC, WinlossIBC, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, ExtraTO, ExtraWL, ExtraComm, NetStake)
    SELECT -- *** DIMENSION *** --
           mc.winlostdate RptDate,
           CASE WHEN mc.recommend = 52466 THEN -2   --8RM
                WHEN mc.recommend = 5707545 THEN -4 --BARM
                ELSE ISNULL(si_oltp.SiteID_DW, -1) END SiteID,
           mc.currency CurrencyID,
           CASE WHEN mc.bettype IN (9, 29) THEN -5                  --Parlay
                WHEN t.BettypeGroupID = 19 THEN -4                  --Odds Adjustment
                WHEN pb.EventType = 255 THEN ISNULL(mc.matchid, -1) --Saba.club sports
                WHEN pb.sporttype <> -1 THEN pb.SportType           --3rd products
                ELSE ISNULL(ev.sportID, -1) END Sporttype,
           mc.bettype Bettype,
           CASE WHEN mc.bettype IN (9, 29) THEN - 2                  --Mixed League
                WHEN mc.bettype = 18000 AND mc.betteam = '1' THEN -3 --Colossus Bets Freeplay
                ELSE ISNULL(ev.leagueid, -1) END LeagueID,
           ISNULL(st.statusid, -1) TicketStatus,
           CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6)) VarianceVR,
           -- *** MEASURE *** --
           SUM(CASE WHEN pb.ProductID = 1 THEN ABS(mc.stake) ELSE mc.stake END * (1 - mc.tpositiontaking)) TurnoverIBC,
           SUM(CASE WHEN t.BettypeGroupID = 6 THEN 0 --Prize Tickets
                    WHEN t.BettypeGroupID = 10 THEN mc.ContributionStake3rd + mc.swinlost + mc.mwinlost + mc.awinlost --Contribution Tickets
                    ELSE (mc.winlost - mc.actual_stake) + mc.swinlost + mc.mwinlost + mc.awinlost END) WinlossIBC,
           SUM(mc.winlost - mc.actual_stake) WinlossP,
           SUM(mc.swinlost) WinlossS,
           SUM(mc.mwinlost) WinlossM,
           SUM(mc.awinlost) WinlossA,
           SUM(mc.scomm) CommissionS,
           SUM(CASE WHEN mc.tpositiontaking = 1 THEN 0 ELSE CASE WHEN pb.ProductID = 1 THEN ABS(mc.stake) ELSE mc.stake END
               * CAST(ISNULL(mc.epositiontaking, 0) AS DECIMAL(10, 8)) END) ExtraTO,
           SUM(CASE WHEN mc.tpositiontaking = 1 THEN 0
                    WHEN t.BettypeGroupID = 6 THEN 0 --Prize Tickets
                    WHEN t.BettypeGroupID = 10 THEN mc.ContributionStake3rd * CAST(ISNULL(mc.epositiontaking, 0) AS DECIMAL(10, 8)) --Contribution Tickets
                    ELSE (mc.winlost - mc.actual_stake) * CAST(ISNULL(mc.epositiontaking, 0) AS DECIMAL(10, 8)) END) ExtraWL,
           SUM(CASE WHEN mc.tpositiontaking = 1 THEN 0
                    ELSE mc.scomm * CAST(ISNULL(mc.epositiontaking, 0) AS DECIMAL(10, 8)) / (1 - mc.tpositiontaking) END) ExtraComm,
           SUM(CASE WHEN t.BettypeGroupID = 13 THEN mc.NetStake
                    WHEN pb.ProductID = 1 THEN ABS(mc.stake)
                    ELSE mc.stake END) NetStake
    FROM #tmpbettrans AS mc
         LEFT JOIN #tmpDW_ProductBettype pb ON pb.bettype = mc.bettype
         LEFT JOIN #tmpDW_tblstatus st ON mc.status = st.status
         LEFT JOIN #tmpDW_BettypeGroup t ON mc.bettype = t.Bettype AND t.BettypeGroupID in (6, 10, 13, 19)
         LEFT JOIN #tmpOLTP_Customer AS si_oltp ON mc.CustID = si_oltp.CustID
		 LEFT JOIN #tmpOLTP_GameEvent ev ON mc.matchid = ev.matchid AND pb.EventType = ev.EventType
    GROUP BY mc.winlostdate,
             CASE WHEN mc.recommend = 52466 THEN -2   --8RM
                  WHEN mc.recommend = 5707545 THEN -4 --BARM
                  ELSE ISNULL(si_oltp.SiteID_DW, -1) END,
             mc.currency,
             CASE WHEN mc.bettype IN (9, 29) THEN -5                  --Parlay
                  WHEN t.BettypeGroupID = 19 THEN -4                  --Odds Adjustment
                  WHEN pb.EventType = 255 THEN ISNULL(mc.matchid, -1) --Saba.club sports
                  WHEN pb.sporttype <> -1 THEN pb.SportType           --3rd products
                  ELSE ISNULL(ev.sportID, -1) END,
             mc.bettype,
             CASE WHEN mc.bettype IN (9, 29) THEN -2                   --Mixed League
                  WHEN mc.bettype = 18000 AND mc.betteam = '1' THEN -3 --Colossus Bets Freeplay
                  ELSE ISNULL(ev.leagueid, -1) END,
             ISNULL(st.statusid, -1),
             CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6))
    OPTION (RECOMPILE)
    --------------------------
    -- 5. Return final data --
    --------------------------

    SELECT RptDate,
           SiteID,
           CurrencyID,
           Sporttype,
           Bettype,
           LeagueID,
           TicketStatus,
           VarianceVR,
           TurnoverIBC,
           WinlossIBC,
           WinlossP,
           WinlossS,
           WinlossM,
           WinlossA,
           CommissionS,
           ExtraTO,
           ExtraWL,
           ExtraComm,
           NetStake
    FROM #tmpFactSiteWinloss


    -------------------------
    -- 6. Drop temp tables --
    -------------------------

    DROP TABLE #tmpBettypeList
    DROP TABLE #tmpHalfWonLoseBettype
    DROP TABLE #tmpDW_BettypeSource
    DROP TABLE #tmpDW_ProductBettype
    DROP TABLE #tmpDW_tblstatus
    DROP TABLE #tmpDW_BettypeGroup
    DROP TABLE #tmpDW_tblsite
    DROP TABLE #tmpOLTP_Customer
    DROP TABLE #tmpOLTP_GameEvent

    DROP TABLE #tmpbettrans
    DROP TABLE #tmpFactSiteWinloss

END

/*<info serverAlias="DBACC-bodb02" isFunction="0" executers="wsv_nap" isNested="1"></info>*/
ALTER PROCEDURE dbo.Acc_Rpt_FactSiteWinloss_Bettrans
	 @winlostdate SMALLDATETIME,
	 @isUseForPayToSupplier BIT = 0
AS
/*
	Created: 20210413@Danny
	Task: Gen data for licensee bettrans staging
	DB: DBACC.bodb02

	Revisions:
		- 20210413@Danny: Initialize SP [RedmineID: #151993]
		- 20220310@Danny: get SB bettype dynamically (#169768)
        - 20230817@Ned.Le: Remove currency test
		- 20240123@Danny: Merge the settings of VS1 VS2 VS3 into Virtual Sports (#199544)
		- 20240920@Danny: Email/Letstalk - Odds Boost Voucher (#210559)
		- 20241107@Danny: Incorporate VS6 (#212749)
		- 20240114@Danny: Email/Letstalk - Offer Direct Member for Super and Master (#215045)
		- 20250616@Cherry: Offer Jackpot Contribution for bettransLC (#225847)
		- 20250828@Cherry: Extend datatype of currency (#233940)

	Exec Acc_Rpt_FactSiteWinloss_Bettrans '2021-05-12' , 0

*/
BEGIN
	SET NOCOUNT ON

	---------------------------------------------------------
	-- 1. Get raw data from bettrans|betransLC|bettransRNG --
	--------------------------------------------------------

	CREATE TABLE #tmpSBBettype (Bettype INT)

    INSERT INTO #tmpSBBettype (Bettype)
    SELECT DISTINCT BetType
    FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
    WHERE ProductID = 1
    
    CREATE CLUSTERED INDEX CIX_tmpHalfWonLoseBettype ON #tmpSBBettype(Bettype)

	-- #tmpDWBettypeSource
	CREATE TABLE #tmpDWBettypeSource (typeid INT, SourceTable VARCHAR(50))

	INSERT INTO #tmpDWBettypeSource (typeid, SourceTable)
	SELECT typeid, SourceTable 
	FROM OPENQUERY(DBWH, 'SELECT  typeid, SourceTable FROM bodb_Account.dbo.Bettype WITH(NOLOCK)')

	CREATE CLUSTERED INDEX CIX_tmpDWBettypeSource ON #tmpDWBettypeSource(typeid)

	DELETE b
	FROM #tmpDWBettypeSource b
	WHERE b.typeid IN (901 ,902, 911, 912)

	
	-- #tmpDW_ProductBettype
	CREATE TABLE #tmpDW_ProductBettype (
		[ProductID] [int] NOT NULL,
		[Bettype] [smallint] NOT NULL,
		[EventType] [tinyint] NULL,
		[sporttype] [smallint] NULL,
	)

	INSERT INTO #tmpDW_ProductBettype (ProductID, Bettype, EventType, sporttype)
	SELECT ProductID, Bettype, EventType, sporttype
	FROM OPENQUERY(DBWH, 'SELECT pb.ProductID, pb.Bettype, pb.EventType, pb.sporttype FROM bodb_Account.dbo.Product_Bettype pb WITH (NOLOCK) ') 

	CREATE CLUSTERED INDEX CIX_tmpDW_ProductBettype ON #tmpDW_ProductBettype(ProductID, Bettype)

	-- #tmpDW_tblstatus
	CREATE TABLE #tmpDW_tblstatus (
		[statusid] [int] NOT NULL,
		[status] [nvarchar](10) NOT NULL,
	)

	INSERT INTO #tmpDW_tblstatus (statusid, status)
	SELECT statusid, status
	FROM OPENQUERY(DBWH, 'SELECT st.statusid, st.status FROM bodb_Account.dbo.tbl_Status st WITH (NOLOCK)')

	CREATE CLUSTERED INDEX CIX_tmpDW_tblstatus ON #tmpDW_tblstatus(status)

	-- #tmpDW_BettypeGroup
	CREATE TABLE #tmpDW_BettypeGroup (
		[BettypeGroupID] [smallint] NOT NULL,
		[Bettype] [int] NOT NULL
	)

	INSERT INTO #tmpDW_BettypeGroup (BettypeGroupID, Bettype)
	SELECT BettypeGroupID, Bettype
	FROM OPENQUERY(DBWH, 'SELECT t.BettypeGroupID, t.Bettype FROM bodb_Account.dbo.BettypeGroup t WITH (NOLOCK)')

	CREATE CLUSTERED INDEX CIX_tmpDW_BettypeGroup ON #tmpDW_BettypeGroup(BettypeGroupID, Bettype)

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

	-- #tmpOLTP_Customer
	CREATE TABLE #tmpOLTP_Customer (
		CustID INT NOT NULL,
		SiteID_DW INT NULL
	)

	CREATE CLUSTERED INDEX CIX_tmpOLTP_Customer ON #tmpOLTP_Customer(CustID)

	-- #tmpGameEvent
	CREATE TABLE #tmpGameEvent(
		MatchID 	INT NOT NULL,
		EventType 	TINYINT NOT NULL,
		EventDate	SMALLDATETIME,
		LeagueID 	INT,
		SportID 	SMALLINT
	)	
	
	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT m.matchid					MatchID,
		   1							EventType,
		   m.eventdate					EventDate,
		   m.leagueid					LeagueID,
		   l.sporttype					SportID
	FROM bodb02.dbo.match m WITH (NOLOCK)
		 LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON m.leagueid = l.leagueid

	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT o.orid						MatchID,
		   2							EventType,
		   o.eventdate					EventDate,
		   o.leagueid					LeagueID,
		   l.sporttype					SportID
	FROM bodb02.dbo.outright o WITH (NOLOCK)
		 LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid

	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT v.EventID					MatchID,
		   3							EventType,
		   CAST(v.EventTime AS DATE)	EventDate,
		   v.LeagueID					LeagueID,
		   l.sporttype					SportID
	FROM bodb02.dbo.VSRaceInfo v WITH (NOLOCK)
		 LEFT JOIN bodb02.dbo.League3rd l WITH (NOLOCK) ON v.LeagueID = l.League3rdId

	INSERT INTO #tmpGameEvent (MatchID, EventType, EventDate, LeagueID, SportID)
	SELECT m.Match3rdId MatchID,
           5             EventType,
           m.eventdate   EventDate,
           m.League3rdId LeagueID,
           l.SportType   SportID
    FROM bodb02.dbo.Match3rd m WITH (NOLOCK)
         LEFT JOIN bodb02.dbo.League3rd l WITH (NOLOCK) ON m.League3rdId = l.League3rdId

	CREATE CLUSTERED INDEX CIX_tmpGameEvent ON #tmpGameEvent(MatchID, EventType)



	-- #tmpbettrans
	CREATE TABLE #tmpbettrans (
		[stake] [money] NOT NULL,
		[status] [nvarchar](15) NULL,
		[winlost] [money] NULL,
		[awinlost] [money] NULL,
		[mwinlost] [money] NULL,
		[tpositiontaking] [smallmoney] NULL,
		[betteam] [nvarchar](10) NULL,
		[winlostdate] [smalldatetime] NULL,
		[actualrate] [float] NULL,
		[matchid] [int] NULL,
		[custid] [int] NOT NULL,
		[recommend] [int] NOT NULL,
		[actual_stake] [money] NULL,
		[currency] [int] NULL,
		[scomm] [money] NULL,
		[swinlost] [money] NULL,
		[refno] [bigint] NULL,
		[virtualrate] [float] NULL,
		[bettype] [int] NULL,
		[ContributionStake3rd] [decimal](19, 8) NULL,
		[SportType] [int] NULL
	
	)

	CREATE TABLE #FactSiteWinloss(
		[RptDate] [date],
		[SiteID] [int],
		[CurrencyID] [int] ,
		[BetType] [int],
		[LeagueID] [int] ,
		[SportType] [int] ,
		[TicketStatus] [int],
		[VarianceVR] [decimal](9, 6),
		[Stake] [decimal](19, 4),
		[WinlossIBC] [decimal](19, 4),
		[WinlossS] [decimal](19, 4),
		[WinlossM] [decimal](19, 4),
		[WinlossA] [decimal](19, 4),
		[WinlossP] [decimal](19, 4),
		[TurnoverIBC] [decimal](19, 4),
		[CommissionS] [decimal](19, 4)	
	)

	IF @isUseForPayToSupplier = 1 
	BEGIN
		DELETE b
		FROM #tmpDWBettypeSource b
		WHERE b.typeid <> 38 AND b.typeid NOT BETWEEN 801 AND 899

		INSERT INTO #tmpbettrans (
					winlostdate
					,bettype
					,stake
					,actual_stake
					,winlost
					,awinlost
					,mwinlost
					,swinlost
					,scomm
					,status
					,currency
					,custid
					,recommend
					,SportType
				)

				SELECT
					b.winlostdate
					,b.bettype
					,SUM(b.stake)
					,SUM(b.actual_stake)
					,SUM(b.winlost)
					,SUM(b.awinlost)
					,SUM(b.mwinlost) 
					,SUM(b.swinlost)  swinlost
					,SUM(b.scomm)	
					,CASE WHEN (
									bt.Bettype IS NOT NULL
									AND ABS(b.modds) = 0.25
									AND b.[statusID] IN (112,113)
								) THEN CONVERT(NVARCHAR(15),'HALF ' + b.STATUS)
							ELSE CONVERT(NVARCHAR(15),b.STATUS)
						END AS [status]
					,b.currency
					,b.custid
					,b.recommend
					,gv.SportID 
				FROM bodb02.dbo.bettrans b (NOLOCK)
				INNER JOIN #tmpGameEvent gv ON gv.MatchID = b.matchid
				LEFT JOIN  #tmpSBBettype bt ON b.bettype = bt.Bettype
				WHERE b.winlostdate = @winlostdate 
					  AND b.bettype IN (SELECT typeid FROM #tmpDWBettypeSource where SourceTable='bettrans')
					  AND b.statusID IN (111, 112, 113)
                      AND b.currency <> 20
				GROUP BY b.winlostdate
						,b.bettype, 
						CASE WHEN (
									bt.Bettype IS NOT NULL
									AND ABS(b.modds) = 0.25
									AND b.[statusID] IN (112,113)
								) THEN CONVERT(NVARCHAR(15),'HALF ' + b.STATUS)
							ELSE CONVERT(NVARCHAR(15),b.STATUS)
						END ,b.currency
					,b.custid, b.recommend ,gv.SportID 
				OPTION (RECOMPILE)

		
		INSERT INTO #tmpOLTP_Customer (CustID)
		SELECT CustID FROM #tmpbettrans GROUP BY CustID

		UPDATE cs
		SET cs.SiteID_DW = s.siteid
		FROM #tmpOLTP_Customer AS cs
			INNER JOIN bodb02.dbo.Customer AS c WITH (NOLOCK) ON cs.CustID = c.CustID
			LEFT JOIN #tmpDW_tblsite AS s ON c.site = s.site


		INSERT INTO #FactSiteWinloss(RptDate, SiteID, CurrencyID, Bettype, TicketStatus, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, SportType)
		SELECT
			   mc.winlostdate																																		RptDate,
			   CASE WHEN mc.recommend = 52466 THEN -2 --8RM
					WHEN mc.recommend = 5707545 THEN -4 --BARM
					ELSE ISNULL(si_oltp.SiteID_DW, -1) END																											SiteID,
			   mc.currency																																			CurrencyID,
			   mc.bettype																																			Bettype,
			   ISNULL(st.statusid, -1)																																TicketStatus,
			   SUM(mc.winlost - mc.actual_stake)																													WinlossP,
			   SUM(mc.swinlost)																																		WinlossS,
			   SUM(mc.mwinlost)																																		WinlossM,
			   SUM(mc.awinlost)																																		WinlossA,
			   SUM(mc.scomm)																																		CommissionS,
			   mc.SportType
		FROM #tmpbettrans mc
		LEFT JOIN #tmpDW_tblstatus st ON mc.status = st.status
		LEFT JOIN #tmpOLTP_Customer si_oltp WITH (NOLOCK) ON mc.custid = si_oltp.CustID
		GROUP BY mc.winlostdate,
				 CASE WHEN mc.recommend = 52466 THEN -2 --8RM
					  WHEN mc.recommend = 5707545 THEN -4 --BARM
					  ELSE ISNULL(si_oltp.SiteID_DW, -1) END,
				 mc.currency,
				 mc.bettype,
				 ISNULL(st.statusid, -1),
				 mc.SportType

		OPTION (RECOMPILE)


		DECLARE @tmpSite TABLE (SiteId_DW INT, LicenseeId INT, SiteName VARCHAR(20))
		INSERT INTO @tmpSite (LicenseeId, SiteName)
		SELECT SiteId, RTRIM(LTRIM(SiteName)) FROM bodb_licensee.dbo.view_site_list WITH (NOLOCK)

		UPDATE s
		SET s.SiteId_DW = t.SiteId
		FROM @tmpSite s
		INNER JOIN #tmpDW_tblsite t WITH (NOLOCK) ON s.SiteName = RTRIM(LTRIM(t.Site))
	
		SELECT	f.rptDate, 
				s.LicenseeId SiteId, 
				CASE WHEN f.BetType = 38 AND f.SportType = 1 THEN -3 
					 WHEN f.BetType = 38 AND f.SportType = 2 THEN -4 
				ELSE -1 END BetTypeId, 
				f.CurrencyId, 
				SUM(CASE WHEN f.BetType = 38 THEN winlossP + commissionS ELSE winlossP + winlossA + winlossM + winlossS + commissionS END) Winloss
		FROM #FactSiteWinloss f WITH (NOLOCK)
			INNER JOIN @tmpSite s ON f.SiteId = s.SiteId_DW
		WHERE f.TicketStatus NOT IN (-1, 18, 9, 10, 14)
			AND f.CurrencyId <> 20
			AND (f.BetType = 38 OR f.BetType BETWEEN 801 AND 899)
		GROUP BY f.rptDate, s.LicenseeId,
				CASE WHEN f.BetType = 38 AND f.SportType = 1 THEN -3 
					 WHEN f.BetType = 38 AND f.SportType = 2 THEN -4 
				ELSE -1 END, f.CurrencyId
		
	END

	
	IF @isUseForPayToSupplier = 0
	BEGIN
		INSERT INTO #tmpbettrans (
			winlostdate
			,bettype
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
			,custid
			,recommend
			,refno
			,virtualrate
			,ContributionStake3rd
		)
		SELECT
			b.winlostdate
			,b.bettype
			,CASE WHEN b.bettype = 18000 THEN CONVERT(NVARCHAR(10),b.currency2) ELSE b.betteam END AS betteam
			,SUM(b.stake)
			,SUM(b.actual_stake)
			,SUM(b.winlost)
			,SUM(b.awinlost)
			,SUM(b.mwinlost + CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN b.swinlost ELSE 0 END) AS mwinlost
			,SUM(CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN (winlost - stake) * (1 - tpositiontaking - ISNULL(oddsspread, 0)) ELSE b.swinlost END) AS swinlost
			,SUM(b.scomm)
			,CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN 1 - ISNULL(oddsspread, 0) ELSE b.tpositiontaking END AS tpositiontaking
			,CASE WHEN b.bettype=1003 THEN b.betdaqid ELSE b.matchID END AS matchid		
			,CASE WHEN (
									bt.Bettype IS NOT NULL
									AND ABS(b.modds) = 0.25
									AND b.[statusID] IN (112,113)
								) THEN CONVERT(NVARCHAR(15),'HALF ' + b.STATUS)
							ELSE CONVERT(NVARCHAR(15),b.STATUS)
						END  AS [status]
			,b.actualrate
			,b.currency
			,b.custid
			,b.recommend
			,CASE WHEN bg.bettype IS NOT NULL THEN b.refno ELSE 0 END refno
			,b.virtualrate
			,NULL ContributionStake3rd
		FROM bodb02.dbo.bettrans b (NOLOCK)
		LEFT JOIN  #tmpSBBettype bt ON b.bettype = bt.Bettype
		LEFT JOIN  #tmpDW_BettypeGroup bg ON b.bettype = bg.Bettype AND bg.BettypeGroupID = 18
		WHERE b.winlostdate = @winlostdate
			  AND b.bettype IN (SELECT typeid FROM #tmpDWBettypeSource where SourceTable='bettrans')
			  AND b.statusID IN (111, 112, 113)
              AND b.currency <> 20
		GROUP BY b.winlostdate, b.bettype, 
				 CASE WHEN b.bettype = 18000 THEN CONVERT(NVARCHAR(10),b.currency2) ELSE b.betteam END,
				 CASE WHEN b.bettype IN (31,32,33,41,42,43) THEN 1 - ISNULL(oddsspread, 0) ELSE b.tpositiontaking END,
				 CASE WHEN b.bettype=1003 THEN b.betdaqid ELSE b.matchID END,
				 CASE WHEN (
									bt.Bettype IS NOT NULL
									AND ABS(b.modds) = 0.25
									AND b.[statusID] IN (112,113)
								) THEN CONVERT(NVARCHAR(15),'HALF ' + b.STATUS)
							ELSE CONVERT(NVARCHAR(15),b.STATUS)
						END 
				,b.actualrate
				,b.currency
				,b.custid
				,b.recommend
				,CASE WHEN bg.bettype IS NOT NULL THEN b.refno ELSE 0 END
				,b.virtualrate
		OPTION (RECOMPILE)
		

		INSERT INTO #tmpbettrans (
			winlostdate
			,bettype
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
			,custid
			,recommend
			,refno
			,virtualrate
			,ContributionStake3rd
		
		)
		SELECT
			b.winlostdate
			,b.GameID bettype
			,NULL betteam
			,SUM(b.stake)
			,SUM(b.actual_stake)
			,SUM(b.winlost)
			,SUM(b.awinlost)
			,SUM(b.mwinlost)
			,SUM(b.swinlost)
			,SUM(b.scomm)
			,b.tpositiontaking
			,b.ProductID matchid
			,CONVERT(NVARCHAR(15),b.STATUS) status
			,b.actualrate
			,b.currency
			,b.custid
			,b.recommend
			,0 AS refno
			,b.virtualrate
			,SUM(b.ContributionStake3rd)
		FROM bodb02.dbo.bettransLC b (NOLOCK)
		WHERE b.winlostdate = @winlostdate
			  AND b.gameID IN (SELECT typeid FROM #tmpDWBettypeSource where SourceTable='bettransLC')
			  AND b.StatusID IN (111, 112, 113)
              AND b.currency <> 20
		GROUP BY b.winlostdate,b.GameID,b.tpositiontaking,b.ProductID, CONVERT(NVARCHAR(15),b.STATUS), b.actualrate, b.currency,b.custid, b.recommend,b.virtualrate
		OPTION (RECOMPILE)

		INSERT INTO #tmpbettrans (
			winlostdate
			,bettype
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
			,custid
			,recommend
			,refno
			,virtualrate
			,ContributionStake3rd
		)
		SELECT
			 b.winlostdate
			,b.GameID bettype
			,NULL betteam
			,SUM(b.stake)
			,SUM(b.actual_stake)
			,SUM(b.winlost)
			,SUM(b.awinlost)
			,SUM(b.mwinlost)
			,SUM(b.swinlost)
			,SUM(b.scomm)
			,b.tpositiontaking
			,b.ProductID matchid
			,CONVERT(NVARCHAR(15),b.STATUS) status
			,b.actualrate
			,b.currency
			,b.custid
			,b.recommend
			,0 AS refno
			,b.virtualrate
			,SUM(b.ContributionStake3rd)
		FROM bodb02.dbo.bettransRNG b (NOLOCK)
		WHERE b.winlostdate = @winlostdate
			  AND b.gameID IN (SELECT typeid FROM #tmpDWBettypeSource where SourceTable='bettransRNG')
			  AND b.StatusID IN (111, 112, 113)
              AND b.currency <> 20
		GROUP BY b.winlostdate, b.GameID, b.tpositiontaking, b.ProductID, CONVERT(NVARCHAR(15),b.STATUS), b.actualrate, b.currency, b.custid, b.recommend, b.virtualrate
		OPTION (RECOMPILE)

		CREATE CLUSTERED INDEX CIX_tmpbettrans ON #tmpbettrans(bettype, matchid)

		--------------------------
		-- 2. Cleaning raw data --
		--------------------------

		-- Clean winlostdate
		UPDATE b
		SET b.winlostdate = DATEADD(DD, DATEDIFF(DD, 0, b.winlostdate), 0)
		FROM #tmpbettrans b WITH (ROWLOCK, UPDLOCK)
		WHERE DATEPART(HOUR, b.winlostdate) > 0
			  OR DATEPART(SECOND, b.winlostdate) > 0
			  OR DATEPART(MINUTE, b.winlostdate) > 0

		-- Cleaning NG2 (23), Keno(8) and Keno Lottery (28) [matchid = 0]
		UPDATE b
		SET b.matchid = 0
		FROM #tmpbettrans b
			 INNER JOIN (SELECT Productid,bettype
						 FROM bodb02.dbo.SportBettypeMatrix mx WITH (NOLOCK)
						 WHERE ProductID IN (8, 23, 28)
						 GROUP BY Productid,bettype) AS td ON b.bettype = td.bettype
		WHERE b.matchid <> 0

		-- Cleaning bettype Parlay (2799) of BetRadar Virtual Sports (27)
		CREATE TABLE #tmpbettransm (refno BIGINT, MatchID INT)

		INSERT INTO #tmpbettransm (refno, MatchID)		
		SELECT refno, MIN(matchid) MatchID
		FROM bodb02.dbo.bettransm (NOLOCK)
		WHERE refno IN (SELECT refno
						FROM bodb02.dbo.bettrans (NOLOCK)
						WHERE bettype IN (SELECT x.bettype FROM #tmpDW_BettypeGroup x WHERE x.BettypeGroupID = 18)
							  AND matchid IN (SELECT x1.bettype FROM #tmpDW_BettypeGroup x1 WHERE x1.BettypeGroupID = 18)
							  AND winlostdate = CAST(@winlostdate AS SMALLDATETIME))
		GROUP BY refno

		UPDATE b
		SET b.matchid = sm.matchid
		FROM #tmpbettrans b
			 LEFT JOIN #tmpbettransm sm ON b.refno = sm.refno
		WHERE b.bettype IN (SELECT x.bettype FROM #tmpDW_BettypeGroup x WHERE x.BettypeGroupID = 18)

		DROP TABLE #tmpbettransm


		INSERT INTO #tmpOLTP_Customer (CustID)
		SELECT CustID FROM #tmpbettrans GROUP BY CustID

		UPDATE cs
		SET cs.SiteID_DW = s.siteid
		FROM #tmpOLTP_Customer AS cs
			INNER JOIN bodb02.dbo.Customer AS c WITH (NOLOCK) ON cs.CustID = c.CustID
			LEFT JOIN #tmpDW_tblsite AS s ON c.site = s.site


		INSERT INTO #FactSiteWinloss(RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR, TurnoverIBC, WinlossIBC, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, Stake)
		SELECT
			   mc.winlostdate																																		RptDate,
			   CASE WHEN mc.recommend = 52466 THEN -2 --8RM
					WHEN mc.recommend = 5707545 THEN -4 --BARM
					ELSE ISNULL(si_oltp.SiteID_DW, -1) END																											SiteID,
			   mc.currency																																			CurrencyID,
			   CASE WHEN mc.bettype IN (9, 29) THEN -5								--Parlay
					WHEN t.BettypeGroupID = 19 THEN -4								--Odds Adjustment
					WHEN pb.EventType = 255 THEN ISNULL(mc.matchid, -1)				--Saba.club sports
					WHEN pb.sporttype <> -1 THEN pb.SportType						--3rd products
					ELSE ISNULL(ev.sportID, -1) END																													Sporttype,
			   mc.bettype																																			Bettype,
			   CASE WHEN mc.bettype IN (9, 29) THEN - 2								--Mixed League
					WHEN mc.bettype = 18000 AND mc.betteam = '1' THEN -3			--Colossus Bets Freeplay
					ELSE ISNULL(ev.leagueid, -1) END																												LeagueID,
			   ISNULL(st.statusid, -1)																																TicketStatus,
			   CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6))																							VarianceVR,
			   -- *** MEASURE *** --
			   SUM(CASE WHEN pb.ProductID = 1 THEN ABS(mc.stake) ELSE mc.stake END * (1 - mc.tpositiontaking))														TurnoverIBC,
			   SUM(CASE WHEN t.BettypeGroupID = 6 THEN 0 --Prize Tickets
						WHEN t.BettypeGroupID = 10 THEN mc.ContributionStake3rd + mc.swinlost + mc.mwinlost + mc.awinlost --Contribution Tickets
						ELSE (mc.winlost - mc.actual_stake) + mc.swinlost + mc.mwinlost + mc.awinlost END)															WinlossIBC,
			   SUM(mc.winlost - mc.actual_stake)																													WinlossP,
			   SUM(mc.swinlost)																																		WinlossS,
			   SUM(mc.mwinlost)																																		WinlossM,
			   SUM(mc.awinlost)																																		WinlossA,
			   SUM(mc.scomm)																																		CommissionS,
			   SUM(CASE WHEN pb.ProductID = 1 THEN abs(stake) ELSE stake END)																						Stake
		FROM #tmpbettrans mc
			 LEFT JOIN #tmpDW_ProductBettype pb ON pb.bettype=mc.bettype
			 LEFT JOIN #tmpDW_tblstatus st ON mc.status = st.status
			 LEFT JOIN #tmpDW_BettypeGroup t ON mc.bettype = t.Bettype AND t.BettypeGroupID in (6, 10, 19)
			 LEFT JOIN #tmpOLTP_Customer si_oltp WITH (NOLOCK) ON mc.custid = si_oltp.CustID
			 LEFT JOIN #tmpGameEvent ev ON mc.matchid  =ev.matchid AND pb.EventType = ev.EventType
		GROUP BY mc.winlostdate,
				 CASE WHEN mc.recommend = 52466 THEN -2 --8RM
					  WHEN mc.recommend = 5707545 THEN -4 --BARM
					  ELSE ISNULL(si_oltp.SiteID_DW, -1) END,
				 mc.currency,
				 CASE WHEN mc.bettype IN (9, 29) THEN -5							--Parlay
					  WHEN t.BettypeGroupID = 19 THEN -4							--Odds Spread Adjustment
					  WHEN pb.EventType = 255 THEN ISNULL(mc.matchid, -1)			--Saba.club sports
					  WHEN pb.sporttype <> -1 THEN pb.SportType						--3rd products
					  ELSE ISNULL(ev.sportID, -1) END,
				 mc.bettype,
				 CASE WHEN mc.bettype IN (9, 29) THEN -2							--Mixed League
					  WHEN mc.bettype = 18000 AND mc.betteam = '1' THEN -3			--Colossus Bets Freeplay
					  ELSE ISNULL(ev.leagueid, -1) END,
				 ISNULL(st.statusid, -1),
				 CAST((mc.virtualrate / mc.actualrate - 1) AS DECIMAL(9, 6))
		OPTION (RECOMPILE)

		SELECT RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR, TurnoverIBC, WinlossIBC, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, Stake
		FROM #FactSiteWinloss
	END

	-------------------------
	-- 5. Drop temp tables --
	-------------------------

	DROP TABLE #FactSiteWinloss
	DROP TABLE #tmpDWBettypeSource
	DROP TABLE #tmpbettrans
	DROP TABLE #tmpDW_ProductBettype
	DROP TABLE #tmpDW_tblstatus
	DROP TABLE #tmpDW_BettypeGroup
	DROP TABLE #tmpDW_tblsite
	DROP TABLE #tmpOLTP_Customer
	DROP TABLE #tmpGameEvent
	DROP TABLE #tmpSBBettype

END


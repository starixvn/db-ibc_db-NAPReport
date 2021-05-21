/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_TreeWinlostByCom
	@FromDate    DATETIME
   , @ToDate      DATETIME
   , @currency    INT
   , @Products    VARCHAR(MAX)
   , @SportType VARCHAR(MAX)
AS
/*  
Created by: Scott  
Date: 2012-12-17 
Task : Report Tree Win Lost  
DB: DBACC.bodb02  
Original SP:   
Revisions:  
	20130115@Scott : fix bug sum total of poker sporttype
	20130418@Scott : Update formula turnover of Racing
	20130702@Dom.Cao: Add Vanriance (+\-)
	20140304@TomVo: 
		Change Name Server (DB06) to Alias Server (DBACC)
		Add Keno Sport (202) -Bettype : 1501 - 1599
	20151226@Johnson: Separate virtual rate by sporttype, bettype [Redmine: #25840]	
	20150529@Jim: add more parameter @ShowGD,@ShowMGSL and apply sport-bettype matrix 
	20150710@Jim: Super Balance fix and Microgaming integration (Feature #38168)
	20150723@Jim: Apply Bettrade [#38815]	
	20150828@Jim: support Colossus Bet (#42608)
	20151110@Billy : Change to new Virtual Rate structure - [Redmine: #47355]
	20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	20151214@Percy: 1. Add new product: Cockfighting [Redmine: #49027]
					  2. Change input parameters
	20160118@Percy: Calculate turnover for RNG Casino [Redmine: #49134]
	20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
	20160615@Sophia: Change READPAST to ROWLOCK because of the Deadlock [Redmind: #59254]
	20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
	2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
	20180411@Franklin: Integrate Pragmatic (#92642)
	20180504@Dominic: Apply new VR concepts - Redminde:#94213
	20180711@Robert: NAP Report - Add Cash Out & Bettrade into Tree Win Loss report [RedmindID: #98005]
	20480815@Robert: Integrate Poker Games into NAP Report [RedmindID: #97830]
	20190107@Kean: Use NoLock hint to bettransRNG and bettransLC [RedmindID: #107415]
	20190117@Robert: Video Poker - Integrate into NAP Reports [RedmindID: #107706]
	20190311@Cherry: Integrate Bet Builder (#109822)
	20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
	20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
	20190918@Robert: Remove inactive products (#120215)	   
	20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
	20191223@Ned.Le: NAP Report - Integrate Spadegaming product (#125712)
	20191231@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
	20200227@Ned.Le: Hotfix thats convert datatype for VarianceVR from DECIMAL(5, 2) to DECIMAL(9, 6)
	20200710@Cherry: Integrate Jackpot Pragmatic (#137271)
	20200724@Cherry: Add filter Sport of Sportbook (#135880)
	20200812@Cherry: Hotfix 139420
	20201001@Cherry: Add Licensee Odds Spread (#141750)
	20201111@Ned.Le: NAP Report - Hotfix Tree Winloss - Block Replication (#145175)
	20210409@Jaden.Tang: Exclude lucky draws from bettransLC (#133731)
	20210520@Jaden:  Support new way to view VR setting (#154903)
*/

BEGIN
    SET NOCOUNT ON;

	-- #TmpResultAll
    CREATE TABLE #TmpResultAll(
	    srecommend        INT
	  , VarianceVR        DECIMAL(19,6)
	  , TurnoverIBC       MONEY
	  , WinlossIBC        MONEY
	  , CommissionS       MONEY
	  , ExtraWL           MONEY
	  , ExtraTO           MONEY
	  , ExtraComm         MONEY
	  /*RM*/
	  , TurnoverIBC_RM    MONEY
	  , WinlossIBC_RM     MONEY
	  , CommissionS_RM    MONEY
	  , ExtraWL_RM        MONEY
	  , ExtraTO_RM        MONEY
	  , ExtraComm_RM      MONEY);
	
	-- @SportBettype
    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @SportBettype TABLE(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(200)
	  , RefTable      TINYINT);
    INSERT INTO @SportBettype
		 SELECT ProductID
			 , Bettype
			 , EventType
			 , SubProduct
			 , RefTable
		 FROM dbo.f_SportBettypeMatrix_Sel
			 (0, 0, 0, 2, '', '', @isTest) AS sb
		 WHERE sb.BetType NOT IN(901, 902, 911, 912);

	-- #PrizeBettypeGroup
	IF OBJECT_ID('tempdb..#PrizeBettypeGroup') IS NOT NULL
	BEGIN
		DROP TABLE #PrizeBettypeGroup;
	END;
	CREATE TABLE #PrizeBettypeGroup (BettypeGroupID SMALLINT, Bettype SMALLINT)
	INSERT INTO #PrizeBettypeGroup
	SELECT BettypeGroupID, Bettype 
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID IN (6, 10)

	-- #Product
    IF OBJECT_ID('tempdb..#Product') IS NOT NULL
	   BEGIN
		  DROP TABLE #Product;
	   END;

    CREATE TABLE #Product(
	    ProductID    INT);

    INSERT INTO #Product(ProductID)
		 SELECT val
		 FROM strSplit
			 (@Products, ',');
	
	-- #tmpBettype
    IF OBJECT_ID('tempdb..#tmpBettype') IS NOT NULL
	   BEGIN
		  DROP TABLE #tmpBettype;
	   END;

    CREATE TABLE #tmpBettype(
	    ProductID    INT
	  , bettype      INT
	  , RefTable     TINYINT);

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = -1
		    )
	   BEGIN
		  WITH tblP(ProductID)
			  AS (
			  SELECT tblP.ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -1)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype
								, RefTable)
				    SELECT tblP.ProductID
					    , tblS.bettype
						, tblS.RefTable
				    FROM tblP
					  , @SportBettype AS tblS
				    WHERE tblS.ProductID = 1
						AND tblS.SubProduct IN('MG-SuperLive');
	   END;

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = -2
		    )
	   BEGIN
		  WITH tblP(ProductID)
			  AS (
			  SELECT tblP.ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -2)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype
								, RefTable)
				    SELECT tblP.ProductID
					    , tblS.bettype
						, tblS.RefTable
				    FROM tblP
					  , @SportBettype AS tblS
				    WHERE tblS.ProductID = 1
						AND tblS.SubProduct IN('BT-Comm', 'BT-Winloss');
	   END;
	   
	IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = -3
		    )
	   BEGIN
		  WITH tblP(ProductID)
			  AS (
			  SELECT tblP.ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -3)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype
								, RefTable)
				    SELECT tblP.ProductID
					    , tblS.bettype
						, tblS.RefTable
				    FROM tblP
					  , @SportBettype AS tblS
				    WHERE tblS.ProductID = 1
						AND tblS.SubProduct IN('Bet Builder');
	   END;

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = 1
		    )
	   BEGIN
		  INSERT INTO #tmpBettype(ProductID
						    , bettype
							, RefTable)
			    SELECT tblP.ProductID
				    , tblS.bettype
					, tblS.RefTable
			    FROM @SportBettype AS tblS
				   INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
			    WHERE tblP.ProductID = 1
					AND tblS.SubProduct NOT IN('MG-SuperLive', 'BT-Comm', 'BT-Winloss', 'Bet Builder');
	   END;
	
	INSERT INTO #tmpBettype(ProductID
					 , bettype
					 , RefTable)
		 SELECT tblP.ProductID
			 , tblS.bettype
			 , tblS.RefTable
		 FROM @SportBettype AS tblS
			INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
		 WHERE tblP.ProductID <> 1;

    CREATE CLUSTERED INDEX IDX_Bettype_bettype_ProductID ON #tmpBettype(bettype, ProductID, RefTable);
    
    -- @SportType	
	CREATE TABLE #tmpSportType (SportType INT)
	CREATE TABLE #tmpMatch (matchid INT, matchtype TINYINT)
	IF @SportType <> ''
    BEGIN
		INSERT INTO #tmpSportType (SportType)
		SELECT val FROM [dbo].strSplit(@SportType, ',')
		
		IF EXISTS(SELECT TOP 1 1 FROM #tmpSportType WHERE SportType = 10000)	-- Other Sports
			INSERT INTO #tmpSportType (SportType)
			SELECT DISTINCT sb.SportType
			FROM bodb02.dbo.SportBettypeMatrix sb WITH(NOLOCK)
			WHERE ProductID = 1 AND sb.SportType NOT IN (1,2,43)
			
		IF NOT EXISTS (SELECT TOP 1 1 FROM #tmpSportType WHERE SportType = 20000) -- Parlay
			DELETE FROM #tmpBettype WHERE bettype IN (9,29)
			
		IF NOT EXISTS (SELECT TOP 1 1 FROM #tmpSportType WHERE SportType = 30000) -- SB Adjustment
			DELETE FROM #tmpBettype WHERE bettype = 999
			
		DELETE FROM #tmpSportType WHERE SportType IN (10000, 20000, 30000)
		
		;WITH CTE_Match AS (
		SELECT matchid AS matchid, leagueid, 0 AS matchtype  FROM bodb02.dbo.match (NOLOCK) WHERE eventdate between @FromDate and @ToDate
		UNION ALL
		SELECT orid AS matchid, leagueid, 1 AS matchtype FROM bodb02.dbo.outright (NOLOCK) WHERE eventdate between @FromDate and @ToDate
		)
		INSERT INTO #tmpMatch(matchid, matchtype)
		SELECT m.matchid,
			   m.matchtype
		FROM CTE_Match m
			 INNER JOIN bodb02.dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE m.leagueid = l.LeagueId
			  AND l.sporttype IN (SELECT SportType FROM #tmpSportType)
		OPTION (RECOMPILE)
	END

	/*-get data from bettransRNG*/
    INSERT INTO #TmpResultAll
		 SELECT b.srecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) AS VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                      TurnoverIBC
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END) AS                                                WinlossIBC
			 , SUM(scomm) AS                                              CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1 THEN 0
					 WHEN bg.BettypeGroupID = 6 THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                        ExtraComm
			 /*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS         TurnoverIBC_RM
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END * actualrate) AS                                   WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                 CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1 THEN 0
					 WHEN bg.BettypeGroupID = 6 THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN bg.BettypeGroupID = 10 THEN b.ContributionStake3rd * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                   ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                   ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS           ExtraComm_RM
		 FROM bettransRNG AS b WITH (NOLOCK)
			  INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			  LEFT JOIN #PrizeBettypeGroup bg ON b.gameID = bg.Bettype
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME) 
			  AND b.statusID NOT IN(0, 1, 101, 102, 103)
			  AND b.currency = @currency
		 GROUP BY b.srecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) OPTION(RECOMPILE);

	/*Get data from bettrans*/
	INSERT INTO #TmpResultAll
		 SELECT b.srecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) AS                     VarianceVR
			 , SUM(CASE
					 WHEN t.ProductID = 1
					 THEN ABS(stake)					 
					 ELSE stake
				  END * (1 - tpositiontaking)) AS                                            TurnoverIBC
			 , SUM(swinlost + mwinlost + awinlost + winlost - actual_stake) AS                WinlossIBC
			 , SUM(scomm) AS                                                                  CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0					 
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN t.ProductID = 1
							THEN ABS(stake)							
							ELSE stake
						 END * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0						 
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
			 /*RM*/
			 , SUM(CASE
					 WHEN t.ProductID = 1
					 THEN ABS(stake)					 
					 ELSE stake
				  END * (1 - tpositiontaking) * actualrate) AS                               TurnoverIBC_RM
			 , SUM((swinlost + mwinlost + awinlost + winlost - actual_stake) * actualrate) AS WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0					 
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN t.ProductID = 1
							THEN ABS(stake)							
							ELSE stake
						 END * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0						 
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettrans AS b WITH (NOLOCK)
			INNER JOIN #tmpBettype AS t ON t.RefTable NOT IN (1, 2) AND t.bettype = b.bettype
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)			  
			  AND b.ruben = 1
			  AND b.statusID NOT IN(101, 102, 103)
			  AND b.currency = @currency
			  AND (t.bettype IN (9,29,999)
				OR t.ProductID <> 1
				OR (t.ProductID = 1 AND t.bettype NOT IN (9,29,10,999) AND b.matchid IN (SELECT matchid FROM #tmpMatch where matchtype = 0))
				OR (t.bettype = 10 AND b.matchid IN (SELECT matchid FROM #tmpMatch where matchtype = 1))
				)
		 GROUP BY b.srecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) OPTION(RECOMPILE);
	
	/*-get data from bettransLC*/
    INSERT INTO #TmpResultAll
		 SELECT b.srecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) AS                     VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                                          TurnoverIBC
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0 /*exclude Lucky Draws*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END) AS                                                WinlossIBC
			 , SUM(scomm) AS                                                                  CommissionS
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0
					 WHEN tpositiontaking = 1 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
			 /*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS                             TurnoverIBC_RM
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0 
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END * actualrate) AS                                   WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN bg.BettypeGroupID = 6 THEN 0
					 WHEN tpositiontaking = 1 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettransLC AS b WITH (NOLOCK)
			  INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			  LEFT JOIN #PrizeBettypeGroup bg ON b.gameID = bg.Bettype
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND b.statusID NOT IN(0, 1, 101, 102, 103)
			  AND b.currency = @currency
		 GROUP BY b.srecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(19, 6)) OPTION(RECOMPILE);

	-- get top 1 vr record of each cust 
	CREATE TABLE #custVRRef (CustID INT, VirtualMultiplier SMALLMONEY);
	INSERT INTO #custVRRef
		SELECT custinfo.custid, ca.virtualMultiplier - 1
		FROM bodb02.dbo.custInfo AS custinfo WITH (NOLOCK)
		CROSS APPLY (SELECT TOP 1 cvs.custid, pvs.bettype,
						bodb02.dbo.f_GetVirtualSetting(cvs.bitmapVirtual, pvs.profileID) AS virtualMultiplier
					FROM bodb02.dbo.CustVirtualSetting cvs WITH (NOLOCK)
					INNER JOIN bodb02.dbo.ProfileVirtualSetting AS pvs WITH (NOLOCK) 
						ON cvs.seqNo = pvs.seqNo
					WHERE cvs.custid = custinfo.custid
					AND pvs.sporttype NOT IN (43, 2) AND pvs.isActive = 1) ca
		WHERE custinfo.custid IN (select srecommend from #TmpResultAll)

	/*-record set main data*/
    SELECT b.srecommend
	    , cs.UserName
	    , ISNULL(CAST(ref.VirtualMultiplier AS VARCHAR(5)), 'N/A') 									AS VirtualRate
	    , SUM(CASE
			    WHEN TurnoverIBC = 0
			    THEN 0
			    ELSE TurnoverIBC - ExtraTO
			END * CASE
					WHEN VarianceVR > 0
					THEN VarianceVR + 1
					ELSE 1
				 END) AS                                                                               Turnover
	    , -SUM(ExtraWL + ExtraComm) AS                                                                    ExtraAmount
	    , SUM(WinlossIBC) AS                                                                              Winloss
	    , SUM(CommissionS) AS                                                                             Commission
	    , SUM(WinlossIBC - ExtraWL + CommissionS - ExtraComm) AS                                          total
	    , SUM(CASE
			    WHEN TurnoverIBC_RM = 0
			    THEN 0
			    ELSE TurnoverIBC_RM - ExtraTO_RM
			END * CASE
					WHEN VarianceVR > 0
					THEN VarianceVR + 1
					ELSE 1
				 END) AS                                                                               TurnoverRM
	    , SUM(CASE
			    WHEN TurnoverIBC = 0
			    THEN 0
			    ELSE TurnoverIBC_RM - ExtraTO_RM
			END * (VarianceVR + 1)) AS                                                                  Virtual_Turnover
	    , SUM(WinlossIBC_RM - ExtraWL_RM + CommissionS_RM - ExtraComm_RM) AS                              TotalRM
	    , SUM((WinlossIBC_RM - ExtraWL_RM) * (VarianceVR + 1) + (CommissionS_RM - ExtraComm_RM) * CASE
																				   WHEN VarianceVR < 0
																				   THEN VarianceVR + 1
																				   ELSE 1
																			    END) AS Virtual_Total
	    , SUM(CASE
			    WHEN VarianceVR > 0
			    THEN(-(WinlossIBC_RM - ExtraWL_RM + CASE
											    WHEN VarianceVR < 0
											    THEN CommissionS_RM - ExtraComm_RM
											    ELSE 0
											END) * VarianceVR)
			    ELSE 0
			END) AS                                                                                     [WLVariance+]
	    , SUM(CASE
			    WHEN VarianceVR < 0
			    THEN(-(WinlossIBC_RM - ExtraWL_RM + CASE
											    WHEN VarianceVR < 0
											    THEN CommissionS_RM - ExtraComm_RM
											    ELSE 0
											END) * VarianceVR)
			    ELSE 0
			END) AS                                                                                     [WLVariance-]
	    , SUM(-(WinlossIBC_RM - ExtraWL_RM + CASE
										WHEN VarianceVR < 0
										THEN CommissionS_RM - ExtraComm_RM
										ELSE 0
									 END) * VarianceVR) AS                                        WLVarianceTotal
	    , SUM(CASE
			    WHEN VarianceVR > 0
			    THEN CASE
					   WHEN TurnoverIBC_RM = 0
					   THEN 0
					   ELSE TurnoverIBC_RM - ExtraTO_RM
				    END * ABS(VarianceVR)
			    ELSE 0
			END) AS                                                                                     [TOVariance+]
	    , SUM(CASE
			    WHEN VarianceVR < 0
			    THEN CASE
					   WHEN TurnoverIBC_RM = 0
					   THEN 0
					   ELSE TurnoverIBC_RM - ExtraTO_RM
				    END * ABS(VarianceVR)
			    ELSE 0
			END) AS                                                                                     [TOVariance-]
	    , SUM(CASE
			    WHEN TurnoverIBC_RM = 0
			    THEN 0
			    ELSE TurnoverIBC_RM - ExtraTO_RM
			END * ABS(VarianceVR)) AS                                                                   TOVarianceTotal
    FROM #TmpResultAll AS b
	   INNER JOIN custinfo AS cs WITH (NOLOCK) ON b.srecommend = cs.custid
	   LEFT JOIN #custVRRef AS ref WITH (NOLOCK) ON b.srecommend = ref.CustID
    GROUP BY b.srecommend
		 , ISNULL(CAST(ref.VirtualMultiplier AS VARCHAR(5)), 'N/A')
		 , cs.username
    ORDER BY username;

	-- Drop temp tables
    DROP TABLE #TmpResultAll;
    DROP TABLE #Product;
    DROP TABLE #tmpBettype;
	DROP TABLE #PrizeBettypeGroup;
	DROP TABLE #tmpSportType;
	DROP TABLE #tmpMatch;
END;

GO

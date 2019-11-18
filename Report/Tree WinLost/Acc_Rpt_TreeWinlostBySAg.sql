/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_TreeWinlostBySAg
	@FromDate      DATETIME
   , @ToDate        DATETIME
   , @srecommend    INT
   , @Products      VARCHAR(4000) /* instead of all @showXXX parameters*/
AS
/*  
Created by: Scott  
Date: 2012-12-14 
Task : Report Tree Win Lost  
DB: DBACC.bodb02  
Original SP:   
Revisions:  
	20130115@Scott : Fix bug sum total of poker sporttype
	20130418@Scott : Update formula turnover of Racing
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
	20190117@Robert: Video Poker - Integrate into NAP Reports (#107706)
	20190311@Cherry: Integrate Bet Builder (#109822)
	20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
	20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
	20190918@Robert: Remove inactive products (#120215)	   
	20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
*/

BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #TmpResultAll(
	    mrecommend        INT
	  , VarianceVR        DECIMAL(5, 2)
	  , TurnoverIBC       DECIMAL(19, 6)
	  , WinlossIBC        DECIMAL(19, 6)
	  , CommissionS       DECIMAL(19, 6)
	  , ExtraWL           DECIMAL(19, 6)
	  , ExtraTO           DECIMAL(19, 6)
	  , ExtraComm         DECIMAL(19, 6)
/*RM*/
	  , TurnoverIBC_RM    DECIMAL(19, 6)
	  , WinlossIBC_RM     DECIMAL(19, 6)
	  , CommissionS_RM    DECIMAL(19, 6)
	  , ExtraWL_RM        DECIMAL(19, 6)
	  , ExtraTO_RM        DECIMAL(19, 6)
	  , ExtraComm_RM      DECIMAL(19, 6));

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @SportBettype TABLE(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(200));
    INSERT INTO @SportBettype
		 SELECT ProductID
			 , Bettype
			 , EventType
			 , SubProduct
		 FROM dbo.f_SportBettypeMatrix_Sel
			 (0, 0, 0, 2, '', '', @isTest) AS sb
		 WHERE sb.BetType NOT IN(901, 902, 911, 912);

	IF OBJECT_ID('tempdb..#PrizeBettypeGroup') IS NOT NULL
	BEGIN
		DROP TABLE #PrizeBettypeGroup;
	END;
	CREATE TABLE #PrizeBettypeGroup (Bettype SMALLINT)
	INSERT INTO #PrizeBettypeGroup
	SELECT Bettype FROM DBDW.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID=6

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



    IF OBJECT_ID('tempdb..#tmpBettype') IS NOT NULL
	   BEGIN
		  DROP TABLE #tmpBettype;
	   END;

    CREATE TABLE #tmpBettype(
	    ProductID    INT
	  , bettype      INT);

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = -1
		    )
	   BEGIN
		  WITH tblP(ProductID)
			  AS (
			  SELECT 1 AS ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -1)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype)
				    SELECT tblS.ProductID
					    , tblS.bettype
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
			  SELECT-2 AS ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -2)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype)
				    SELECT tblP.ProductID
					    , tblS.bettype
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
			  SELECT 1 AS ProductID
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -3)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype)
				    SELECT tblS.ProductID
					    , tblS.bettype
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
						    , bettype)
			    SELECT tblP.ProductID
				    , tblS.bettype
			    FROM @SportBettype AS tblS
				   INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
			    WHERE tblP.ProductID = 1
					AND tblS.SubProduct NOT IN('MG-SuperLive', 'BT-Comm', 'BT-Winloss', 'Bet Builder');
	   END;
/*-- Extra PT */

    CREATE TABLE #ExtraPT(
	    ProductID     INT
	  , Sporttype     INT
	  , SubProduct    VARCHAR(500)
	  , SuperID       INT
	  , ExtraPT       DECIMAL(9, 8));

    INSERT INTO #ExtraPT(ProductID
				   , Sporttype
				   , SubProduct
				   , SuperID
				   , ExtraPT)
		 SELECT ProductID
			 , SportType
			 , SubProduct
			 , SuperId
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @FromDate BETWEEN FromDate AND ToDate
			  AND SubProduct NOT IN('BT-Sold', 'BT-Bought', 'CO-Cashout', 'CO-Bought')
		 GROUP BY ProductID
			   , SportType
			   , SubProduct
			   , SuperId;

    CREATE TABLE #ExtraComm(
	    ProductID        INT
	  , Sporttype        INT
	  , SubProduct       VARCHAR(500)
	  , SuperID          INT
	  , ExtraCommRate    DECIMAL(9, 8));

    INSERT INTO #ExtraComm(ProductID
					, Sporttype
					, SubProduct
					, SuperID
					, ExtraCommRate)
		 SELECT ProductID
			 , SportType
			 , SubProduct
			 , SuperId
			 , SUM(ExtraCommRate) AS ExtraCommRate
		 FROM bodb02.dbo.Acc_GroupExtraCommRateSetting AS a WITH (NOLOCK)
		 WHERE @FromDate BETWEEN FromDate AND ToDate
			  AND SubProduct NOT IN('BT-Sold', 'BT-Bought', 'CO-Cashout', 'CO-Bought')
		 GROUP BY ProductID
			   , SportType
			   , SubProduct
			   , SuperId;

    CREATE TABLE #Match44(
	    MatchID      INT
	    PRIMARY KEY
	  , SportType    INT);

    INSERT INTO #Match44(MatchID
				   , sporttype)
		 SELECT matchid
			 , l.sporttype
		 FROM bodb02..match AS m(NOLOCK)
			INNER JOIN bodb02..League AS l(NOLOCK) ON m.leagueid = l.leagueid
		 WHERE l.sporttype = 44;

    CREATE TABLE #ProductBettype(
	    Bettype       INT
	    PRIMARY KEY
	  , ProductID     INT
	  , SubProduct    VARCHAR(500));

    INSERT INTO #ProductBettype(ProductID
						, bettype
						, SubProduct)
		 SELECT DISTINCT
			   productID
			 , bettype
			 , CASE
				  WHEN SubProduct IN(SELECT SubProduct
								 FROM bodb02.dbo.Acc_GroupExtraPTSetting
									 (NOLOCK)
								 WHERE SubProduct <> '')
				  THEN SubProduct
				  ELSE ''
			   END AS SubProduct
		 FROM bodb02.dbo.SportBettypeMatrix
			 (NOLOCK) AS sb
		 WHERE sb.BetType NOT IN(901, 902, 911, 912);

    INSERT INTO #tmpBettype(ProductID
					 , bettype)
		 SELECT tblP.ProductID
			 , tblS.bettype
		 FROM @SportBettype AS tblS
			INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
		 WHERE tblP.ProductID <> 1;

    CREATE CLUSTERED INDEX IDX_Bettype_bettype_ProductID ON #tmpBettype(bettype, ProductID);

    INSERT INTO #TmpResultAll
		 SELECT b.mrecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) AS VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                      TurnoverIBC
			 , SUM(CASE
					 WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN t.bettype IN(2198, 2398, 2998)
					 THEN b.ContributionRate * b.BetStake + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END) AS                                                WinlossIBC
			 , SUM(scomm) AS                                              CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1 THEN 0
					 WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN b.gameID IN(2198, 2398, 2998)
					 THEN(b.ContributionRate * b.BetStake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                        ExtraComm
/*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS         TurnoverIBC_RM
			 , SUM(CASE
					 WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN t.bettype IN(2198, 2398, 2998)
					 THEN b.ContributionRate * b.BetStake + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END * actualrate) AS                                   WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                 CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1 THEN 0
					 WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
					 WHEN b.gameID IN(2198, 2398, 2998)
					 THEN(b.ContributionRate * b.BetStake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                   ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                   ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS           ExtraComm_RM
		 FROM bettransRNG AS b WITH (NOLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.gameID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = 0
			LEFT JOIN #PrizeBettypeGroup bg ON b.gameID = bg.Bettype
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID IN(6, 22, 24, 32, 34)
			  AND b.statusID NOT IN(0, 1, 101, 102, 103)
			  AND b.currency <> 20
			  AND b.srecommend = @srecommend
		 GROUP BY b.mrecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);



    INSERT INTO #TmpResultAll
		 SELECT b.mrecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) AS                     VarianceVR
			 , SUM(CASE
					 WHEN pb.ProductID = 1
					 THEN ABS(stake)					 
					 ELSE stake
				  END * (1 - tpositiontaking)) AS                                            TurnoverIBC
			 , SUM(swinlost + mwinlost + awinlost + winlost - actual_stake) AS                WinlossIBC
			 , SUM(scomm) AS                                                                  CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0					 
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN pb.ProductID = 1
							THEN ABS(stake)							
							ELSE stake
						 END * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0						 
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
/*RM*/
			 , SUM(CASE
					 WHEN pb.ProductID = 1
					 THEN ABS(stake)					 
					 ELSE stake
				  END * (1 - tpositiontaking) * actualrate) AS                               TurnoverIBC_RM
			 , SUM((swinlost + mwinlost + awinlost + winlost - actual_stake) * actualrate) AS WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0					 
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN pb.ProductID = 1
							THEN ABS(stake)							
							ELSE stake
						 END * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0						 
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettrans AS b WITH (ROWLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.bettype
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.bettype
			LEFT JOIN #Match44 AS m44 ON b.matchid = m44.MatchID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = ISNULL(m44.SportType, 0)
			LEFT JOIN #ExtraComm AS excomm ON excomm.SuperID = b.srecommend
									    AND excomm.ProductID = pb.ProductID
									    AND excomm.SubProduct = pb.SubProduct
									    AND excomm.Sporttype = ISNULL(m44.SportType, 0)
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID NOT IN(6, 21, 22, 24, 32, 34) /* excule AllBet	*/			  
			  AND b.ruben = 1
			  AND b.statusID NOT IN(101, 102, 103)
			  AND b.currency <> 20
			  AND b.srecommend = @srecommend
		 GROUP BY b.mrecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);

    INSERT INTO #TmpResultAll
		 SELECT b.mrecommend
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) AS                     VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                                          TurnoverIBC
			 , SUM(swinlost + mwinlost + awinlost + winlost - actual_stake) AS                WinlossIBC
			 , SUM(scomm) AS                                                                  CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
/*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS                             TurnoverIBC_RM
			 , SUM((swinlost + mwinlost + awinlost + winlost - actual_stake) * actualrate) AS WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(19, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettransLC AS b WITH (NOLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.gameID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = 0
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID = 21 /* AllBet	*/
			  AND b.statusID NOT IN(0, 1, 101, 102, 103)
			  AND b.currency <> 20
			  AND b.srecommend = @srecommend
		 GROUP BY b.mrecommend
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);


    SELECT b.mrecommend
	    , cm.username
	    , ISNULL(cm.virtualmultiplier, 1) AS                                                              EnableVirtualrate
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
	   INNER JOIN custinfo AS cm WITH (NOLOCK) ON b.mrecommend = cm.custid
    GROUP BY b.mrecommend
		 , cm.username
		 , ISNULL(cm.virtualmultiplier, 1)
    ORDER BY username;

    DROP TABLE #TmpResultAll;
    DROP TABLE #ExtraPT;
    DROP TABLE #ExtraComm;
    DROP TABLE #ProductBettype;
    DROP TABLE #Match44;
    DROP TABLE #Product;
    DROP TABLE #tmpBettype;
	DROP TABLE #PrizeBettypeGroup;
END;


GO

GRANT EXECUTE ON dbo.Acc_Rpt_TreeWinlostBySAg TO [bodbAdminNet];
GO
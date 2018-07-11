/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_TreeWinlostByProduct
	@FromDate             DATETIME
   , @ToDate               DATETIME
   , @Products             VARCHAR(4000)
/* 8RM account*/
   , @TurnOver_8RM         MONEY         = 0 OUTPUT
   , @Total_8RM            MONEY         = 0 OUTPUT
   , @VirtualTotal_8RM     MONEY         = 0 OUTPUT
/* BARM account*/
   , @TurnOver_BARM        MONEY         = 0 OUTPUT
   , @Total_BARM           MONEY         = 0 OUTPUT
   , @VirtualTotal_BARM    MONEY         = 0 OUTPUT
AS
/*    
Created by: Scott    
Date: 2012-12-14   
Task : Report Tree Win Lost    
DB: DBACC.bodb02    
Original SP:     
Revisions:    
	- 20130115@Scott : fix bug sum total of poker sporttype
	- 20130122@Scott : Does not use #bettrans14,query data direct bettrans14
	- 20130418@Scott : Update formula turnover of Racing
	- 20130702@Dom.Cao: Add Vanriance (+\-)
	- 20140304@TomVo: 
		Change Name Server (DB06) to Alias Server (DBACC)
		Add Keno Sport (202) -Bettype : 1501 - 1599
	- 20150529@Jim: add more parameter @ShowGD,@ShowMGSL and apply sport-bettype matrix 	
	- 20150710@Jim: Super Balance fix and Microgaming integration (Feature #38168)
	- 20150723@Jim: Apply Bettrade [#38815]
	- 20150828@Jim: support Colossus Bet (#42608)
	- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	- 20151214@Percy: 1. Add new product: Cockfighting [Redmine: #49027]
					  2. Change input parameters
	- 20160118@Percy: Calculate turnover for RNG Casino [Redmine: #49134]
	- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
	- 20160615@Sophia: Change READPAST to ROWLOCK because of the Deadlock [Redmind: #59254]
	- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	- 20160916@Robert: Integrate new product NG2 [RedmindID: #63460]
	- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
	- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
	- 20180411@Franklin: Integrate Pragmatic (#92642)
	- 20180504@Dominic: Apply new VR concepts - Redminde:#94213
	- 20180711@Robert: NAP Report - Add Cash Out & Bettrade into Tree Win Loss report [RedmindID: #98005]
*/

BEGIN

    SET NOCOUNT ON;

    DECLARE @tmpIBCFee TABLE(
	    partnerID    INT
	  , IBCFee       BIT);
    DECLARE @CommSetting TABLE(
	    MatchID          INT
	  , IBCFee           BIT
	  , ToteCommWin      SMALLMONEY
	  , ToteCommPlace    SMALLMONEY
	  , ToteCommWP       SMALLMONEY
	  , ToteFee          SMALLMONEY);

    CREATE TABLE #TmpResultAll(
	    Currency          TINYINT
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


    IF OBJECT_ID('tempdb..#Product') IS NOT NULL
	   BEGIN
		  DROP TABLE #Product;
	   END;

    CREATE TABLE #Product(
	    ProductID       INT
	  , IsNoTurnover    BIT
	  , IsNoVirtual     BIT);

    DECLARE @DocHandler    INT;

    BEGIN TRY
	   EXEC sp_xml_preparedocument
		   @DocHandler OUTPUT
		 , @Products;

	   INSERT INTO #Product(ProductID
					  , IsNoTurnover
					  , IsNoVirtual)
			SELECT ProductID
				, IsNoTurnover
				, IsNoVirtual
			FROM OPENXML(@DocHandler, '/ROOT/Product', 1) WITH(ProductID    INT, IsNoTurnover BIT, IsNoVirtual BIT) AS Data;

	   EXEC sp_xml_removedocument
		   @DocHandler;
    END TRY
    BEGIN CATCH
	   SELECT ErrCode = 100
		   , ErrMsg = N'Paramter invalid.';

	   RETURN;
    END CATCH;

    IF OBJECT_ID('tempdb..#tmpBettype') IS NOT NULL
	   BEGIN
		  DROP TABLE #tmpBettype;
	   END;

    CREATE TABLE #tmpBettype(
	    ProductID       INT
	  , bettype         INT
	  , IsNoTurnover    BIT
	  , IsNoVirtual     BIT);

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM #Product AS P
			   WHERE p.ProductID = -1
		    )
	   BEGIN
		  WITH tblP(ProductID
				, IsNoTurnover
				, IsNoVirtual)
			  AS (
			  SELECT 1 AS ProductID
				  , IsNoTurnover
				  , IsNoVirtual
			  FROM #Product AS tblP
			  WHERE tblP.ProductID = -1)
			  INSERT INTO #tmpBettype(ProductID
							    , bettype
							    , IsNoTurnover
							    , IsNoVirtual)
				    SELECT tblS.ProductID
					    , tblS.bettype
					    , tblP.IsNoTurnover
					    , tblP.IsNoVirtual
				    FROM tblP
					  , @SportBettype AS tblS
				    WHERE tblS.ProductID = 1
						AND tblS.SubProduct IN('MG-SuperLive');
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
						    , IsNoTurnover
						    , IsNoVirtual)
			    SELECT tblP.ProductID
				    , tblS.bettype
				    , tblP.IsNoTurnover
				    , tblP.IsNoVirtual
			    FROM @SportBettype AS tblS
				   INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
			    WHERE tblP.ProductID = 1
					AND tblS.SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought');
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
					 , bettype
					 , IsNoTurnover
					 , IsNoVirtual)
		 SELECT tblP.ProductID
			 , tblS.bettype
			 , tblP.IsNoTurnover
			 , tblP.IsNoVirtual
		 FROM @SportBettype AS tblS
			INNER JOIN #Product AS tblP ON tblS.ProductID = tblP.ProductID
		 WHERE tblP.ProductID <> 1;

    CREATE CLUSTERED INDEX IDX_Bettype_bettype_ProductID ON #tmpBettype(bettype, ProductID);
/*Get data from bettransRNG*/

    INSERT INTO #TmpResultAll
		 SELECT b.currency
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) AS VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                      TurnoverIBC
			 , SUM(CASE
					 WHEN t.bettype IN(2199, 2399, 2999)
					 THEN 0 /*Progressive Jackpot*/
					 WHEN t.bettype IN(2198, 2398, 2998)
					 THEN b.ContributionRate * b.BetStake + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END) AS                                                WinlossIBC
			 , SUM(scomm) AS                                              CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 WHEN b.gameID IN(2199, 2399, 2999)
					 THEN 0 /*Progressive Jackpot*/
					 WHEN b.gameID IN(2198, 2398, 2998)
					 THEN(b.ContributionRate * b.BetStake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                        ExtraComm
/*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS         TurnoverIBC_RM
			 , SUM(CASE
					 WHEN t.bettype IN(2199, 2399, 2999)
					 THEN 0 /*Progressive Jackpot*/
					 WHEN t.bettype IN(2198, 2398, 2998)
					 THEN b.ContributionRate * b.BetStake + swinlost + mwinlost + awinlost /*Jackpot Contribution*/
					 ELSE swinlost + mwinlost + awinlost + winlost - actual_stake
				  END * actualrate) AS                                   WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                 CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 WHEN b.gameID IN(2199, 2399, 2999)
					 THEN 0 /*Progressive Jackpot*/
					 WHEN b.gameID IN(2198, 2398, 2998)
					 THEN(b.ContributionRate * b.BetStake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) /*Jackpot Contribution*/
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                   ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                   ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS           ExtraComm_RM
		 FROM bettransRNG AS b WITH (ROWLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.gameID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = 0
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID IN(6, 17, 22, 24, 32)
			  AND b.statusID NOT IN(0, 1, 101, 102, 103, 121)
			  AND b.currency <> 20
		 GROUP BY b.currency
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);
/*-get data from bettransLC*/

    INSERT INTO #TmpResultAll
		 SELECT b.currency
			 , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) AS                     VarianceVR
			 , SUM(stake * (1 - tpositiontaking)) AS                                          TurnoverIBC
			 , SUM(swinlost + mwinlost + awinlost + winlost - actual_stake) AS                WinlossIBC
			 , SUM(scomm) AS                                                                  CommissionS
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                                    ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
/*RM*/
			 , SUM(stake * (1 - tpositiontaking) * actualrate) AS                             TurnoverIBC_RM
			 , SUM((swinlost + mwinlost + awinlost + winlost - actual_stake) * actualrate) AS WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE stake * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettransLC AS b WITH (ROWLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.gameID
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.gameID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = 0
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID = 21
			  AND b.statusID NOT IN(0, 1, 101, 102, 103, 121)
			  AND b.currency <> 20
		 GROUP BY b.currency
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);
/*Get data from bettrans*/

    INSERT INTO #TmpResultAll
		 SELECT b.currency
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
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                                    ExtraWL
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN pb.ProductID = 1
							THEN ABS(stake)
							ELSE stake
						 END * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END) AS                                                                    ExtraTO
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END) AS DECIMAL(19, 6)) AS                                            ExtraComm
/*RM*/
			 , SUM(ABS(stake) * (1 - tpositiontaking) * actualrate) AS                        TurnoverIBC_RM
			 , SUM((swinlost + mwinlost + awinlost + winlost - actual_stake) * actualrate) AS WinlossIBC_RM
			 , SUM(scomm * actualrate) AS                                                     CommissionS_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                                       ExtraWL_RM
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN pb.ProductID = 1
							THEN ABS(stake)
							ELSE stake
						 END * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8))
				  END * actualrate) AS                                                       ExtraTO_RM
			 , CAST(SUM(CASE
						 WHEN tpositiontaking = 1
						 THEN 0
						 ELSE scomm * CAST(ISNULL(ExtraPT, 0) AS DECIMAL(10, 8)) / (1 - tpositiontaking)
					  END * actualrate) AS DECIMAL(19, 6)) AS                               ExtraComm_RM
		 FROM bettrans AS b WITH (ROWLOCK)
			INNER JOIN #tmpBettype AS t ON t.bettype = b.bettype
			INNER JOIN #ProductBettype AS pb ON pb.Bettype = b.bettype
			LEFT JOIN #Match44 AS m44 ON b.matchid = m44.MatchID
			LEFT JOIN #ExtraPT AS expt ON expt.SuperID = b.srecommend
									AND expt.ProductID = pb.ProductID
									AND expt.SubProduct = pb.SubProduct
									AND expt.Sporttype = ISNULL(m44.SportType, 0)
		 WHERE winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
			  AND t.ProductID NOT IN(2, 6, 9, 17, 21, 22, 24, 32)
			  AND b.ruben = 1
			  AND b.statusID NOT IN(101, 102, 103, 121)
			  AND b.currency <> 20
		 GROUP BY b.currency
			   , CAST(b.virtualrate / b.actualrate - 1 AS DECIMAL(5, 2)) OPTION(RECOMPILE);

    SELECT @TurnOver_8RM = SUM(ABS(stake) * (1 - tpositiontaking) * actualrate)
	    , @Total_8RM = -SUM((swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) * actualrate)
	    , @VirtualTotal_8RM = -SUM((swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) * CASE
																					   WHEN t.IsNoVirtual = 0
																					   THEN b.virtualrate
																					   ELSE actualrate
																				    END)
    FROM bettrans AS b WITH (NOLOCK)
	   INNER JOIN #tmpBettype AS t ON t.bettype = b.bettype
    WHERE recommend = 52466
		AND ruben = 1
		AND winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
		AND b.statusID NOT IN(101, 102, 103, 121);

    SELECT @TurnOver_BARM = SUM(ABS(stake) * (1 - tpositiontaking) * actualrate)
	    , @Total_BARM = -SUM((swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) * actualrate)
	    , @VirtualTotal_BARM = -SUM((swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) * CASE
																					    WHEN t.IsNoVirtual = 0
																					    THEN b.virtualrate
																					    ELSE actualrate
																					END)
    FROM bettrans AS b WITH (NOLOCK)
	   INNER JOIN #tmpBettype AS t ON t.bettype = b.bettype
    WHERE recommend = 5707545
		AND ruben = 1
		AND winlostdate BETWEEN CAST(@FromDate AS SMALLDATETIME) AND CAST(@ToDate AS SMALLDATETIME)
		AND b.statusID NOT IN(101, 102, 103, 121);
/*-record set main data*/

    SELECT currency
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
    FROM #TmpResultAll
    GROUP BY currency;

    DROP TABLE #TmpResultAll;
    DROP TABLE #ExtraPT;
    DROP TABLE #ProductBettype;
    DROP TABLE #Match44;
    DROP TABLE #Product;
    DROP TABLE #tmpBettype;
END;


GO

GRANT VIEW DEFINITION ON dbo.Acc_Rpt_TreeWinlostByProduct TO [vnteam];
GO

GRANT EXECUTE ON dbo.Acc_Rpt_TreeWinlostByProduct TO [bodbAdminNet];
GO
USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Products]    Script Date: 5/22/2018 8:51:28 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Products    Script Date: 5/21/2018 9:03:23 AM ******/
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Products    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Products]
      @StartDate SMALLDATETIME,
      @EndDate   SMALLDATETIME
AS

/*	Creator: Sophia.Nguyen
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #48448]
	DB: DBACC/bodb02	
		
	Revisions:
		- 20160622@Sophia: 	. Remove group by ExtraPT to avoid duplicated data. [Redmine: #59732]
							. Ignore param @EndDate because of the performance, and business supports only one day 
		 
		- 20160915@Percy: Integrate NG2 [RedmineID: #63460]
		- 20160922@Percy: Use local parameter to prevent bad parameter sniffing [RedmindID: #64573]
		- 20161130@Percy: Integrate Fishing World [RedmineID: #67757]
		- 20161213@Sophia: Remove parameter @winlostdate, use @StartDate to obtain parameter sniffing [RedmindID: #68634]
		- 20160112@Percy: Change Extra PT formula [RedmineID: #70208]
		- 20170323@Percy: Integrate Cash Out [RemineID: #73419]
		- 20170720@Franklin: Integrate Lottery and Betradar Virtual Sports (#78184)
		- 20170825@Franklin: Integrate Lucky 3 (#78214)
		- 20171013@Franklin: ExtraPT Setting - DB Restructure (#84802)
		- 20171102@Franklin: Bullfighting(#85382)
		- 20171211@Franklin: Exchange(#86456)
		- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
		- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
	Explanation's Param:
	
*/

    BEGIN
        SET NOCOUNT ON;
        DECLARE @EffectedDate DATETIME; -- 20160112@Percy: Applying date of changing extra PT formula [RedmineID: #70208]
        SELECT @EffectedDate = '2017-01-19';
	
        ------Get Sport Bettype Matrix------
        -- Check SP Version	 
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBettype( ProductID  INT,
                                    Bettype    INT,
                                    EventType  INT,
                                    SubProduct VARCHAR(500),
                                    RefTable   TINYINT,
                                    CasinoType TINYINT );
        INSERT INTO #SportBettype
               ( ProductID,
                 Bettype,
                 EventType,
                 SubProduct,
                 RefTable,
                 CasinoType
               )
               SELECT ProductID,
                      Bettype,
                      EventType,
                      SubProduct,
                      RefTable,
                      CasinoType
               FROM dbo.f_SportBettypeMatrix_Sel( 0, 0, 0, 2, '', '', @isTest )
               WHERE bettype NOT IN( 911, 912 ); -- remove Cash Out
        --- End Sport Bettype Matrix------

		CREATE TABLE #tmp_src( 
						   srecommend				    INT,
						   bettype					    INT,
                           site                         TINYINT,
                           Sporttype                    INT,
                           winlost_actualrate           MONEY,
                           SMAWinloss				    MONEY,
                           commission_actualrate        MONEY,
                           HouseWinloss_actualrate      MONEY,
                           HouseWinloss_virtualrate     MONEY,
						   HouseWinloss_variance        MONEY,
                           grosscomm_actualrate         DECIMAL(19,6),
						   grosscomm_virtualrate        DECIMAL(19,6),
						   grosscomm_variance           DECIMAL(19,6),
                           ProductId                    INT,
                           CasinoType                   TINYINT,
                           turnover_actualrate          MONEY,
                           turnover_virtualrate         MONEY,
                           stake_actualrate             MONEY,
                           stake_virtualrate            MONEY,
                           WinlossForExtraPT_actualrate  MONEY,
                           WinlossForExtraPT_virtualrate MONEY);

        CREATE TABLE #src( srecommend                INT,
                           site                      TINYINT,
                           Sporttype                 INT,
                           winlost_actualrate        MONEY,
                           SMAWinloss				 MONEY,
                           commission_actualrate     MONEY,
                           HouseWinloss_actualrate      MONEY,
                           HouseWinloss_virtualrate     MONEY,
						   HouseWinloss_variance        MONEY,
                           grosscomm_actualrate      MONEY,
						   grosscomm_virtualrate     MONEY,
						   grosscomm_variance        MONEY,
                           ProductId                 INT,
                           CasinoType                TINYINT,
                           turnover_actualrate       MONEY,
                           turnover_virtualrate      MONEY,
                           stake_actualrate          MONEY,
                           stake_virtualrate         MONEY,
                           WinlossForExtraPT_actualrate  MONEY,
                           WinlossForExtraPT_virtualrate MONEY );
        CREATE TABLE #srcDetail( srecommend                   INT,
                                 site                         TINYINT,
                                 winlost_actualrate           MONEY,
                                 SMAWinloss					  MONEY,
                                 commission_actualrate        MONEY,
                                 HouseWinloss_actualrate         MONEY,
                                 HouseWinloss_virtualrate        MONEY,
								 HouseWinloss_variance           MONEY,
                                 grosscomm_actualrate         MONEY,
								 grosscomm_virtualrate        MONEY,
								 grosscomm_variance           MONEY,
                                 ProductId                    INT,
                                 CasinoType                   TINYINT,
                                 turnover_actualrate          MONEY,
                                 turnover_virtualrate         MONEY,
                                 stake_actualrate             MONEY,
                                 stake_virtualrate            MONEY,
                                 WinlossForExtraPT_actualrate     MONEY,
                                 WinlossForExtraPT_virtualrate    MONEY );
        CREATE TABLE #Result( DisplayOrder     INT,
                              ProductId        INT,
                              ProductName      NVARCHAR(50),
                              site             TINYINT,
                              winlost          MONEY,
                              Position         MONEY,
                              Commission       MONEY,
                              RealHouseWinloss    MONEY,
                              VirtualHouseWinloss MONEY,
							  VarianceIncome   MONEY,
                              RealTurnover     MONEY,
                              VirtualTurnover  MONEY,
                              ExtraPT          MONEY,
                              NewExtraPT       MONEY );


        --- Deposit Super
        CREATE TABLE #DepSuper( custid INT );
        INSERT INTO #DepSuper
               SELECT custid
               FROM f_DepSuper_1( 'All' );
	
	
        ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( ProductID  INT,
                                   Sporttype  INT,
                                   SubProduct VARCHAR(100),
                                   SuperID    INT,
                                   ExtraPT    DECIMAL(9, 8));
        INSERT INTO #ExtraPT_Sel
               ( ProductID, Sporttype, SubProduct, SuperID, ExtraPT)
               SELECT ProductID, SportType, SubProduct, SuperId, SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY ProductID, SportType, SubProduct, SuperId;
	
        ----------------------	Racing -------------------------------------
        DECLARE @RBWinlost TABLE( site      TINYINT,
                                  winlost   MONEY,
                                  pos       MONEY,
                                  comm      MONEY,
                                  HouseWinloss MONEY,
                                  turnover  MONEY );	


        ---insert company's comm setting that is recieved from Phumelela into this temp table.
        DECLARE @tmpIBCFee TABLE( partnerID INT,
                                  IBCFee    BIT );
        DECLARE @CommSetting TABLE( MatchId       INT,
                                    IBCFee        BIT,
                                    ToteCommWin   SMALLMONEY,
                                    ToteCommPlace SMALLMONEY,
                                    ToteCommWP    SMALLMONEY,
                                    ToteFee       SMALLMONEY );
        INSERT INTO @tmpIBCFee
               ( partnerID,
                 IBCFee
               )
               SELECT 1,
                      1 --RACE-PHU
               UNION ALL
               SELECT 2,
                      0 --RACE-ATRUK
               UNION ALL
               SELECT 3,
                      0 --RACE-ATRIRL
               UNION ALL
               SELECT 4,
                      0 --RACE-RUK
               UNION ALL
               SELECT 5,
                      1 --RACE-TABCORP
               UNION ALL
               SELECT 6,
                      1 --RACE-TABCORPNSW
               UNION ALL
               SELECT 101,
                      1 --GREY-DTOTEUK
               UNION ALL
               SELECT 102,
                      1 --GREY-DTOTEIRL
               UNION ALL
               SELECT 103,
                      1 --GREY-TABCORP
               UNION ALL
               SELECT 104,
                      1 --GREY-TABCORPNSW
               UNION ALL
               SELECT 201,
                      1 --HAR-TABCORP
               UNION ALL
               SELECT 202,
                      1; --HAR-TABCORPNSW	


        INSERT INTO @CommSetting
               ( MatchId,
                 IBCFee,
                 ToteCommWin,
                 ToteCommPlace,
                 ToteCommWP,
                 ToteFee
               )
               SELECT DISTINCT o.orid AS MatchId,
                               t.IBCFee,
                               p.ToteCommWin,
                               p.ToteCommPlace,
                               ( p.ToteCommWin + p.ToteCommPlace ) / 2 ToteCommWP,
                               p.ToteFee
               FROM outright o WITH ( NOLOCK )
                    INNER JOIN LeagueDetail p WITH ( NOLOCK ) ON o.LeagueId = p.LeagueId
                                                             AND p.programDate = o.programDate
                    INNER JOIN RacingMeeting r WITH ( NOLOCK ) ON r.meetingID = p.LeagueId
                    INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
               WHERE o.EventDate = @StartDate;
	
	
        ----------------------------------- 
        INSERT INTO @RBWinlost
               ( site,
                 winlost,
                 pos,
                 comm,
                 HouseWinloss,
                 turnover
               )
               SELECT CASE
                          WHEN dep.custid IS NULL
                          THEN 1
                          ELSE 2
                      END AS site,
                      SUM(( b.winlost - b.actual_stake ) * b.actualrate) AS winlost,
                      SUM(( b.awinlost + b.mwinlost + b.swinlost ) * b.actualrate) AS pos,
                      SUM(b.scomm * b.actualrate) AS comm,
                      -( SUM(( CASE
                                   WHEN b.bettype = 33
                                   THEN bm.WLIBC
                                   ELSE-( b.winlost - b.actual_stake ) * ISNULL(b.oddsspread, 0)
                               END ) * b.actualrate) - SUM(CASE
                                                               WHEN cs.IBCFee = 0
                                                               THEN 0
                                                               ELSE( CASE
                                                                         WHEN b.bettype = 33
                                                                         THEN bm.TOPhum
                                                                         WHEN b.bettype IN( 31, 32 )
                                                                         THEN b.actual_stake * ( 1 - b.tpositiontaking - ISNULL(b.oddsspread, 0))
                                                                         ELSE 0
                                                                     END ) * b.actualrate * cs.ToteFee
                                                           END) --FeeDue2 
                         + SUM(( CASE b.bettype
                                     WHEN 31
                                     THEN b.actual_stake * cs.ToteCommWin * ( 1 - b.tpositiontaking - ISNULL(oddsspread, 0))
                                     WHEN 32
                                     THEN b.actual_stake * cs.ToteCommPlace * ( 1 - b.tpositiontaking - ISNULL(oddsspread, 0))
                                     WHEN 33
                                     THEN bm.TOPhum * cs.ToteCommWP
                                     ELSE 0
                                 END ) * b.actualrate) --commIncomeIBC
                         - SUM(b.scomm * b.actualrate)) AS realHouseWinloss,
                      SUM(CASE
                              WHEN b.bettype = 33
                              THEN bm.TOIBC * b.actualrate
                              ELSE b.actual_stake * ISNULL(oddsspread, 0) * b.actualrate
                          END) AS turnover
               FROM bettrans b WITH ( nolock )
                    INNER JOIN @CommSetting AS cs ON b.MatchId = cs.MatchId
                    LEFT JOIN( 
                               SELECT refno,
                                      SUM(CASE
                                              WHEN bm.bettype = 32
                                               AND liveawayscore = 0
                                              THEN 0
                                              ELSE stake * ISNULL(oddsspread, 0)
                                          END) TOIBC,
                                      -SUM(( winlost - stake ) * ISNULL(oddsspread, 0)) WLIBC,
                                      SUM(CASE
                                              WHEN bm.bettype = 32
                                               AND liveawayscore = 0
                                              THEN 0
                                              WHEN bm.bettype = 31
                                                OR ( bm.bettype = 32
                                                 AND liveawayscore <> 0
                                                   )
                                              THEN stake * ( 1 - tpositiontaking - ISNULL(oddsspread, 0))
                                              ELSE 0
                                          END) TOPhum
                               FROM bettransm bm WITH ( nolock )
                                    INNER JOIN #SportBettype s ON s.Bettype = bm.bettype
                               WHERE s.ProductID = 2
                               GROUP BY refno ) bm ON b.transid = bm.refno
                    INNER JOIN #SportBettype s ON s.Bettype = b.bettype
                    LEFT JOIN( 
                               SELECT custid
                               FROM #DepSuper ) dep ON b.srecommend = dep.custid
               WHERE b.ruben = 1
                 AND s.ProductID = 2
                 AND b.MatchId > 0
                 AND b.winlostdate = @StartDate
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY CASE
                            WHEN dep.custid IS NULL
                            THEN 1
                            ELSE 2
                        END;

        -------------------------------------- End of Racing -------------------------------------------------
        CREATE TABLE #Match( MatchId   INT,
                             sporttype SMALLINT,
                             [type]    TINYINT );--, primary key(MatchId, type))
        INSERT INTO #Match
               SELECT m.MatchId,
                      s.sporttype,
                      m.type
               FROM(
                   SELECT MatchId,
                          LeagueId,
                          exrisk,
                          MatchCode,
                          0 AS type --'match'
                   FROM match WITH ( NOLOCK )
                   WHERE EventDate = @StartDate
                   UNION ALL
                   SELECT orid,
                          LeagueId,
                          0,
                          MatchCode,
                          1 AS type --'outright'
                   FROM outright WITH ( NOLOCK )
                   WHERE EventDate = @StartDate ) m
                   INNER JOIN league l WITH ( NOLOCK ) ON m.LeagueId = l.LeagueId
                   INNER JOIN Sports s WITH ( NOLOCK ) ON l.sporttype = s.sporttype;
        CREATE CLUSTERED INDEX CIX_MatchID ON #Match( MatchID, [Type] );
	
        --------------------------------------------------------------------------------
        ---1. Sportsbook only and outright
        INSERT INTO #tmp_src
               ( srecommend,bettype,site,SportType,
                 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 ProductId,turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,WinlossForExtraPT_virtualrate
               )
               SELECT srecommend,
			          b.bettype,
                      1 AS site,
                    CASE WHEN m.sporttype = 44 THEN 44
                        WHEN m.Sporttype = 1 THEN 1 ELSE 2 END AS SportType,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss,
                      SUM(scomm * actualrate) commission_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) HouseWinloss_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost ) * virtualrate 
								+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) HouseWinloss_virtualrate,
					  SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost
								+ CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) HouseWinloss_variance,
                      SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                      1 AS ProductId,
                      SUM(( 1 - b.tpositiontaking ) * ABS(stake) * CASE
                                                                               WHEN virtualrate > actualrate
                                                                               THEN virtualrate
                                                                               ELSE actualrate
                                                                           END
                          ) AS turnover_actualrate,
                      SUM(( 1 - b.tpositiontaking ) * ABS(stake) * virtualrate) AS turnover_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE ABS(stake) * CASE
                                                    WHEN virtualrate > actualrate
                                                    THEN virtualrate
                                                    ELSE actualrate
                                                END
                          END) AS stake_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE ABS(stake) * virtualrate
                          END) AS stake_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * actualrate )
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * virtualrate )
                          END) AS WinlossForExtraPT_virtualrate
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
											AND  m.type = (CASE WHEN b.bettype = 10 THEN 1 ELSE 0 END)
               WHERE winlostdate = @StartDate
				 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY srecommend,b.bettype,
                        CASE
                            WHEN m.sporttype = 44 THEN 44
                            WHEN m.Sporttype = 1 THEN 1 ELSE 2 END
				OPTION (RECOMPILE)

       -----------Remove betype of MertricGaming and Bettrade
		DELETE #tmp_src
		WHERE bettype NOT IN (
				   SELECT bettype FROM #SportBettype s
				   WHERE s.productID = 1
				   AND s.EventType IN (1,2)
				   AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm','BT-Winloss') 
		)

		------Soccer and Other Sports
		INSERT INTO #src
               ( srecommend,site,SportType,ProductId,
                 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,WinlossForExtraPT_virtualrate
               )
			   SELECT srecommend,site,SportType,ProductId,
                 SUM(winlost_actualrate), SUM(SMAWinloss), SUM(commission_actualrate),
                 SUM(HouseWinloss_actualrate), SUM(HouseWinloss_virtualrate), SUM(HouseWinloss_variance),
                 SUM(grosscomm_actualrate), SUM(grosscomm_virtualrate), SUM(grosscomm_variance),
                 SUM(turnover_actualrate),SUM(turnover_virtualrate),SUM(stake_actualrate),SUM(stake_virtualrate),
                 SUM(WinlossForExtraPT_actualrate),SUM(WinlossForExtraPT_virtualrate)
			   FROM #tmp_src
			   GROUP BY srecommend,site,SportType,ProductId
			      		 
        ------ BARM (only)
        INSERT INTO #src
               ( srecommend,site,SportType,
                 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 ProductId,turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,WinlossForExtraPT_virtualrate
               )
               SELECT 2 AS srecommend,
                      2 AS site,
                           CASE
                               WHEN m.sporttype = 44
                               THEN 44
                               WHEN m.Sporttype = 1
                               THEN 1
                               ELSE 2
                           END AS SportType,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss,
                      SUM(scomm * actualrate) commission_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) HouseWinloss_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost ) * virtualrate 
								+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) HouseWinloss_virtualrate,
					  SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost
								+ CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) HouseWinloss_variance,
                      SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                      1 AS ProductId,
                      SUM(( 1 - b.tpositiontaking ) * ABS(stake) * CASE
                                                                               WHEN virtualrate > actualrate
                                                                               THEN virtualrate
                                                                               ELSE actualrate
                                                                           END
                          ) AS turnover_actualrate,
                      SUM(( 1 - b.tpositiontaking ) * ABS(stake) * virtualrate) AS turnover_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE ABS(stake) * CASE
                                                    WHEN virtualrate > actualrate
                                                    THEN virtualrate
                                                    ELSE actualrate
                                                END
                          END) AS stake_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE ABS(stake) * virtualrate
                          END) AS stake_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * actualrate )
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * virtualrate )
                          END) AS WinlossForExtraPT_virtualrate
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.bettype = s.bettype
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.recommend = 5707545
                 AND b.winlostdate = @StartDate
                 AND b.bettype < 19001
                 AND b.statusID IN( 111, 112, 113 )
                 AND b.ruben = 1
                 AND m.type = CASE
                                  WHEN b.bettype = 10
                                  THEN 1
                                  ELSE 0
                              END
                 AND s.productID = 1
                 AND s.EventType IN( 1, 2 )
                 AND s.SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
               GROUP BY CASE
                            WHEN m.sporttype = 44
                            THEN 44
                            WHEN m.Sporttype = 1
                            THEN 1
                            ELSE 2
                        END;	

		
        ----- Minus data of BARM 
        UPDATE c
          SET c.winlost_actualrate = c.winlost_actualrate - d.winlost_actualrate,
              c.SMAWinloss = c.SMAWinloss - d.SMAWinloss,
              c.commission_actualrate = c.commission_actualrate - d.commission_actualrate,
              c.HouseWinloss_actualrate = c.HouseWinloss_actualrate - d.HouseWinloss_actualrate,
              c.HouseWinloss_virtualrate = c.HouseWinloss_virtualrate - d.HouseWinloss_virtualrate,
			  c.HouseWinloss_variance = c.HouseWinloss_variance - d.HouseWinloss_variance,
              c.grosscomm_actualrate = c.grosscomm_actualrate - d.grosscomm_actualrate,
			  c.grosscomm_virtualrate = c.grosscomm_virtualrate - d.grosscomm_virtualrate,
			  c.grosscomm_variance = c.grosscomm_variance - d.grosscomm_variance,
              c.turnover_actualrate = c.turnover_actualrate - d.turnover_actualrate,
              c.turnover_virtualrate = c.turnover_virtualrate - d.turnover_virtualrate,
              c.stake_actualrate = c.stake_actualrate - d.stake_actualrate,
              c.stake_virtualrate = c.stake_virtualrate - d.stake_virtualrate,
              c.WinlossForExtraPT_actualrate = c.WinlossForExtraPT_actualrate - d.WinlossForExtraPT_actualrate,
              c.WinlossForExtraPT_virtualrate = c.WinlossForExtraPT_virtualrate - d.WinlossForExtraPT_virtualrate
        FROM #src c
             INNER JOIN #src d ON c.srecommend = d.srecommend
                              AND c.SportType = d.SportType
        WHERE c.srecommend = 2
          AND c.Site = 1
          AND d.Site = 2;
								 

        ---2. Not Sportsbook and not have detail table yet ; and special Sportsbook : Parlay, Metric gaming, Bettrade
        INSERT INTO #src
               ( srecommend,site,SportType,
                 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 ProductId,CasinoType,turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,
                 WinlossForExtraPT_virtualrate
               )
               SELECT srecommend,
                      1 AS site,
                      0 AS SportType,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss,
                      SUM(scomm * actualrate) commission_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) HouseWinloss_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost ) * virtualrate 
								+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) HouseWinloss_virtualrate,
					  SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost
								+ CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) HouseWinloss_variance,
                      SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                                                  CASE s.SubProduct
                                                      WHEN 'MG-SuperLive' THEN-1
                                                      WHEN 'BT-Comm' THEN-2
                                                      WHEN 'BT-Winloss' THEN-2
                                                      ELSE CASE WHEN s.EventType = 0 AND ProductID = 1 THEN-3 ELSE s.ProductID END
                                                  END AS ProductID,
                      s.CasinoType,
                      SUM(( 1 - b.tpositiontaking ) * (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END)
													* CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                          ) AS turnover_actualrate,
                      SUM(( 1 - b.tpositiontaking ) * (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) * virtualrate) AS turnover_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) 
								   * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                          END) AS stake_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) * virtualrate
                          END) AS stake_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * actualrate )
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * virtualrate )
                          END) AS WinlossForExtraPT_virtualrate
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.bettype = s.bettype
               WHERE winlostdate = @StartDate
                 AND b.statusID IN( 111, 112, 113 )
                 AND b.ruben = 1
                 AND (( s.productID <> 1 AND s.RefTable NOT IN( 1, 2 ))
						  OR (s.productID = 1 AND s.SubProduct IN( 'MG-SuperLive', 'BT-Comm', 'BT-Winloss' ))
						  OR (s.productID = 1 AND s.EventType = 0))
               GROUP BY srecommend,
                        CASE s.SubProduct
                            WHEN 'MG-SuperLive' THEN-1
                            WHEN 'BT-Comm' THEN-2
                            WHEN 'BT-Winloss' THEN-2
                            ELSE CASE WHEN s.EventType = 0 AND ProductID = 1 THEN-3 ELSE s.ProductID END
                        END,
                        s.CasinoType;   

        ----3. Get from Detail table ----------
        -- Get bettransRNG data	
        INSERT INTO #srcDetail
               ( srecommend,site,
				 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 ProductId,CasinoType,turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,WinlossForExtraPT_virtualrate
               )
               SELECT b.srecommend,
                      1 AS site,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss,
                      SUM(scomm * actualrate) commission_actualrate,
                      SUM(( CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost + scomm
                                ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm
                            END ) * actualrate) HouseWinloss_actualrate,
                      SUM(( CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
                                ELSE winlost - actual_stake + awinlost + mwinlost + swinlost
                            END ) * virtualrate 
							      + scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) HouseWinloss_virtualrate,
                      SUM((( CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost
                                ELSE winlost - actual_stake + awinlost + mwinlost + swinlost
                            END ) + CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) HouseWinloss_variance,
                      SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                      s.ProductID,
                      s.CasinoType,
                      SUM(( 1 - b.tpositiontaking ) * stake * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END) AS turnover_actualrate,
                      SUM(( 1 - b.tpositiontaking ) * stake * virtualrate) AS turnover_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE stake * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                          END) AS stake_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE stake * virtualrate
                          END) AS stake_virtualrate,
                      SUM((CASE
                              WHEN b.tpositiontaking = 1
                                THEN 0
							  WHEN b.gameId IN( 2199, 2399, 2999 )
                                THEN 0 --Progressive Jackpot
                              WHEN b.gameId IN( 2198, 2398, 2998 )
                                THEN ContributionRate * BetStake  --Jackpot Contribution
                              ELSE winlost - actual_stake
                          END) * actualrate) AS WinlossForExtraPT_actualrate,
                      SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
							  WHEN b.gameId IN( 2199, 2399, 2999 )
                                THEN 0 --Progressive Jackpot
                              WHEN b.gameId IN( 2198, 2398, 2998 )
                                THEN ContributionRate * BetStake  --Jackpot Contribution
                              ELSE winlost - actual_stake
                          END) * virtualrate ) AS WinlossForExtraPT_virtualrate
               FROM bettransRNG b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.gameid = s.bettype
               WHERE winlostdate = @StartDate
                     ----AND s.ProductID IN (6,17,22) 	---- OW RNG(6), Microgaming - RNG Casino (17), Voidbridge (22)
                 AND s.RefTable = 1  --- Use Table BettransRNG
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY b.srecommend,
                        s.ProductID,
                        s.CasinoType;
			 
	 	 
        -- Get bettransLC Data
        INSERT INTO #srcDetail
               ( srecommend,site,
                 winlost_actualrate,SMAWinloss,commission_actualrate,
                 HouseWinloss_actualrate,HouseWinloss_virtualrate,HouseWinloss_variance,
                 grosscomm_actualrate,grosscomm_virtualrate,grosscomm_variance,
                 ProductId,CasinoType,turnover_actualrate,turnover_virtualrate,stake_actualrate,stake_virtualrate,
                 WinlossForExtraPT_actualrate,WinlossForExtraPT_virtualrate
               )
               SELECT b.srecommend,
                      1 AS site,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss,
                      SUM(scomm * actualrate) commission_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) HouseWinloss_actualrate,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost ) * virtualrate 
								+ scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) HouseWinloss_virtualrate,
					  SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost
								+ CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) HouseWinloss_variance,
                      SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE
                                WHEN b.tpositiontaking = 1
                                THEN 0
                                ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                      s.ProductID,
                      s.CasinoType,
                      SUM(( 1 - b.tpositiontaking ) * stake * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END) AS turnover_actualrate,
                      SUM(( 1 - b.tpositiontaking ) * stake * virtualrate) AS turnover_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE stake * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                          END) AS stake_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE stake * virtualrate
                          END) AS stake_virtualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * actualrate )
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( winlost - actual_stake ) * virtualrate )
                          END) AS WinlossForExtraPT_virtualrate
               FROM bettransLC b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.gameid = s.bettype
               WHERE winlostdate = @StartDate
                     ----AND s.ProductID = 21  ---- AllBet (21)
                 AND s.RefTable = 2  --- Use Table BettransLC
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY b.srecommend,
                        s.ProductID,
                        s.CasinoType;
			 
        -------------------------------------------------------

        UPDATE #src
          SET site = 2
        WHERE srecommend IN( SELECT CustId
                             FROM #DepSuper );
        UPDATE #srcDetail
          SET site = 2
        WHERE srecommend IN( SELECT CustId
                             FROM #DepSuper );  
	

        ---------------------------------------------------------		  
        -------------Insert to Result table to get data----------
        -----1. Soccer and Others
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT CASE
                          WHEN b.Sporttype = 1
                          THEN-5
                          WHEN b.sporttype IN( 2, 44 )
                          THEN-4
                      END AS ProductID,
                      site,
                      SUM(winLost_actualrate) AS winlost,
                      SUM(SMAWinloss) AS Position,
                      SUM(commission_actualrate) AS Commission,
                      SUM(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0))) AS RealHouseWinloss,
                      SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
					  SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
                      SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
                      SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( winlost_actualrate ) * e.ExtraPT
                          END) AS ExtraPT,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                          END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND e.ProductID = b.ProductId
                                            AND e.Sporttype = CASE
                                                                  WHEN b.sporttype = 44
                                                                  THEN 44
                                                                  ELSE 0
                                                              END
                                            AND e.SubProduct = ''
               WHERE b.ProductId = 1
               GROUP BY CASE
                            WHEN b.Sporttype = 1
                            THEN-5
                            WHEN b.sporttype IN( 2, 44 )
                            THEN-4
                        END,
                        site; 		
	 	

			   
        ----METRIC GAMING -SUPER LIVE
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT b.ProductID,
                      site,
                      SUM(ISNULL(b.winlost_actualrate, 0)) WinLost,
                      SUM(ISNULL(b.SMAWinloss, 0)) Position,
                      SUM(ISNULL(commission_actualrate, 0)) Commission,
                      SUM(ISNULL(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0)), 0)) AS RealHouseWinloss,
                      SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
					  SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
                      SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
                      SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( winlost_actualrate ) * e.ExtraPT
                          END) AS ExtraPT,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                          END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND b.ProductId = -1
                                            AND e.ProductID = 1
                                            AND e.Sporttype = 0
                                            AND e.SubProduct = 'MG-SuperLive'
               WHERE b.ProductId = -1
               GROUP BY b.ProductId,
                        site; 

	
        --- Parlay			 
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT b.ProductId,
                      site,
                      SUM(winlost_actualrate) WinLost,
                      SUM(SMAWinloss) Position,
                      SUM(commission_actualrate) Commission,
                      SUM(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0))) AS RealHouseWinloss,
                      SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
					  SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
                      SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
                      SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( winlost_actualrate ) * e.ExtraPT
                          END) AS ExtraPT,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                          END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND b.ProductID = -3
                                            AND e.ProductID = 1
                                            AND e.Sporttype = 0
                                            AND e.SubProduct = ''
               WHERE b.ProductID = -3
               GROUP BY b.ProductId,
                        site;
	
        ----NUMBER GAME			
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT b.ProductId,
                      site,
                      SUM(winlost_actualrate) WinLost,
                      SUM(SMAWinloss) Position,
                      SUM(commission_actualrate) Commission,
                      SUM(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0))) AS RealHouseWinloss,
                      SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
					  SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
                      SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
                      SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( winlost_actualrate ) * e.ExtraPT
                          END) AS ExtraPT,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                          END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND b.ProductID = e.ProductId
               WHERE b.ProductId = 3
               GROUP BY b.ProductId,
                        site;


        ---Racing
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT 2 AS ProductId,
                      site,
                      WinLost,
                      Pos AS Position,
                      Comm AS Commission,
                      HouseWinloss AS RealHouseWinloss,
                      HouseWinloss AS VirtualHouseWinloss,
					  0 AS VarianceIncome,
                      turnover AS RealTurnover,
                      0 VirtualTurnover,
                      0 ExtraPT,
                      0 NewExtraPT
               FROM @RBWinlost;

        ---bettrade
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT b.ProductId,
                      site,
                      SUM(ISNULL(b.winlost_actualrate, 0)) WinLost,
                      SUM(ISNULL(b.SMAWinloss, 0)) Position,
                      0 AS Commission,
                      SUM(ISNULL(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0)), 0)) AS RealHouseWinloss,
                      SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
					  SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
                      0 AS RealTurnover,
                      0 AS VirtualTurnover,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( winlost_actualrate ) * e.ExtraPT
                          END) AS ExtraPT,
                      SUM(CASE ISNULL(e.ExtraPT, 0)
                              WHEN 0
                              THEN 0
                              ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                          END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND b.ProductId = -2
                                            AND e.ProductId = 1
                                            AND e.Sporttype = 0
                                            AND ( e.SubProduct = 'BT-Comm'
                                               OR e.SubProduct = 'BT-Winloss'
                                                )
               WHERE b.ProductId = -2
               GROUP BY site,
                        b.ProductId;

        ------------------------------------------
        ---Live casino and Casino and 3rd Party
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT	
               --CASE WHEN b.ProductId IN (14) THEN 6   ---- Casino
               --	ELSE CASE WHEN  b.ProductId IN (4,11,12,13) THEN 4  ---Live Casino
               --		ELSE b.ProductId END END AS ProductId  ,

               CASE
                   WHEN b.CasinoType = 1
                   THEN 6  ---- Casino
                   WHEN b.CasinoType = 2
                   THEN 4  ---Live Casino
                   ELSE b.ProductId
               END AS ProductId,
               site,
               SUM(winlost_actualrate) WinLost,
               SUM(SMAWinloss) Position,
               SUM(commission_actualrate) Commission,
               SUM(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0))) AS RealHouseWinloss,
               SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
			   SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
               SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
               SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
               SUM(CASE ISNULL(e.ExtraPT, 0)
                       WHEN 0
                       THEN 0
                       ELSE( winlost_actualrate ) * e.ExtraPT
                   END) AS ExtraPT,
               SUM(CASE ISNULL(e.ExtraPT, 0)
                       WHEN 0
                       THEN 0
                       ELSE( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * e.ExtraPT
                   END) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND e.ProductID = b.ProductId
               WHERE b.ProductId IN( 5, 8, 15, 23, 25, 26, 27, 28, 30, 31 ) ---Virtual Sports, Keno, Colossus Bets, NG2 (3rd), CashOut, Betradar Virtual Sports, Lottery, Lucky 3, Bullfighting, Exchange
                     --- OR b.ProductId IN (4,11,12,13)    -----SLI, AG Casino, Gold Deluxe, MGC Live casino  (liveCasino)
                     --- OR b.ProductId IN (6, 14) --- Macau (Casino)
                  OR b.CasinoType IN( 1, 2 )
               GROUP BY site,
                        CASE
                            WHEN b.CasinoType = 1
                            THEN 6   ---- Casino
                            WHEN b.CasinoType = 2
                            THEN 4  ---Live Casino
                            ELSE b.ProductId
                        END;
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT	
               --CASE WHEN b.ProductId IN (6,17,22) THEN 6  --- Casino
               --	ELSE 4	--- Live Casino
               --	END AS ProductId,	
						
               CASE
                   WHEN b.CasinoType = 1
                   THEN 6  ---- Casino
                   WHEN b.CasinoType = 2
                   THEN 4  ---Live Casino
                   ELSE b.ProductId
               END AS ProductId,
               site,
               SUM(winlost_actualrate) WinLost,
               SUM(SMAWinloss) Position,
               SUM(commission_actualrate) Commission,
               SUM(HouseWinloss_actualrate - (( WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0))) AS RealHouseWinloss,
               SUM(HouseWinloss_virtualrate - (( WinlossForExtraPT_virtualrate + grosscomm_virtualrate ) * ISNULL(e.ExtraPT, 0))) AS VirtualHouseWinloss,
			   SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome,
               SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
               SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
               SUM(CASE ISNULL(e.ExtraPT, 0)
                       WHEN 0
                       THEN 0
                       ELSE( winlost_actualrate ) * e.ExtraPT
                   END) AS ExtraPT,
               SUM(( b.WinlossForExtraPT_actualrate + grosscomm_actualrate ) * ISNULL(e.ExtraPT, 0)) AS NewExtraPT
               FROM #srcDetail b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND e.ProductID = b.ProductId
               WHERE b.ProductId IN( 24 ) -- Fishing World
                     ---OR  b.ProductId IN (6,17,22) --- OW RNG + Microgaming - RNG Casino, Macau Games (Casino)
                  OR b.CasinoType IN( 1, 2 )
               GROUP BY site,
                        CASE
                            WHEN b.CasinoType = 1
                            THEN 6  ---- Casino
                            WHEN b.CasinoType = 2
                            THEN 4  ---Live Casino
                            ELSE b.ProductId
                        END;

        -----2. Total ----------------------------------------------------------------
        -- Get win lost of agent '8RM' , 'BARM'
        INSERT INTO #Result
               ( ProductId,
                 site,
                 winlost,
                 Position,
                 Commission,
                 RealHouseWinloss,
                 VirtualHouseWinloss,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover,
                 ExtraPT,
                 NewExtraPT
               )
               SELECT CASE
                          WHEN m.Sporttype = 1
                          THEN-98
                          ELSE-99
                      END AS ProductId,
                             CASE b.recommend
                                 WHEN 52466
                                 THEN 1
                                 WHEN 5707545
                                 THEN 2
                             END AS site,
                      -SUM(winlost - actual_stake) WinLost,
                      -SUM(awinlost + mwinlost + swinlost) Position,
                      SUM(scomm) Commission,
                      -SUM(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealHouseWinloss,
                      -SUM(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualHouseWinloss,
					  0 AS VarianceIncome,
                      SUM(( 1 - tpositiontaking ) * ABS(stake)) RealTurnover,
                      SUM(( 1 - tpositiontaking ) * ABS(stake)) VirtualTurnover,
                      0 AS ExtraPT,
                      0 AS NewExtraPT
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.bettype = s.bettype
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.recommend IN( 52466, 5707545 )
                 AND b.winlostdate = @StartDate
                 AND b.bettype < 19001
                 AND b.statusID IN( 111, 112, 113 )
                 AND b.ruben = 1
                 AND m.type = CASE
                                  WHEN b.bettype = 10
                                  THEN 1
                                  ELSE 0
                              END
                 AND s.productID = 1
                 AND s.EventType IN( 1, 2 )
                 AND s.SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
               GROUP BY CASE
                            WHEN m.Sporttype = 1
                            THEN-98
                            ELSE-99
                        END,
                        CASE b.recommend
                            WHEN 52466
                            THEN 1
                            WHEN 5707545
                            THEN 2
                        END;					
        -----3. Total ----------------------------------------------------------------
        --------------------------------------------
        ----Get Result----

        DECLARE @ProductOrder AS TABLE( DisplayOrder INT,
                                        ProductId    INT,
                                        ProductName  NVARCHAR(50),
                                        Site         TINYINT DEFAULT( 0 ));
        INSERT INTO @ProductOrder
               ( DisplayOrder,
                 ProductId,
                 ProductName
               )
        VALUES( 1, -5, 'Soccer' ),
				( 2, -4, 'Other Sports' ),
				( 3, -3, 'Parlay' ),
				( 4, -1, 'Metric Gaming - Superlive' ),        
				( 5, 8, 'Keno' ),
				( 6, 3, 'Number Game' ),
				( 7, 4, 'Live Casino' ),
				( 8, 6, 'Casino' ),
				( 9, 5, 'Virtual Sports' ),
				( 10, 27, 'Virtual Sports 2' ),
				( 11, 28, 'Lottery' ),
				( 12, 23, 'NG2' ),
				( 13, -2, 'Bettrade' ),
				( 14, 25, 'Cash Out' ),
				( 15, 15, 'Colossus Bets' ),
				( 16, 24, 'Fishing World' ),
				( 17, 26, 'Lucky 3' ),
				( 18, 30, 'Bullfighting' ),
				( 19, 31, 'Exchange' ),
				( 20, 2, 'Racing' );

        INSERT INTO @ProductOrder
               ( DisplayOrder,
                 ProductId,
                 ProductName,
                 Site
               )
        VALUES( 100, -98, 'Soccer 8RM', 1 ),
              ( 100, -98, 'Soccer BARM', 2 ),
              ( 101, -99, 'Other Sports 8RM', 1 ),
              ( 101, -99, 'Other Sports BARM', 2 );
        UPDATE R
          SET DisplayOrder = P.DisplayOrder,
              ProductName = P.ProductName
        FROM #Result R
             INNER JOIN @ProductOrder P ON P.ProductID = R.ProductId
                                       AND P.Site = CASE
                                                        WHEN P.Site <> 0
                                                        THEN r.Site
                                                        ELSE 0
                                                    END;
        SELECT CASE
                   WHEN d.DisplayOrder IN( 100, 101 )
                   THEN 'RM'
                   ELSE d.ProductName
               END AS GroupName,
                      CASE
                          WHEN d.DisplayOrder IN( 100, 101 )
                          THEN d.ProductName
                          WHEN d.Site = 1
                          THEN 'Credit'
                          WHEN d.Site = 2
                          THEN 'Deposit'
                      END AS RowName,
               d.DisplayOrder,
               site,
               SUM(d.winlost) AS MemberWinLoss,
               SUM(d.Position) AS SMAWinLoss,
               SUM(d.Commission) AS Commission,
               SUM(d.RealHouseWinloss) AS RealIncome,
               SUM(d.VirtualHouseWinloss) AS VirtualIncome,
               SUM(d.VarianceIncome) AS VarianceIncome,
               SUM(d.RealTurnover) AS RealTurnover,
               SUM(d.VirtualTurnover) AS VirtualTurnover,
               SUM(CASE
                       WHEN @StartDate < @EffectedDate
                       THEN-d.extraPT
                       ELSE-d.NewExtraPT
                   END) AS extraPT
        FROM #Result d
        GROUP BY CASE
                     WHEN d.DisplayOrder IN( 100, 101 )
                     THEN 'RM'
                     ELSE d.ProductName
                 END,
                 CASE
                     WHEN d.DisplayOrder IN( 100, 101 )
                     THEN d.ProductName
                     WHEN d.Site = 1
                     THEN 'Credit'
                     WHEN d.Site = 2
                     THEN 'Deposit'
                 END,
                 d.DisplayOrder,
                 site
        ORDER BY DisplayOrder ASC,
                 site;
        DROP TABLE #tmp_src;
        DROP TABLE #src;
        DROP TABLE #srcDetail;
        DROP TABLE #DepSuper;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Match;
        DROP TABLE #Result;
        DROP TABLE #SportBettype;
    END;
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

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
		- 20180816@Cherry: Integrate Poker Games (#97830)
		- 20180824@Jacob: Integrate Poker Games (#97830) - Remove Racing
		- 20180831@Kean: Integrate Insurance Of Poker Games (#97830)
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
                           HouseWinloss_actualrate   MONEY,
                           HouseWinloss_virtualrate  MONEY,
						   HouseWinloss_variance     MONEY,
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

		CREATE TABLE #tmp_srcDetail(srecommend                 INT,
									bettype					   INT,
                                 site                          TINYINT,
                                 winlost_actualrate            MONEY,
								 winlost_virtualrate           MONEY,
								 winlost_jackpot_actualrate    MONEY,
								 winlost_jackpot_virtualrate   MONEY,
                                 SMAWinloss_actualrate		   MONEY,
								 SMAWinloss_virtualrate		   MONEY,
                                 commission_actualrate         MONEY,
								 commission_virtualrate        MONEY,
								 commission_variance           MONEY,
                                 grosscomm_actualrate          DECIMAL(19,6),
								 grosscomm_virtualrate         DECIMAL(19,6),
								 grosscomm_variance            DECIMAL(19,6),
                                 turnover_actualrate           MONEY,
                                 turnover_virtualrate          MONEY,
                                 stake_actualrate              MONEY,
                                 stake_virtualrate             MONEY,
								 WinlossForExtraPT_actualrate  MONEY,
								 WinlossForExtraPT_virtualrate MONEY,
								 WinlossJackpotForExtraPT_actualrate  MONEY,
								 WinlossJackpotForExtraPT_virtualrate MONEY);
        CREATE TABLE #srcDetail( srecommend                   INT,
                                 site                         TINYINT,
                                 winlost_actualrate           MONEY,
                                 SMAWinloss					  MONEY,
                                 commission_actualrate        MONEY,
                                 HouseWinloss_actualrate      MONEY,
                                 HouseWinloss_virtualrate     MONEY,
								 HouseWinloss_variance        MONEY,
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

		---- Extra Comm for PokerGame Insurance
        CREATE TABLE #ExtraComm_Sel( ProductID  INT,
                                   Sporttype  INT,
                                   SubProduct VARCHAR(100),
                                   SuperID    INT,
                                   ExtraComm    DECIMAL(9, 8));
        INSERT INTO #ExtraComm_Sel
               ( ProductID, Sporttype, SubProduct, SuperID, ExtraComm)
               SELECT ProductID, SportType, SubProduct, SuperId, SUM(ExtraCommRate) AS ExtraComm
               FROM bodb02.dbo.Acc_GroupExtraCommRateSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY ProductID, SportType, SubProduct, SuperId;
	
	
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
                      SUM(( CASE WHEN b.tpositiontaking = 1 THEN 0
                                 WHEN s.ProductID = 33 THEN -b.oddsspread  -- Poker Games
                                 ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * b.actualrate) grosscomm_actualrate,
					  SUM(( CASE WHEN b.tpositiontaking = 1 THEN 0
                                 WHEN s.ProductID = 33 THEN -b.oddsspread  -- Poker Games
                                 ELSE b.scomm / ( 1 - b.tpositiontaking )
                            END ) * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) grosscomm_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate 
							   THEN  (CASE WHEN b.tpositiontaking = 1 THEN 0 
											WHEN s.ProductID = 33 THEN -b.oddsspread  -- Poker Games
											ELSE b.scomm / ( 1 - b.tpositiontaking ) END)
							   ELSE 0 END) * (actualrate - virtualrate)) grosscomm_variance,
                      CASE s.SubProduct
                          WHEN 'MG-SuperLive' THEN-1
                          WHEN 'BT-Comm' THEN-2
                          WHEN 'BT-Winloss' THEN-2
                          ELSE CASE WHEN s.EventType = 0 AND ProductID = 1 THEN-3 ELSE s.ProductID END
                      END AS ProductID,
                      s.CasinoType,
                      SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
								ELSE ( 1 - b.tpositiontaking ) * (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END)
													* CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END 
                          END) AS turnover_actualrate,
                      SUM(CASE WHEN s.ProductID = 33 THEN 0  -- Poker Games
							   ELSE( 1 - b.tpositiontaking ) * (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) * virtualrate
						  END) AS turnover_virtualrate,
                      SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
							   WHEN s.ProductID = 33 THEN 0  -- Poker Games
                               ELSE (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) 
								   * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                          END) AS stake_actualrate,
                      SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
							   WHEN s.ProductID = 33 THEN 0  -- Poker Games
                               ELSE (CASE WHEN s.productID = 1 THEN ABS(stake) ELSE stake END) * virtualrate
                          END) AS stake_virtualrate,
                      SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
							   WHEN s.ProductID = 33 THEN (ISNULL(b.transid2, 0) * 1.0/10000) * actualrate  -- Insurance Of Poker Games
                               ELSE(( winlost - actual_stake ) * actualrate )
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
							   WHEN s.ProductID = 33 THEN (ISNULL(b.transid2, 0) * 1.0/10000) * virtualrate  -- Insurance Of Poker Games
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

		-- Get bettransRNG data
	     INSERT INTO #tmp_srcDetail
               ( srecommend, bettype,site,
                winlost_actualrate, winlost_virtualrate, winlost_jackpot_actualrate, winlost_jackpot_virtualrate,
                SMAWinloss_actualrate, SMAWinloss_virtualrate, commission_actualrate, commission_virtualrate, commission_variance,
                grosscomm_actualrate, grosscomm_virtualrate, grosscomm_variance,
                turnover_actualrate, turnover_virtualrate, stake_actualrate, stake_virtualrate,
				WinlossForExtraPT_actualrate, WinlossForExtraPT_virtualrate, WinlossJackpotForExtraPT_actualrate, WinlossJackpotForExtraPT_virtualrate)
               SELECT b.srecommend, b.gameID AS bettype, 1 AS site,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
					  SUM(( winlost - actual_stake ) * virtualrate) winlost_virtualrate,
					  SUM(( b.ContributionRate * b.BetStake ) * actualrate) winlost_jackpot_actualrate,
					  SUM(( b.ContributionRate * b.BetStake ) * virtualrate) winlost_jackpot_virtualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss_actualrate,
					  SUM(( awinlost + mwinlost + swinlost ) * virtualrate) SMAWinloss_virtualrate,
                      SUM(scomm * actualrate) commission_actualrate,
					  SUM(scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) commission_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) commission_variance,
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
                          END) AS WinlossForExtraPT_virtualrate,
					  SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( b.ContributionRate * b.BetStake ) * actualrate )
                          END) AS WinlossJackpotForExtraPT_actualrate,
                      SUM(CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(( b.ContributionRate * b.BetStake ) * virtualrate )
                          END) AS WinlossJackpotForExtraPT_virtualrate
               FROM bettransRNG b WITH ( NOLOCK )
               WHERE winlostdate = @StartDate
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY b.srecommend,b.gameID
			   OPTION (RECOMPILE)
		-- Get bettransLC data
        INSERT INTO #tmp_srcDetail
               ( srecommend, bettype, site,
                winlost_actualrate, winlost_virtualrate,
                SMAWinloss_actualrate, SMAWinloss_virtualrate, commission_actualrate, commission_virtualrate, commission_variance,
                grosscomm_actualrate, grosscomm_virtualrate, grosscomm_variance,
                turnover_actualrate, turnover_virtualrate, stake_actualrate, stake_virtualrate,
				WinlossForExtraPT_actualrate, WinlossForExtraPT_virtualrate)
               SELECT b.srecommend, b.gameID AS bettype, 1 AS site,
                      SUM(( winlost - actual_stake ) * actualrate) winlost_actualrate,
					  SUM(( winlost - actual_stake ) * virtualrate) winlost_virtualrate,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinloss_actualrate,
					  SUM(( awinlost + mwinlost + swinlost ) * virtualrate) SMAWinloss_virtualrate,
                      SUM(scomm * actualrate) commission_actualrate,
					  SUM(scomm * CASE WHEN b.virtualrate < b.actualrate THEN b.virtualrate ELSE b.actualrate END) commission_virtualrate,
					  SUM((CASE WHEN b.virtualrate < b.actualrate THEN b.scomm ELSE 0 END) * (actualrate - virtualrate)) commission_variance,
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
               WHERE winlostdate = @StartDate
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY b.srecommend, b.gameID
			    OPTION (RECOMPILE)

        ----3. Get from Temporary Detail table ----------
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
                      SUM(b.winlost_actualrate) winlost_actualrate,
                      SUM(b.SMAWinloss_actualrate) SMAWinloss,
                      SUM(b.commission_actualrate) commission_actualrate,
                      SUM(CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.winlost_jackpot_actualrate + b.SMAWinloss_actualrate + b.commission_actualrate
                                ELSE b.winlost_actualrate + b.SMAWinloss_actualrate + b.commission_actualrate
                            END) HouseWinloss_actualrate,
                      SUM(( CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.winlost_jackpot_virtualrate + b.SMAWinloss_virtualrate
                                ELSE b.winlost_virtualrate + b.SMAWinloss_virtualrate
                            END ) + b.commission_virtualrate) HouseWinloss_virtualrate,
                      SUM(( CASE
                                WHEN s.Bettype IN( 2199, 2399, 2999 )
                                THEN 0
                                WHEN s.Bettype IN( 2198, 2398, 2998 )
                                THEN b.winlost_jackpot_actualrate - winlost_jackpot_virtualrate  + b.SMAWinloss_actualrate - b.SMAWinloss_virtualrate
                                ELSE b.winlost_actualrate - b.winlost_virtualrate + b.SMAWinloss_actualrate - b.SMAWinloss_virtualrate
                            END ) + b.grosscomm_variance) HouseWinloss_variance,
                      SUM(grosscomm_actualrate) grosscomm_actualrate,
					  SUM(grosscomm_virtualrate) grosscomm_virtualrate,
					  SUM(grosscomm_variance) grosscomm_variance,
                      s.ProductID,
                      s.CasinoType,
                      SUM(turnover_actualrate) AS turnover_actualrate,
                      SUM(turnover_virtualrate) AS turnover_virtualrate,
                      SUM(stake_actualrate) AS stake_actualrate,
                      SUM(stake_virtualrate) AS stake_virtualrate,
                      SUM(CASE
							  WHEN b.Bettype IN( 2199, 2399, 2999 )
                                THEN 0 --Progressive Jackpot
                              WHEN b.Bettype IN( 2198, 2398, 2998 )
                                THEN WinlossJackpotForExtraPT_actualrate  --Jackpot Contribution
                              ELSE WinlossForExtraPT_actualrate
                          END) AS WinlossForExtraPT_actualrate,
                      SUM(CASE
							  WHEN b.Bettype IN( 2199, 2399, 2999 )
                                THEN 0 --Progressive Jackpot
                              WHEN b.Bettype IN( 2198, 2398, 2998 )
                                THEN WinlossJackpotForExtraPT_virtualrate  --Jackpot Contribution
                              ELSE WinlossForExtraPT_virtualrate
                          END) AS WinlossForExtraPT_virtualrate
               FROM #tmp_srcDetail b WITH ( NOLOCK )
                    INNER JOIN #SportBettype s ON b.bettype = s.bettype
				WHERE s.RefTable IN (1,2)
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
		---For Poker Games
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
               SELECT b.ProductId AS ProductId,
               site,
               SUM(winlost_actualrate) WinLost,
               SUM(SMAWinloss) Position,
               SUM(commission_actualrate) Commission,
               SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate * ISNULL(e.ExtraPT, 0) + b.grosscomm_actualrate * ISNULL(c.ExtraComm, 0))) AS RealHouseWinloss,
               SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate * ISNULL(e.ExtraPT, 0) + b.grosscomm_virtualrate * ISNULL(c.ExtraComm, 0))) AS VirtualHouseWinloss,
			   SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(c.ExtraComm, 0)) AS VarianceIncome,
               SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover,
               SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover,
               SUM(CASE ISNULL(e.ExtraPT, 0)
                       WHEN 0
                       THEN 0
                       ELSE( winlost_actualrate ) * e.ExtraPT
                   END) AS ExtraPT,
               SUM(WinlossForExtraPT_actualrate * ISNULL(e.ExtraPT, 0) +  grosscomm_actualrate * ISNULL(c.ExtraComm, 0)) AS NewExtraPT
               FROM #src b
                    LEFT JOIN #ExtraPT_Sel e ON b.srecommend = e.superID
                                            AND e.ProductID = b.ProductId
					LEFT JOIN #ExtraComm_Sel c ON b.srecommend = c.superID
                                            AND b.ProductId = c.ProductID
               WHERE b.ProductId = 33
               GROUP BY site,
                        b.ProductId;
        ---Live casino and Casino and 3rd Party exclude Poker Games
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
               WHERE b.ProductId IN( 5, 8, 15, 23, 25, 26, 27, 28, 30, 31) ---Virtual Sports, Keno, Colossus Bets, NG2 (3rd), CashOut, Betradar Virtual Sports, Lottery, Lucky 3, Bullfighting, Exchange
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
				( 9, 33, 'Poker Games'),
				( 10, 5, 'Virtual Sports' ),
				( 11, 27, 'Virtual Sports 2' ),
				( 12, 28, 'Lottery' ),
				( 13, 23, 'NG2' ),
				( 14, -2, 'Bettrade' ),
				( 15, 25, 'Cash Out' ),
				( 16, 15, 'Colossus Bets' ),
				( 17, 24, 'Fishing World' ),
				( 18, 26, 'Lucky 3' ),
				( 19, 30, 'Bullfighting' ),
				( 20, 31, 'Exchange' );

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
		DROP TABLE #tmp_srcDetail;
        DROP TABLE #src;
        DROP TABLE #srcDetail;
        DROP TABLE #DepSuper;
        DROP TABLE #ExtraPT_Sel;
		DROP TABLE #ExtraComm_Sel;
        DROP TABLE #Match;
        DROP TABLE #Result;
        DROP TABLE #SportBettype;
    END;
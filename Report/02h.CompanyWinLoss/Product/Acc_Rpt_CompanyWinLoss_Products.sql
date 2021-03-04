/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Products
	@StartDate    SMALLDATETIME 
   , @EndDate      SMALLDATETIME 
   , @IsNoDraw BIT = 0
AS
    BEGIN
/*	Creator: Sophia.Nguyen
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #48448]
	DB: DBACC/bodb02	

Revisions:
- 20160622@Sophia: 	. Remove group by ExtraPT to avoid duplicated data. [Redmine: #59732]. Ignore param @EndDate because of the performance, and business supports only one day 		 
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
- 20180917@Robert: House WL by Product - Poker Games should be last index (#101618)
- 20190121@Franklin: Integrate Poker Games (#107706)
- 20190308@Jacob: Integrate BetBuilder (#109822)
- 20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
- 20190517@Cherry: Change Keno name to RNG Keno (#113670)
- 20190925@Jacob: Group By CN88 (#118824)
- 20190918@Robert: Remove inactive products (#120215)
- 20191015@Robert: Integrate NPH into reports (#121661)
- 20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
- 20191201@Cherry: Change product name NPH to Saba Promotion (#124605)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200313@Ned.Le: NAP Report - Incorporate Virtual Games (#130326)
- 20200323@Ned.Le: NAP Report - Incorporate 4D (#130845)
- 20200331@Ned.Le: NAP Report - Incorporate new Table Games (#131095)
- 20200520@Cherry: Integrate Saba.club (#134441)
- 20200522@Cherry: Integrate RNG War (#132009)
- 20200713@Ned.Le: NAP Report - Incorporate Jackpot Games (#137271)
- 20200930@Jaden.Tang: Odds Spread Adjustment (#141750)
- 20201126@Cherry: Integrate Virtual Sports 3 (#146010)
- 20201222@Kean: Support to filter NoDraw and separate the SABA sports - NAP Report (#147451) 
- 20210303@Cherry: Change product name "Indo 4D" to "Togel 4D" (#149710)

Explanation's Param:

*/

	   SET NOCOUNT ON;
	   DECLARE @EffectedDate    DATETIME; -- 20160112@Percy: Applying date of changing extra PT formula [RedmineID: #70208]
	   SELECT @EffectedDate = '2017-01-19';

	   -- Get Special Bettype Group
	   CREATE TABLE #SpecialBettypeGroup (BettypeGroupID SMALLINT, Bettype SMALLINT)
	   INSERT INTO #SpecialBettypeGroup (BettypeGroupID, Bettype)
	   SELECT BettypeGroupID, Bettype FROM DBWH.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID IN (6, 10)

	   --Get Sport Bettype Matrix--
	   -- Check SP Version	 
	   DECLARE @isTest    BIT = 0, @LeagueGroupStr VARCHAR(500);
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBettype(
		   ProductID     INT
		 , Bettype       INT
		 , EventType     INT
		 , SubProduct    VARCHAR(500)
		 , RefTable      TINYINT
		 , CasinoType    TINYINT
		 , ApplyNoDraw BIT);
	   INSERT INTO #SportBettype(ProductID
						  , Bettype
						  , EventType
						  , SubProduct
						  , RefTable
						  , CasinoType
						  , ApplyNoDraw)
			SELECT ProductID
				, Bettype
				, EventType
				, SubProduct
				, RefTable
				, CasinoType
				,0
			FROM dbo.f_SportBettypeMatrix_Sel
				(0, 0, 0, 2, '', '', @isTest)
			WHERE bettype NOT IN(911, 912); -- remove Cash Out

			UPDATE #SportBettype
			SET ApplyNoDraw = 1
			WHERE (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
                                 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
                                 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
	   -- End Sport Bettype Matrix--

	   CREATE TABLE #tmp_src(
		   srecommend                       INT
		 , bettype                          INT
		 , site                             TINYINT
		 , Sporttype                        INT
		 , winlost_actualrate               MONEY
		 , SMAWinloss                       MONEY
		 , commission_actualrate            MONEY
		 , HouseWinloss_actualrate          MONEY
		 , HouseWinloss_virtualrate         MONEY
		 , HouseWinloss_variance            MONEY
		 , grosscomm_actualrate             DECIMAL(19, 6)
		 , grosscomm_virtualrate            DECIMAL(19, 6)
		 , grosscomm_variance               DECIMAL(19, 6)
		 , ProductId                        INT
		 , CasinoType                       TINYINT
		 , turnover_actualrate              MONEY
		 , turnover_virtualrate             MONEY
		 , stake_actualrate                 MONEY
		 , stake_virtualrate                MONEY
		 , WinlossForExtraPT_actualrate     MONEY
		 , WinlossForExtraPT_virtualrate    MONEY);
	   CREATE TABLE #src(
		   srecommend                       INT
		 , site                             TINYINT
		 , Sporttype                        INT
		 , winlost_actualrate               MONEY
		 , SMAWinloss                       MONEY
		 , commission_actualrate            MONEY
		 , HouseWinloss_actualrate          MONEY
		 , HouseWinloss_virtualrate         MONEY
		 , HouseWinloss_variance            MONEY
		 , grosscomm_actualrate             MONEY
		 , grosscomm_virtualrate            MONEY
		 , grosscomm_variance               MONEY
		 , ProductId                        INT
		 , CasinoType                       TINYINT
		 , turnover_actualrate              MONEY
		 , turnover_virtualrate             MONEY
		 , stake_actualrate                 MONEY
		 , stake_virtualrate                MONEY
		 , WinlossForExtraPT_actualrate     MONEY
		 , WinlossForExtraPT_virtualrate    MONEY);
	   CREATE TABLE #tmp_srcDetail(
		   srecommend                              INT
		 , bettype                                 INT
		 , site                                    TINYINT
		 , winlost_actualrate                      MONEY
		 , winlost_virtualrate                     MONEY
		 , winlost_jackpot_actualrate              MONEY
		 , winlost_jackpot_virtualrate             MONEY
		 , SMAWinloss_actualrate                   MONEY
		 , SMAWinloss_virtualrate                  MONEY
		 , commission_actualrate                   MONEY
		 , commission_virtualrate                  MONEY
		 , commission_variance                     MONEY
		 , grosscomm_actualrate                    DECIMAL(19, 6)
		 , grosscomm_virtualrate                   DECIMAL(19, 6)
		 , grosscomm_variance                      DECIMAL(19, 6)
		 , turnover_actualrate                     MONEY
		 , turnover_virtualrate                    MONEY
		 , stake_actualrate                        MONEY
		 , stake_virtualrate                       MONEY
		 , WinlossForExtraPT_actualrate            MONEY
		 , WinlossForExtraPT_virtualrate           MONEY
		 , WinlossJackpotForExtraPT_actualrate     MONEY
		 , WinlossJackpotForExtraPT_virtualrate    MONEY);
	   CREATE TABLE #srcDetail(
		   srecommend                       INT
		 , site                             TINYINT
		 , winlost_actualrate               MONEY
		 , SMAWinloss                       MONEY
		 , commission_actualrate            MONEY
		 , HouseWinloss_actualrate          MONEY
		 , HouseWinloss_virtualrate         MONEY
		 , HouseWinloss_variance            MONEY
		 , grosscomm_actualrate             MONEY
		 , grosscomm_virtualrate            MONEY
		 , grosscomm_variance               MONEY
		 , ProductId                        INT
		 , CasinoType                       TINYINT
		 , turnover_actualrate              MONEY
		 , turnover_virtualrate             MONEY
		 , stake_actualrate                 MONEY
		 , stake_virtualrate                MONEY
		 , WinlossForExtraPT_actualrate     MONEY
		 , WinlossForExtraPT_virtualrate    MONEY);
	   CREATE TABLE #Result(
		   DisplayOrder           INT
		 , ProductId              INT
		 , ProductName            NVARCHAR(50)
		 , site                   TINYINT
		 , winlost                MONEY
		 , Position               MONEY
		 , Commission             MONEY
		 , RealHouseWinloss       MONEY
		 , VirtualHouseWinloss    MONEY
		 , VarianceIncome         MONEY
		 , RealTurnover           MONEY
		 , VirtualTurnover        MONEY
		 , ExtraPT                MONEY
		 , NewExtraPT             MONEY);
	   -- Deposit Super
	   CREATE TABLE #DepSuper(
		   custid    INT);
	   INSERT INTO #DepSuper
			SELECT custid
			FROM f_DepSuper_1
				('All');
	   -- #SABALeagueGroup
		CREATE TABLE #SABALeagueGroup(LeagueGroupID INT)
		SELECT @LeagueGroupStr = [VValue] FROM DBWH.[bodb_Account].[dbo].[SystemSettings] WHERE VID = 5

		INSERT INTO #SABALeagueGroup
		SELECT val FROM dbo.strSplit(@LeagueGroupStr,',')
	   -- Match
	   CREATE TABLE #Match(
		   MatchId      INT
		 , sporttype    SMALLINT
		 , type         TINYINT
		 , IsSabaSport BIT);--, primary key(MatchId, type))
	   
	   INSERT INTO #Match
			SELECT m.MatchId
				, s.sporttype
				, m.type
				, CASE WHEN saba.LeagueGroupID IS NULL THEN 0 ELSE 1 END IsSabaSport
			FROM
				(
				    SELECT MatchId
					    , LeagueId
					    , exrisk
					    , MatchCode
					    , 0 AS type --'match'
				    FROM match WITH(NOLOCK)
				    WHERE EventDate = @StartDate
				    UNION ALL
				    SELECT orid
					    , LeagueId
					    , 0
					    , MatchCode
					    , 1 AS type --'outright'
				    FROM outright WITH(NOLOCK)
				    WHERE EventDate = @StartDate
				) AS m
			    INNER JOIN league AS l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
			    INNER JOIN Sports AS s WITH(NOLOCK) ON l.sporttype = s.sporttype
				LEFT JOIN #SABALeagueGroup saba ON l.LeagueGroupID = saba.LeagueGroupID;
	   CREATE CLUSTERED INDEX CIX_MatchID ON #Match(MatchID, Type);
	   --
	   --1. Sportsbook only and outright
	   INSERT INTO #tmp_src(srecommend
					  , bettype
					  , site
					  , SportType
					  , winlost_actualrate
					  , SMAWinloss
					  , commission_actualrate
					  , HouseWinloss_actualrate
					  , HouseWinloss_virtualrate
					  , HouseWinloss_variance
					  , grosscomm_actualrate
					  , grosscomm_virtualrate
					  , grosscomm_variance
					  , ProductId
					  , turnover_actualrate
					  , turnover_virtualrate
					  , stake_actualrate
					  , stake_virtualrate
					  , WinlossForExtraPT_actualrate
					  , WinlossForExtraPT_virtualrate)
			SELECT srecommend
				, b.bettype
				, 1 AS site
				, CASE
					 WHEN m.sporttype = 44
					 THEN 44
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN 1 -- Real Soccer
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1 -- SABA Soccer
					 ELSE 2
				  END AS SportType
				, SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss
				, SUM(scomm * actualrate) AS commission_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS HouseWinloss_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate + scomm * CASE
																						  WHEN b.virtualrate < b.actualrate
																						  THEN b.virtualrate
																						  ELSE b.actualrate
																					   END) AS HouseWinloss_virtualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + CASE
																	    WHEN b.virtualrate < b.actualrate
																	    THEN b.scomm
																	    ELSE 0
																	END) * (actualrate - virtualrate)) AS HouseWinloss_variance
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * b.actualrate * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * CASE
							 WHEN b.virtualrate < b.actualrate
							 THEN b.virtualrate
							 ELSE b.actualrate
						  END * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN CASE
							    WHEN b.tpositiontaking = 1
							    THEN 0
							    ELSE b.scomm / (1 - b.tpositiontaking)
							END
						ELSE 0
					 END * (actualrate - virtualrate) * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_variance
				, 1 AS ProductId
				-- Apply NoDraw
				, SUM((1 - b.tpositiontaking) * ABS(stake) * CASE
													    WHEN virtualrate > actualrate
													    THEN virtualrate
													    ELSE actualrate
													END *
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
																			 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
																			 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
																			 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_actualrate
				, SUM((1 - b.tpositiontaking) * ABS(stake) * virtualrate *
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
																			 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
																			 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
																			 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE ABS(stake) * CASE
										  WHEN virtualrate > actualrate
										  THEN virtualrate
										  ELSE actualrate
									   END
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) *
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
																			 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
																			 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
																			 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE ABS(stake) * virtualrate
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) *
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
																			 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
																			 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
																			 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_virtualrate
			FROM bettrans AS b WITH(NOLOCK)
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
									AND m.type = CASE
												  WHEN b.bettype = 10
												  THEN 1
												  ELSE 0
											   END
			WHERE winlostdate = @StartDate
				 AND b.ruben = 1
				 AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
			GROUP BY srecommend
				  , b.bettype
				  , CASE
					   WHEN m.sporttype = 44
					   THEN 44
					   WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN 1 -- Real Soccer
					   WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1 -- SABA Soccer
					   ELSE 2
				    END OPTION(RECOMPILE);
	   --Remove betype of MertricGaming and Bettrade AND Bet Builder
	   DELETE #tmp_src
	   WHERE bettype NOT IN
					    (
						   SELECT bettype
						   FROM #SportBettype AS s
						   WHERE s.productID = 1
							    AND s.EventType IN(1, 2)
							    AND s.SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
					    );
	   --Soccer and Other Sports
	   INSERT INTO #src(srecommend
				   , site
				   , SportType
				   , ProductId
				   , winlost_actualrate
				   , SMAWinloss
				   , commission_actualrate
				   , HouseWinloss_actualrate
				   , HouseWinloss_virtualrate
				   , HouseWinloss_variance
				   , grosscomm_actualrate
				   , grosscomm_virtualrate
				   , grosscomm_variance
				   , turnover_actualrate
				   , turnover_virtualrate
				   , stake_actualrate
				   , stake_virtualrate
				   , WinlossForExtraPT_actualrate
				   , WinlossForExtraPT_virtualrate)
			SELECT srecommend
				, site
				, SportType
				, ProductId
				, SUM(winlost_actualrate)
				, SUM(SMAWinloss)
				, SUM(commission_actualrate)
				, SUM(HouseWinloss_actualrate)
				, SUM(HouseWinloss_virtualrate)
				, SUM(HouseWinloss_variance)
				, SUM(grosscomm_actualrate)
				, SUM(grosscomm_virtualrate)
				, SUM(grosscomm_variance)
				, SUM(turnover_actualrate)
				, SUM(turnover_virtualrate)
				, SUM(stake_actualrate)
				, SUM(stake_virtualrate)
				, SUM(WinlossForExtraPT_actualrate)
				, SUM(WinlossForExtraPT_virtualrate)
			FROM #tmp_src
			GROUP BY srecommend
				  , site
				  , SportType
				  , ProductId;
	   -- BARM (only)
	   INSERT INTO #src(srecommend
				   , site
				   , SportType
				   , winlost_actualrate
				   , SMAWinloss
				   , commission_actualrate
				   , HouseWinloss_actualrate
				   , HouseWinloss_virtualrate
				   , HouseWinloss_variance
				   , grosscomm_actualrate
				   , grosscomm_virtualrate
				   , grosscomm_variance
				   , ProductId
				   , turnover_actualrate
				   , turnover_virtualrate
				   , stake_actualrate
				   , stake_virtualrate
				   , WinlossForExtraPT_actualrate
				   , WinlossForExtraPT_virtualrate)
			SELECT 2 AS srecommend
				, 2 AS site
				, CASE
					 WHEN m.sporttype = 44
					 THEN 44
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN 1 -- Real Soccer
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1 -- SABA Soccer
					 ELSE 2
				  END AS SportType
				, SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss
				, SUM(scomm * actualrate) AS commission_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS HouseWinloss_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate + scomm * CASE
																						  WHEN b.virtualrate < b.actualrate
																						  THEN b.virtualrate
																						  ELSE b.actualrate
																					   END) AS HouseWinloss_virtualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + CASE
																	    WHEN b.virtualrate < b.actualrate
																	    THEN b.scomm
																	    ELSE 0
																	END) * (actualrate - virtualrate)) AS HouseWinloss_variance
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * b.actualrate * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * CASE
							 WHEN b.virtualrate < b.actualrate
							 THEN b.virtualrate
							 ELSE b.actualrate
						  END * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN CASE
							    WHEN b.tpositiontaking = 1
							    THEN 0
							    ELSE b.scomm / (1 - b.tpositiontaking)
							END
						ELSE 0
					 END * (actualrate - virtualrate) * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_variance
				, 1 AS ProductId
				-- Apply NoDraw
				, SUM((1 - b.tpositiontaking) * ABS(stake) * CASE
													    WHEN virtualrate > actualrate
													    THEN virtualrate
													    ELSE actualrate
													END * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_actualrate
				, SUM((1 - b.tpositiontaking) * ABS(stake) * virtualrate * 
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE ABS(stake) * CASE
										  WHEN virtualrate > actualrate
										  THEN virtualrate
										  ELSE actualrate
									   END
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) * 
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE ABS(stake) * virtualrate
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) * 
															CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_virtualrate
			FROM bettrans AS b WITH(NOLOCK)
			    INNER JOIN #SportBettype AS s ON b.bettype = s.bettype
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
			WHERE b.recommend = 5707545
				 AND b.winlostdate = @StartDate
				 AND b.bettype < 19001
				 AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
				 AND b.ruben = 1
				 AND m.type = CASE
							   WHEN b.bettype = 10
							   THEN 1
							   ELSE 0
						    END
				 AND s.productID = 1
				 AND s.EventType IN(1, 2)
				 AND s.SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			GROUP BY CASE
					   WHEN m.sporttype = 44
					   THEN 44
					   WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN 1 -- Real Soccer
					   WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1 -- SABA Soccer
					   ELSE 2
				    END;
	   -- Minus data of BARM 
	   UPDATE c
			SET 
			    c.winlost_actualrate = c.winlost_actualrate - d.winlost_actualrate
			  , c.SMAWinloss = c.SMAWinloss - d.SMAWinloss
			  , c.commission_actualrate = c.commission_actualrate - d.commission_actualrate
			  , c.HouseWinloss_actualrate = c.HouseWinloss_actualrate - d.HouseWinloss_actualrate
			  , c.HouseWinloss_virtualrate = c.HouseWinloss_virtualrate - d.HouseWinloss_virtualrate
			  , c.HouseWinloss_variance = c.HouseWinloss_variance - d.HouseWinloss_variance
			  , c.grosscomm_actualrate = c.grosscomm_actualrate - d.grosscomm_actualrate
			  , c.grosscomm_virtualrate = c.grosscomm_virtualrate - d.grosscomm_virtualrate
			  , c.grosscomm_variance = c.grosscomm_variance - d.grosscomm_variance
			  , c.turnover_actualrate = c.turnover_actualrate - d.turnover_actualrate
			  , c.turnover_virtualrate = c.turnover_virtualrate - d.turnover_virtualrate
			  , c.stake_actualrate = c.stake_actualrate - d.stake_actualrate
			  , c.stake_virtualrate = c.stake_virtualrate - d.stake_virtualrate
			  , c.WinlossForExtraPT_actualrate = c.WinlossForExtraPT_actualrate - d.WinlossForExtraPT_actualrate
			  , c.WinlossForExtraPT_virtualrate = c.WinlossForExtraPT_virtualrate - d.WinlossForExtraPT_virtualrate
	   FROM #src c
		  INNER JOIN #src d ON c.srecommend = d.srecommend
						   AND c.SportType = d.SportType
	   WHERE c.srecommend = 2
		    AND c.Site = 1
		    AND d.Site = 2;
	   --2. Not Sportsbook and not have detail table yet ; and special Sportsbook : Parlay, Metric gaming, Bettrade, Bet Builder
	   INSERT INTO #src(srecommend
				   , site
				   , SportType
				   , winlost_actualrate
				   , SMAWinloss
				   , commission_actualrate
				   , HouseWinloss_actualrate
				   , HouseWinloss_virtualrate
				   , HouseWinloss_variance
				   , grosscomm_actualrate
				   , grosscomm_virtualrate
				   , grosscomm_variance
				   , ProductId
				   , CasinoType
				   , turnover_actualrate
				   , turnover_virtualrate
				   , stake_actualrate
				   , stake_virtualrate
				   , WinlossForExtraPT_actualrate
				   , WinlossForExtraPT_virtualrate)
			SELECT srecommend
				, 1 AS site
				, 0 AS SportType
				, SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss
				, SUM(scomm * actualrate) AS commission_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS HouseWinloss_actualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate + scomm * CASE
																						  WHEN b.virtualrate < b.actualrate
																						  THEN b.virtualrate
																						  ELSE b.actualrate
																					   END) AS HouseWinloss_virtualrate
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + CASE
																	    WHEN b.virtualrate < b.actualrate
																	    THEN b.scomm
																	    ELSE 0
																	END) * (actualrate - virtualrate)) AS HouseWinloss_variance
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * b.actualrate * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * CASE
							 WHEN b.virtualrate < b.actualrate
							 THEN b.virtualrate
							 ELSE b.actualrate
						  END * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN CASE
							    WHEN b.tpositiontaking = 1
							    THEN 0
							    ELSE b.scomm / (1 - b.tpositiontaking)
							END
						ELSE 0
					 END * (actualrate - virtualrate) * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_variance
				, CASE s.SubProduct
					   WHEN 'MG-SuperLive'
					   THEN-1
					   WHEN 'BT-Comm'
					   THEN-2
					   WHEN 'BT-Winloss'
					   THEN-2
					   WHEN 'Bet Builder'
					   THEN-6
					   WHEN 'Odds Spread Adjustment'
					   THEN-7 /*odds spread (#141750)*/
					   ELSE CASE
							  WHEN s.EventType = 0
								  AND ProductID = 1
							  THEN-3 /*parlay*/
							  ELSE s.ProductID
						   END
				    END AS ProductID
				, s.CasinoType
				, SUM((1 - b.tpositiontaking) * CASE
											 WHEN s.productID = 1
											 THEN ABS(stake)
											 ELSE stake
										  END * CASE
												  WHEN virtualrate > actualrate
												  THEN virtualrate
												  ELSE actualrate
											   END * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_actualrate
				, SUM((1 - b.tpositiontaking) * CASE
											 WHEN s.productID = 1
											 THEN ABS(stake)
											 ELSE stake
										  END * virtualrate * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS turnover_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE CASE
							    WHEN s.productID = 1
							    THEN ABS(stake)
							    ELSE stake
							END * CASE
									WHEN virtualrate > actualrate
									THEN virtualrate
									ELSE actualrate
								 END
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE CASE
							    WHEN s.productID = 1
							    THEN ABS(stake)
							    ELSE stake
							END * virtualrate
					 END * CAST(epositiontaking AS DECIMAL(9, 8)) * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND ABS(modds) = 0.25 --to identify Half won/lost tickets
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS stake_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_virtualrate
			FROM bettrans AS b WITH(NOLOCK)
			    INNER JOIN #SportBettype AS s ON b.bettype = s.bettype
			WHERE winlostdate = @StartDate
				 AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
				 AND b.ruben = 1
				 AND
					(s.productID <> 1 AND s.RefTable NOT IN(1, 2)
					 OR s.productID = 1 AND s.SubProduct IN('MG-SuperLive', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
					 OR s.productID = 1 AND s.EventType = 0) /*include "Odds Spread Adjustment" & "Parlay"*/
			GROUP BY srecommend
				  , CASE s.SubProduct
					   WHEN 'MG-SuperLive'
					   THEN-1
					   WHEN 'BT-Comm'
					   THEN-2
					   WHEN 'BT-Winloss'
					   THEN-2
					   WHEN 'Bet Builder'
					   THEN-6
					   WHEN 'Odds Spread Adjustment'
					   THEN-7 /*odds spread (#141750)*/
					   ELSE CASE
							  WHEN s.EventType = 0
								  AND ProductID = 1
							  THEN-3 /*parlay*/
							  ELSE s.ProductID
						   END
				    END
				  , s.CasinoType;				  

	   -- Get bettransRNG data
	   INSERT INTO #tmp_srcDetail(srecommend
						   , bettype
						   , site
						   , winlost_actualrate
						   , winlost_virtualrate
						   , winlost_jackpot_actualrate
						   , winlost_jackpot_virtualrate
						   , SMAWinloss_actualrate
						   , SMAWinloss_virtualrate
						   , commission_actualrate
						   , commission_virtualrate
						   , commission_variance
						   , grosscomm_actualrate
						   , grosscomm_virtualrate
						   , grosscomm_variance
						   , turnover_actualrate
						   , turnover_virtualrate
						   , stake_actualrate
						   , stake_virtualrate
						   , WinlossForExtraPT_actualrate
						   , WinlossForExtraPT_virtualrate
						   , WinlossJackpotForExtraPT_actualrate
						   , WinlossJackpotForExtraPT_virtualrate)
			SELECT b.srecommend
				, b.gameID AS bettype
				, 1 AS site
				, SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
				, SUM((winlost - actual_stake) * virtualrate) AS winlost_virtualrate
				, SUM(b.ContributionStake3rd * actualrate) AS winlost_jackpot_actualrate
				, SUM(b.ContributionStake3rd * virtualrate) AS winlost_jackpot_virtualrate
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss_actualrate
				, SUM((awinlost + mwinlost + swinlost) * virtualrate) AS SMAWinloss_virtualrate
				, SUM(scomm * actualrate) AS commission_actualrate
				, SUM(scomm * CASE
							   WHEN b.virtualrate < b.actualrate
							   THEN b.virtualrate
							   ELSE b.actualrate
						    END) AS commission_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN b.scomm
						ELSE 0
					 END * (actualrate - virtualrate)) AS commission_variance
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * b.actualrate * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * CASE
							 WHEN b.virtualrate < b.actualrate
							 THEN b.virtualrate
							 ELSE b.actualrate
						  END * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN CASE
							    WHEN b.tpositiontaking = 1
							    THEN 0
							    ELSE b.scomm / (1 - b.tpositiontaking)
							END
						ELSE 0
					 END * (actualrate - virtualrate) * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_variance
				, SUM((1 - b.tpositiontaking) * stake * CASE
												    WHEN virtualrate > actualrate
												    THEN virtualrate
												    ELSE actualrate
												END) AS turnover_actualrate
				, SUM((1 - b.tpositiontaking) * stake * virtualrate) AS turnover_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE stake * CASE
									  WHEN virtualrate > actualrate
									  THEN virtualrate
									  ELSE actualrate
								   END
					 END * CAST(epositiontaking AS DECIMAL(9, 8))) AS stake_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE stake * virtualrate
					 END * CAST(epositiontaking AS DECIMAL(9, 8))) AS stake_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.ContributionStake3rd * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossJackpotForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.ContributionStake3rd * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossJackpotForExtraPT_virtualrate
			FROM bettransRNG AS b WITH(NOLOCK)
			WHERE winlostdate = @StartDate
				 AND b.statusID IN(111, 112, 113)
			GROUP BY b.srecommend
				  , b.gameID OPTION(RECOMPILE);
	   -- Get bettransLC data
	   INSERT INTO #tmp_srcDetail(srecommend
						   , bettype
						   , site
						   , winlost_actualrate
						   , winlost_virtualrate
						   , SMAWinloss_actualrate
						   , SMAWinloss_virtualrate
						   , commission_actualrate
						   , commission_virtualrate
						   , commission_variance
						   , grosscomm_actualrate
						   , grosscomm_virtualrate
						   , grosscomm_variance
						   , turnover_actualrate
						   , turnover_virtualrate
						   , stake_actualrate
						   , stake_virtualrate
						   , WinlossForExtraPT_actualrate
						   , WinlossForExtraPT_virtualrate)
			SELECT b.srecommend
				, b.gameID AS bettype
				, 1 AS site
				, SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
				, SUM((winlost - actual_stake) * virtualrate) AS winlost_virtualrate
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss_actualrate
				, SUM((awinlost + mwinlost + swinlost) * virtualrate) AS SMAWinloss_virtualrate
				, SUM(scomm * actualrate) AS commission_actualrate
				, SUM(scomm * CASE
							   WHEN b.virtualrate < b.actualrate
							   THEN b.virtualrate
							   ELSE b.actualrate
						    END) AS commission_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN b.scomm
						ELSE 0
					 END * (actualrate - virtualrate)) AS commission_variance
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * b.actualrate * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE b.scomm / (1 - b.tpositiontaking)
					 END * CASE
							 WHEN b.virtualrate < b.actualrate
							 THEN b.virtualrate
							 ELSE b.actualrate
						  END * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_virtualrate
				, SUM(CASE
						WHEN b.virtualrate < b.actualrate
						THEN CASE
							    WHEN b.tpositiontaking = 1
							    THEN 0
							    ELSE b.scomm / (1 - b.tpositiontaking)
							END
						ELSE 0
					 END * (actualrate - virtualrate) * CAST(epositiontaking AS DECIMAL(9, 8))) AS grosscomm_variance
				, SUM((1 - b.tpositiontaking) * stake * CASE
												    WHEN virtualrate > actualrate
												    THEN virtualrate
												    ELSE actualrate
												END) AS turnover_actualrate
				, SUM((1 - b.tpositiontaking) * stake * virtualrate) AS turnover_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE stake * CASE
									  WHEN virtualrate > actualrate
									  THEN virtualrate
									  ELSE actualrate
								   END
					 END * CAST(epositiontaking AS DECIMAL(9, 8))) AS stake_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE stake * virtualrate
					 END * CAST(epositiontaking AS DECIMAL(9, 8))) AS stake_virtualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * actualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE(winlost - actual_stake) * virtualrate * CAST(epositiontaking AS DECIMAL(9, 8))
					 END) AS WinlossForExtraPT_virtualrate
			FROM bettransLC AS b WITH(NOLOCK)
			WHERE winlostdate = @StartDate
				 AND b.statusID IN(111, 112, 113)
			GROUP BY b.srecommend
				  , b.gameID OPTION(RECOMPILE);
	   --3. Get from Temporary Detail table --
	   INSERT INTO #srcDetail(srecommend
					    , site
					    , winlost_actualrate
					    , SMAWinloss
					    , commission_actualrate
					    , HouseWinloss_actualrate
					    , HouseWinloss_virtualrate
					    , HouseWinloss_variance
					    , grosscomm_actualrate
					    , grosscomm_virtualrate
					    , grosscomm_variance
					    , ProductId
					    , CasinoType
					    , turnover_actualrate
					    , turnover_virtualrate
					    , stake_actualrate
					    , stake_virtualrate
					    , WinlossForExtraPT_actualrate
					    , WinlossForExtraPT_virtualrate)
			SELECT b.srecommend
				, 1 AS site
				, SUM(b.winlost_actualrate) AS winlost_actualrate
				, SUM(b.SMAWinloss_actualrate) AS SMAWinloss
				, SUM(b.commission_actualrate) AS commission_actualrate
				, SUM(CASE
						WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
						WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
						THEN b.winlost_jackpot_actualrate + b.SMAWinloss_actualrate + b.commission_actualrate
						ELSE b.winlost_actualrate + b.SMAWinloss_actualrate + b.commission_actualrate
					 END) AS HouseWinloss_actualrate
				, SUM(CASE
						WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
						WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
						THEN b.winlost_jackpot_virtualrate + b.SMAWinloss_virtualrate
						ELSE b.winlost_virtualrate + b.SMAWinloss_virtualrate
					 END + b.commission_virtualrate) AS HouseWinloss_virtualrate
				, SUM(CASE
						WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
						WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
						THEN b.winlost_jackpot_actualrate - winlost_jackpot_virtualrate + b.SMAWinloss_actualrate - b.SMAWinloss_virtualrate
						ELSE b.winlost_actualrate - b.winlost_virtualrate + b.SMAWinloss_actualrate - b.SMAWinloss_virtualrate
					 END + b.grosscomm_variance) AS HouseWinloss_variance
				, SUM(grosscomm_actualrate) AS grosscomm_actualrate
				, SUM(grosscomm_virtualrate) AS grosscomm_virtualrate
				, SUM(grosscomm_variance) AS grosscomm_variance
				, s.ProductID
				, s.CasinoType
				, SUM(turnover_actualrate) AS turnover_actualrate
				, SUM(turnover_virtualrate) AS turnover_virtualrate
				, SUM(stake_actualrate) AS stake_actualrate
				, SUM(stake_virtualrate) AS stake_virtualrate
				, SUM(CASE
						WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
						WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
						THEN WinlossJackpotForExtraPT_actualrate  --Jackpot Contribution
						ELSE WinlossForExtraPT_actualrate
					 END) AS WinlossForExtraPT_actualrate
				, SUM(CASE
						WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
						WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
						THEN WinlossJackpotForExtraPT_virtualrate  --Jackpot Contribution
						ELSE WinlossForExtraPT_virtualrate
					 END) AS WinlossForExtraPT_virtualrate
			FROM #tmp_srcDetail AS b WITH(NOLOCK)
			    INNER JOIN #SportBettype AS s ON b.bettype = s.bettype
				LEFT JOIN #SpecialBettypeGroup bg ON b.bettype = bg.Bettype
			WHERE s.RefTable IN(1, 2)
			GROUP BY b.srecommend
				  , s.ProductID
				  , s.CasinoType;
	   --

	   UPDATE #src
			SET 
			    site = 2
	   WHERE srecommend IN
					   (
						  SELECT CustId
						  FROM #DepSuper
					   );
	   UPDATE #srcDetail
			SET 
			    site = 2
	   WHERE srecommend IN
					   (
						  SELECT CustId
						  FROM #DepSuper
					   );
	   UPDATE #src
			SET 
			    site = 3
	   WHERE srecommend IN
					   (
						  SELECT CustId
						  FROM CS_CustSuper AS cn88
					   );
	   --		  
	   --Insert to Result table to get data--
	   --1. Soccer and Others
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT CASE
					 WHEN b.Sporttype = 1
					 THEN-5
					 WHEN b.Sporttype = -1 THEN -1000 -- Harcode for SABA
					 WHEN b.sporttype IN(2, 44)
					 THEN-4
				  END AS ProductID
				, site
				, SUM(winLost_actualrate) AS winlost
				, SUM(SMAWinloss) AS Position
				, SUM(commission_actualrate) AS Commission
				, SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, SUM(turnover_actualrate - stake_actualrate) AS RealTurnover
				, SUM(turnover_virtualrate - stake_virtualrate) AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #src AS b
			WHERE b.ProductId = 1
			GROUP BY CASE
					   WHEN b.Sporttype = 1
					   THEN-5
					   WHEN b.Sporttype = -1 THEN -1000 -- Harcode for SABA
					   WHEN b.sporttype IN(2, 44)
					   THEN-4
				    END
				  , site;
	   --METRIC GAMING -SUPER LIVE, BET BUILDER
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT b.ProductID
				, site
				, SUM(ISNULL(b.winlost_actualrate, 0)) AS WinLost
				, SUM(ISNULL(b.SMAWinloss, 0)) AS Position
				, SUM(ISNULL(commission_actualrate, 0)) AS Commission
				, SUM(ISNULL(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate), 0)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, SUM(turnover_actualrate - stake_actualrate) AS RealTurnover
				, SUM(turnover_virtualrate - stake_virtualrate) AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #src AS b
			WHERE b.ProductId IN (-1, -6)
			GROUP BY b.ProductId
				  , site;
	   -- Parlay, NUMBER GAME, Licensee Odds Spread		 
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT b.ProductId
				, site
				, SUM(winlost_actualrate) AS WinLost
				, SUM(SMAWinloss) AS Position
				, SUM(commission_actualrate) AS Commission
				, SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, SUM(turnover_actualrate - stake_actualrate) AS RealTurnover
				, SUM(turnover_virtualrate - stake_virtualrate) AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #src AS b
			WHERE b.ProductID IN (-3, 3, -7)
			GROUP BY b.ProductId
				  , site;

	   --bettrade
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT b.ProductId
				, site
				, SUM(ISNULL(b.winlost_actualrate, 0)) AS WinLost
				, SUM(ISNULL(b.SMAWinloss, 0)) AS Position
				, 0 AS Commission
				, SUM(ISNULL(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate), 0)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, 0 AS RealTurnover
				, 0 AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #src AS b
			WHERE b.ProductId = -2
			GROUP BY site
				  , b.ProductId;
	   --Live casino and Casino and 3rd Party
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT CASE
					 WHEN b.CasinoType = 1
					 THEN 6  -- Casino
					 WHEN b.CasinoType = 2
					 THEN 4  --Live Casino
					 ELSE b.ProductId
				  END AS ProductId
				, site
				, SUM(winlost_actualrate) AS WinLost
				, SUM(SMAWinloss) AS Position
				, SUM(commission_actualrate) AS Commission
				, SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, SUM(turnover_actualrate - stake_actualrate) AS RealTurnover
				, SUM(turnover_virtualrate - stake_virtualrate) AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #src AS b
			WHERE b.ProductId IN(5, 8, 15, 23, 25, 27, 28, 31, --Virtual Sports, Keno, Colossus Bets, NG2 (3rd), CashOut, Betradar Virtual Sports, Lottery, Exchange
								 37, 38, 43, 40, 49)           --Saba Promotion, Virtual Games, Indo 4D, Table Games, Virtual Sports 3
				 OR b.CasinoType IN(1, 2)
			GROUP BY site
				  , CASE
					   WHEN b.CasinoType = 1
					   THEN 6   -- Casino
					   WHEN b.CasinoType = 2
					   THEN 4  --Live Casino
					   ELSE b.ProductId
				    END;
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT CASE
					 WHEN b.CasinoType = 1
					 THEN 6  -- Casino
					 WHEN b.CasinoType = 2
					 THEN 4  --Live Casino
					 ELSE b.ProductId
				  END AS ProductId
				, site
				, SUM(winlost_actualrate) AS WinLost
				, SUM(SMAWinloss) AS Position
				, SUM(commission_actualrate) AS Commission
				, SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate)) AS RealHouseWinloss
				, SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate)) AS VirtualHouseWinloss
				, SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) - grosscomm_variance) AS VarianceIncome
				, SUM(turnover_actualrate - stake_actualrate) AS RealTurnover
				, SUM(turnover_virtualrate - stake_virtualrate) AS VirtualTurnover
				, SUM(WinlossForExtraPT_actualrate) AS ExtraPT
				, SUM(b.WinlossForExtraPT_actualrate + grosscomm_actualrate) AS NewExtraPT
			FROM #srcDetail AS b
			WHERE b.ProductId IN(24, 42, 50) -- Fishing World, Saba.club, RNG War
				 OR b.CasinoType IN(1, 2)
			GROUP BY site
				  , CASE
					   WHEN b.CasinoType = 1
					   THEN 6  -- Casino
					   WHEN b.CasinoType = 2
					   THEN 4  --Live Casino
					   ELSE b.ProductId
				    END;				 
	   --2. Total --
	   -- Get win lost of agent '8RM' , 'BARM'
	   INSERT INTO #Result(ProductId
					 , site
					 , winlost
					 , Position
					 , Commission
					 , RealHouseWinloss
					 , VirtualHouseWinloss
					 , VarianceIncome
					 , RealTurnover
					 , VirtualTurnover
					 , ExtraPT
					 , NewExtraPT)
			SELECT CASE
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN -98
					 WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1001
					 ELSE-99
				  END AS ProductId
				, CASE b.recommend
					 WHEN 52466
					 THEN 1
					 WHEN 5707545
					 THEN 2
				  END AS site
				, -SUM(winlost - actual_stake) AS WinLost
				, -SUM(awinlost + mwinlost + swinlost) AS Position
				, SUM(scomm) AS Commission
				, -SUM(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) AS RealHouseWinloss
				, -SUM(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) AS VirtualHouseWinloss
				, 0 AS VarianceIncome
				, SUM((1 - tpositiontaking) * ABS(stake) * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND statusID IN (112, 113) --WON, LOSE
																			 AND ABS(modds) = 0.25 --to actually identify tickets that settled as Half won/lost
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS RealTurnover
				, SUM((1 - tpositiontaking) * ABS(stake) * CASE WHEN @IsNoDraw = 1 
															 THEN CASE WHEN s.ApplyNoDraw = 1 AND statusID IN (112, 113) --WON, LOSE
																			 AND ABS(modds) = 0.25 --to actually identify tickets that settled as Half won/lost
																	   THEN 0.5
																  ELSE 1 END
															 ELSE 1 END) AS VirtualTurnover
				, 0 AS ExtraPT
				, 0 AS NewExtraPT
			FROM bettrans AS b WITH(NOLOCK)
			    INNER JOIN #SportBettype AS s ON b.bettype = s.bettype
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
			WHERE b.recommend IN(52466, 5707545)
				 AND b.winlostdate = @StartDate
				 AND b.bettype < 19001
				 AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
				 AND b.ruben = 1
				 AND m.type = CASE
							   WHEN b.bettype = 10
							   THEN 1
							   ELSE 0
						    END
				 AND s.productID = 1
				 AND s.EventType IN(1, 2)
				 AND s.SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			GROUP BY CASE
					  WHEN m.Sporttype = 1 AND m.IsSabaSport = 0 THEN -98
					  WHEN m.Sporttype = 1 AND m.IsSabaSport = 1 THEN -1001
					   ELSE-99
				    END
				  , CASE b.recommend
					   WHEN 52466
					   THEN 1
					   WHEN 5707545
					   THEN 2
				    END;					
	   --3. Total --
	   --
	   --Get Result--

	   DECLARE @ProductOrder AS TABLE(
		   DisplayOrder    INT
		 , ProductId       INT
		 , ProductName     NVARCHAR(50)
		 , Site            TINYINT DEFAULT 0);
	   INSERT INTO @ProductOrder(DisplayOrder
						  , ProductId
						  , ProductName)
	   VALUES
			(1, -5, 'Soccer'),
			(2, -1000, 'SABA Soccer'),
			(3, -4, 'Other Sports'),
			(4, -3, 'Parlay'),
			(5, -7, 'SB Adjustment'),
			(6, -1, 'Metric Gaming - Superlive'),
			(7, -6, 'Bet Builder'),
			(8, 8, 'RNG Keno'),
			(9, 3, 'Number Game'),
			(10, 4, 'Live Casino'),
			(11, 6, 'Casino'),
			(12, 5, 'Virtual Sports'),
			(13, 27, 'Virtual Sports 2'),
			(14, 28, 'Lottery'),
			(15, 23, 'NG2'),
			(16, -2, 'Bettrade'),
			(17, 25, 'Cash Out'),
			(18, 15, 'Colossus Bets'),
			(19, 24, 'Fishing World'),
			(20, 31, 'Exchange'),
			(21, 37, 'Saba Promotion'),
			(22, 38, 'Virtual Games'),
			(23, 43, 'Togel 4D'),
			(24, 40, 'Table Game'),
			(25, 42, 'Saba.club'),
			(26, 50, 'RNG War'),
			(27, 49, 'Virtual Sports 3');

	   INSERT INTO @ProductOrder(DisplayOrder
						  , ProductId
						  , ProductName
						  , Site)
	   VALUES
			(100, -98, 'Soccer 8RM', 1),
			(100, -98, 'Soccer BARM', 2),
			(101, -1001, 'SABA Soccer 8RM', 1),
			(101, -1001, 'SABA Soccer BARM', 2),

			(102, -99, 'Other Sports 8RM', 1),
			(102, -99, 'Other Sports BARM', 2);
	   UPDATE R
			SET 
			    DisplayOrder = P.DisplayOrder
			  , ProductName = P.ProductName
	   FROM #Result R
		  INNER JOIN @ProductOrder P ON P.ProductID = R.ProductId
								  AND P.Site = CASE
											    WHEN P.Site <> 0
											    THEN r.Site
											    ELSE 0
											END;
	   SELECT CASE
			    WHEN d.DisplayOrder IN(100, 101, 102)
			    THEN 'RM'
			    ELSE d.ProductName
			END AS GroupName
		   , CASE
			    WHEN d.DisplayOrder IN(100, 101, 102)
			    THEN d.ProductName
			    WHEN d.Site = 1
			    THEN 'Credit'
			    WHEN d.Site = 2
			    THEN 'Deposit'
			    WHEN d.Site = 3
			    THEN 'CN88'
			END AS RowName
		   , d.DisplayOrder
		   , site
		   , SUM(d.winlost) AS MemberWinLoss
		   , SUM(d.Position) AS SMAWinLoss
		   , SUM(d.Commission) AS Commission
		   , SUM(d.RealHouseWinloss) AS RealIncome
		   , SUM(d.VirtualHouseWinloss) AS VirtualIncome
		   , SUM(d.VarianceIncome) AS VarianceIncome
		   , SUM(d.RealTurnover) AS RealTurnover
		   , SUM(d.VirtualTurnover) AS VirtualTurnover
		   , SUM(CASE
				   WHEN @StartDate < @EffectedDate
				   THEN-d.extraPT
				   ELSE-d.NewExtraPT
			    END) AS extraPT
	   FROM #Result AS d
	   GROUP BY CASE
				 WHEN d.DisplayOrder IN(100, 101, 102)
				 THEN 'RM'
				 ELSE d.ProductName
			  END
			, CASE
				 WHEN d.DisplayOrder IN(100, 101, 102)
				 THEN d.ProductName
				 WHEN d.Site = 1
				 THEN 'Credit'
				 WHEN d.Site = 2
				 THEN 'Deposit'
				 WHEN d.Site = 3
				 THEN 'CN88'
			  END
			, d.DisplayOrder
			, site
	   ORDER BY DisplayOrder ASC
			, site;
	   DROP TABLE #tmp_src;
	   DROP TABLE #tmp_srcDetail;
	   DROP TABLE #src;
	   DROP TABLE #srcDetail;
	   DROP TABLE #DepSuper;
	   DROP TABLE #Match;
	   DROP TABLE #Result;
	   DROP TABLE #SportBettype;
	   DROP TABLE #SpecialBettypeGroup
	   DROP TABLE #SABALeagueGroup;
    END
GO
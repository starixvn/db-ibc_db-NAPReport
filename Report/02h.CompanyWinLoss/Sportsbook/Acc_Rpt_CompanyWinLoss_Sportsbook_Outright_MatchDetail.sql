/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail] @StartDate SMALLDATETIME, 
                                                                               @EndDate   SMALLDATETIME, 
                                                                               @SportType SMALLINT      = 1,
																			   @IsSabaSport TINYINT = 0,
																			   @IsNoDraw BIT = 0
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
  20160301@Jacob: Initialize Company Win Loss Report
  20180419@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
  20190828@Cherry: Hot fix Bet Buider (#119077)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20201222@Kean: Support to filter NoDraw and separate the SABA sports - NAP Report (#147451)
- 20210323@Kean: Daily Win Loss (2h) Soccer Minor Bet Types do not use @IsSabaSport parameter (#152100)

Parameters:
@IsSabaSport: 2 - ALL. 0 - Non-SABA. 1 - SABA 
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @SportType=2

*/

     SET NOCOUNT ON;
	 BEGIN -- #SABALeagueGroup
		DECLARE @LeagueGroupStr VARCHAR(500);
		CREATE TABLE #SABALeagueGroup(LeagueGroupID INT)
		SELECT @LeagueGroupStr = [VValue] FROM DBWH.[bodb_Account].[dbo].[SystemSettings] WHERE VID = 5

		INSERT INTO #SABALeagueGroup
		SELECT val FROM dbo.strSplit(@LeagueGroupStr,',')
	END;
    BEGIN -- #Match

        CREATE TABLE #Match
                     (MatchId   INT, 
                      LeagueId  INT, 
                      teamid    INT, 
                      MatchCode NVARCHAR(50)
                     );
        INSERT INTO #Match
               SELECT orid, 
                      o.LeagueId, 
                      o.teamid, 
                      o.MatchCode
               FROM outright o WITH(NOLOCK)
                    INNER JOIN league l WITH(NOLOCK) ON o.LeagueId = l.LeagueId
               WHERE EventDate = @StartDate
                     AND l.sporttype = @SportType
					 AND (@IsSabaSport = 2
							OR (@IsSabaSport = 0 AND l.LeagueGroupID NOT IN (SELECT LeagueGroupID FROM #SABALeagueGroup)) 
							OR (@IsSabaSport = 1 AND l.LeagueGroupID IN (SELECT LeagueGroupID FROM #SABALeagueGroup))
						);
    END;
    BEGIN -- #Data

        CREATE TABLE #Data
                     (MatchId         INT, 
                      MatchCode       VARCHAR(100), 
                      TeamId          INT, 
                      LeagueId        INT, 
                      MemberWinLoss   MONEY, 
                      SMAWinLoss      MONEY, 
                      ExtraPT         MONEY, 
                      Commission      MONEY, 
                      RealIncome      MONEY, 
                      VirtualIncome   MONEY, 
                      VarianceIncome  MONEY, 
                      RealTurnover    MONEY, 
                      VirtualTurnover MONEY
                     );
    END;
    BEGIN -- Outright

        INSERT INTO #Data
               SELECT m.MatchId, 
                      m.MatchCode, 
                      m.TeamId, 
                      m.LeagueId, 
                      SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                      SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate) Commission, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                  WHEN tpositiontaking = 1
                                                                                                  THEN 0
                                                                                                  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                              END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END) * virtualrate + (scomm - (CASE
                                                                                                                        WHEN tpositiontaking = 1
                                                                                                                        THEN 0
                                                                                                                        ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                    END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                                    WHEN virtualrate < actualrate
                                                                                                                                                                    THEN virtualrate / actualrate
                                                                                                                                                                    ELSE 1
                                                                                                                                                                END) VirtualIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END + CASE
                                                                                               WHEN virtualrate < actualrate
                                                                                               THEN(b.scomm - (CASE
                                                                                                                   WHEN tpositiontaking = 1
                                                                                                                   THEN 0
                                                                                                                   ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                               END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0))
                                                                                               ELSE 0
                                                                                           END) * (actualrate - virtualrate)) VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) VirtualTurnover
               FROM bettrans b WITH(NOLOCK)
                    INNER JOIN #Match m WITH(NOLOCK) ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = 10
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
               GROUP BY m.MatchId, 
                        m.MatchCode, 
                        m.TeamId, 
                        m.LeagueId;
    END;
    BEGIN -- RM

        INSERT INTO #Data
               SELECT 0 AS MatchId,
                      CASE
                          WHEN b.recommend = 52466
                          THEN '8RM Total'
                          ELSE 'BARM Total'
                      END MatchCode, 
                      0 TeamId, 
                      0 LeagueId, 
                      -SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                      -SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate) Commission, 
                      -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                   WHEN tpositiontaking = 1
                                                                                                   THEN 0
                                                                                                   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                               END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
                      -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                      END) * virtualrate + (scomm - (CASE
                                                                                                                         WHEN tpositiontaking = 1
                                                                                                                         THEN 0
                                                                                                                         ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                     END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                                     WHEN virtualrate < actualrate
                                                                                                                                                                     THEN virtualrate / actualrate
                                                                                                                                                                     ELSE 1
                                                                                                                                                                 END) VirtualIncome, 
                      -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                      END + CASE
                                                                                                WHEN virtualrate < actualrate
                                                                                                THEN(b.scomm - (CASE
                                                                                                                    WHEN tpositiontaking = 1
                                                                                                                    THEN 0
                                                                                                                    ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0))
                                                                                                ELSE 0
                                                                                            END) * (actualrate - virtualrate)) VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) AS RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) AS VirtualTurnover
               FROM bettrans b WITH(NOLOCK)
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = 10
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
                    AND b.recommend IN(52466, 5707545)
               GROUP BY CASE
                            WHEN b.recommend = 52466
                            THEN '8RM Total'
                            ELSE 'BARM Total'
                        END;
    END;
    BEGIN -- Query

        SELECT d.MatchId, 
               d.MatchCode, 
               @SportType SportType, 
               d.TeamId AS HomeId, 
               d.LeagueId, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.VirtualIncome AS VirtualIncome, 
               d.VarianceIncome AS VarianceIncome, 
               d.RealTurnover AS RealTurnover, 
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY LeagueId, 
                 MatchCode, 
                 HomeId;
    END;
    
	DROP TABLE #Match;
    DROP TABLE #Data;
	DROP TABLE #SABALeagueGroup;
GO
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_MatchDetail] @StartDate SMALLDATETIME, 
                                                                      @EndDate   SMALLDATETIME, 
                                                                      @SportType SMALLINT      = 1, 
                                                                      @BetType   INT           = 1, 
                                                                      @IsHedge   INT           = 2, 
                                                                      @IsCorners INT           = 2,
                                                                      @IsLive    INT           = 2,
																	  @IsSabaSport TINYINT = 0,
																	  @IsNoDraw BIT = 0 
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190220@Dominic: Recompile exec plan to avoid parameter sniffing
- 20190313@Jacob: Integrate BetBuilder (#109822)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20201222@Kean: Support to filter NoDraw and separate the SABA sports - NAP Report (#147451)
- 20210323@Kean: Daily Win Loss (2h) Soccer Minor Bet Types do not use @IsSabaSport parameter (#152100)
- 20210326@Kean: HotFix, Missing data when league.LeagueGroupId is NULL - NAP Report (#152390)
- 20210520@Kean: SABA Soccer PinGoal - NAP Report (#155447)
- 20220125@Ned.Le: NAP Report - Separate Time Machine Corner with TW (#167882)
- 20220210@Ned.Le: NAP Report - Incorporate SABA Basketball PinGoal (#168364)

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
@IsHedge: 2 - ALL. 0 - Non-Hedge. 1 - Hedge
@IsCorners: 2 - ALL. 0 - Non-Corners. 1 - Corners
@IsSabaSport: 2 - ALL. 0 - Non-SABA. 1 - SABA. 3 - SABA Soccer PinGoal. 4 - SABA Basketball PinGoal

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @SportType=2, @BetType=1, @IsHedge = 0, @IsCorners=2, @IsLive = 2

*/

     SET NOCOUNT ON;
	BEGIN -- #SABALeagueGroup
		DECLARE @LeagueGroupStr VARCHAR(500)
		SELECT @LeagueGroupStr = [VValue] FROM DBWH.[bodb_Account].[dbo].[SystemSettings] WHERE VID = 5

        CREATE TABLE #SABALeagueGroup(LeagueGroupID INT)
		INSERT INTO #SABALeagueGroup
		SELECT val FROM dbo.strSplit(@LeagueGroupStr,',')

		CREATE TABLE #SABALeague (
				LeagueGroupType INT,
				LeagueGroupID INT,
				LeagueID INT
		)
		INSERT INTO #SABALeague(LeagueGroupType, LeagueGroupID, LeagueID)
		SELECT CASE WHEN LeagueGroupID = 113 THEN 2
                    WHEN LeagueGroupID = 122 THEN 3
		            ELSE 1 END LeagueGroupType,
		       LeagueGroupID,
		       leagueid LeagueID
		FROM bodb02.dbo.League l (NOLOCK)
		WHERE l.sporttype = @SportType
			AND LeagueGroupID IN (SELECT LeagueGroupID FROM #SABALeagueGroup)
	END;
    BEGIN -- #Match

        CREATE TABLE #Match
                     (MatchId   INT, 
                      MatchCode NVARCHAR(50), 
                      IsNeutral BIT, 
                      EventDate DATETIME, 
                      LeagueId  INT, 
                      HomeId    INT, 
                      AwayId    INT
                     );
        INSERT INTO #Match
               SELECT DISTINCT m.MatchId, 
                      m.MatchCode, 
                      m.IsNeutral, 
                      m.EventDate, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId
               FROM Match m WITH(NOLOCK)
			   INNER JOIN league AS l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
               WHERE m.sporttype = @SportType
                     AND EventDate = @StartDate
                     AND (@IsHedge = 2 OR (@IsHedge = 1 AND MatchCode LIKE '%Hedge%')
                                       OR (@IsHedge = 0 AND MatchCode NOT LIKE '%Hedge%'))
                     AND (@IsCorners = 2 OR (@IsCorners = 1 AND ISNULL(ChildMatchType, 0) = 204)
                                         OR (@IsCorners = 0 AND ISNULL(ChildMatchType, 0) <> 204))
		     AND ((@IsSabaSport = 2) OR
			  (@IsSabaSport = 0 AND l.leagueid NOT IN (SELECT LeagueID FROM #SABALeague)) OR
			  (@IsSabaSport = 1 AND l.leagueid IN (SELECT LeagueID FROM #SABALeague WHERE LeagueGroupType = 1)) OR
			  (@IsSabaSport = 3 AND l.leagueid IN (SELECT LeagueID FROM #SABALeague WHERE LeagueGroupType = 2)) OR
                          (@IsSabaSport = 4 AND l.leagueid IN (SELECT LeagueID FROM #SABALeague WHERE LeagueGroupType = 3)))
    END;
    BEGIN -- #Data	
        CREATE TABLE #Data
                     (MatchId         INT, 
                      MatchCode       VARCHAR(100), 
                      IsNeutral       BIT, 
                      EventDate       DATETIME, 
                      LeagueId        INT, 
                      HomeId          INT, 
                      AwayId          INT, 
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
    BEGIN -- INSERT INTO #Data
        INSERT INTO #Data
               SELECT b.MatchId, 
                      m.MatchCode, 
                      ISNULL(m.IsNeutral, 0) AS IsNeutral, 
                      m.EventDate, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId, 
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
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = @BetType
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
               GROUP BY b.MatchId, 
                        m.MatchCode, 
                        m.IsNeutral, 
                        m.HomeId, 
                        m.AwayId, 
                        m.EventDate, 
                        m.LeagueId OPTION(RECOMPILE);
    END;
    BEGIN -- RM

        INSERT INTO #Data
               SELECT 0 AS MatchId,
                      CASE
                          WHEN b.recommend = 52466
                          THEN '8RM Total'
                          ELSE 'BARM Total'
                      END MatchCode, 
                      0 AS IsNeutral, 
                      '1990-01-01' EventDate, 
                      0 LeagueId, 
                      0 HomeId, 
                      0 AwayId, 
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
                     AND b.BetType = @BetType
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
                    AND b.recommend IN(52466, 5707545)
               GROUP BY CASE
                            WHEN b.recommend = 52466
                            THEN '8RM Total'
                            ELSE 'BARM Total'
                        END OPTION(RECOMPILE);
    END;
    BEGIN -- Query

        SELECT d.MatchId, 
               d.MatchCode, 
               d.IsNeutral, 
               d.EventDate, 
               @SportType SportType, 
               d.LeagueId, 
               d.HomeId, 
               d.AwayId, 
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
                 MatchCode;
    END;
    
	DROP TABLE #Match;
    DROP TABLE #Data;
	DROP TABLE #SABALeagueGroup;
	DROP TABLE #SABALeague;
GO
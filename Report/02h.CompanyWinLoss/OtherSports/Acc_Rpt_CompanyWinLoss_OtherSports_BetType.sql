/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_OtherSports_BetType] @StartDate SMALLDATETIME, 
                                                                   @EndDate   SMALLDATETIME, 
                                                                   @SportType INT, 
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
- 20160801@Sophia: Revise code for Deposit and Credit ammount
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200722@Roy: Incorporate New Basketball Sport for BetBuilder Product - NAP Report (#138082)
- 20201222@Kean: Support to filter NoDraw and separate the SABA sports - NAP Report (#147451)
- 20210326@Kean: HotFix, Missing data when league.LeagueGroupId is NULL - NAP Report (#152390)
- 20212203@Jaden: Support SABA789 (#151326)
- 20220210@Ned.Le: NAP Report - Incorporate SABA Basketball PinGoal (#168364)
- 20220211@Ned.Le: Extend range for column BettypeName

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
@IsSabaSport: 2 - ALL. 0 - Non-SABA. 1 - SABA. 4 - SABA Basketball PinGoal

Example:
EXEC [Acc_Rpt_CompanyWinLoss_OtherSports_BetType] @EndDate='2020-01-01',@StartDate='2016-01-01', @SportType = 2, @IsLive = 2

*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType     INT, 
                      BetTypeName NVARCHAR(200)
                     );
        INSERT INTO #SportBetType
               SELECT DISTINCT b.typeid, 
                      b.typenamee
               FROM dbo.f_SportBetTypeMatrix_Sel(1, @SportType, 0, 2, '', '', @isTest) s
                    INNER JOIN BetType b WITH(NOLOCK) ON s.BetType = b.typeid
               WHERE SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
               AND EventType IN(1, 2);
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
                     (CustId INT
                      PRIMARY KEY
                     );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK)
    END;
	BEGIN -- #SABALeagueGroup
        DECLARE @LeagueGroupStr VARCHAR(500)
		SELECT @LeagueGroupStr = [VValue] FROM DBWH.[bodb_Account].[dbo].[SystemSettings] WHERE VID = 5

        CREATE TABLE #SABALeagueGroup(LeagueGroupID INT)
		INSERT INTO #SABALeagueGroup
		SELECT val FROM dbo.strSplit(@LeagueGroupStr,',')
	END;
    BEGIN -- #Match

        CREATE TABLE #Match
                     (MatchId INT, 
                      type    VARCHAR(10), 
                      PRIMARY KEY(MatchId, type)
                     );
        INSERT INTO #Match
               SELECT DISTINCT 
                      m.MatchId, 
                      m.type
               FROM
               (
                   SELECT MatchId, 
                          LeagueId, 
                          'match' AS type
                   FROM Match WITH(NOLOCK)
                   WHERE EventDate = @StartDate
                   UNION ALL
                   SELECT orid, 
                          LeagueId, 
                          'outright' AS type
                   FROM outright WITH(NOLOCK)
                   WHERE EventDate = @StartDate
               ) m
               INNER JOIN league l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
               WHERE l.sporttype = @SportType
			         AND ((@IsSabaSport = 2) OR
                          (@IsSabaSport = 0 AND (l.LeagueGroupID NOT IN (SELECT LeagueGroupID FROM #SABALeagueGroup) OR l.LeagueGroupID IS NULL)) OR
					      (@IsSabaSport = 1 AND (l.LeagueGroupID IN (SELECT LeagueGroupID FROM #SABALeagueGroup WHERE LeagueGroupID <> 122))) OR
                          (@IsSabaSport = 4 AND (l.LeagueGroupID IN (122))))
    END;
    BEGIN -- #Data
        CREATE TABLE #tmp_Data
                     (srecommend      INT, 
                      bettype         INT, 
                      liveindicator   BIT, 
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
        CREATE TABLE #Data
                     (GroupId         INT, 
                      GroupName       NVARCHAR(50), 
                      RowName         NVARCHAR(50), 
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
    BEGIN -- BetType
        INSERT INTO #tmp_Data
               SELECT srecommend, 
                      bettype, 
                      liveindicator, 
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
                                                                                              END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
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
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND m.type = CASE
                                      WHEN b.BetType = 10
                                      THEN 'outright'
                                      ELSE 'match'
                                  END
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
               GROUP BY srecommend, 
                        bettype, 
                        liveindicator OPTION(RECOMPILE);
        INSERT INTO #Data
               SELECT sb.BetType GroupId, 
                      sb.BetTypeName GroupName,
                      CASE
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END AS RowName, 
                      SUM(MemberWinLoss) MemberWinLoss, 
                      SUM(SMAWinLoss) AS SMAWinLoss, 
                      SUM(ExtraPT) AS ExtraPT, 
                      SUM(Commission) Commission, 
                      SUM(RealIncome) AS RealIncome, 
                      SUM(VirtualIncome) VirtualIncome, 
                      SUM(VarianceIncome) VarianceIncome, 
                      SUM(RealTurnover) AS RealTurnover, 
                      SUM(VirtualTurnover) AS VirtualTurnover
               FROM #tmp_Data AS b WITH(NOLOCK)
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
               WHERE @IsLive > 1
                     OR b.liveindicator = @IsLive
               GROUP BY sb.BetType, 
                        sb.BetTypeName,
                        CASE
                            WHEN dep.CustId IS NULL
                                 AND cn88.CustId IS NOT NULL
                            THEN 'CN88'
                            WHEN dep.CustId IS NULL
                                 AND cn88.CustId IS NULL
                            THEN 'Credit'
                            ELSE 'Deposit'
                        END;
    END;
    BEGIN -- Sophia
        -- BARM only
        INSERT INTO #Data
               SELECT sb.BetType GroupId, 
                      sb.BetTypeName GroupName, 
                      'BARM' AS RowName, 
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
                                                                                              END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
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
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
               WHERE b.recommend = 5707545
                     AND b.winlostdate = @StartDate
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND m.type = CASE
                                      WHEN b.BetType = 10
                                      THEN 'outright'
                                      ELSE 'match'
                                  END
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
               GROUP BY sb.BetType, 
                        sb.BetTypeName;
        INSERT INTO #Data
               (GroupId, 
                GroupName, 
                RowName, 
                MemberWinLoss, 
                SMAWinLoss, 
                ExtraPT, 
                Commission, 
                RealIncome, 
                VirtualIncome, 
                VarianceIncome, 
                RealTurnover, 
                VirtualTurnover
               )
               SELECT GroupId, 
                      GroupName, 
                      'Deposit' AS RowName, 
                      0 AS MemberWinLoss, 
                      0 AS SMAWinLoss, 
                      0 AS ExtraPT, 
                      0 AS Commission, 
                      0 AS RealIncome, 
                      0 AS VirtualIncome, 
                      0 AS VarianceIncome, 
                      0 AS RealTurnover, 
                      0 AS VirtualTurnover
               FROM
               (
                   SELECT GroupId, 
                          GroupName
                   FROM #Data
                   WHERE RowName = 'BARM'
                   EXCEPT
                   SELECT GroupId, 
                          GroupName
                   FROM #Data
                   WHERE RowName = 'Deposit'
               ) D;

        -- Update Credit = Credit - BARM, Deposit = Deposit + BARM
        UPDATE c
          SET 
              c.MemberWinLoss = ISNULL(c.MemberWinLoss, 0) + CASE
                                                                 WHEN c.RowName = 'Credit'
                                                                 THEN-ISNULL(d.MemberWinLoss, 0)
                                                                 ELSE ISNULL(d.MemberWinLoss, 0)
                                                             END, 
              c.SMAWinLoss = ISNULL(c.SMAWinLoss, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.SMAWinLoss, 0)
                                                           ELSE ISNULL(d.SMAWinLoss, 0)
                                                       END, 
              c.ExtraPT = ISNULL(c.ExtraPT, 0) + CASE
                                                     WHEN c.RowName = 'Credit'
                                                     THEN-ISNULL(d.ExtraPT, 0)
                                                     ELSE ISNULL(d.ExtraPT, 0)
                                                 END, 
              c.Commission = ISNULL(c.Commission, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.Commission, 0)
                                                           ELSE ISNULL(d.Commission, 0)
                                                       END, 
              c.RealIncome = ISNULL(c.RealIncome, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.RealIncome, 0)
                                                           ELSE ISNULL(d.RealIncome, 0)
                                                       END, 
              c.VirtualIncome = ISNULL(c.VirtualIncome, 0) + CASE
                                                                 WHEN c.RowName = 'Credit'
                                                                 THEN-ISNULL(d.VirtualIncome, 0)
                                                                 ELSE ISNULL(d.VirtualIncome, 0)
                                                             END, 
              c.VarianceIncome = ISNULL(c.VarianceIncome, 0) + CASE
                                                                   WHEN c.RowName = 'Credit'
                                                                   THEN-ISNULL(d.VarianceIncome, 0)
                                                                   ELSE ISNULL(d.VarianceIncome, 0)
                                                               END, 
              c.RealTurnover = ISNULL(c.RealTurnover, 0) + CASE
                                                               WHEN c.RowName = 'Credit'
                                                               THEN-ISNULL(d.RealTurnover, 0)
                                                               ELSE ISNULL(d.RealTurnover, 0)
                                                           END, 
              c.VirtualTurnover = ISNULL(c.VirtualTurnover, 0) + CASE
                                                                     WHEN c.RowName = 'Credit'
                                                                     THEN-ISNULL(d.VirtualTurnover, 0)
                                                                     ELSE ISNULL(d.VirtualTurnover, 0)
                                                                 END
        FROM #Data c
             FULL JOIN #Data d ON c.GroupId = d.GroupId
                                  AND c.GroupName = d.GroupName
                                  AND d.RowName = 'BARM'
                                  AND c.RowName IN('Credit', 'Deposit');

        --Delete BARM row used for calculate
        DELETE #Data
        WHERE RowName = 'BARM';
    END;
    BEGIN -- RM

        INSERT INTO #Data
               SELECT 0, 
                      'RM',
                      CASE
                          WHEN b.recommend = 52466
                          THEN '8RM Total'
                          WHEN b.recommend = 5707545
                          THEN 'BARM Total'
                          ELSE ''
                      END AS RowName, 
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
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND m.type = CASE
                                      WHEN b.BetType = 10
                                      THEN 'outright'
                                      ELSE 'match'
                                  END
                     AND b.ruben = 1
                     AND  ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
                    AND b.recommend IN(52466, 5707545)
               GROUP BY CASE
                            WHEN b.recommend = 52466
                            THEN '8RM Total'
                            WHEN b.recommend = 5707545
                            THEN 'BARM Total'
                            ELSE ''
                        END;
    END;
    BEGIN -- Query

        SELECT d.GroupId AS GroupId, 
               d.GroupName AS GroupName, 
               d.RowName AS RowName, 
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
        ORDER BY GroupName, 
                 RowName;
    END;
    
	DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
    DROP TABLE #Match;
    DROP TABLE #Data;
    DROP TABLE #tmp_Data;
	DROP TABLE #SABALeagueGroup;
GO
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_SystemParlay] @StartDate SMALLDATETIME, 
                                                            @EndDate   SMALLDATETIME, 
                                                            @Site      NVARCHAR(20)  = 'ALL'
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP. Not use @EndDate because we get only one day on (bettrans/bettrans14 range)
- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20212203@Jaden: Support SABA789 (#151326)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_SystemParlay] @EndDate='2020-01-01',@StartDate='2016-01-01', @Site= 'ALL'

*/

     SET NOCOUNT ON;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
        (CustId INT
         PRIMARY KEY
        );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK)
    END;
    BEGIN -- #Data

        CREATE TABLE #Data
        (GroupName       NVARCHAR(50), 
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
     IF @Site = 'ALL'
         BEGIN
             INSERT INTO #Data
                    SELECT CASE liveawayscore
                               WHEN 1
                               THEN 'Soccer Sport Total'
                               WHEN 2
                               THEN 'Others Sport Total'
                               WHEN 3
                               THEN 'Multi Sport Total'
                               ELSE ''
                           END AS GroupName, 
                           'System Parlay(' + STATUS + ')' AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) MemberWinLost, 
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
                               END) RealTurnover, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                               END) VirtualTurnover
                    FROM bettrans b WITH(NOLOCK)
                    WHERE b.winlostdate = @StartDate
                          AND BetType = 29
                          AND betteam <> '1'
                          AND ruben = 1
                          AND statusID IN(111, 112, 113)
                    GROUP BY 'System Parlay(' + STATUS + ')',
                             CASE liveawayscore
                                 WHEN 1
                                 THEN 'Soccer Sport Total'
                                 WHEN 2
                                 THEN 'Others Sport Total'
                                 WHEN 3
                                 THEN 'Multi Sport Total'
                                 ELSE ''
                             END;
     END;
         ELSE
         IF @Site = 'Deposit'
             BEGIN
                 INSERT INTO #Data
                        SELECT CASE liveawayscore
                                   WHEN 1
                                   THEN 'Soccer Sport Total'
                                   WHEN 2
                                   THEN 'Others Sport Total'
                                   WHEN 3
                                   THEN 'Multi Sport Total'
                                   ELSE ''
                               END AS GroupName, 
                               'System Parlay(' + STATUS + ')' AS RowName, 
                               SUM((winlost - actual_stake) * actualrate) MemberWinLost, 
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
                                   END) RealTurnover, 
                               SUM(CASE
                                       WHEN tpositiontaking = 1
                                       THEN 0
                                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                                   END) VirtualTurnover
                        FROM bettrans b WITH(NOLOCK)
                             INNER JOIN #DepositSuper dep ON b.srecommend = dep.custid
                        WHERE b.winlostdate = @StartDate
                              AND BetType = 29
                              AND betteam <> '1'
                              AND ruben = 1
                              AND statusID IN(111, 112, 113)
                        GROUP BY 'System Parlay(' + STATUS + ')',
                                 CASE liveawayscore
                                     WHEN 1
                                     THEN 'Soccer Sport Total'
                                     WHEN 2
                                     THEN 'Others Sport Total'
                                     WHEN 3
                                     THEN 'Multi Sport Total'
                                     ELSE ''
                                 END;
         END;
             ELSE
             IF @Site = 'Credit'
                 BEGIN
                     INSERT INTO #Data
                            SELECT CASE liveawayscore
                                       WHEN 1
                                       THEN 'Soccer Sport Total'
                                       WHEN 2
                                       THEN 'Others Sport Total'
                                       WHEN 3
                                       THEN 'Multi Sport Total'
                                       ELSE ''
                                   END AS GroupName, 
                                   'System Parlay(' + STATUS + ')' AS RowName, 
                                   SUM((winlost - actual_stake) * actualrate) MemberWinLost, 
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
                                       END) RealTurnover, 
                                   SUM(CASE
                                           WHEN tpositiontaking = 1
                                           THEN 0
                                           ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                                       END) VirtualTurnover
                            FROM bettrans b WITH(NOLOCK)                                
                            WHERE b.winlostdate = @StartDate
                                  AND BetType = 29
                                  AND betteam <> '1'
                                  AND ruben = 1
                                  AND statusID IN(111, 112, 113)
                                 AND NOT EXISTS
                            (
                                SELECT 1
                                FROM #DepositSuper dep
                                WHERE b.srecommend = dep.custid
                            )
                                 AND NOT EXISTS
                            (
                                SELECT 1
                                FROM CS_CustSuper AS cn88 WITH(NOLOCK)
                                WHERE b.srecommend = cn88.CustId
                            )
                            GROUP BY 'System Parlay(' + STATUS + ')',
                                     CASE liveawayscore
                                         WHEN 1
                                         THEN 'Soccer Sport Total'
                                         WHEN 2
                                         THEN 'Others Sport Total'
                                         WHEN 3
                                         THEN 'Multi Sport Total'
                                         ELSE ''
                                     END;
             END;
                 ELSE
                 IF @Site = 'CN88'
                     BEGIN
                         INSERT INTO #Data
                                SELECT CASE liveawayscore
                                           WHEN 1
                                           THEN 'Soccer Sport Total'
                                           WHEN 2
                                           THEN 'Others Sport Total'
                                           WHEN 3
                                           THEN 'Multi Sport Total'
                                           ELSE ''
                                       END AS GroupName, 
                                       'System Parlay(' + STATUS + ')' AS RowName, 
                                       SUM((winlost - actual_stake) * actualrate) MemberWinLost, 
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
                                           END) RealTurnover, 
                                       SUM(CASE
                                               WHEN tpositiontaking = 1
                                               THEN 0
                                               ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                                           END) VirtualTurnover
                                FROM bettrans b WITH(NOLOCK)
                                     INNER JOIN CS_CustSuper cn88 ON b.srecommend = cn88.custid
                                WHERE b.winlostdate = @StartDate
                                      AND BetType = 29
                                      AND betteam <> '1'
                                      AND ruben = 1
                                      AND statusID IN(111, 112, 113)
                                GROUP BY 'System Parlay(' + STATUS + ')',
                                         CASE liveawayscore
                                             WHEN 1
                                             THEN 'Soccer Sport Total'
                                             WHEN 2
                                             THEN 'Others Sport Total'
                                             WHEN 3
                                             THEN 'Multi Sport Total'
                                             ELSE ''
                                         END;
                 END;
    BEGIN -- Query

        SELECT d.GroupName AS GroupName, 
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
        ORDER BY GroupName DESC, 
                 RowName;
    END;
    
	DROP TABLE #Data;
    DROP TABLE #DepositSuper;
GO
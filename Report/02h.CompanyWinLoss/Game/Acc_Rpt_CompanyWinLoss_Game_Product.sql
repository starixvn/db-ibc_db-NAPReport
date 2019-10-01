
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Product] @StartDate  SMALLDATETIME, 
                                                            @EndDate    SMALLDATETIME, 
                                                            @CasinoType INT
AS

/*
Creator: Franklin
Date: 2016-02-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP. Not use @EndDate because we get only one day on (bettrans/bettrans14 range)
- 20160112@Percy: Change Extra PT formula [RedmineID: #70208]
- 20171013@Franklin: ExtraPT Setting - DB Restructure (#84802)
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
- 20190925@Jacob: Group By CN88 (#118824)
- 20190918@Robert: Remove inactive products (#120215)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_Product] @EndDate='2020-01-01',@StartDate='2017-01-05', @CasinoType = 1
*/

     SET NOCOUNT ON;
     DECLARE @EffectedDate DATETIME; -- 20160112@Percy: Applying date of changing extra PT formula [RedmineID: #70208]
     SELECT @EffectedDate = '2017-01-19';
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (ProductID   INT, 
                      ProductName NVARCHAR(50), 
                      BetType     INT, 
                      RefTable    INT
                     );
        INSERT INTO #SportBetType
               SELECT s.ProductID,
                      CASE                          
                          WHEN s.ProductID = 6
                          THEN 'MBC - RNG Casino'
                          ELSE p.ProductName
                      END, 
                      s.BetType, 
                      s.RefTable
               FROM dbo.f_SportBetTypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
                    INNER JOIN Products p WITH(NOLOCK) ON p.ProductID = s.ProductID
               WHERE s.CasinoType = @CasinoType;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
                     (CustId INT
                      PRIMARY KEY
                     );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1('All');
    END;
    BEGIN --#ExtraPT
        CREATE TABLE #ExtraPT
                     (ProductID INT, 
                      SuperID   INT, 
                      ExtraPT   DECIMAL(9, 8)
                     );
        INSERT INTO #ExtraPT
               SELECT ProductID, 
                      SuperId, 
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH(NOLOCK)
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY ProductID, 
                        SuperId;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data
                     (GroupId       INT, 
                      GroupName     NVARCHAR(50), 
                      RowName       NVARCHAR(50), 
                      MemberWinLoss MONEY, 
                      SMAWinLoss    MONEY, 
                      Commission    MONEY, 
                      RealIncome    MONEY, 
                      RealTurnover  MONEY, 
                      ExtraPT       MONEY, 
                      NewExtraPT    MONEY
                     );
    END;
     IF EXISTS -- BetTrans
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable NOT IN(1, 2)
     )
         BEGIN
             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId, 
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                           SUM(scomm * actualrate) Commission, 
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                       WHEN tpositiontaking = 1
                                                                                                       THEN 0
                                                                                                       ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                   END) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) AS RealTurnover, 
                           SUM((winlost - actual_stake) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT, 
                           SUM((CASE
                                    WHEN tpositiontaking = 1
                                    THEN winlost - actual_stake
                                    ELSE winlost - actual_stake + scomm / (1 - tpositiontaking)
                                END * ISNULL(e.ExtraPT, 0)) * actualrate) AS NewExtraPT
                    FROM bettrans AS b WITH(NOLOCK)
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                         LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable NOT IN(1, 2)
                         AND b.ruben = 1
                         AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId, 
                             sb.ProductName,
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
     IF EXISTS -- bettransRNG
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 1
     )
         BEGIN
             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId, 
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss, 
                           SUM(scomm * actualrate) Commission, 
                           SUM((CASE
                                    WHEN b.gameId IN(2198, 2398, 2998)
                                    THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                                         WHEN tpositiontaking = 1
                                                                                                                         THEN 0
                                                                                                                         ELSE b.ContributionRate * b.BetStake + b.scomm / (1 - b.tpositiontaking)
                                                                                                                     END) * ISNULL(e.ExtraPT, 0)
                                    WHEN b.gameId IN(2199, 2399, 2999, 4300)
                                    THEN 0
                                    ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                                WHEN tpositiontaking = 1
                                                                                                                THEN 0
                                                                                                                ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                            END) * ISNULL(e.ExtraPT, 0)
                                END) * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) RealTurnover, 
                           SUM((CASE
                                    WHEN tpositiontaking = 1
                                    THEN 0
                                    WHEN b.gameId IN(2198, 2398, 2998)
                                    THEN b.ContributionRate * b.BetStake
                                    WHEN b.gameId IN(2199, 2399, 2999, 4300)
                                    THEN 0
                                    ELSE winlost - actual_stake
                                END) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT, 
                           SUM((CASE
                                    WHEN tpositiontaking = 1
                                    THEN 0
                                    WHEN b.gameId IN(2199, 2399, 2999, 4300)
                                    THEN 0 --Progressive Jackpot
                                    WHEN b.gameId IN(2198, 2398, 2998)
                                    THEN ContributionRate * BetStake + 1.0 * scomm / (1 - tpositiontaking) --Jackpot Contribution
                                    ELSE winlost - actual_stake + 1.0 * scomm / (1 - tpositiontaking)
                                END) * ISNULL(e.ExtraPT, 0) * actualrate) AS NewExtraPT
                    FROM bettransRNG b WITH(NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId, 
                             sb.ProductName,
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
     IF EXISTS -- bettransLC
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 2
     )
         BEGIN --

             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId, 
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss, 
                           SUM(scomm * actualrate) Commission, 
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                       WHEN tpositiontaking = 1
                                                                                                       THEN 0
                                                                                                       ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                   END) * ISNULL(e.ExtraPT, 0)) * actualrate) RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) RealTurnover, 
                           SUM((winlost - actual_stake) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT, 
                           SUM((CASE
                                    WHEN tpositiontaking = 1
                                    THEN winlost - actual_stake
                                    ELSE winlost - actual_stake + scomm / (1 - tpositiontaking)
                                END * ISNULL(e.ExtraPT, 0)) * actualrate) AS NewExtraPT
                    FROM bettransLC b WITH(NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 2
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId, 
                             sb.ProductName,
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
    BEGIN -- Query

        SELECT d.GroupId AS GroupId, 
               d.GroupName AS GroupName, 
               d.RowName AS RowName, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.RealTurnover AS RealTurnover,
               CASE
                   WHEN @StartDate < @EffectedDate
                   THEN-d.ExtraPT
                   ELSE-d.NewExtraPT
               END AS ExtraPT
        FROM #Data AS d
        ORDER BY GroupName, 
                 RowName;
    END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #Data;
     DROP TABLE #ExtraPT;
GO
USE [bodb02];
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
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]

Example:
EXEC [Acc_Rpt_CompanyWinLoss_SystemParlay] @EndDate='2020-01-01',@StartDate='2016-01-01', @Site= 'ALL'

*/

     SET NOCOUNT ON;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
     END;
     BEGIN -- #Data

         CREATE TABLE #Data
         (GroupName       NVARCHAR(50),
          RowName         NVARCHAR(50),
          MemberWinLoss   MONEY,
          SMAWinLoss      MONEY,
          Commission      MONEY,
          RealIncome      MONEY,
          VirtualIncome   MONEY,
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
                           'System Parlay('+status+')' AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLost,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover,
                           SUM((1 - tpositiontaking) * ABS(stake) * virtualrate) VirtualTurnover
                    FROM bettrans b WITH (NOLOCK)
                    WHERE b.winlostdate = @StartDate
                          AND BetType = 29
                          AND betteam <> '1'
                          AND ruben = 1
                          AND statusID IN(111, 112, 113)
                    GROUP BY 'System Parlay('+status+')',
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
                           'System Parlay('+status+')' AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLost,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover,
                           SUM((1 - tpositiontaking) * ABS(stake) * virtualrate) VirtualTurnover
                    FROM bettrans b WITH (NOLOCK)
                         INNER JOIN #DepositSuper dep ON b.srecommend = dep.custid
                    WHERE b.winlostdate = @StartDate
                          AND BetType = 29
                          AND betteam <> '1'
                          AND ruben = 1
                          AND statusID IN(111, 112, 113)
                    GROUP BY 'System Parlay('+status+')',
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
                           'System Parlay('+status+')' AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLost,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover,
                           SUM((1 - tpositiontaking) * ABS(stake) * virtualrate) VirtualTurnover
                    FROM bettrans b WITH (NOLOCK)
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
                    GROUP BY 'System Parlay('+status+')',
                             CASE liveawayscore
                                 WHEN 1
                                 THEN 'Soccer Sport Total'
                                 WHEN 2
                                 THEN 'Others Sport Total'
                                 WHEN 3
                                 THEN 'Multi Sport Total'
                                 ELSE ''
                             END;
         END;;
     BEGIN -- Query

         SELECT d.GroupName AS GroupName,
                d.RowName AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.VirtualIncome AS VirtualIncome,
                d.RealIncome - d.VirtualIncome AS VarianceIncome,
                d.RealTurnover AS RealTurnover,
                d.VirtualTurnover AS VirtualTurnover
         FROM #Data AS d
         ORDER BY GroupName DESC,
                  RowName;
     END;
     DROP TABLE #Data;
     DROP TABLE #DepositSuper;

-------------------


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_SystemParlay] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_SystemParlay] TO [vnteam];
GO
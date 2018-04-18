USE [bodb02]
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Game_Site_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site_14] @StartDate SMALLDATETIME,
                                                          @EndDate   SMALLDATETIME,
                                                          @BetType   INT,
                                                          @Site      NVARCHAR(50)
AS

/*
Creator: Franklin
Date: 2016-02-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
				   
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_Site_14] @BetType = 2101,@EndDate='2020-01-01',@Site = 'Credit',@StartDate='2016-01-01'
*/

     SET NOCOUNT ON;
     BEGIN -- #SportBetType
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType  INT,
          RefTable INT
         );
         INSERT INTO #SportBetType
                SELECT BetType,
                       RefTable
                FROM bodb02.dbo.f_SportBetTypeMatrix_Sel(0, 0, @BetType, 2, '', '', @isTest);
     END;
     BEGIN -- #Agent

         CREATE TABLE #Agent
         (CustId INT PRIMARY KEY,
          Site   NVARCHAR(50)
         );
         IF @Site = 'Deposit'
             BEGIN
                 INSERT INTO #Agent
                        SELECT c.CustId,
                               Site
                        FROM customer AS c WITH (NOLOCK)
                        WHERE c.RoleID = 2
                              AND EXISTS
                        (
                            SELECT 1
                            FROM f_DepSuper_1('All') dep
                            WHERE c.srecommend = dep.CustId
                        );
             END;
         ELSE
             BEGIN
                 INSERT INTO #Agent
                        SELECT c.CustId,
                               Site
                        FROM customer AS c WITH (NOLOCK)
                        WHERE c.RoleID = 2
                              AND NOT EXISTS
                        (
                            SELECT 1
                            FROM f_DepSuper_1('All') dep
                            WHERE c.srecommend = dep.CustId
                        );
             END;
     END;
     BEGIN -- #Data

         CREATE TABLE #Data
         (RowName       NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     IF EXISTS -- bettrans
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable NOT IN(1, 2)
         AND BetType = @BetType
     )
         BEGIN
             INSERT INTO #Data
                    SELECT dep.Site RowName,
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
                    FROM bettrans14 AS b WITH (NOLOCK)
                         JOIN #Agent AS dep ON b.recommend = dep.CustId
                    WHERE b.winlostdate = @StartDate
                          AND b.BetType = @BetType
                          AND b.ruben = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site;
         END;
     IF EXISTS -- bettransRNG
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 1
               AND BetType = @BetType
     )
         BEGIN
             INSERT INTO #Data
                    SELECT dep.Site RowName,
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((CASE WHEN b.gameId IN (2198, 2398, 2998) THEN b.ContributionRate*b.BetStake + awinlost + mwinlost + swinlost + scomm
									 WHEN b.gameId IN (2199, 2399, 2999) THEN 0
									 ELSE winlost - actual_stake  + awinlost + mwinlost + swinlost + scomm 
								END) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
                    FROM bettransRnG14 b WITH (NOLOCK)
                         JOIN #Agent dep ON b.recommend = dep.custid
                    WHERE b.winlostdate = @StartDate
                          AND b.gameId = @BetType
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site;
         END;
     IF EXISTS -- bettransLC
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 2
               AND BetType = @BetType
     )
         BEGIN
             INSERT INTO #Data
                    SELECT dep.Site RowName,
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
                    FROM bettransLC14 b WITH (NOLOCK)
                         JOIN #Agent dep ON b.recommend = dep.custid
                    WHERE b.winlostdate = @StartDate
                          AND b.gameId = @BetType
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site;
         END;
     BEGIN -- Query

         SELECT d.RowName AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover
         FROM #Data AS d
         ORDER BY RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #Agent;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site_14] TO [vnteam];
GO
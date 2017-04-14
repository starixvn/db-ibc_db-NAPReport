IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType_14] @StartDate SMALLDATETIME,
                                                             @EndDate   SMALLDATETIME,
                                                             @ProductId INT
AS

/*
Creator: Franklin
Date: 2016-12-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_BetType_14] @EndDate='2020-01-01',@StartDate='2016-01-01',@ProductId=6
*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType     INT,
          BetTypeName NVARCHAR(50),
          RefTable    INT
         );
         INSERT INTO #SportBetType
                SELECT BetType,
                       b.typenamee,
                       RefTable
                FROM dbo.f_SportBetTypeMatrix_Sel(@ProductId, 0, 0, 2, '', '', @isTest) s
                     INNER JOIN BetType b WITH (NOLOCK) ON b.typeid = s.BetType;
     END;
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
         (GroupId       INT,
          GroupName     NVARCHAR(50),
          RowName       NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     IF EXISTS -- Bettrans
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable NOT IN(1, 2)
     )
         BEGIN
             INSERT INTO #Data
                    SELECT sb.BetType AS GroupId,
                           sb.BetTypeName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
                    FROM bettrans14 AS b WITH (NOLOCK)
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                         LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable NOT IN(1, 2)
                         AND b.ruben = 1
                         AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.BetType,
                             sb.BetTypeName,
                             CASE
                                 WHEN dep.CustId IS NULL
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
                    SELECT sb.BetType AS GroupId,
                           sb.BetTypeName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover
                    FROM bettransRnG14 b WITH (NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.BetType,
                             sb.BetTypeName,
                             CASE
                                 WHEN dep.CustId IS NULL
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
         BEGIN
             INSERT INTO #Data
                    SELECT sb.BetType AS GroupId,
                           sb.BetTypeName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover
                    FROM bettransLC14 b WITH (NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 2
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.BetType,
                             sb.BetTypeName,
                             CASE
                                 WHEN dep.CustId IS NULL
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
                d.RealTurnover AS RealTurnover
         FROM #Data AS d
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType_14] TO [vnteam];
GO
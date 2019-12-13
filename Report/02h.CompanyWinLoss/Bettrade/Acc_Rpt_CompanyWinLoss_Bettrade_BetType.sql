/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_BetType] @StartDate SMALLDATETIME, 
                                                                @EndDate   SMALLDATETIME
AS

/*
Creator: Franklin
Date: 2016-02-24
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160224@Franklin: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Bettrade_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType(BetType INT);
        INSERT INTO #SportBetType
               SELECT BetType
               FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'BT-Comm', '', @isTest)
               UNION
               SELECT BetType
               FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'BT-Winloss', '', @isTest);
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
    BEGIN -- Query

        SELECT 0 AS GroupId, 
               'Bettrade' AS GroupName,
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
               -SUM((CASE
                         WHEN b.tpositiontaking = 1
                         THEN 0
                         ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                     END) * ISNULL(b.epositiontaking, 0) * actualrate) AS ExtraPT, 
               SUM(scomm * actualrate) Commission, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                           WHEN tpositiontaking = 1
                                                                                           THEN 0
                                                                                           ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                       END) * ISNULL(b.epositiontaking, 0)) * actualrate) AS RealIncome, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
                                                                                               WHEN virtualrate > actualrate
                                                                                               THEN virtualrate
                                                                                               ELSE actualrate
                                                                                           END
                   END) AS RealTurnover
        FROM bettrans AS b WITH(NOLOCK)
             INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
        WHERE b.winlostdate = @StartDate
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY CASE
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NOT NULL
                     THEN 'CN88'
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NULL
                     THEN 'Credit'
                     ELSE 'Deposit'
                 END
        ORDER BY GroupName, 
                 RowName;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
GO
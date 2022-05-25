USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType] @StartDate SMALLDATETIME, 
                                                                   @EndDate   SMALLDATETIME
AS

/*
Creator: 20180228@Franklin
Task:  Integrate Colossus Bets - Free Play Integration (#90774)
DB: DBACC/bodb02

Revisions:
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20212203@Jaden: Support SABA789 (#151326)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_ColossusBet_BetType] @StartDate='2016-09-13', @EndDate='2020-01-01'

*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType     INT, 
                      BetTypeName NVARCHAR(50)
                     );
        INSERT INTO #SportBetType
               SELECT b.typeid, 
                      b.typenamee
               FROM dbo.f_SportBetTypeMatrix_Sel(15, 0, 0, 2, '', '', @isTest) s
                    INNER JOIN BetType b WITH(NOLOCK) ON s.BetType = b.typeid;
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
    BEGIN -- Query

        SELECT sb.BetType AS GroupId,
               CASE
                   WHEN b.BetType = 18000
                        AND ISNULL(b.currency2, 0) = 1
                   THEN sb.BetTypeName + ' (Free Play)'
                   ELSE sb.BetTypeName
               END AS GroupName,
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
                     END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
               SUM(scomm * actualrate) Commission, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                           WHEN tpositiontaking = 1
                                                                                           THEN 0
                                                                                           ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                       END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                          WHEN virtualrate > actualrate
                                                                                          THEN virtualrate
                                                                                          ELSE actualrate
                                                                                      END
                   END) AS RealTurnover
        FROM dbo.bettrans AS b WITH(NOLOCK)
             INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
        WHERE b.winlostdate = @StartDate
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY sb.BetType,
                 CASE
                     WHEN b.BetType = 18000
                          AND ISNULL(b.currency2, 0) = 1
                     THEN sb.BetTypeName + ' (Free Play)'
                     ELSE sb.BetTypeName
                 END,
                 CASE
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
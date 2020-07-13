/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType] @StartDate SMALLDATETIME, 
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
- 20160720@Sophia: . Revise SP. Not use @EndDate because we get only one day on (bettrans/bettrans14 range)
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 2019.04.01@Kean: Improve performance for House Win Loss by Product (#106315)
- 20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
- 20190925@Jacob: Group By CN88 (#118824)
- 20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200713@Ned.Le: NAP Report - Incorporate Jackpot Games (#137271)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_BetType] @EndDate='2020-01-01',@StartDate='2016-01-01',@ProductId=6
*/

     SET NOCOUNT ON;
	BEGIN --#SpecialBettypeGroup
		CREATE TABLE #SpecialBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)
		INSERT INTO #SpecialBettypeGroup (BettypeGroupID, Bettype)
		SELECT BettypeGroupID, Bettype FROM DBWH.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID IN (6, 10)
	END;
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
                    INNER JOIN BetType b WITH(NOLOCK) ON b.typeid = s.BetType;
        CREATE CLUSTERED INDEX CIX_BetType ON #SportBetType(BetType, RefTable);
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
    BEGIN -- #Data

        CREATE TABLE #Data
                     (GroupId       INT, 
                      GroupName     NVARCHAR(50), 
                      RowName       NVARCHAR(50), 
                      MemberWinLoss MONEY, 
                      SMAWinLoss    MONEY, 
                      ExtraPT       MONEY, 
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
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
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
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
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
                          AND sb.RefTable NOT IN(1, 2)
                         AND b.ruben = 1
                         AND b.statusID IN(111, 112, 113)
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
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss, 
                           SUM((CASE
                                    WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
                                    THEN(CASE
                                             WHEN tpositiontaking = 1
                                             THEN 0
                                             ELSE b.ContributionRate * b.BetStake + b.scomm / (1 - b.tpositiontaking)
                                         END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                    WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
                                    ELSE(CASE
                                             WHEN tpositiontaking = 1
                                             THEN 0
                                             ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                         END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                END) * actualrate) AS ExtraPT, 
                           SUM(scomm * actualrate) Commission, 
                           SUM((CASE
                                    WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
                                    THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                                         WHEN tpositiontaking = 1
                                                                                                                         THEN 0
                                                                                                                         ELSE b.ContributionRate * b.BetStake + b.scomm / (1 - b.tpositiontaking)
                                                                                                                     END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                    WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
                                    ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                                WHEN tpositiontaking = 1
                                                                                                                THEN 0
                                                                                                                ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                            END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                END) * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) RealTurnover
                    FROM bettransRNG b WITH(NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
						 LEFT JOIN #SpecialBettypeGroup bg ON b.gameID = bg.Bettype
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 1
                          AND b.statusID IN(111, 112, 113)
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
                             END OPTION(RECOMPILE);
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
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss, 
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
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) RealTurnover
                    FROM bettransLC b WITH(NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 2
                          AND b.statusID IN(111, 112, 113)
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
                             END OPTION(RECOMPILE);
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
               d.RealTurnover AS RealTurnover
        FROM #Data AS d
        ORDER BY GroupName, 
                 RowName;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
    DROP TABLE #Data;
	DROP TABLE #SpecialBettypeGroup;
GO

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_PokerGames_BetType] @StartDate SMALLDATETIME,
                                                                  @EndDate   SMALLDATETIME,
                                                                  @ProductId INT           = 33,
                                                                  @SportType INT           = 0,
                                                                  @IsLive    INT           = 2
AS

/*
Creator: 20180824@Cherry
Task:  Poker Games Integration - Implement Company Winloss By Products report [#97830]
DB: DBACC/bodb02

Revisions:
- 20180831@Kean: Integrate Insurance Of Poker Games (#97830)
- 20190121@Franklin: Integrate Poker Games (#107706)
- 20190925@Jacob: Group By CN88 (#118824)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_PokerGames_BetType] @StartDate='2018-08-21', @EndDate='2018-08-21', @ProductId = 33, @SportType = 0

*/


     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;
     SELECT @FDate = @StartDate,
            @TDate = @EndDate;
         BEGIN --#SportBetType
             DECLARE @isTest BIT= 0;
             SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
             CREATE TABLE #SportBetType
                          (BetType     INT,
                           BetTypeName NVARCHAR(50),
                           RefTable    INT
                          );
             INSERT INTO #SportBetType
                    SELECT b.typeid,
                           b.typenamee,
                           RefTable
                    FROM dbo.f_SportBetTypeMatrix_Sel(@ProductId, @SportType, 0, 2, '', '', @isTest) s
                         INNER JOIN BetType b WITH (NOLOCK) ON s.BetType = b.typeid;
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
         BEGIN ---- Extra PT
             CREATE TABLE #ExtraPT_Sel
                          (SuperID   INT,
                           Sporttype INT,
                           ExtraPT   DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     Sporttype,
                     ExtraPT
                    )
                    SELECT SuperId,
                           Sporttype,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = 33
                    GROUP BY SuperId,
                             Sporttype;

            -- Extra Comm
             CREATE TABLE #ExtraComm_Sel
                          (SuperID   INT,
                           Sporttype INT,
                           ExtraComm DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraComm_Sel
                    (SuperID,
                     Sporttype,
                     ExtraComm
                    )
                    SELECT SuperId,
                           a.Sporttype,
                           SUM(ExtraCommRate) AS ExtraComm
                    FROM bodb02.dbo.Acc_GroupExtraCommRateSetting a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = @ProductID
                    GROUP BY SuperId,
                             a.Sporttype;
         END;
         BEGIN
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
                    SELECT sb.BetType,
                           sb.BetTypeName,
                           CASE
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END,
                           SUM((winlost - actual_stake) * actualrate),
                           SUM((awinlost + mwinlost + swinlost) * actualrate),
                           SUM(((-b.oddsspread) * ISNULL(c.ExtraComm, 0) + (ISNULL(b.transid2, 0) * 1.0 / 10000) * ISNULL(e.ExtraPT, 0)) * actualrate),
                           SUM(scomm * actualrate),
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (-b.oddsspread) * ISNULL(c.ExtraComm, 0) - (ISNULL(b.transid2, 0) * 1.0 / 10000) * ISNULL(e.ExtraPT, 0)) * actualrate),
                           0
                    FROM bettrans AS b WITH (NOLOCK)
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                         LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                         LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
                         LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                         LEFT JOIN #ExtraComm_Sel c ON c.SuperID = b.srecommend
                    WHERE b.winlostdate = @FDate
                          AND sb.RefTable NOT IN(1, 2)
                         AND (@IsLive = 2
                              OR b.liveindicator = @IsLive)
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
                    SELECT sb.BetType,
                           sb.BetTypeName,
                           CASE
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NOT NULL
                               THEN 'CN88'
                               WHEN dep.CustId IS NULL
                                    AND cn88.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END,
                           SUM((winlost - actual_stake) * actualrate),
                           SUM((awinlost + mwinlost + swinlost) * actualrate),
                           SUM((CASE
                                    WHEN tpositiontaking = 1
                                    THEN 0
                                    ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                END) * ISNULL(e.ExtraPT, 0) * actualrate),
                           SUM(scomm * actualrate),
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                       WHEN tpositiontaking = 1
                                                                                                       THEN 0
                                                                                                       ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                   END) * ISNULL(e.ExtraPT, 0)) * actualrate),
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END)
                    FROM bettransRNG b WITH (NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
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
                             END;
         END;
         BEGIN -- Query
             SELECT d.GroupId,
                    d.GroupName,
                    d.RowName,
                    d.MemberWinLoss,
                    d.SMAWinLoss,
                    -d.ExtraPT AS ExtraPT,
                    d.Commission,
                    d.RealIncome,
                    d.RealTurnover
             FROM #Data AS d
             ORDER BY GroupName,
                      RowName;
         END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #ExtraPT_Sel;
     DROP TABLE #ExtraComm_Sel;
     DROP TABLE #Data;
GO

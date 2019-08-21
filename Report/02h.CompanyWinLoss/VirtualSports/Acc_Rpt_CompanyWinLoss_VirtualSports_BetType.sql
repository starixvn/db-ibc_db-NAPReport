
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType] @StartDate SMALLDATETIME, 
                                                                     @EndDate   SMALLDATETIME, 
                                                                     @SportType SMALLINT
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSports_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 181
*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType     INT, 
                      BetTypeName NVARCHAR(50), 
                      EventType   INT
                     );
        INSERT INTO #SportBetType
               SELECT b.typeid, 
                      b.typenamee, 
                      s.EventType
               FROM dbo.f_SportBetTypeMatrix_Sel(5, @SportType, 0, 2, '', '', @isTest) s
                    INNER JOIN BetType b WITH(NOLOCK) ON s.BetType = b.typeid;
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
    BEGIN -- Extra PT
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
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH(NOLOCK)
               WHERE @StartDate BETWEEN FromDate AND Todate
                     AND a.ProductId = 5
               GROUP BY SuperId, 
                        Sporttype;
    END;
     IF EXISTS -- Virtual Sportsbook
     (
         SELECT 1
         FROM #SportBetType
         WHERE EventType = 1
     )
         BEGIN
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
                    -SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT, 
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
                        END) AS RealTurnover
             FROM bettrans AS b WITH(NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
                  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                  INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
             WHERE b.winlostdate = @StartDate
                   AND m.sporttype = @SportType
                   AND b.MatchId > 0
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
                      END
             ORDER BY GroupName, 
                      RowName;
     END;
         ELSE -- Virtual Racing
         BEGIN
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
                    -SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT, 
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
                        END) AS RealTurnover
             FROM bettrans AS b WITH(NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                  INNER JOIN VSRaceInfo AS r WITH(NOLOCK) ON r.EventId = b.MatchId
             WHERE b.winlostdate = @StartDate
                   AND r.sporttype = @SportType
                   AND b.MatchId > 0
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
                      END
             ORDER BY GroupName, 
                      RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #ExtraPT_Sel;
GO
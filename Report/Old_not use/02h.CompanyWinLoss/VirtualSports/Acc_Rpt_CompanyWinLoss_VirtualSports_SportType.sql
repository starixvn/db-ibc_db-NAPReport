USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_SportType] @StartDate SMALLDATETIME, 
                                                                       @EndDate   SMALLDATETIME
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
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20212203@Jaden: Support SABA789 (#151326)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSports_SportType]	@StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType
        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType   INT, 
                      EventType INT
                     );
        INSERT INTO #SportBetType
               SELECT s.BetType, 
                      s.EventType
               FROM dbo.f_SportBetTypeMatrix_Sel(5, 0, 0, 2, '', '', @isTest) s;
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
    BEGIN -- #Data

        CREATE TABLE #Data
                     (SportType     INT, 
                      Site          NVARCHAR(50), 
                      MemberWinLoss MONEY, 
                      SMAWinLoss    MONEY, 
                      ExtraPT       MONEY, 
                      Commission    MONEY, 
                      RealIncome    MONEY, 
                      RealTurnover  MONEY
                     );
    END;
    BEGIN -- Virtual Soccer

        INSERT INTO #Data
               SELECT m.sporttype,
                      CASE
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END AS Site, 
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
                    INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
               WHERE b.winlostdate = @StartDate
                     AND sb.EventType = 1
                     AND b.MatchId > 0
                     AND b.ruben = 1
                     AND b.statusID IN(111, 112, 113)
               GROUP BY m.sporttype,
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
    BEGIN -- Virtual HR

        INSERT INTO #Data
               SELECT r.SportType AS SportType,
                      CASE
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
                          WHEN dep.CustId IS NULL
                               AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END AS site, 
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
                    INNER JOIN VSRaceInfo AS r WITH(NOLOCK) ON b.MatchId = r.EventId
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
               WHERE b.winlostdate = @StartDate
                     AND sb.EventType = 3
                     AND b.MatchId > 0
                     AND b.ruben = 1
                     AND b.statusID IN(111, 112, 113)
               GROUP BY r.sporttype,
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

        SELECT s.SportType AS GroupId, 
               s.SportName AS GroupName, 
               d.Site AS RowName, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.RealTurnover AS RealTurnover
        FROM #Data AS d
             INNER JOIN Sports AS s WITH(NOLOCK) ON d.SportType = s.SportType
        ORDER BY GroupName, 
                 RowName;
    END;
    
	DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
    DROP TABLE #Data;
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14] @StartDate SMALLDATETIME,
                                                                   @EndDate   SMALLDATETIME,
                                                                   @SportType SMALLINT,
                                                                   @BetType   INT,
                                                                   @Site      VARCHAR(20)
AS

/*Creator:
Jacob;
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 180, @BetType = 1203, @Site = 'Credit'
*/

     SET NOCOUNT ON;
     BEGIN --@EventType    
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         DECLARE @EventType INT;
         SELECT @EventType = s.EventType
         FROM dbo.f_SportBetTypeMatrix_Sel(5, @SportType, @BetType, 2, '', '', @isTest) s;
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
     IF @EventType = 1 -- Virtual Soccer
         BEGIN
             SELECT Site RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    SUM(scomm * actualrate) Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                    SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN match14 AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
                  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
             WHERE b.winlostdate = @StartDate
                   AND b.BetType = @BetType
                   AND m.sporttype = @SportType
                   AND b.MatchId > 0
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY Site
             ORDER BY RowName;
         END;
     ELSE -- Virtual HR
         BEGIN
             SELECT Site AS RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    SUM(scomm * actualrate) Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                    SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN VSRaceInfo AS r WITH (NOLOCK) ON r.EventId = b.MatchId
                  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
             WHERE b.winlostdate = @StartDate
                   AND b.BetType = @BetType
                   AND r.sporttype = @SportType
                   AND b.MatchId > 0
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY Site
             ORDER BY RowName;
         END;
     DROP TABLE #Agent;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_Site_14] TO [vnteam];
GO
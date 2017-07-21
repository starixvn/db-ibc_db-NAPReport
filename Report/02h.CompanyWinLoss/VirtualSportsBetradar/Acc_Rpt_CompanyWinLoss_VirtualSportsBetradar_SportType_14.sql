USE [bodb02];
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14] @StartDate SMALLDATETIME,
                                                                                   @EndDate   SMALLDATETIME
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20170720@Franklin: Add Betradar Virtual Sports (78495)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14]	@StartDate='2016-01-01', @EndDate='2020-01-01'
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
                FROM dbo.f_SportBetTypeMatrix_Sel(27, 0, 0, 2, '', '', @isTest) s;
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
         (SportType     INT,
          Site          NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     BEGIN -- Virtual Sports Betradar not include parlay bettype.

         INSERT INTO #Data
                SELECT m.sporttype,
                       CASE
                           WHEN dep.CustId IS NULL
                           THEN 'Credit'
                           ELSE 'Deposit'
                       END AS Site,
                       SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                       SUM(scomm * actualrate) Commission,
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                       SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
                FROM bettrans14 AS b WITH (NOLOCK)
                     INNER JOIN match14 AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                WHERE b.winlostdate = @StartDate
                      AND sb.EventType = 1
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY m.sporttype,
                         CASE
                             WHEN dep.CustId IS NULL
                             THEN 'Credit'
                             ELSE 'Deposit'
                         END;
     END;
     BEGIN -- Parlay
         INSERT INTO #Data
                SELECT bsm.sporttype,
                       CASE
                           WHEN dep.CustId IS NULL
                           THEN 'Credit'
                           ELSE 'Deposit'
                       END AS site,
                       SUM((b.winlost - b.actual_stake) * b.actualrate) AS MemberWinLoss,
                       SUM((b.awinlost + b.mwinlost + b.swinlost) * b.actualrate) AS SMAWinLoss,
                       SUM(b.scomm * b.actualrate) Commission,
                       SUM((b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm) * b.actualrate) AS RealIncome,
                       SUM((1 - b.tpositiontaking) * ABS(b.stake) * b.actualrate) AS RealTurnover
                FROM bettrans14 AS b WITH (NOLOCK)
                     INNER JOIN
                (
                    SELECT DISTINCT
                           bm.refno,
                           m.sporttype
                    FROM bodb02.dbo.bettransm14 bm WITH (NOLOCK)
                         INNER JOIN bodb02.dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid
                ) bsm ON b.refno = bsm.refno
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                WHERE b.winlostdate = @StartDate
                      AND sb.EventType = 0
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY bsm.sporttype,
                         CASE
                             WHEN dep.CustId IS NULL
                             THEN 'Credit'
                             ELSE 'Deposit'
                         END;
     END;
     BEGIN -- Query

         SELECT d.SportType AS GroupId,
                s.SportName AS GroupName,
                d.Site AS RowName,
                SUM(d.MemberWinLoss) AS MemberWinLoss,
                SUM(d.SMAWinLoss) AS SMAWinLoss,
                SUM(d.Commission) AS Commission,
                SUM(d.RealIncome) AS RealIncome,
                SUM(d.RealTurnover) AS RealTurnover
         FROM #Data AS d
              INNER JOIN Sports AS s WITH (NOLOCK) ON d.SportType = s.SportType
         GROUP BY d.SportType,
                  s.SportName,
                  d.Site
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType_14] TO [vnteam];
GO
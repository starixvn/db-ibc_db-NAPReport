IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive] @StartDate SMALLDATETIME,
                                                                         @EndDate   SMALLDATETIME
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
Example:
EXEC [Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive] @EndDate='2020-01-01',@StartDate='2016-01-01'

*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType(BetType INT);
         INSERT INTO #SportBetType
                SELECT s.BetType
                FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'MG-SuperLive', '', @isTest) s;
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
         (GroupId         INT,
          GroupName       NVARCHAR(50),
          RowName         NVARCHAR(50),
          MemberWinLoss   MONEY,
          SMAWinLoss      MONEY,
          Commission      MONEY,
          RealIncome      MONEY,
          VirtualIncome   MONEY,
          RealTurnover    MONEY,
          VirtualTurnover MONEY
         );
     END;
     BEGIN -- INSERT INTO #Data
         INSERT INTO #Data
                SELECT liveindicator AS GroupId,
                       CASE liveindicator
                           WHEN 1
                           THEN 'Metric Gaming - Superlive Live'
                           ELSE 'Metric Gaming - Superlive Non-Live'
                       END AS GroupName,
                       CASE
                           WHEN dep.CustId IS NULL
                           THEN 'Credit'
                           ELSE 'Deposit'
                       END AS RowName,
                       SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                       SUM(scomm * actualrate) Commission,
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS VirtualIncome,
                       SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover,
                       SUM((1 - tpositiontaking) * ABS(stake) * virtualrate) AS VirtualTurnover
                FROM bettrans b WITH (NOLOCK)
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                WHERE b.winlostdate = @StartDate
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY liveindicator,
                         CASE liveindicator
                             WHEN 1
                             THEN 'Metric Gaming - Superlive Live'
                             ELSE 'Metric Gaming - Superlive Non-Live'
                         END,
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
                d.VirtualIncome AS VirtualIncome,
                d.RealIncome - d.VirtualIncome AS VarianceIncome,
                d.RealTurnover AS RealTurnover,
                d.VirtualTurnover AS VirtualTurnover
         FROM #Data AS d
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_LiveNonLive] TO [vnteam];
GO
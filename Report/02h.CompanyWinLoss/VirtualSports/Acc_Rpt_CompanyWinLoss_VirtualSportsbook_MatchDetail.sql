/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] @StartDate SMALLDATETIME, 
                                                                             @EndDate   SMALLDATETIME, 
                                                                             @SportType SMALLINT, 
                                                                             @BetType   INT
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

Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 180, @BetType = 1201
*/

     SET NOCOUNT ON;

     SELECT m.MatchId, 
            m.MatchCode, 
            m.HomeId, 
            m.AwayId, 
            m.LeagueId, 
            SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
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
                    ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * b.stake * CASE
                                                                                       WHEN virtualrate > actualrate
                                                                                       THEN virtualrate
                                                                                       ELSE actualrate
                                                                                   END
                END) AS RealTurnover
     FROM bettrans AS b WITH(NOLOCK)
          INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
     WHERE b.winlostdate = @StartDate
           AND b.BetType = @BetType
           AND m.SportType = @SportType
           AND b.MatchId > 0
           AND b.ruben = 1
           AND statusID IN(111, 112, 113)
     GROUP BY m.MatchId, 
              m.MatchCode, 
              m.HomeId, 
              m.AwayId, 
              m.LeagueId
     ORDER BY m.LeagueId, 
              m.MatchCode, 
              m.HomeId, 
              m.AwayId;

GO
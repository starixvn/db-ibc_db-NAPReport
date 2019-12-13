/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] @StartDate SMALLDATETIME, 
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
- 20170720@Franklin: Add Betradar Virtual Sports (78495)
- 20180323@Franklin: Betradar Virtual Sports (phase 2) (91098)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 190, @BetType = 2700
*/

    SET NOCOUNT ON;
    
    BEGIN
        CREATE TABLE #Data
                     (LeagueId      INT, 
                      MatchId       INT, 
                      MatchCode     NVARCHAR(50), 
                      HomeId        INT, 
                      AwayId        INT, 
                      MemberWinLoss MONEY, 
                      SMAWinLoss    MONEY, 
                      ExtraPT       MONEY, 
                      Commission    MONEY, 
                      RealIncome    MONEY, 
                      RealTurnover  MONEY
                     );
        INSERT INTO #Data
               SELECT m.leagueid, 
                      m.matchid, 
                      m.matchcode, 
                      m.homeid, 
                      m.awayid, 
                      SUM((winlost - actual_stake) * actualrate), 
                      SUM((awinlost + mwinlost + swinlost) * actualrate), 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(b.epositiontaking, 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate), 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                  WHEN tpositiontaking = 1
                                                                                                  THEN 0
                                                                                                  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                              END) * ISNULL(b.epositiontaking, 0)) * actualrate), 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * b.stake * CASE
                                                                                                 WHEN virtualrate > actualrate
                                                                                                 THEN virtualrate
                                                                                                 ELSE actualrate
                                                                                             END
                          END)
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.bettype = @BetType
                     AND m.sporttype = @SportType
                     AND b.matchid > 0
                     AND b.ruben = 1
                     AND statusID IN(111, 112, 113)
               GROUP BY m.matchid, 
                        m.matchcode, 
                        m.homeid, 
                        m.awayid, 
                        m.leagueid
               ORDER BY m.leagueid, 
                        m.matchcode, 
                        m.homeid, 
                        m.awayid;
    END;
    BEGIN -- Query
        SELECT d.MatchId, 
               d.MatchCode, 
               d.HomeId, 
               d.AwayId, 
               d.LeagueId, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.RealTurnover AS RealTurnover
        FROM #Data d;
    END;

    DROP TABLE #Data;
GO
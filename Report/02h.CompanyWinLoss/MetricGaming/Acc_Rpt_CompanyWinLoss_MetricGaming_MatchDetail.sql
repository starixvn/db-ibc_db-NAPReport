/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_MatchDetail] @StartDate SMALLDATETIME, 
                                                                        @EndDate   SMALLDATETIME, 
                                                                        @BetType   INT           = 1, 
                                                                        @IsLive    INT           = 2
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

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
Example:
EXEC [Acc_Rpt_CompanyWinLoss_MetricGaming_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @BetType=1, @IsLive = 2

*/

     SET NOCOUNT ON;
    BEGIN -- #Match

        CREATE TABLE #Match
                     (MatchId   INT, 
                      MatchCode NVARCHAR(50), 
                      IsNeutral BIT, 
                      EventDate DATETIME, 
                      SportType INT, 
                      LeagueId  INT, 
                      HomeId    INT, 
                      AwayId    INT
                     );
        INSERT INTO #Match
               SELECT m.MatchId, 
                      m.MatchCode, 
                      m.IsNeutral, 
                      m.EventDate, 
                      m.SportType, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId
               FROM Match m WITH(NOLOCK)
               WHERE EventDate = @StartDate;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data
                     (MatchId         INT, 
                      MatchCode       VARCHAR(100), 
                      IsNeutral       BIT, 
                      EventDate       DATETIME, 
                      SportType       INT, 
                      LeagueId        INT, 
                      HomeId          INT, 
                      AwayId          INT, 
                      MemberWinLoss   MONEY, 
                      SMAWinLoss      MONEY, 
                      ExtraPT         MONEY, 
                      Commission      MONEY, 
                      RealIncome      MONEY, 
                      VirtualIncome   MONEY, 
                      VarianceIncome  MONEY, 
                      RealTurnover    MONEY, 
                      VirtualTurnover MONEY
                     );
    END;
    BEGIN -- INSERT INTO #Data

        INSERT INTO #Data
               SELECT b.MatchId, 
                      m.MatchCode, 
                      ISNULL(m.IsNeutral, 0) AS IsNeutral, 
                      m.EventDate, 
                      m.SportType, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId, 
                      SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                      SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(b.epositiontaking, 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate) Commission, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                  WHEN tpositiontaking = 1
                                                                                                  THEN 0
                                                                                                  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                              END) * ISNULL(b.epositiontaking, 0)) * actualrate) RealIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
                                                                                     END) * virtualrate + (scomm - (CASE
                                                                                                                        WHEN tpositiontaking = 1
                                                                                                                        THEN 0
                                                                                                                        ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                    END) * ISNULL(b.epositiontaking, 0)) * actualrate * CASE
                                                                                                                                                                    WHEN virtualrate < actualrate
                                                                                                                                                                    THEN virtualrate / actualrate
                                                                                                                                                                    ELSE 1
                                                                                                                                                                END) VirtualIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
                                                                                     END + CASE
                                                                                               WHEN virtualrate < actualrate
                                                                                               THEN(b.scomm - (CASE
                                                                                                                   WHEN tpositiontaking = 1
                                                                                                                   THEN 0
                                                                                                                   ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                               END) * ISNULL(b.epositiontaking, 0))
                                                                                               ELSE 0
                                                                                           END) * (actualrate - virtualrate)) VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END) RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * virtualrate
                          END) VirtualTurnover
               FROM bettrans b WITH(NOLOCK)
                    INNER JOIN match m WITH(NOLOCK) ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = @BetType
                     AND m.EventDate = @StartDate
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND b.MatchId > 0
                     AND b.ruben = 1
                     AND statusID IN(111, 112, 113)
               GROUP BY b.MatchId, 
                        m.MatchCode, 
                        m.IsNeutral, 
                        m.EventDate, 
                        m.SportType, 
                        m.LeagueId, 
                        m.HomeId, 
                        m.AwayId, 
                        m.LeagueId;
    END;
    BEGIN -- Query

        SELECT d.MatchId, 
               d.MatchCode, 
               d.IsNeutral, 
               d.EventDate, 
               d.SportType, 
               d.LeagueId, 
               d.HomeId, 
               d.AwayId, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.VirtualIncome AS VirtualIncome, 
               d.VarianceIncome AS VarianceIncome, 
               d.RealTurnover AS RealTurnover, 
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY LeagueId, 
                 MatchCode;
    END;

    DROP TABLE #Match;
    DROP TABLE #Data;
GO
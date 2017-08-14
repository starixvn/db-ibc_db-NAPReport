USE [bodb02] 
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] @StartDate SMALLDATETIME,
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
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 190, @BetType = 2700
*/

     SET NOCOUNT ON;
     BEGIN
         CREATE TABLE #Data
         (LeagueId      INT,
          LeagueName    NVARCHAR(50),
          MatchId       INT,
          MatchCode     NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
         INSERT INTO #Data
                SELECT m.LeagueId,
                       l.leaguename,
                       m.MatchId,
                       m.MatchCode,
                       SUM((winlost - actual_stake) * actualrate),
                       SUM((awinlost + mwinlost + swinlost) * actualrate),
                       SUM(scomm * actualrate),
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate),
                       SUM((1 - tpositiontaking) * ABS(b.stake) * actualrate)
                FROM bettrans AS b WITH (nolock)
                     INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
                     INNER JOIN dbo.league AS l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
                WHERE b.winlostdate = @StartDate
                      AND b.BetType = @BetType
                      AND m.SportType = @SportType
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND statusID IN(111, 112, 113)
                GROUP BY m.MatchId,
                         m.MatchCode,
                         m.LeagueId,
                         l.leaguename
                ORDER BY m.LeagueId,
                         m.MatchCode;
     END;
     BEGIN -- Query
         SELECT d.leaguename AS GroupName,
                d.LeagueId AS GroupId,
                d.MatchCode AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover
         FROM #Data d;
     END;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail] TO [vnteam];
GO
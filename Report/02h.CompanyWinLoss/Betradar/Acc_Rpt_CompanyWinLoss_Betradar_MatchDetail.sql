USE [bodb02] 
GO

IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Betradar_MatchDetail]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Betradar_MatchDetail];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Betradar_MatchDetail] @StartDate SMALLDATETIME,
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
		
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 181, @BetType = 1231
*/

     SET NOCOUNT ON;
     BEGIN -- #Data

         CREATE TABLE #Data
         (LeagueId      INT,
          EventType     DATETIME,
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     BEGIN -- #Data

         INSERT INTO #Data
                SELECT r.LeagueId,
                       r.EventTime,
                       SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                       SUM(scomm * actualrate) Commission,
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                       SUM((1 - tpositiontaking) * ABS(b.stake) * actualrate) AS RealTurnover
                FROM bettrans AS b WITH (nolock)
                     INNER JOIN VSRaceInfo AS r WITH (nolock) ON b.MatchId = r.EventId
                WHERE b.winlostdate = @StartDate
                      AND b.BetType = @BetType
                      AND r.SportType = @SportType
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY r.LeagueId,
                         r.EventTime;
     END;
     BEGIN -- Query

         SELECT l.leaguename AS GroupName,
                l.LeagueId AS GroupId,
                SUBSTRING(CONVERT( VARCHAR, d.EventType, 108), 1, 5) AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover
         FROM #Data AS d
              INNER JOIN league AS l WITH (NOLOCK) ON d.LeagueId = l.LeagueId
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Betradar_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Betradar_MatchDetail] TO [vnteam];
GO
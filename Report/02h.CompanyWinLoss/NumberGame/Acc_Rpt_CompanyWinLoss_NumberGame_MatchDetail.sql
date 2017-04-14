IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] @StartDate SMALLDATETIME,
                                                                       @EndDate   SMALLDATETIME,
                                                                       @BetType   INT,
                                                                       @IsLive    BIT
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
	
Example:
EXEC [Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] @BetType=81,@IsLive=0,@StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
     BEGIN -- #Data

         CREATE TABLE #Data
         (LeagueId      INT,
          MatchCode     NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     BEGIN -- Insert Into #Data

         INSERT INTO #Data
                SELECT m.LeagueId,
                       m.MatchCode,
                       SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                       SUM(scomm * actualrate) Commission,
                       SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                       SUM((1 - tpositiontaking) * ABS(b.stake) * actualrate) AS RealTurnover
                FROM bettrans AS b WITH (nolock)
                     INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
                WHERE b.winlostdate = @StartDate
                      AND b.BetType = @BetType
                      AND b.liveindicator = @IsLive
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND statusID IN(111, 112, 113)
                GROUP BY m.MatchCode,
                         m.LeagueId;
     END;
     BEGIN -- Query      

         SELECT l.leaguename AS GroupName,
                d.MatchCode AS RowName,
                d.MemberWinLoss,
                d.SMAWinLoss,
                d.Commission,
                d.RealIncome,
                d.RealTurnover
         FROM #Data AS d
              INNER JOIN league AS l WITH (nolock) ON l.LeagueId = d.LeagueId
         WHERE l.sporttype = 161
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] TO [vnteam];
GO
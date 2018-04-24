IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] @StartDate SMALLDATETIME,
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
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 180, @BetType = 1201
*/

     SET NOCOUNT ON;

	 BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
								   Sporttype  INT,
                                   ExtraPT DECIMAL(9, 8));
            INSERT INTO #ExtraPT_Sel
               ( SuperID,
			     Sporttype,
                 ExtraPT
               )
               SELECT SuperId,Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = 5
               GROUP BY SuperId,Sporttype;
    END;

     SELECT m.MatchId,
            m.MatchCode,
            m.HomeId,
            m.AwayId,
            m.LeagueId,
            SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
            SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
            SUM(scomm * actualrate) Commission,
            SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                       SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
     FROM bettrans AS b WITH (nolock)
          INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
		  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
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

	DROP TABLE #ExtraPT_Sel;
-------------------

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsbook_MatchDetail] TO [vnteam];
GO
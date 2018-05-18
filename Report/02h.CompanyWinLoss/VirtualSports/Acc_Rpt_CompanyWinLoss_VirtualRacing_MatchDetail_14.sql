USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14] @StartDate SMALLDATETIME,
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
EXEC [Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 181, @BetType = 1231
*/

     SET NOCOUNT ON;
     BEGIN -- #Data

         CREATE TABLE #Data
         (LeagueId      INT,
          EventType     DATETIME,
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
		  ExtraPT       MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
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
     BEGIN -- #Data

         INSERT INTO #Data
                SELECT r.LeagueId,
                       r.EventTime,
                       SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
					   SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                       SUM(scomm * actualrate) Commission,
                       SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                       SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
                FROM bettrans14 AS b WITH (nolock)
                     INNER JOIN VSRaceInfo AS r WITH (nolock) ON b.MatchId = r.EventId
					 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
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
				-d.ExtraPT AS ExtraPT,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover
         FROM #Data AS d
              INNER JOIN league AS l WITH (NOLOCK) ON d.LeagueId = l.LeagueId
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #Data;
	 DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_14] TO [vnteam];
GO
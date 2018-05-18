USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail]
       @StartDate SMALLDATETIME,
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
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
	
Example:
EXEC [Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] @BetType=81,@IsLive=0,@StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
     CREATE TABLE #ExtraPT_Sel( SuperID INT,
                                ExtraPT DECIMAL(9, 8));
     INSERT INTO #ExtraPT_Sel
            ( SuperID,
              ExtraPT
            )
            SELECT SuperId,
                   SUM(ExtraPT) AS ExtraPT
            FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
            WHERE @StartDate BETWEEN FromDate AND Todate
              AND a.ProductId = 3
            GROUP BY SuperId;
    BEGIN -- #Data

        CREATE TABLE #Data( LeagueId      INT,
                            MatchCode     NVARCHAR(50),
                            MemberWinLoss MONEY,
                            SMAWinLoss    MONEY,
							ExtraPT       MONEY,
                            Commission    MONEY,
                            RealIncome    MONEY,
                            RealTurnover  MONEY );
    END;
    BEGIN -- Insert Into #Data

        INSERT INTO #Data
               SELECT m.LeagueId,
                      m.MatchCode,
                      SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
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
               FROM bettrans AS b WITH ( nolock )
                    INNER JOIN match AS m WITH ( nolock ) ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
               WHERE b.winlostdate = @StartDate
                 AND b.BetType = @BetType
                 AND b.liveindicator = @IsLive
                 AND b.MatchId > 0
                 AND b.ruben = 1
                 AND statusID IN( 111, 112, 113 )
               GROUP BY m.MatchCode,
                        m.LeagueId;
    END;
    BEGIN -- Query      

        SELECT l.leaguename AS GroupName,
               d.MatchCode AS RowName,
               d.MemberWinLoss,
               d.SMAWinLoss,
			   -d.ExtraPT AS ExtraPT,
               d.Commission,
               d.RealIncome,
               d.RealTurnover
        FROM #Data AS d
             INNER JOIN league AS l WITH ( nolock ) ON l.LeagueId = d.LeagueId
        WHERE l.sporttype = 161
        ORDER BY GroupName,
                 RowName;
    END;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] TO [vnteam];
GO
IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @SportType SMALLINT = 1
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
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @SportType=2

*/

     SET NOCOUNT ON;
    BEGIN -- #Match

        CREATE TABLE #Match( MatchId   INT,
                             LeagueId  INT,
                             teamid    INT,
                             MatchCode NVARCHAR(50));
        INSERT INTO #Match
               SELECT orid,
                      o.LeagueId,
                      o.teamid,
                      o.MatchCode
               FROM outright o WITH ( NOLOCK )
                    INNER JOIN league l WITH ( NOLOCK ) ON o.LeagueId = l.LeagueId
               WHERE EventDate = @StartDate
                 AND l.sporttype = @SportType;
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
                 AND a.ProductId = 1
                 AND a.SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
               GROUP BY SuperId,Sporttype;
    END;
    BEGIN -- #Data
	 DECLARE @sport BIT = 0;
     SELECT @sport = CASE WHEN @SportType = 44 THEN 44 ELSE 0 END

        CREATE TABLE #Data( MatchId         INT,
                            MatchCode       VARCHAR(100),
                            TeamId          INT,
                            LeagueId        INT,
                            MemberWinLoss   MONEY,
                            SMAWinLoss      MONEY,
                            Commission      MONEY,
                            RealIncome      MONEY,
                            VirtualIncome   MONEY,
							VarianceIncome  MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- Outright


        INSERT INTO #Data
               SELECT m.MatchId,
                      m.MatchCode,
                      m.TeamId,
                      m.LeagueId,
                      SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
                      SUM(scomm * actualrate) Commission,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) RealIncome,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                      END ) * virtualrate + ( scomm - ( CASE
                                                                                                                            WHEN tpositiontaking = 1
                                                                                                                            THEN 0
                                                                                                                            ELSE b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                        END ) * ISNULL(e.ExtraPT, 0)) * actualrate) VirtualIncome,
					  SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                      END) * (actualrate - virtualrate)) VarianceIncome,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) RealTurnover,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
                          END) VirtualTurnover
               FROM bettrans b WITH ( nolock )
                    INNER JOIN #Match m WITH ( nolock ) ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
											  AND e.Sporttype = @sport
               WHERE b.winlostdate = @StartDate
                 AND b.BetType = 10
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY m.MatchId,
                        m.MatchCode,
                        m.TeamId,
                        m.LeagueId;
    END;
    BEGIN -- RM

        INSERT INTO #Data
               SELECT 0 AS MatchId,
                           CASE
                               WHEN b.recommend = 52466
                               THEN '8RM Total'
                               ELSE 'BARM Total'
                           END MatchCode,
                      0 TeamId,
                      0 LeagueId,
                      -SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      -SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
                      SUM(scomm * actualrate) Commission,
                      -SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                     WHEN tpositiontaking = 1
                                                                                                     THEN 0
                                                                                                     ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                 END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                      -SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                           WHEN tpositiontaking = 1
                                                                                           THEN 0
                                                                                           ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                       END ) * virtualrate + ( scomm - ( CASE
                                                                                                                             WHEN tpositiontaking = 1
                                                                                                                             THEN 0
                                                                                                                             ELSE b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                         END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS VirtualIncome,
					  -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                      END) * (actualrate - virtualrate)) VarianceIncome,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
                          END) AS VirtualTurnover
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
											  AND e.Sporttype = @sport
               WHERE b.winlostdate = @StartDate
                 AND b.BetType = 10
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
                 AND b.recommend IN( 52466, 5707545 )
               GROUP BY CASE
                            WHEN b.recommend = 52466
                            THEN '8RM Total'
                            ELSE 'BARM Total'
                        END;
    END;
    BEGIN -- Query

        SELECT d.MatchId,
               d.MatchCode,
               @SportType SportType,
               d.TeamId AS HomeId,
               d.LeagueId,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.VirtualIncome AS VirtualIncome,
               d.VarianceIncome AS VarianceIncome,
               d.RealTurnover AS RealTurnover,
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY LeagueId,
                 MatchCode,
                 HomeId;
    END;
        DROP TABLE #Match;
        DROP TABLE #Data;
        DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Outright_MatchDetail] TO [vnteam];
GO
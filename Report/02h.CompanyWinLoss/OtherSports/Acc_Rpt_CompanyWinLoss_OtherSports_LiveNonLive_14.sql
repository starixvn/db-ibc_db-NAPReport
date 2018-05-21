USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20160801@Sophia: Revise code for Deposit and Credit ammount
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14] @EndDate='2020-01-01',@StartDate='2016-01-01'

*/


     SET NOCOUNT ON;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType INT );
        INSERT INTO #SportBetType
               SELECT s.BetType
               FROM dbo.f_SportBetTypeMatrix_Sel( 1, 0, 0, 2, '', '', @isTest ) s
               WHERE SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
                 AND EventType IN( 1, 2 );
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper( CustId INT PRIMARY KEY );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1( 'All' );
    END;
    BEGIN -- #Match

        CREATE TABLE #Match( MatchId INT,
							sporttype SMALLINT,
                             type    VARCHAR(10),
                             PRIMARY KEY( MatchId, type ));
        INSERT INTO #Match
               SELECT DISTINCT m.MatchId,
			          s.SportType,
                      m.type
               FROM(
                   SELECT MatchId,
                          LeagueId,
                          'match' AS type
                   FROM match14 WITH ( NOLOCK )
                   WHERE EventDate = @StartDate
                   UNION ALL
                   SELECT orid,
                          LeagueId,
                          'outright' AS type
                   FROM outright14 WITH ( NOLOCK )
                   WHERE EventDate = @StartDate ) m
                   INNER JOIN league l WITH ( NOLOCK ) ON m.LeagueId = l.LeagueId
				   INNER JOIN Sports s WITH ( NOLOCK ) ON l.sporttype = s.sporttype
               WHERE l.sporttype > 1;
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
                 AND a.SubProduct = ''
               GROUP BY SuperId,Sporttype;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data( GroupId         INT,
                            GroupName       NVARCHAR(50),
                            RowName         NVARCHAR(50),
                            MemberWinLoss   MONEY,
                            SMAWinLoss      MONEY,
							ExtraPT         MONEY,
                            Commission      MONEY,
                            RealIncome      MONEY,
                            VirtualIncome   MONEY,
							VarianceIncome  MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- Live AND Non-Live
        INSERT INTO #Data
               SELECT liveindicator AS GroupId,
                                       CASE liveindicator
                                           WHEN 1
                                           THEN 'Other Sports Live'
                                           ELSE 'Other Sports Non-Live'
                                       END AS GroupName,
                                              CASE
                                                  WHEN dep.CustId IS NULL
                                                  THEN 'Credit'
                                                  ELSE 'Deposit'
                                              END AS RowName,
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
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                    WHEN tpositiontaking = 1
                                                                                    THEN 0
                                                                                    ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                END ) * virtualrate + ( scomm - ( CASE
                                                                                                                    WHEN tpositiontaking = 1
                                                                                                                    THEN 0
                                                                                                                    ELSE b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                END ) * ISNULL(e.ExtraPT, 0)
																										) * actualrate * CASE WHEN virtualrate < actualrate THEN virtualrate / actualrate ELSE 1 END 
					) VirtualIncome,
					SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE WHEN tpositiontaking = 1 THEN 0 ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0) END
					+ CASE WHEN virtualrate < actualrate THEN (b.scomm -  (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) END) * ISNULL(e.ExtraPT, 0)) ELSE 0 END															  
																				) * (actualrate - virtualrate)) VarianceIncome,
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
               FROM bettrans14 AS b WITH ( NOLOCK )
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
					INNER JOIN #Match AS m ON b.MatchId = m.MatchId
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
											 AND e.Sporttype = (CASE WHEN m.sporttype = 44 THEN 44 ELSE 0 END)
               WHERE b.winlostdate = @StartDate
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY liveindicator,
                        CASE liveindicator
                            WHEN 1
                            THEN 'Other Sports Live'
                            ELSE 'Other Sports Non-Live'
                        END,
                        CASE
                            WHEN dep.CustId IS NULL
                            THEN 'Credit'
                            ELSE 'Deposit'
                        END;
    END;
    BEGIN -- Sophia				 
        ------ BARM only
        INSERT INTO #Data
               SELECT liveindicator AS GroupId,
                                       CASE liveindicator
                                           WHEN 1
                                           THEN 'Other Sports Live'
                                           ELSE 'Other Sports Non-Live'
                                       END AS GroupName,
                      'BARM' AS RowName,
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
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                    WHEN tpositiontaking = 1
                                                                                    THEN 0
                                                                                    ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                END ) * virtualrate + ( scomm - ( CASE
                                                                                                                    WHEN tpositiontaking = 1
                                                                                                                    THEN 0
                                                                                                                    ELSE b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                END ) * ISNULL(e.ExtraPT, 0)
																										) * actualrate * CASE WHEN virtualrate < actualrate THEN virtualrate / actualrate ELSE 1 END 
					) VirtualIncome,
					SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE WHEN tpositiontaking = 1 THEN 0 ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0) END
					+ CASE WHEN virtualrate < actualrate THEN (b.scomm -  (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) END) * ISNULL(e.ExtraPT, 0)) ELSE 0 END															  
																				) * (actualrate - virtualrate)) VarianceIncome,
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
               FROM bettrans14 AS b WITH ( NOLOCK )
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
											 AND e.Sporttype = (CASE WHEN m.sporttype = 44 THEN 44 ELSE 0 END)
               WHERE b.recommend = 5707545
                 AND b.winlostdate = @StartDate
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY liveindicator,
                        CASE liveindicator
                            WHEN 1
                            THEN 'Other Sports Live'
                            ELSE 'Other Sports Non-Live'
                        END;
        INSERT INTO #Data
               ( GroupId,
                 GroupName,
                 RowName,
                 MemberWinLoss,
                 SMAWinLoss,
				 ExtraPT,
                 Commission,
                 RealIncome,
                 VirtualIncome,
				 VarianceIncome,
                 RealTurnover,
                 VirtualTurnover
               )
               SELECT GroupId,
                      GroupName,
                      'Deposit' AS RowName,
                      0 AS MemberWinLoss,
                      0 AS SMAWinLoss,
					  0 AS ExtraPT,
                      0 AS Commission,
                      0 AS RealIncome,
                      0 AS VirtualIncome,
					  0 AS VarianceIncome,
                      0 AS RealTurnover,
                      0 AS VirtualTurnover
               FROM(
                   SELECT GroupId,
                          GroupName
                   FROM #Data
                   WHERE RowName = 'BARM'
                   EXCEPT
                   SELECT GroupId,
                          GroupName
                   FROM #Data
                   WHERE RowName = 'Deposit' ) D;
								
        ---- Update Credit = Credit - BARM, Deposit = Deposit + BARM
        UPDATE c
          SET c.MemberWinLoss = ISNULL(c.MemberWinLoss, 0) + CASE
                                                                 WHEN c.RowName = 'Credit'
                                                                 THEN-ISNULL(d.MemberWinLoss, 0)
                                                                 ELSE ISNULL(d.MemberWinLoss, 0)
                                                             END,
              c.SMAWinLoss = ISNULL(c.SMAWinLoss, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.SMAWinLoss, 0)
                                                           ELSE ISNULL(d.SMAWinLoss, 0)
                                                       END,
			  c.ExtraPT = ISNULL(c.ExtraPT, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.ExtraPT, 0)
                                                           ELSE ISNULL(d.ExtraPT, 0)
                                                       END,
              c.Commission = ISNULL(c.Commission, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.Commission, 0)
                                                           ELSE ISNULL(d.Commission, 0)
                                                       END,
              c.RealIncome = ISNULL(c.RealIncome, 0) + CASE
                                                           WHEN c.RowName = 'Credit'
                                                           THEN-ISNULL(d.RealIncome, 0)
                                                           ELSE ISNULL(d.RealIncome, 0)
                                                       END,
              c.VirtualIncome = ISNULL(c.VirtualIncome, 0) + CASE
                                                                 WHEN c.RowName = 'Credit'
                                                                 THEN-ISNULL(d.VirtualIncome, 0)
                                                                 ELSE ISNULL(d.VirtualIncome, 0)
                                                             END,
              c.VarianceIncome = ISNULL(c.VarianceIncome, 0) + CASE
                                                                 WHEN c.RowName = 'Credit'
                                                                 THEN-ISNULL(d.VarianceIncome, 0)
                                                                 ELSE ISNULL(d.VarianceIncome, 0)
                                                             END,
              c.RealTurnover = ISNULL(c.RealTurnover, 0) + CASE
                                                               WHEN c.RowName = 'Credit'
                                                               THEN-ISNULL(d.RealTurnover, 0)
                                                               ELSE ISNULL(d.RealTurnover, 0)
                                                           END,
              c.VirtualTurnover = ISNULL(c.VirtualTurnover, 0) + CASE
                                                                     WHEN c.RowName = 'Credit'
                                                                     THEN-ISNULL(d.VirtualTurnover, 0)
                                                                     ELSE ISNULL(d.VirtualTurnover, 0)
                                                                 END
        FROM #Data c
             FULL JOIN #Data d ON c.GroupId = d.GroupId
                              AND c.GroupName = d.GroupName
                              AND d.RowName = 'BARM'
                              AND c.RowName IN( 'Credit', 'Deposit' );


        -----Delete BARM row used for calculate
        DELETE #Data
        WHERE RowName = 'BARM';
    END;
    BEGIN -- RM   

        INSERT INTO #Data
               SELECT 0,
                      'RM',
                      CASE
                          WHEN b.recommend = 52466
                          THEN '8RM Total'
                          WHEN b.recommend = 5707545
                          THEN 'BARM Total'
                          ELSE ''
                      END AS RowName,
                      -SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      -SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
					  SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
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
                                                                                                                END ) * ISNULL(e.ExtraPT, 0)
																										) * actualrate * CASE WHEN virtualrate < actualrate THEN virtualrate / actualrate ELSE 1 END 
					) VirtualIncome,
					-SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE WHEN tpositiontaking = 1 THEN 0 ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0) END
					+ CASE WHEN virtualrate < actualrate THEN (b.scomm -  (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) END) * ISNULL(e.ExtraPT, 0)) ELSE 0 END															  
																				) * (actualrate - virtualrate)) VarianceIncome,
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
               FROM bettrans14 b WITH ( NOLOCK )
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
					INNER JOIN #Match AS m ON b.MatchId = m.MatchId
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
											 AND e.Sporttype = (CASE WHEN m.sporttype = 44 THEN 44 ELSE 0 END)
               WHERE b.winlostdate = @StartDate
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
                 AND b.recommend IN( 52466, 5707545 )
               GROUP BY CASE
                            WHEN b.recommend = 52466
                            THEN '8RM Total'
                            WHEN b.recommend = 5707545
                            THEN 'BARM Total'
                            ELSE ''
                        END;
    END;
    BEGIN -- Query

        SELECT d.GroupId AS GroupId,
               d.GroupName AS GroupName,
               d.RowName AS RowName,
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
        ORDER BY GroupName,
                 RowName;
    END;
        DROP TABLE #SportBetType;
        DROP TABLE #DepositSuper;
        DROP TABLE #Match;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_OtherSports_LiveNonLive_14] TO [vnteam];
GO
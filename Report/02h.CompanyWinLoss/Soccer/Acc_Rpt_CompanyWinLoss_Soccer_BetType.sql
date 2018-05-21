USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Soccer_BetType]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.[Acc_Rpt_CompanyWinLoss_Soccer_BetType]    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Soccer_BetType]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @IsMajor   BIT = 1,
       @IsLive    INT = 2
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)


Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Soccer_BetType] @EndDate='2020-01-01',@StartDate='2016-01-01', @IsMajor = 1, @IsLive = 2

*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType INT );
        INSERT INTO #SportBetType
               SELECT s.BetType
               FROM dbo.f_SportBetTypeMatrix_Sel( 1, 1, 0, 2, '', '', @isTest ) s
               WHERE SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
                 AND EventType IN( 1, 2 );
    END;
    BEGIN -- Bet Type
        DECLARE @BetType TABLE( BetType      INT PRIMARY KEY,
                                BetTypeName  NVARCHAR(50),
                                DisplayOrder INT IDENTITY(1, 1));
        INSERT INTO @BetType
               ( BetType
               )
        VALUES( 1 ),
              ( 301 ),
              ( 3 ),
              ( 302 ),
              ( 7 ),
              ( 303 ),
              ( 8 ),
              ( 304 ),
              ( 2 ),
              ( 5 ),
              ( 4 ),
              ( 6 ),
              ( 10 );
        INSERT INTO @BetType
               ( BetType
               )
               SELECT typeid
               FROM BetType b WITH ( NOLOCK )
                    INNER JOIN #SportBetType sb ON sb.BetType = b.typeid
               WHERE b.typeid > 10
                 AND b.typeid NOT IN( 301, 302, 303, 304 );
        IF @IsMajor = 1
            BEGIN
                DELETE @BetType
                WHERE Bettype NOT IN( 1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304 );
            END;
        ELSE
            BEGIN
                DELETE @BetType
                WHERE Bettype IN( 1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304 );
            END;
        UPDATE b
          SET b.BetTypeName = bt.typenamee
        FROM @BetType b
             INNER JOIN BetType( NOLOCK ) bt ON b.BetType = bt.typeid;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper( CustId INT PRIMARY KEY );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1( 'All' );
    END;
    BEGIN -- #Match

        CREATE TABLE #Match( MatchId   INT,
                             MatchCode NVARCHAR(50),
                             type      VARCHAR(10),
                             PRIMARY KEY( MatchId, type ));
        INSERT INTO #Match
               SELECT DISTINCT m.MatchId,
                      m.MatchCode,
                      m.type
               FROM(
                   SELECT MatchId,
                          LeagueId,
                          MatchCode,
                          'match' AS type
                   FROM Match WITH ( NOLOCK )
                   WHERE EventDate = @StartDate
                   UNION ALL
                   SELECT orid,
                          LeagueId,
                          MatchCode,
                          'outright' AS type
                   FROM outright WITH ( NOLOCK )
                   WHERE EventDate = @StartDate ) m
                   INNER JOIN league l WITH ( NOLOCK ) ON m.LeagueId = l.LeagueId
               WHERE l.sporttype = 1;
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

        CREATE TABLE #Data( GroupId         INT,
                            GroupName       NVARCHAR(50),
                            DisplayOrder    INT,
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
    BEGIN -- Bet Type
        INSERT INTO #Data
               SELECT sb.BetType GroupId,
                                 CASE
                                     WHEN m.MatchCode LIKE '%hedge%'
                                     THEN sb.BetTypeName + ' (hedge)'
                                     ELSE sb.BetTypeName
                                 END GroupName,
                      sb.DisplayOrder,
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
               FROM bettrans AS b WITH ( NOLOCK )
                    INNER JOIN @BetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
												AND e.Sporttype = 0
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                 AND ( @IsLive > 1
                    OR b.liveindicator = @IsLive
                     )
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY sb.BetType,
                           CASE
                               WHEN m.MatchCode LIKE '%hedge%'
                               THEN sb.BetTypeName + ' (hedge)'
                               ELSE sb.BetTypeName
                           END,
                        sb.DisplayOrder,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END;
    END;
    BEGIN -- Sophia				 
        ------ BARM (site only)
        INSERT INTO #Data
               SELECT sb.BetType GroupId,
                                 CASE
                                     WHEN m.MatchCode LIKE '%hedge%'
                                     THEN sb.BetTypeName + ' (hedge)'
                                     ELSE sb.BetTypeName
                                 END GroupName,
                      sb.DisplayOrder,
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
               FROM bettrans AS b WITH ( NOLOCK )
                    INNER JOIN @BetType AS sb ON sb.BetType = b.BetType
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
												AND e.Sporttype = 0
               WHERE b.recommend = 5707545
                 AND b.winlostdate = @StartDate
                 AND ( @IsLive > 1
                    OR b.liveindicator = @IsLive
                     )
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY sb.BetType,
                           CASE
                               WHEN m.MatchCode LIKE '%hedge%'
                               THEN sb.BetTypeName + ' (hedge)'
                               ELSE sb.BetTypeName
                           END,
                        sb.DisplayOrder;
						 
        --- set data default for 'Deposit' if there is no data
        INSERT INTO #Data
               ( GroupId,
                 GroupName,
                 DisplayOrder,
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
                      DisplayOrder,
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
                          GroupName,
                          DisplayOrder
                   FROM #Data
                   WHERE RowName = 'BARM'
                   EXCEPT
                   SELECT GroupId,
                          GroupName,
                          DisplayOrder
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
                      10000000,
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
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN @BetType AS sb ON sb.BetType = b.BetType
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
												AND e.Sporttype = 0
               WHERE b.winlostdate = @StartDate
                 AND ( @IsLive > 1
                    OR b.liveindicator = @IsLive
                     )
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

        SELECT d.GroupId GroupId,
               d.GroupName AS GroupName,
               d.DisplayOrder,
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
        ORDER BY CASE
                     WHEN d.GroupName LIKE '%(hedge)%'
                     THEN 1
                     ELSE 0
                 END,
                 DisplayOrder;
    END;
        DROP TABLE #SportBetType;
        DROP TABLE #DepositSuper;
        DROP TABLE #Match;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Soccer_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Soccer_BetType] TO [vnteam];
GO
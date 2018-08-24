/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Game_Site    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @BetType   INT,
       @Site      NVARCHAR(50)
AS

/*
Creator: Franklin
Date: 2016-02-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 2018.06.04@Dominic: Force to recompile (#96143)
				   
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_Site] @BetType = 2101,@EndDate='2020-01-01',@Site = 'Credit',@StartDate='2016-01-01'
*/

     SET NOCOUNT ON;
    BEGIN -- #SportBetType
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( ProductID INT,
                                    BetType   INT,
                                    RefTable  INT );
        INSERT INTO #SportBetType
               SELECT ProductID,
                      BetType,
                      RefTable
               FROM bodb02.dbo.f_SportBetTypeMatrix_Sel( 0, 0, @BetType, 2, '', '', @isTest );
    END;
    BEGIN -- #Agent

        CREATE TABLE #Agent( CustId INT PRIMARY KEY,
                             Site   NVARCHAR(50));
        IF @Site = 'Deposit'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND EXISTS( 
                                     SELECT 1
                                     FROM f_DepSuper_1( 'All' ) dep
                                     WHERE c.srecommend = dep.CustId );
            END;
        ELSE
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND NOT EXISTS( 
                                         SELECT 1
                                         FROM f_DepSuper_1( 'All' ) dep
                                         WHERE c.srecommend = dep.CustId );
            END;
    END;
    BEGIN --#ExtraPT
        CREATE TABLE #ExtraPT( ProductID INT,
                               SuperID   INT,
                               ExtraPT   DECIMAL(9, 8));
        INSERT INTO #ExtraPT
               SELECT ProductID,
                      SuperId,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY ProductID,
                        SuperId;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data( RowName       NVARCHAR(50),
                            MemberWinLoss MONEY,
                            SMAWinLoss    MONEY,
							ExtraPT       MONEY,
                            Commission    MONEY,
                            RealIncome    MONEY,
                            RealTurnover  MONEY );
    END;
        IF EXISTS -- bettrans
        ( SELECT 1
          FROM #SportBetType
          WHERE RefTable NOT IN( 1, 2 )
            AND BetType = @BetType )
            BEGIN
                INSERT INTO #Data
                       SELECT dep.Site RowName,
                              SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
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
                                                                                                               WHEN virtualrate > actualrate
                                                                                                               THEN virtualrate
                                                                                                               ELSE actualrate
                                                                                                           END
                                  END) AS RealTurnover
                       FROM bettrans AS b WITH ( NOLOCK )
                            INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
                            INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                            LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                AND sb.ProductId = e.ProductId
                       WHERE b.winlostdate = @StartDate
                         AND b.BetType = @BetType
                         AND b.ruben = 1
                         AND b.statusID IN( 111, 112, 113 )
                       GROUP BY dep.Site
					   OPTION(RECOMPILE)
            END;
                IF EXISTS -- bettransRNG
                ( SELECT 1
                  FROM #SportBetType
                  WHERE RefTable = 1
                    AND BetType = @BetType )
                    BEGIN
                        INSERT INTO #Data
                               SELECT dep.Site RowName,
                                      SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
                                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
									  SUM(( CASE
                                                WHEN b.gameId IN( 2198, 2398, 2998 )
                                                THEN (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.ContributionRate * b.BetStake + b.scomm / ( 1 - b.tpositiontaking )
													  END ) * ISNULL(e.ExtraPT, 0)
                                                WHEN b.gameId IN( 2199, 2399, 2999 )
                                                THEN 0
                                                ELSE (CASE WHEN tpositiontaking = 1 THEN 0 ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                      END ) * ISNULL(e.ExtraPT, 0)
                                            END ) * actualrate) AS ExtraPT,
                                      SUM(scomm * actualrate) Commission,
                                      SUM(( CASE
                                                WHEN b.gameId IN( 2198, 2398, 2998 )
                                                THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                                                      WHEN tpositiontaking = 1
                                                                                                                                      THEN 0
                                                                                                                                      ELSE b.ContributionRate * b.BetStake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                                  END ) * ISNULL(e.ExtraPT, 0)
                                                WHEN b.gameId IN( 2199, 2399, 2999 )
                                                THEN 0
                                                ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                                             WHEN tpositiontaking = 1
                                                                                                                             THEN 0
                                                                                                                             ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                         END ) * ISNULL(e.ExtraPT, 0)
                                            END ) * actualrate) AS RealIncome,
                                      SUM(CASE
                                              WHEN tpositiontaking = 1
                                              THEN 0
                                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                                       WHEN virtualrate > actualrate
                                                                                                                       THEN virtualrate
                                                                                                                       ELSE actualrate
                                                                                                                   END
                                          END) AS RealTurnover
                               FROM bettransRNG b WITH ( NOLOCK )
                                    INNER JOIN #Agent dep ON b.recommend = dep.custid
                                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.gameId
                                    LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                        AND sb.ProductId = e.ProductId
                               WHERE b.winlostdate = @StartDate
                                 AND b.gameId = @BetType
                                 AND b.statusID IN( 111, 112, 113 )
                               GROUP BY dep.Site
							   OPTION(RECOMPILE)
                    END;
                        IF EXISTS -- bettransLC
                        ( SELECT 1
                          FROM #SportBetType
                          WHERE RefTable = 2
                            AND BetType = @BetType )
                            BEGIN
                                INSERT INTO #Data
                                       SELECT dep.Site RowName,
                                              SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
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
                                                                                                                               WHEN virtualrate > actualrate
                                                                                                                               THEN virtualrate
                                                                                                                               ELSE actualrate
                                                                                                                           END
                                                  END) AS RealTurnover
                                       FROM bettransLC b WITH ( NOLOCK )
                                            INNER JOIN #Agent dep ON b.recommend = dep.custid
                                            INNER JOIN #SportBetType AS sb ON sb.BetType = b.gameId
                                            LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                                AND sb.ProductId = e.ProductId
                                       WHERE b.winlostdate = @StartDate
                                         AND b.gameId = @BetType
                                         AND b.statusID IN( 111, 112, 113 )
                                       GROUP BY dep.Site
									   OPTION(RECOMPILE)
                            END;
    BEGIN -- Query

        SELECT d.RowName AS RowName,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
			   -d.ExtraPT AS ExtraPT,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.RealTurnover AS RealTurnover
        FROM #Data AS d
        ORDER BY RowName;
    END;
        DROP TABLE #SportBetType;
        DROP TABLE #Agent;
        DROP TABLE #ExtraPT;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Site] TO [vnteam];
GO
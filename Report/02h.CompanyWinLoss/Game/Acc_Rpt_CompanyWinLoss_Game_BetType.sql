USE [bodb02];
GO
IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @ProductId INT
AS

/*
Creator: Franklin
Date: 2016-12-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_BetType] @EndDate='2020-01-01',@StartDate='2016-01-01',@ProductId=6
*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType     INT,
                                    BetTypeName NVARCHAR(50),
                                    RefTable    INT );
        INSERT INTO #SportBetType
               SELECT BetType,
                      b.typenamee,
                      RefTable
               FROM dbo.f_SportBetTypeMatrix_Sel( @ProductId, 0, 0, 2, '', '', @isTest ) s
                    INNER JOIN BetType b WITH ( NOLOCK ) ON b.typeid = s.BetType;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper( CustId INT PRIMARY KEY );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1( 'All' );
    END;
    BEGIN ---- Extra PT 
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
                 AND a.ProductId = @ProductId
               GROUP BY SuperId;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data( GroupId       INT,
                            GroupName     NVARCHAR(50),
                            RowName       NVARCHAR(50),
                            MemberWinLoss MONEY,
                            SMAWinLoss    MONEY,
                            Commission    MONEY,
                            RealIncome    MONEY,
                            RealTurnover  MONEY );
    END;
        IF EXISTS -- Bettrans
        ( SELECT 1
          FROM #SportBetType
          WHERE RefTable NOT IN( 1, 2 ))
            BEGIN
                INSERT INTO #Data
                       SELECT sb.BetType AS GroupId,
                              sb.BetTypeName AS GroupName,
                                                CASE
                                                    WHEN dep.CustId IS NULL
                                                    THEN 'Credit'
                                                    ELSE 'Deposit'
                                                END AS RowName,
                              SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
                              SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
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
                       FROM bettrans AS b WITH ( NOLOCK )
                            INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                            LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                            LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                       WHERE b.winlostdate = @StartDate
                         AND sb.RefTable NOT IN( 1, 2 )
                         AND b.ruben = 1
                         AND b.statusID IN( 111, 112, 113 )
                       GROUP BY sb.BetType,
                                sb.BetTypeName,
                                   CASE
                                       WHEN dep.CustId IS NULL
                                       THEN 'Credit'
                                       ELSE 'Deposit'
                                   END;
            END;
                IF EXISTS -- bettransRNG
                ( SELECT 1
                  FROM #SportBetType
                  WHERE RefTable = 1 )
                    BEGIN
                        INSERT INTO #Data
                               SELECT sb.BetType AS GroupId,
                                      sb.BetTypeName AS GroupName,
                                                        CASE
                                                            WHEN dep.CustId IS NULL
                                                            THEN 'Credit'
                                                            ELSE 'Deposit'
                                                        END AS RowName,
                                      SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinLoss,
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
                                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                                       THEN virtualrate
                                                                                                                       ELSE actualrate
                                                                                                                   END
                                          END) RealTurnover
                               FROM bettransRNG b WITH ( NOLOCK )
                                    INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                                    LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                               WHERE b.winlostdate = @StartDate
                                 AND sb.RefTable = 1
                                 AND b.statusID IN( 111, 112, 113 )
                               GROUP BY sb.BetType,
                                        sb.BetTypeName,
                                           CASE
                                               WHEN dep.CustId IS NULL
                                               THEN 'Credit'
                                               ELSE 'Deposit'
                                           END;
                    END;
                        IF EXISTS -- bettransLC
                        ( SELECT 1
                          FROM #SportBetType
                          WHERE RefTable = 2 )
                            BEGIN
                                INSERT INTO #Data
                                       SELECT sb.BetType AS GroupId,
                                              sb.BetTypeName AS GroupName,
                                                                CASE
                                                                    WHEN dep.CustId IS NULL
                                                                    THEN 'Credit'
                                                                    ELSE 'Deposit'
                                                                END AS RowName,
                                              SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                                              SUM(( awinlost + mwinlost + swinlost ) * actualrate) SMAWinLoss,
                                              SUM(scomm * actualrate) Commission,
                                              SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                                            WHEN tpositiontaking = 1
                                                                                                                            THEN 0
                                                                                                                            ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                        END ) * ISNULL(e.ExtraPT, 0)) * actualrate) RealIncome,
                                              SUM(CASE
                                                      WHEN tpositiontaking = 1
                                                      THEN 0
                                                      ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                                               WHEN virtualrate / actualrate - 1 > 0
                                                                                                                               THEN virtualrate
                                                                                                                               ELSE actualrate
                                                                                                                           END
                                                  END) RealTurnover
                                       FROM bettransLC b WITH ( NOLOCK )
                                            INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                                            LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                                            LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                                       WHERE b.winlostdate = @StartDate
                                         AND sb.RefTable = 2
                                         AND b.statusID IN( 111, 112, 113 )
                                       GROUP BY sb.BetType,
                                                sb.BetTypeName,
                                                   CASE
                                                       WHEN dep.CustId IS NULL
                                                       THEN 'Credit'
                                                       ELSE 'Deposit'
                                                   END;
                            END;
    BEGIN -- Query

        SELECT d.GroupId AS GroupId,
               d.GroupName AS GroupName,
               d.RowName AS RowName,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.RealTurnover AS RealTurnover
        FROM #Data AS d
        ORDER BY GroupName,
                 RowName;
    END;
        DROP TABLE #SportBetType;
        DROP TABLE #DepositSuper;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_BetType] TO [vnteam];
GO
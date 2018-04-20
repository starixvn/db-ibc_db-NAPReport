USE [bodb02];
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Parlay]
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
- 20160720@Sophia: . Revise SP
				   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range) 
- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Parlay] @EndDate='2020-01-01',@StartDate='2016-01-01'

*/

     SET NOCOUNT ON;
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
                 AND a.ProductId = 1
                 AND a.Sporttype = 0
                 AND a.SubProduct = ''
               GROUP BY SuperId;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data( GroupId         INT,
                            GroupName       NVARCHAR(50),
                            RowName         NVARCHAR(50),
                            MemberWinLoss   MONEY,
                            SMAWinLoss      MONEY,
                            Commission      MONEY,
                            RealIncome      MONEY,
                            VirtualIncome   MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- Query
        INSERT INTO #Data
               SELECT CASE
                          WHEN bettype = 9
                            OR ( bettype = 29
                             AND betteam = '1'
                               )
                          THEN 9
                          ELSE 29
                      END AS GroupId,
                             CASE
                                 WHEN bettype = 9
                                   OR ( bettype = 29
                                    AND betteam = '1'
                                      )
                                 THEN 'Mix Parlay'
                                 ELSE 'System Parlay'
                             END AS GroupName,
                                    CASE
                                        WHEN dep.CustId IS NULL
                                        THEN 'Credit'
                                        ELSE 'Deposit'
                                    END AS RowName,
                      SUM(( winlost - actual_stake ) * actualrate) MemberWinlost,
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
               FROM bettrans b WITH ( NOLOCK )
                    LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
               WHERE b.winlostdate = @StartDate
                 AND BetType IN( 9, 29 )
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY CASE
                            WHEN bettype = 9
                              OR ( bettype = 29
                               AND betteam = '1'
                                 )
                            THEN 9
                            ELSE 29
                        END,
                        CASE
                            WHEN bettype = 9
                              OR ( bettype = 29
                               AND betteam = '1'
                                 )
                            THEN 'Mix Parlay'
                            ELSE 'System Parlay'
                        END,
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
               d.VirtualIncome AS VirtualIncome,
               d.RealIncome - d.VirtualIncome AS VarianceIncome,
               d.RealTurnover AS RealTurnover,
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY GroupName DESC,
                 RowName;
    END;
        DROP TABLE #Data;
        DROP TABLE #DepositSuper;
        DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Parlay] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Parlay] TO [vnteam];
GO
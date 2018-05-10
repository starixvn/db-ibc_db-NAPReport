IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @IsLive    INT = 2
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
Example:
EXEC [Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14] @EndDate='2020-01-01',@StartDate='2016-01-01', @IsLive = 2

*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType     INT,
                                    BetTypeName NVARCHAR(50));
        INSERT INTO #SportBetType
               SELECT b.typeid,
                      b.typenamee
               FROM dbo.f_SportBetTypeMatrix_Sel( 1, 0, 0, @IsLive, 'MG-SuperLive', '', @isTest ) s
                    INNER JOIN BetType b WITH ( NOLOCK ) ON s.BetType = b.typeid;
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
                 AND a.ProductId = 1
                 AND a.SubProduct IN( 'MG-SuperLive' )
				 AND a.Sporttype = 0
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
							VarianceIncome  MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- INSERT INTO #Data
        INSERT INTO #Data
               SELECT 
				sb.BetType GroupId,
                sb.BetTypeName GroupName,
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
                    END) RealTurnover,
                SUM(CASE
                        WHEN tpositiontaking = 1
                        THEN 0
                        ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
                    END) VirtualTurnover
               FROM bettrans14 AS b WITH ( NOLOCK )
                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
               WHERE b.winlostdate = @StartDate
                 AND ( @IsLive > 1
                    OR b.liveindicator = @IsLive
                     )
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
    BEGIN -- Query


        SELECT d.GroupId GroupId,
               d.GroupName AS GroupName,
               d.RowName AS RowName,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
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
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_MetricGaming_BetType_14] TO [vnteam];
GO
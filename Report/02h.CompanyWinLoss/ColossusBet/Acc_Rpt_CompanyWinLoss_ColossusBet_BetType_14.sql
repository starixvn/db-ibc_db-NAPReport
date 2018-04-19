USE bodb02;
GO
IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME
AS

/*	
Creator: 20180228@Franklin
Task:  Integrate Colossus Bets - Free Play Integration (#90774)
DB: DBACC/bodb02

Revisions: 
	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14] @StartDate='2016-09-13', @EndDate='2020-01-01'
		
*/

    BEGIN
        SET NOCOUNT ON;
        BEGIN --#SportBetType     
            DECLARE @isTest BIT = 0;
            SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
            CREATE TABLE #SportBetType( BetType     INT,
                                        BetTypeName NVARCHAR(50));
            INSERT INTO #SportBetType
                   SELECT b.typeid,
                          b.typenamee
                   FROM dbo.f_SportBetTypeMatrix_Sel( 15, 0, 0, 2, '', '', @isTest ) s
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
                     AND a.ProductId = 15
                   GROUP BY SuperId;
        END;
        BEGIN -- Query

            SELECT sb.BetType AS GroupId,
                                 CASE
                                     WHEN b.BetType = 18000
                                      AND ISNULL(b.currency2, 0) = 1
                                     THEN sb.BetTypeName + ' (Free Play)'
                                     ELSE sb.BetTypeName
                                 END AS GroupName,
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
                                                                                                 ELSE winlost - actual_stake + b.scomm / 1 - b.tpositiontaking
                                                                                             END ) * ISNULL(e.ExtraPT, 0) ) * actualrate) AS RealIncome,
                   SUM(CASE
                           WHEN tpositiontaking = 1
                           THEN 0
                           ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                    WHEN virtualrate / actualrate - 1 > 0
                                                                                                    THEN virtualrate
                                                                                                    ELSE actualrate
                                                                                                END
                       END) AS RealTurnover
            FROM dbo.bettrans14 AS b WITH ( NOLOCK )
                 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                 LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
            WHERE b.winlostdate = @StartDate
              AND b.ruben = 1
              AND b.statusID IN( 111, 112, 113 )
            GROUP BY sb.BetType,
                        CASE
                            WHEN b.BetType = 18000
                             AND ISNULL(b.currency2, 0) = 1
                            THEN sb.BetTypeName + ' (Free Play)'
                            ELSE sb.BetTypeName
                        END,
                        CASE
                            WHEN dep.CustId IS NULL
                            THEN 'Credit'
                            ELSE 'Deposit'
                        END
            ORDER BY GroupName,
                     RowName;
        END;
        DROP TABLE #SportBetType;
        DROP TABLE #DepositSuper;
    END;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType_14] TO [vnteam];
GO
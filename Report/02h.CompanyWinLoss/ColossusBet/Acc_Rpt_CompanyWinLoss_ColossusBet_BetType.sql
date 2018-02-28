USE bodb02
GO

IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME
AS

/*	
Creator: 20180228@Franklin
Task:  Integrate Colossus Bets - Free Play Integration (#90774)
DB: DBACC/bodb02

Revisions: 
	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_ColossusBet_BetType] @StartDate='2016-09-13', @EndDate='2020-01-01'
		
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
                   SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) AS RealIncome,
                   SUM(( 1 - tpositiontaking ) * ABS(stake) * actualrate) AS RealTurnover
            FROM bettrans AS b WITH ( NOLOCK )
                 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                 LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
            WHERE b.winlostdate = @StartDate
			  AND b.BetType = 18000
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_BetType] TO [vnteam];
GO
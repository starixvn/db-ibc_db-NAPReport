IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14]
       @StartDate  SMALLDATETIME,
       @EndDate    SMALLDATETIME,
       @BetType    INT,
       @Site       NVARCHAR(50),
       @IsFreePlay BIT
AS

/*
Creator: 20180228@Franklin
Task:  Integrate Colossus Bets - Free Play Integration (#90774)
DB: DBACC/bodb02
Revisions: 

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @Site = 'Credit', @BetType = 18000, @IsFreePlay = 1


*/

     SET NOCOUNT ON;
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
    BEGIN -- Query

        SELECT Site AS RowName,
               SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
               SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
               SUM(scomm * actualrate) Commission,
               SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) AS RealIncome,
               SUM(( 1 - tpositiontaking ) * ABS(stake) * actualrate) AS RealTurnover
        FROM dbo.bettrans14 AS b WITH ( NOLOCK )
             INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
        WHERE b.winlostdate = @StartDate
          AND (( @IsFreePlay = 1
             AND ISNULL(b.currency2, 0) = 1
               )
            OR ( @IsFreePlay = 0
             AND ISNULL(b.currency2, 0) <> 1
               )
              )
          AND b.BetType = @BetType
          AND b.ruben = 1
          AND b.statusID IN( 111, 112, 113 )
        GROUP BY Site
        ORDER BY RowName;
    END;
        DROP TABLE #Agent;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_ColossusBet_Site_14] TO [vnteam];
GO
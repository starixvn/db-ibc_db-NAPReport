IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType_14] @StartDate SMALLDATETIME,
                                                                 @EndDate   SMALLDATETIME
AS

/*
Creator: 20170418@Jacob
DB: DBACC/bodb02
Revisions: 	 
    - 20170418@Jacob: Integrate Cash Out - Redmine:#73419		
Parameter's Explanation:
	- @Site: credit, deposit	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_CashOut_BetType_14] @StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
     END;
     BEGIN -- Query

         SELECT 0 AS GroupId,
                'Cash Out' AS GroupName,
                CASE
                    WHEN dep.CustId IS NULL
                    THEN 'Credit'
                    ELSE 'Deposit'
                END AS RowName,
                SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                SUM(scomm * actualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
         FROM bettrans14 AS b WITH (NOLOCK)

              LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
         WHERE b.winlostdate = @StartDate
               AND b.ruben = 1
               AND b.statusID IN(111, 112, 113)
               AND b.BetType BETWEEN 913 AND 914
         GROUP BY CASE
                      WHEN dep.CustId IS NULL
                      THEN 'Credit'
                      ELSE 'Deposit'
                  END
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #DepositSuper;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType_14] TO [vnteam];
GO
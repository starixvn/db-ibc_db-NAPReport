IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site_14] @StartDate SMALLDATETIME,
                                                              @EndDate   SMALLDATETIME,
                                                              @Site      NVARCHAR(50)
AS

/*
Creator: 20170418@Jacob
DB: DBACC/bodb02
Revisions: 	 
    - 20170418@Jacob: Integrate Cash Out - Redmine:#73419		
Parameter's Explanation:
	- @Site: credit, deposit	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_CashOut_Site_14] @StartDate='2016-08-24', @EndDate='2020-01-01', @Site = 'Deposit'
*/

     SET NOCOUNT ON;
     BEGIN -- #Agent

         CREATE TABLE #Agent
         (CustId INT PRIMARY KEY,
          Site   NVARCHAR(50)
         );
         IF @Site = 'Deposit'
             BEGIN
                 INSERT INTO #Agent
                        SELECT c.CustId,
                               Site
                        FROM customer AS c WITH (NOLOCK)
                        WHERE c.RoleID = 2
                              AND EXISTS
                        (
                            SELECT 1
                            FROM f_DepSuper_1('All') dep
                            WHERE c.srecommend = dep.CustId
                        );
             END;
         ELSE
             BEGIN
                 INSERT INTO #Agent
                        SELECT c.CustId,
                               Site
                        FROM customer AS c WITH (NOLOCK)
                        WHERE c.RoleID = 2
                              AND NOT EXISTS
                        (
                            SELECT 1
                            FROM f_DepSuper_1('All') dep
                            WHERE c.srecommend = dep.CustId
                        );
             END;
     END;
     BEGIN -- Query

         SELECT Site AS RowName,
                SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                SUM(scomm * actualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
         FROM bettrans14 AS b WITH (NOLOCK)
              INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
         WHERE b.winlostdate = @StartDate
               AND b.ruben = 1
               AND b.statusID IN(111, 112, 113)
               AND b.BetType BETWEEN 913 AND 914
         GROUP BY Site
         ORDER BY RowName;
     END;
     DROP TABLE #Agent;

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site_14] TO [vnteam];
GO
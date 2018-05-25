USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_CashOut_Site    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @Site      NVARCHAR(50)
AS


/*
Creator: 20170418@Jacob
DB: DBACC/bodb02
Revisions: 	 
    - 20170418@Jacob: Integrate Cash Out - Redmine:#73419		
    - 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
Parameter's Explanation:
	- @Site: credit, deposit	
Example: 

EXEC [Acc_Rpt_CompanyWinLoss_CashOut_Site] @StartDate='2016-08-24', @EndDate='2020-01-01', @Site = 'Deposit'
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
                 AND a.ProductId = 25
               GROUP BY SuperId;
    END;
    BEGIN -- Query

        SELECT Site AS RowName,
               SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
               SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
			   -SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
               SUM(scomm * actualrate) Commission,
               SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                             WHEN tpositiontaking = 1
                                                                                             THEN 0
                                                                                             ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                         END ) * ISNULL(e.ExtraPT, 0) ) * actualrate) AS RealIncome,
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
             LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
        WHERE b.winlostdate = @StartDate
          AND b.ruben = 1
          AND b.statusID IN( 111, 112, 113 )
          AND b.BetType BETWEEN 913 AND 914
        GROUP BY Site
        ORDER BY RowName;
    END;
        DROP TABLE #Agent;
        DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_Site] TO [vnteam];
GO
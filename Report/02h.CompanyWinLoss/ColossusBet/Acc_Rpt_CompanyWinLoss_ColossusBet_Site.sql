/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_ColossusBet_Site @StartDate  SMALLDATETIME, 
                                                            @EndDate    SMALLDATETIME, 
                                                            @BetType    INT, 
                                                            @Site       VARCHAR(50), 
                                                            @IsFreePlay BIT
AS

/*
Creator: 20180228@Franklin
Task:  Integrate Colossus Bets - Free Play Integration (#90774)
DB: DBACC/bodb02

Revisions:
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_ColossusBet_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @Site = 'Credit', @BetType = 18000, @IsFreePlay = 1

*/

     SET NOCOUNT ON;
    BEGIN -- #Agent
        CREATE TABLE #Agent
        (CustId INT
         PRIMARY KEY, 
         Site   VARCHAR(50)
        );
        IF @Site = 'CN88'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId, 
                              c.Site
                       FROM customer AS c WITH(NOLOCK)
                            INNER JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                       WHERE c.RoleID = 2;
        END;
            ELSE
            IF @Site = 'Deposit'
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                INNER JOIN Dep_CustSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545);
                    INSERT INTO #Agent
                           SELECT 5707545, 
                                  'BEST-ODDS';
            END;
                ELSE
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                LEFT JOIN Dep_CustSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                                LEFT JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545)
                                AND dep.CustId IS NULL
                                AND cn88.CustId IS NULL;
                    INSERT INTO #Agent
                           SELECT 52466, 
                                  'XYZBET';--8RM;
            END;
    END;
    BEGIN -- Query

        SELECT Site AS RowName, 
               SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
               SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
               -SUM(CASE
                        WHEN b.tpositiontaking = 1
                        THEN 0
                        ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                    END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
               SUM(scomm * actualrate) AS Commission, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                      END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                          WHEN virtualrate > actualrate
                                                                                          THEN virtualrate
                                                                                          ELSE actualrate
                                                                                      END
                   END) AS RealTurnover
        FROM dbo.bettrans AS b WITH(NOLOCK)
             INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
        WHERE b.winlostdate = @StartDate
              AND b.BetType = @BetType
              AND (@IsFreePlay = 1
                   AND ISNULL(b.currency2, 0) = 1
                   OR @IsFreePlay = 0
                   AND ISNULL(b.currency2, 0) <> 1)
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY Site
        ORDER BY RowName;
    END;
    
	DROP TABLE #Agent;
GO
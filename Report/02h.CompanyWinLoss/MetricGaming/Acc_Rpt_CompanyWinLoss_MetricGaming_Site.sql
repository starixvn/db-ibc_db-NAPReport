/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_MetricGaming_Site @StartDate SMALLDATETIME, 
                                                             @EndDate   SMALLDATETIME, 
                                                             @BetType   INT, 
                                                             @IsLive    INT           = 2, 
                                                             @Site      VARCHAR(20)
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20212203@Jaden: Support SABA789 (#151326)

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
Example:
EXEC [Acc_Rpt_CompanyWinLoss_MetricGaming_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @BetType = 1, @IsLive = 2,  @Site = 'Credit'
*/

     SET NOCOUNT ON;
    BEGIN -- #Agent
        CREATE TABLE #Agent
        (CustId INT
         PRIMARY KEY, 
         Site   VARCHAR(50)
        );
    
        CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
        INSERT INTO #DepositSuper
            SELECT custid FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);

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
                                INNER JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
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
                                LEFT JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
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
    BEGIN -- #Data

        CREATE TABLE #Data
        (RowName         NVARCHAR(50), 
         MemberWinLoss   MONEY, 
         SMAWinLoss      MONEY, 
         ExtraPT         MONEY, 
         Commission      MONEY, 
         RealIncome      MONEY, 
         VirtualIncome   MONEY, 
         VarianceIncome  MONEY, 
         RealTurnover    MONEY, 
         VirtualTurnover MONEY
        );
    END;
    BEGIN -- INSERT INTO #Data

        INSERT INTO #Data
               SELECT ag.site AS RowName, 
                      SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
                      SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM(CASE
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
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END) * virtualrate + (scomm - CASE
                                                                                                                       WHEN tpositiontaking = 1
                                                                                                                       THEN 0
                                                                                                                       ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                   END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                                  WHEN virtualrate < actualrate
                                                                                                                                                                  THEN virtualrate / actualrate
                                                                                                                                                                  ELSE 1
                                                                                                                                                              END) AS VirtualIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END + CASE
                                                                                               WHEN virtualrate < actualrate
                                                                                               THEN b.scomm - CASE
                                                                                                                  WHEN tpositiontaking = 1
                                                                                                                  THEN 0
                                                                                                                  ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                              END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                               ELSE 0
                                                                                           END) * (actualrate - virtualrate)) AS VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END) AS RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END) AS VirtualTurnover
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN #Agent AS ag ON b.recommend = ag.custid
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = @BetType
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND b.ruben = 1
                     AND b.statusID IN(111, 112, 113)
               GROUP BY ag.site;
    END;
    BEGIN -- Query

        SELECT d.RowName, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.VirtualIncome AS VirtualIncome, 
               d.VarianceIncome AS VarianceIncome, 
               d.RealTurnover AS RealTurnover, 
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY RowName;
    END;
    
	DROP TABLE #Agent;
    DROP TABLE #Data;
    DROP TABLE #DepositSuper;
GO
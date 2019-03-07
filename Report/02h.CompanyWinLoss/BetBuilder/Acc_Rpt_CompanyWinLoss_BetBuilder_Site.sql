
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_BetBuilder_Site @StartDate SMALLDATETIME,
                                                           @EndDate   SMALLDATETIME,
                                                           @SportType SMALLINT, -- Dummy Parameter
                                                           @BetType   INT           = 38,
                                                           @IsHedge   INT           = 2, -- Dummy Parameter
                                                           @IsLive    INT           = 2, -- Dummy Parameter
                                                           @Site      VARCHAR(20)
AS

/*
Creator: Jacob
Date: 2019-03-13
Task:  Integrate BetBuilder (#109822)
DB: DBACC/bodb02

Revisions:
- 20190313@Jacob: Integrate BetBuilder (#109822)
Parameters:

Example:
EXEC [Acc_Rpt_CompanyWinLoss_BetBuilder_Site] @EndDate='2019-03-03',@StartDate='2019-03-12', @Site = 'Credit'

*/

     SET NOCOUNT ON;
         BEGIN -- #Agent
             CREATE TABLE #Agent
                          (CustId INT
                           PRIMARY KEY,
                           Site   VARCHAR(50)
                          );
             IF @Site = 'Deposit'
                 BEGIN
                     INSERT INTO #Agent
                            SELECT c.CustId,
                                   c.Site
                            FROM customer AS c WITH (NOLOCK)
                                 LEFT JOIN Dep_CustSuper AS dep WITH (NOLOCK) ON c.srecommend = dep.custid
                            WHERE c.RoleID = 2
                                  AND c.CustId NOT IN(52466, 5707545)
                                 AND dep.custid IS NOT NULL;
                     INSERT INTO #Agent
                            SELECT 5707545,
                                   'BEST-ODDS';
                 END;
                 ELSE
                 BEGIN
                     INSERT INTO #Agent
                     SELECT c.CustId,
                            c.Site
                     FROM customer AS c WITH (NOLOCK)
                          LEFT JOIN Dep_CustSuper AS dep WITH (NOLOCK) ON c.srecommend = dep.custid
                     WHERE c.RoleID = 2
                           AND c.CustId NOT IN(52466, 5707545)
                          AND dep.custid IS NULL;
                     INSERT INTO #Agent
                     SELECT 52466,
                            'XYZBET';--8RM;
                 END;
         END;
         BEGIN -- Extra PT 
             CREATE TABLE #ExtraPT_Sel
                          (SuperID INT,
                           ExtraPT DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     ExtraPT
                    )
                    SELECT SuperId,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = 1
                          AND a.SubProduct = 'Bet Builder'
                    GROUP BY SuperId;
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
                               END * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                           SUM(scomm * actualrate) AS Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                      WHEN tpositiontaking = 1
                                                                                                      THEN 0
                                                                                                      ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                  END * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                              WHEN tpositiontaking = 1
                                                                                              THEN 0
                                                                                              ELSE(winlost - actual_stake) * ISNULL(e.ExtraPT, 0)
                                                                                          END) * virtualrate + (scomm - CASE
                                                                                                                            WHEN tpositiontaking = 1
                                                                                                                            THEN 0
                                                                                                                            ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                        END * ISNULL(e.ExtraPT, 0)) * actualrate * CASE
                                                                                                                                                                       WHEN virtualrate < actualrate
                                                                                                                                                                       THEN virtualrate / actualrate
                                                                                                                                                                       ELSE 1
                                                                                                                                                                   END) AS VirtualIncome,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                              WHEN tpositiontaking = 1
                                                                                              THEN 0
                                                                                              ELSE(winlost - actual_stake) * ISNULL(e.ExtraPT, 0)
                                                                                          END + CASE
                                                                                                    WHEN virtualrate < actualrate
                                                                                                    THEN b.scomm - CASE
                                                                                                                       WHEN tpositiontaking = 1
                                                                                                                       THEN 0
                                                                                                                       ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                   END * ISNULL(e.ExtraPT, 0)
                                                                                                    ELSE 0
                                                                                                END) * (actualrate - virtualrate)) AS VarianceIncome,
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                           WHEN virtualrate > actualrate
                                                                                                           THEN virtualrate
                                                                                                           ELSE actualrate
                                                                                                       END
                               END) AS RealTurnover,
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
                               END) AS VirtualTurnover
                    FROM bettrans AS b WITH (NOLOCK)
                         INNER JOIN #Agent AS ag ON b.recommend = ag.custid
                         LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
                    WHERE b.winlostdate = @StartDate
                          AND b.bettype = @BetType
                          AND b.ruben = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY ag.site OPTION(RECOMPILE);
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
     DROP TABLE #ExtraPT_Sel;
GO
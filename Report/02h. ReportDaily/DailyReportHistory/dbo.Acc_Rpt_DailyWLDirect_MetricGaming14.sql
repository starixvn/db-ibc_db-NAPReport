ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_MetricGaming14] @WinlostDate DATETIME,
                                                             @SubProduct  VARCHAR(500) = 'MG-SuperLive'
AS
     BEGIN
         SET NOCOUNT ON;

/*	Creator: 20150526@Sophia
	Task: Metric Gaming WinLost Summary report 
	DB: DBACC/bodb02
	
	Revisions: 
		- 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product [RedmineID#55584], select column b.liveindicator and using sporttype betype matrix function

*/

         ----Get Sport Bettype Matrix------
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         DECLARE @SportBettype TABLE
         (ProductID  INT,
          Bettype    INT,
          EventType  INT,
          SubProduct VARCHAR(500)
         );
         INSERT INTO @SportBettype
                SELECT ProductID,
                       Bettype,
                       EventType,
                       SubProduct
                FROM bodb02.dbo.f_SportBettypeMatrix_Sel(1, 0, 0, 2, '', '', @isTest);
         CREATE TABLE #DepAgent(custid INT PRIMARY KEY);
         INSERT INTO #DepAgent
                SELECT custid
                FROM dbo.custInfo WITH (NOLOCK)
                WHERE srecommend IN
                (
                    SELECT custid
                    FROM f_DepSuper_1('All')
                )
                AND roleid = 2
                UNION
                SELECT 5707545;--BARM

         SELECT s.ProductID,
                b.bettype,
                b.liveindicator,
                CASE
                    WHEN dep.custid IS NULL
                    THEN 1
                    ELSE 2
                END AS site,
                SUM((winlost - actual_stake) * virtualrate) WinLost,
                SUM((awinlost + mwinlost + swinlost) * virtualrate) Position,
                SUM(scomm * virtualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealLineTotal,
			 SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualLineTotal,
                SUM((1 - tpositiontaking) * stake * actualrate) RealTurnover,
			 SUM((1 - tpositiontaking) * stake * virtualrate) VirtualTurnover
         FROM dbo.bettrans14 b WITH (NOLOCK)
              INNER JOIN @SportBettype s ON s.bettype = b.bettype
              LEFT JOIN
         (
             SELECT custid
             FROM #DepAgent
         ) dep ON b.recommend = dep.custid
         WHERE s.SubProduct = @SubProduct
               AND b.winlostdate = @winlostdate
               AND b.ruben = 1
               AND b.statusID NOT IN(101, 102, 103, 121)
         GROUP BY s.ProductID,
                  b.Bettype,
                  b.liveindicator,
                  CASE
                      WHEN dep.custid IS NULL
                      THEN 1
                      ELSE 2
                  END
         ORDER BY b.Bettype,
                  Site;
         DROP TABLE #DepAgent;
     END;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_MetricGaming14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_MetricGaming14] TO [vnteam];
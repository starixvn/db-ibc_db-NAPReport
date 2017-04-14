ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_MetricGaming_Bettype_Site] @winlostdate   DATETIME,
                                                                             @bettype       INT,
                                                                             @site          TINYINT,
                                                                             @liveindicator BIT
AS

/*
	Creator: 20150526@Sophia
	Task: Report winlost summary for Metric Gaming by site
	DB: DBACC/bodb02 
		
	Revisions:
			- 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product [RedmineID#55584] 
	Parameter's Explanation:
		- @site: 1: credit
				2: deposit	
*/

     BEGIN
         SET NOCOUNT ON;
         CREATE TABLE #DepAgent
         (custid INT PRIMARY KEY,
          site   VARCHAR(50)
         );
         INSERT INTO #DepAgent
         (custid,
          site
         )
                SELECT c.custid,
                       site
                FROM dbo.customer c WITH (NOLOCK)
                     LEFT JOIN
                (
                    SELECT custid
                    FROM f_DepSuper_1('All')
                ) dep ON c.srecommend = dep.custid
                WHERE roleid = 2
                      AND 1 = CASE
                                  WHEN @site = 1
                                       AND dep.custid IS NULL
                                  THEN 1
                                  WHEN @site = 2
                                       AND dep.custid IS NOT NULL
                                  THEN 1
                                  ELSE 0
                              END
                      AND c.custid NOT IN(52466, 5707545);--8RM, BARM

         INSERT INTO #DepAgent
         (custid,
          site
         )
                SELECT 52466,
                       'XYZBET'
                WHERE @site = 1--8RM
                UNION
                SELECT 5707545,
                       'BEST-ODDS'
                WHERE @site = 2; --BARM

         SELECT ag.site,
                SUM((winlost - actual_stake) * virtualrate) WinLost,
                SUM((awinlost + mwinlost + swinlost) * virtualrate) Position,
                SUM(scomm * virtualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealLineTotal,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) VirtualLineTotal,
                SUM((1 - tpositiontaking) * stake * actualrate) RealTurnover,
                SUM((1 - tpositiontaking) * stake * virtualrate) VirtualTurnover
         FROM dbo.bettrans b WITH (NOLOCK)
              INNER JOIN #DepAgent ag ON b.recommend = ag.custid
         WHERE b.winlostdate = @winlostdate
               AND b.bettype = @bettype
               AND b.ruben = 1
               AND b.statusID NOT IN(101, 102, 103, 121)
               AND b.liveindicator = @liveindicator
         GROUP BY site
         ORDER BY site;
         DROP TABLE #DepAgent;
     END;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_MetricGaming_Bettype_Site] TO [bodbAdminNet];
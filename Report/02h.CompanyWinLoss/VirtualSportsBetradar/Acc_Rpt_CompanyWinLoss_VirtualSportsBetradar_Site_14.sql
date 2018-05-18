USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14] @StartDate SMALLDATETIME,
                                                                   @EndDate   SMALLDATETIME,
                                                                   @SportType SMALLINT,
                                                                   @BetType   INT,
                                                                   @Site      VARCHAR(20)
AS

/*Creator:
Jacob;
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20170720@Franklin: Add Betradar Virtual Sports (78495)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 180, @BetType = 1203, @Site = 'Credit'
*/

     SET NOCOUNT ON;
     BEGIN --@EventType    
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         DECLARE @EventType INT;
         SELECT @EventType = s.EventType
         FROM dbo.f_SportBetTypeMatrix_Sel(27, @SportType, @BetType, 2, '', '', @isTest) s;
     END;
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
	 BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
								   Sporttype  INT,
                                   ExtraPT DECIMAL(9, 8));
            INSERT INTO #ExtraPT_Sel
               ( SuperID,
			     Sporttype,
                 ExtraPT
               )
               SELECT SuperId,Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = 27
               GROUP BY SuperId,Sporttype;
    END;
	 IF @EventType = 1
         BEGIN
             SELECT Site RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
					-SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                    SUM(scomm * actualrate) Commission,
                    SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                    SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN match14 AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
                  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
				  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @StartDate
                   AND b.BetType = @BetType
                   AND m.sporttype = @SportType
                   AND b.MatchId > 0
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY Site
             ORDER BY RowName;
         END;
     ELSE
		BEGIN
             SELECT Site RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
					-SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                    SUM(scomm * actualrate) Commission,
                    SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                    SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN 
                  (
                    SELECT DISTINCT
                           bm.refno,
                           m.sporttype
                    FROM dbo.bettransm14 bm WITH (NOLOCK)
                         INNER JOIN dbo.match14 m WITH (NOLOCK) ON bm.matchid = m.matchid
                  ) bsm ON b.refno = bsm.refno
                  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
				  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @StartDate
                   AND b.BetType = @BetType
                   AND bsm.sporttype = @SportType
                   AND b.MatchId > 0
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY Site
             ORDER BY RowName;
         END;          
     
	 DROP TABLE #ExtraPT_Sel;                 
     DROP TABLE #Agent;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_Site_14] TO [vnteam];
GO
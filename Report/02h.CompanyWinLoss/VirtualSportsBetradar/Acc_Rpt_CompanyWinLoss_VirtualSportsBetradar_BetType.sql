/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_BetType] @StartDate SMALLDATETIME,
                                                                              @EndDate   SMALLDATETIME,
                                                                              @SportType SMALLINT
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 20170720@Franklin: Add Betradar Virtual Sports (78495)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 190
*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType     INT,
          BetTypeName NVARCHAR(50),
          EventType   INT
         );
         INSERT INTO #SportBetType
                SELECT b.typeid,
                       b.typenamee,
                       s.EventType
                FROM dbo.f_SportBetTypeMatrix_Sel(27, @SportType, 0, 2, '', '', @isTest) s
                     INNER JOIN BetType b WITH (NOLOCK) ON s.BetType = b.typeid;
     END;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
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
     BEGIN -- #Data

         CREATE TABLE #Data
         (BetType       INT,
          BetTypeName   NVARCHAR(50),
          Site          NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
		  ExtraPT       MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
         INSERT INTO #Data -- Virtualsports betradar bettype not include parlay
                SELECT sb.BetType,
                       sb.BetTypeName,
                       CASE
                          WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
					 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END,
                       SUM((winlost - actual_stake) * actualrate),
                       SUM((awinlost + mwinlost + swinlost) * actualrate),
					   SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                       SUM(scomm * actualrate),
                       SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate),
                       SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate > actualrate
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END)
                FROM bettrans AS b WITH (NOLOCK)
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                     LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
					 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                     INNER JOIN match AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
                WHERE b.winlostdate = @StartDate
                      AND sb.EventType = 1
                      AND m.sporttype = @SportType
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY sb.BetType,
                         sb.BetTypeName,
                         CASE
                          WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
					 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END;
         INSERT INTO #Data -- Parlay bettype
                SELECT sb.BetType,
                       sb.BetTypeName,
                       CASE
                          WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
					 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END AS site,
                       SUM((b.winlost - b.actual_stake) * b.actualrate),
                       SUM((b.awinlost + b.mwinlost + b.swinlost) * b.actualrate),
					   SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                       SUM(b.scomm * b.actualrate),
                       SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate),
                       SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate > actualrate
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END)
                FROM bettrans AS b WITH (NOLOCK)
                     INNER JOIN
                (
                    SELECT DISTINCT
                           bm.refno,
                           m.sporttype
                    FROM dbo.bettransm bm WITH (NOLOCK)
                         INNER JOIN dbo.match m WITH (NOLOCK) ON bm.matchid = m.matchid
                ) bsm ON b.refno = bsm.refno
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
					 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                WHERE b.winlostdate = @StartDate
                      AND bsm.sporttype = @SportType
                      AND sb.EventType = 0
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY sb.BetType,
                         sb.BetTypeName,
                         CASE
                          WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
                          THEN 'CN88'
					 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END;
     END;
     BEGIN -- Query Data
         SELECT d.BetType AS GroupId,
                d.BetTypeName AS GroupName,
                d.Site AS RowName,
                SUM(d.MemberWinLoss) AS MemberWinLoss,
                SUM(d.SMAWinLoss) AS SMAWinLoss,
				-SUM(d.ExtraPT) AS ExtraPT,
                SUM(d.Commission) AS Commission,
                SUM(d.RealIncome) AS RealIncome,
                SUM(d.RealTurnover) AS RealTurnover
         FROM #Data AS d
         GROUP BY d.BetType,
                  d.BetTypeName,
                  d.Site
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
	 DROP TABLE #ExtraPT_Sel;
     DROP TABLE #Data;
GO

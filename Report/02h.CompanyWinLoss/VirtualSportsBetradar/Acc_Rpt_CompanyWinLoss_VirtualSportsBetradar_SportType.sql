/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType] @StartDate SMALLDATETIME,
                                                                                @EndDate   SMALLDATETIME
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
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_SportType]	@StartDate='2016-01-01', @EndDate='2020-01-01'
*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType   INT,
          EventType INT
         );
         INSERT INTO #SportBetType
                SELECT s.BetType,
                       s.EventType
                FROM dbo.f_SportBetTypeMatrix_Sel(27, 0, 0, 2, '', '', @isTest) s;
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
         (SportType     INT,
          Site          NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
		  ExtraPT       MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     BEGIN -- Virtual Sports Betradar not include parlay bettype.

         INSERT INTO #Data
                SELECT m.sporttype,
                       CASE
                           WHEN dep.CustId IS NULL
                           THEN 'Credit'
                           ELSE 'Deposit'
                       END AS Site,
                       SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                       SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
					   SUM((CASE
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
                                                                                                       WHEN virtualrate > actualrate
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
                FROM bettrans AS b WITH (NOLOCK)
                     INNER JOIN match AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
                     INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                     LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
					 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
                WHERE b.winlostdate = @StartDate
                      AND sb.EventType = 1
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY m.sporttype,
                         CASE
                             WHEN dep.CustId IS NULL
                             THEN 'Credit'
                             ELSE 'Deposit'
                         END;
     END;
     BEGIN -- Parlay

         INSERT INTO #Data
                SELECT bsm.sporttype,
                       CASE
                           WHEN dep.CustId IS NULL
                           THEN 'Credit'
                           ELSE 'Deposit'
                       END AS site,
                       SUM((b.winlost - b.actual_stake) * b.actualrate) AS MemberWinLoss,
                       SUM((b.awinlost + b.mwinlost + b.swinlost) * b.actualrate) AS SMAWinLoss,
					   SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                       SUM(b.scomm * b.actualrate) Commission,
                       SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                       SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                       WHEN virtualrate > actualrate
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) AS RealTurnover
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
                      AND sb.EventType = 0
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY bsm.sporttype,
                         CASE
                             WHEN dep.CustId IS NULL
                             THEN 'Credit'
                             ELSE 'Deposit'
                         END;
     END;
     BEGIN -- Query

         SELECT d.SportType AS GroupId,
                s.SportName AS GroupName,
                d.Site AS RowName,
                SUM(d.MemberWinLoss) AS MemberWinLoss,
                SUM(d.SMAWinLoss) AS SMAWinLoss,
				-SUM(d.ExtraPT) AS ExtraPT,
                SUM(d.Commission) AS Commission,
                SUM(d.RealIncome) AS RealIncome,
                SUM(d.RealTurnover) AS RealTurnover
         FROM #Data AS d
              INNER JOIN Sports AS s WITH (NOLOCK) ON d.SportType = s.SportType
         GROUP BY d.SportType,
                  s.SportName,
                  d.Site
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
	 DROP TABLE #ExtraPT_Sel;
     DROP TABLE #Data;
GO

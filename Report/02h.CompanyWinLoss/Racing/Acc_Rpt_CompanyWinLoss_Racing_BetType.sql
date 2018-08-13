/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Racing_BetType] @StartDate SMALLDATETIME,
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
		
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Racing_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 151
*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType     INT,
          BetTypeName NVARCHAR(50)
         );
         INSERT INTO #SportBetType
                SELECT b.typeid,
                       b.typenamee
                FROM dbo.f_SportBetTypeMatrix_Sel(2, @SportType, 0, 2, '', '', @isTest) s
                     INNER JOIN BetType b WITH (NOLOCK) ON s.BetType = b.typeid;
     END;
     BEGIN -- @IBCFee

         DECLARE @IBCFee TABLE
         (partnerId INT,
          IBCFee    BIT
         );
         INSERT INTO @IBCFee
         (partnerId,
          IBCFee
         )
                SELECT 1,
                       1 --RACE-PHU
                UNION ALL
                SELECT 2,
                       0 --RACE-ATRUK
                UNION ALL
                SELECT 3,
                       0 --RACE-ATRIRL
                UNION ALL
                SELECT 4,
                       0 --RACE-RUK
                UNION ALL
                SELECT 5,
                       1 --RACE-TABCORP
                UNION ALL
                SELECT 6,
                       1 --RACE-TABCORPNSW
                UNION ALL
                SELECT 101,
                       1 --GREY-DTOTEUK
                UNION ALL
                SELECT 102,
                       1 --GREY-DTOTEIRL
                UNION ALL
                SELECT 103,
                       1 --GREY-TABCORP
                UNION ALL
                SELECT 104,
                       1 --GREY-TABCORPNSW
                UNION ALL
                SELECT 201,
                       1 --HAR-TABCORP
                UNION ALL
                SELECT 202,
                       1; --HAR-TABCORPNSW

     END;
     BEGIN -- #CommSetting

         CREATE TABLE #CommSetting
         (MatchId       INT,
          IBCFee        BIT,
          ToteCommWin   SMALLMONEY,
          ToteCommPlace SMALLMONEY,
          ToteCommWP    SMALLMONEY,
          ToteFee       SMALLMONEY
         );
         INSERT INTO #CommSetting
         (MatchId,
          IBCFee,
          ToteCommWin,
          ToteCommPlace,
          ToteCommWP,
          ToteFee
         )
                SELECT DISTINCT
                       o.orid AS MatchId,
                       t.IBCFee,
                       p.ToteCommWin,
                       p.ToteCommPlace,
                       (p.ToteCommWin + p.ToteCommPlace) / 2 AS ToteCommWP,
                       p.ToteFee
                FROM outright AS o WITH (NOLOCK)
                     INNER JOIN LeagueDetail AS p WITH (NOLOCK) ON o.LeagueId = p.LeagueId
                                                                   AND p.programDate = o.programDate
                     INNER JOIN RacingMeeting AS r WITH (NOLOCK) ON p.LeagueId = r.meetingid
                     INNER JOIN league AS l WITH (NOLOCK) ON p.LeagueId = l.LeagueId
                     INNER JOIN @IBCFee AS t ON r.partnerId = t.partnerId
                WHERE o.EventDate = @StartDate
                      AND l.sporttype = @SportType;
     END;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
     END;
     BEGIN -- Query		

         SELECT sb.BetType AS GroupId,
                sb.BetTypeName AS GroupName,
                CASE
                    WHEN dep.CustId IS NULL
                    THEN 'Credit'
                    ELSE 'Deposit'
                END AS RowName,
                SUM((b.winlost - b.actual_stake) * b.actualrate) AS MemberWinLoss,
                SUM((b.awinlost + b.mwinlost + b.swinlost) * b.actualrate) AS SMAWinLoss,
                SUM(b.scomm * b.actualrate) AS Commission,
                -(SUM((CASE
                           WHEN b.BetType = 33
                           THEN bm.WLIBC
                           ELSE-(b.winlost - b.actual_stake) * ISNULL(b.oddsspread, 0)
                       END) * b.actualrate) - SUM(CASE
                                                      WHEN cs.IBCFee = 0
                                                      THEN 0
                                                      ELSE(CASE
                                                               WHEN b.BetType = 33
                                                               THEN bm.TOPhum
                                                               WHEN b.BetType IN(31, 32)
                                                               THEN b.actual_stake * (1 - b.tpositiontaking - ISNULL(b.oddsspread, 0))
                                                               ELSE 0
                                                           END) * b.actualrate * cs.ToteFee
                                                  END) --FeeDue2 
         + SUM((CASE b.BetType
                    WHEN 31
                    THEN b.actual_stake * cs.ToteCommWin * (1 - b.tpositiontaking - ISNULL(oddsspread, 0))
                    WHEN 32
                    THEN b.actual_stake * cs.ToteCommPlace * (1 - b.tpositiontaking - ISNULL(oddsspread, 0))
                    WHEN 33
                    THEN bm.TOPhum * cs.ToteCommWP
                    ELSE 0
                END) * b.actualrate) --commIncomeIBC
         - SUM(b.scomm * b.actualrate)) AS RealIncome,
                SUM(CASE
                        WHEN b.BetType = 33
                        THEN bm.TOIBC * b.actualrate
                        ELSE b.actual_stake * ISNULL(oddsspread, 0) * b.actualrate
                    END) AS RealTurnover
         FROM bettrans AS b WITH (nolock)
              INNER JOIN #CommSetting AS cs ON b.MatchId = cs.MatchId
              INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
              LEFT JOIN
         (
             SELECT refno,
                    SUM(CASE
                            WHEN bm.BetType = 32
                                 AND liveawayscore = 0
                            THEN 0
                            ELSE stake * ISNULL(oddsspread, 0)
                        END) AS TOIBC,
                    -SUM((winlost - stake) * ISNULL(oddsspread, 0)) AS WLIBC,
                    SUM(CASE
                            WHEN bm.BetType = 32
                                 AND liveawayscore = 0
                            THEN 0
                            WHEN bm.BetType = 31
                                 OR (bm.BetType = 32
                                     AND liveawayscore <> 0)
                            THEN stake * (1 - tpositiontaking - ISNULL(oddsspread, 0))
                            ELSE 0
                        END) AS TOPhum
             FROM bettransm bm WITH (nolock)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = bm.BetType
             GROUP BY refno
         ) AS bm ON b.transid = bm.refno
              LEFT JOIN
         (
             SELECT CustId
             FROM #DepositSuper
         ) AS dep ON b.srecommend = dep.CustId
         WHERE b.winlostdate = @StartDate
               AND b.MatchId > 0
               AND b.ruben = 1
               AND b.statusID IN(111, 112, 113)
         GROUP BY sb.BetType,
                  sb.BetTypeName,
                  CASE
                      WHEN dep.CustId IS NULL
                      THEN 'Credit'
                      ELSE 'Deposit'
                  END
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #CommSetting;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Racing_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Racing_BetType] TO [vnteam];
GO
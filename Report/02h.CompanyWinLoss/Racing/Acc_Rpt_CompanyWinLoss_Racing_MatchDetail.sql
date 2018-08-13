/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Racing_MatchDetail] @StartDate SMALLDATETIME,
                                                                   @EndDate   SMALLDATETIME,
                                                                   @SportType SMALLINT,
                                                                   @BetType   INT
AS

    
/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
		
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Racing_MatchDetail] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 151, @BetType = 31
*/

     SET NOCOUNT ON;
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
          MeetingId     INT,
          IBCFee        BIT,
          Race          VARCHAR(10),
          ToteCommWin   SMALLMONEY,
          ToteCommPlace SMALLMONEY,
          ToteCommWP    SMALLMONEY,
          ToteFee       SMALLMONEY
         );
         INSERT INTO #CommSetting
         (MatchId,
          MeetingId,
          IBCFee,
          Race,
          ToteCommWin,
          ToteCommPlace,
          ToteCommWP,
          ToteFee
         )
                SELECT DISTINCT
                       o.orid AS MatchId,
                       o.LeagueId,
                       t.IBCFee,
                       o.groupmatch,
                       p.ToteCommWin,
                       p.ToteCommPlace,
                       (p.ToteCommWin + p.ToteCommPlace) / 2 AS ToteCommWP,
                       p.ToteFee
                FROM outright AS o WITH (NOLOCK)
                     INNER JOIN LeagueDetail AS p WITH (NOLOCK) ON o.LeagueId = p.LeagueId
                                                                   AND p.programDate = o.programDate
                     INNER JOIN League AS l WITH (NOLOCK) ON p.LeagueId = l.LeagueId
                     INNER JOIN RacingMeeting AS r WITH (NOLOCK) ON p.LeagueId = r.meetingId
                     INNER JOIN @IBCFee AS t ON r.partnerId = t.partnerId
                WHERE o.EventDate = @StartDate
                      AND l.sporttype = @sporttype;
     END;
     BEGIN -- #Data

         CREATE TABLE #Data
         (LeagueId      INT,
          Race          NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY
         );
     END;
     BEGIN -- INSERT INTO #Data

         INSERT INTO #Data
                SELECT cs.MeetingId AS LeagueId,
                       cs.Race AS Race,
                       SUM((b.winlost - b.actual_stake) * b.actualrate) AS MemberWinLoss,
                       SUM((b.awinlost + b.mwinlost + b.swinlost) * b.actualrate) AS SMAWinLoss,
                       SUM(b.scomm * b.actualrate) AS Commission,
                       -(SUM((CASE
                                  WHEN BetType = 33
                                  THEN bm.WLIBC
                                  ELSE-(b.winlost - b.actual_stake) * ISNULL(b.oddsspread, 0)
                              END) * b.actualrate) - SUM(CASE
                                                             WHEN cs.IBCFee = 0
                                                             THEN 0
                                                             ELSE(CASE
                                                                      WHEN b.BetType = 33
                                                                      THEN bm.TOPhum
                                                                      WHEN BetType IN(31, 32)
                                                                      THEN b.actual_stake * (1 - b.tpositiontaking - ISNULL(b.oddsspread, 0))
                                                                      ELSE 0
                                                                  END) * b.actualrate * cs.ToteFee
                                                         END) --FeeDue2 
                + SUM((CASE BetType
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
                               WHEN BetType = 33
                               THEN bm.TOIBC * b.actualrate
                               ELSE b.actual_stake * ISNULL(oddsspread, 0) * b.actualrate
                           END) AS RealTurnover
                FROM bettrans AS b WITH (nolock)
                     INNER JOIN #CommSetting AS cs ON b.MatchId = cs.MatchId
                     LEFT JOIN
                (
                    SELECT refno,
                           SUM(CASE
                                   WHEN BetType = 32
                                        AND liveawayscore = 0
                                   THEN 0
                                   ELSE stake * ISNULL(oddsspread, 0)
                               END) AS TOIBC,
                           -SUM((winlost - stake) * ISNULL(oddsspread, 0)) AS WLIBC,
                           SUM(CASE
                                   WHEN BetType = 32
                                        AND liveawayscore = 0
                                   THEN 0
                                   WHEN BetType = 31
                                        OR (BetType = 32
                                            AND liveawayscore <> 0)
                                   THEN stake * (1 - tpositiontaking - ISNULL(oddsspread, 0))
                                   ELSE 0
                               END) AS TOPhum
                    FROM bettransm WITH (nolock)
                    WHERE Bettype = @Bettype
                    GROUP BY refno
                ) AS bm ON b.transid = bm.refno
                WHERE b.winlostdate = @StartDate
                      AND b.BetType = @BetType
                      AND b.MatchId > 0
                      AND b.ruben = 1
                      AND b.statusID IN(111, 112, 113)
                GROUP BY cs.MeetingId,
                         cs.Race;
     END;
     BEGIN -- Query

         SELECT l.LeagueId AS GroupId,
                l.leaguename AS GroupName,
                d.Race AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover
         FROM #Data AS d
              INNER JOIN league AS l WITH (NOLOCK) ON l.LeagueId = d.LeagueId
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #CommSetting;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Racing_MatchDetail] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Racing_MatchDetail] TO [vnteam];
GO
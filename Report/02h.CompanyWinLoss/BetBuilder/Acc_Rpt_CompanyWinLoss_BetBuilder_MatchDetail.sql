/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_BetBuilder_MatchDetail] @StartDate SMALLDATETIME, 
                                                                      @EndDate   SMALLDATETIME, 
                                                                      @SportType SMALLINT,
                                                                      @BetType   INT           = 38, 
                                                                      @IsHedge   INT           = 2, -- Dummy Parameter
                                                                      @IsLive    INT           = 2-- Dummy Parameter
AS

/*
Creator: Jacob
Date: 2019-03-08
Task:  Integrate BetBuilder (#109822)
DB: DBACC/bodb02

Revisions:
- 20190313@Jacob: Integrate BetBuilder (#109822)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200722@Roy: Incorporate New Basketball Sport for BetBuilder Product - NAP Report (#138082)
Example:
EXEC [Acc_Rpt_CompanyWinLoss_BetBuilder_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @SportType =2, @BetType = 38

*/

     SET NOCOUNT ON;
    BEGIN -- #Match

        CREATE TABLE #Match
                     (MatchId   INT, 
                      MatchCode NVARCHAR(50), 
                      IsNeutral BIT, 
                      EventDate DATETIME, 
                      LeagueId  INT, 
                      HomeId    INT, 
                      AwayId    INT
                     );
        INSERT INTO #Match
               SELECT m.MatchId, 
                      m.MatchCode, 
                      m.IsNeutral, 
                      m.EventDate, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId
               FROM Match m WITH(NOLOCK)
					INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid
               WHERE m.EventDate = @StartDate
					AND l.sporttype = @SportType
				GROUP BY m.MatchId, 
                      m.MatchCode, 
                      m.IsNeutral, 
                      m.EventDate, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId
			   OPTION (RECOMPILE)
    END;
    BEGIN -- #Data	
        CREATE TABLE #Data
                     (MatchId         INT, 
                      MatchCode       VARCHAR(100), 
                      IsNeutral       BIT, 
                      EventDate       DATETIME, 
                      LeagueId        INT, 
                      HomeId          INT, 
                      AwayId          INT, 
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
               SELECT b.MatchId, 
                      m.MatchCode, 
                      ISNULL(m.IsNeutral, 0) AS IsNeutral, 
                      m.EventDate, 
                      m.LeagueId, 
                      m.HomeId, 
                      m.AwayId, 
                      SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                      SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate) Commission, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                  WHEN tpositiontaking = 1
                                                                                                  THEN 0
                                                                                                  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                              END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END) * virtualrate + (scomm - (CASE
                                                                                                                        WHEN tpositiontaking = 1
                                                                                                                        THEN 0
                                                                                                                        ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                    END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                                    WHEN virtualrate < actualrate
                                                                                                                                                                    THEN virtualrate / actualrate
                                                                                                                                                                    ELSE 1
                                                                                                                                                                END) VirtualIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END + CASE
                                                                                               WHEN virtualrate < actualrate
                                                                                               THEN(b.scomm - (CASE
                                                                                                                   WHEN tpositiontaking = 1
                                                                                                                   THEN 0
                                                                                                                   ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                               END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0))
                                                                                               ELSE 0
                                                                                           END) * (actualrate - virtualrate)) VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END) RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END) VirtualTurnover
               FROM bettrans b WITH(NOLOCK)
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.bettype = @BetType
                     AND b.ruben = 1
                     AND statusID IN(111, 112, 113)
               GROUP BY b.MatchId, 
                        m.MatchCode, 
                        m.IsNeutral, 
                        m.HomeId, 
                        m.AwayId, 
                        m.EventDate, 
                        m.LeagueId OPTION(RECOMPILE);
    END;
    BEGIN -- Query

        SELECT d.MatchId, 
               d.MatchCode, 
               d.IsNeutral, 
               d.EventDate, 
               @SportType SportType, 
               d.LeagueId, 
               d.HomeId, 
               d.AwayId, 
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
        ORDER BY LeagueId, 
                 MatchCode;
    END;

    DROP TABLE #Match;
    DROP TABLE #Data;
GO
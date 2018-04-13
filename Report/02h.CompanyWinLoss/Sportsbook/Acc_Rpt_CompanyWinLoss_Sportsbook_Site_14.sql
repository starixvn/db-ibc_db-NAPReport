IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @SportType SMALLINT,
       @BetType   INT,
       @IsHedge   INT = 2,
       @IsLive    INT = 2,
       @Site      VARCHAR(20)
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
@IsHedge: 2 - ALL. 0 - Non-Hedge. 1 - Hedge

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 1, @BetType = 1, @IsHedge=0, @IsLive=2,  @Site = 'Credit'
*/

     SET NOCOUNT ON;
    BEGIN -- #Agent

        CREATE TABLE #Agent( CustId INT PRIMARY KEY,
                             Site   NVARCHAR(50));
        IF @Site = 'Deposit'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND c.CustId NOT IN( 52466, 5707545 )
                         AND EXISTS( 
                                     SELECT 1
                                     FROM f_DepSuper_1( 'All' ) dep
                                     WHERE c.srecommend = dep.CustId );
                INSERT INTO #Agent
                       SELECT 5707545,
                              'BEST-ODDS'; --BARM
            END;
        ELSE
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND c.CustId NOT IN( 52466, 5707545 )
                         AND NOT EXISTS( 
                                         SELECT 1
                                         FROM f_DepSuper_1( 'All' ) dep
                                         WHERE c.srecommend = dep.CustId );
                INSERT INTO #Agent
                       SELECT 52466,
                              'XYZBET';--8RM;
            END;
    END;
    BEGIN -- Match
        CREATE TABLE #Match( MatchId INT,
                             type    VARCHAR(10),
                             PRIMARY KEY( MatchId, type ));
        INSERT INTO #Match
               SELECT m.MatchId,
                      m.type
               FROM(
                   SELECT MatchId,
                          LeagueId,
                          'match' AS type
                   FROM match14 WITH ( nolock )
                   WHERE @BetType <> 10
                     AND EventDate = @StartDate
                     AND ( @IsHedge = 2
                        OR ( @IsHedge = 1
                         AND MatchCode LIKE '%Hedge%'
                           )
                        OR ( @IsHedge = 0
                         AND MatchCode NOT LIKE '%Hedge%'
                           )
                         )
                   UNION ALL
                   SELECT orid,
                          LeagueId,
                          'outright' AS type
                   FROM outright14 WITH ( nolock )
                   WHERE @BetType = 10
                     AND EventDate = @StartDate ) m
                   INNER JOIN league l WITH ( nolock ) ON m.LeagueId = l.LeagueId
                   INNER JOIN sports sp WITH ( nolock ) ON l.sporttype = sp.sporttype
               WHERE sp.sporttype = @sporttype;
    END;
    BEGIN -- #Data

        CREATE TABLE #Data( RowName         NVARCHAR(50),
                            MemberWinLoss   MONEY,
                            SMAWinLoss      MONEY,
                            Commission      MONEY,
                            RealIncome      MONEY,
                            VirtualIncome   MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- INSERT INTO #Data
        INSERT INTO #Data
               SELECT ag.site RowName,
                      SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
                      SUM(scomm * actualrate) Commission,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * actualrate) RealIncome,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm ) * virtualrate) VirtualIncome,
                      SUM(( 1 - tpositiontaking ) * ABS(stake) * actualrate) RealTurnover,
                      SUM(( 1 - tpositiontaking ) * ABS(stake) * virtualrate) VirtualTurnover
               FROM bettrans14 b WITH ( NOLOCK )
                    INNER JOIN #Agent ag ON b.recommend = ag.custid
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                 AND b.BetType = @BetType
                 AND ( @IsLive > 1
                    OR b.liveindicator = @IsLive
                     )
                 AND m.type = CASE
                                  WHEN b.BetType = 10
                                  THEN 'outright'
                                  ELSE 'match'
                              END
                 AND b.ruben = 1
                 AND b.statusID IN( 111, 112, 113 )
               GROUP BY ag.site;
    END;
    BEGIN -- Query

        SELECT d.RowName,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.VirtualIncome AS VirtualIncome,
               d.RealIncome - d.VirtualIncome AS VarianceIncome,
               d.RealTurnover AS RealTurnover,
               d.VirtualTurnover AS VirtualTurnover
        FROM #Data AS d
        ORDER BY RowName;
    END;
        DROP TABLE #Agent;
        DROP TABLE #Match;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site_14] TO [vnteam];
GO
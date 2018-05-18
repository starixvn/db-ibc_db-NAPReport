USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Sportsbook_Site    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site]
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
- 20180413@Franklin: hotfix [#93594]
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
@IsHedge: 2 - ALL. 0 - Non-Hedge. 1 - Hedge

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 1, @BetType = 1, @IsHedge=0, @IsLive=2,  @Site = 'Credit'
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
                   FROM Match WITH ( nolock )
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
                   FROM outright WITH ( nolock )
                   WHERE @BetType = 10 
				   AND EventDate = @StartDate ) m
                   INNER JOIN league l WITH ( nolock ) ON m.LeagueId = l.LeagueId
                   INNER JOIN sports sp WITH ( nolock ) ON l.sporttype = sp.sporttype
               WHERE sp.sporttype = @sporttype;
    END;
    BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
								   Sporttype  INT,
                                   ExtraPT DECIMAL(9, 8));
		DECLARE @sport INT = 0;
        SELECT @sport = CASE WHEN @SportType = 44 THEN 44 ELSE 0 END
        INSERT INTO #ExtraPT_Sel
               ( SuperID,
			     Sporttype,
                 ExtraPT
               )
               SELECT SuperId,Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = 1
                 AND a.SubProduct NOT IN( 'MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss' )
				 AND a.Sporttype = @sport
               GROUP BY SuperId,Sporttype;
    END;
    BEGIN -- #Data
	

        CREATE TABLE #Data( RowName         NVARCHAR(50),
                            MemberWinLoss   MONEY,
                            SMAWinLoss      MONEY,
							ExtraPT         MONEY,
                            Commission      MONEY,
                            RealIncome      MONEY,
                            VirtualIncome   MONEY,
							VarianceIncome  MONEY,
                            RealTurnover    MONEY,
                            VirtualTurnover MONEY );
    END;
    BEGIN -- INSERT INTO #Data
        INSERT INTO #Data
               SELECT ag.site RowName,
                      SUM(( winlost - actual_stake ) * actualrate) MemberWinLoss,
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
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
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate) RealIncome,
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                    WHEN tpositiontaking = 1
                                                                                    THEN 0
                                                                                    ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
                                                                                END ) * virtualrate + ( scomm - ( CASE
                                                                                                                    WHEN tpositiontaking = 1
                                                                                                                    THEN 0
                                                                                                                    ELSE b.scomm / ( 1 - b.tpositiontaking )
                                                                                                                END ) * ISNULL(e.ExtraPT, 0)
																										) * actualrate * CASE WHEN virtualrate < actualrate THEN virtualrate / actualrate ELSE 1 END 
					) VirtualIncome,
					SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE WHEN tpositiontaking = 1 THEN 0 ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0) END
					+ CASE WHEN virtualrate < actualrate THEN (b.scomm -  (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) END) * ISNULL(e.ExtraPT, 0)) ELSE 0 END															  
																				) * (actualrate - virtualrate)) VarianceIncome,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END) RealTurnover,
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
                          END) VirtualTurnover
               FROM bettrans b WITH ( NOLOCK )
                    INNER JOIN #Agent ag ON b.recommend = ag.custid
                    INNER JOIN #Match m ON b.MatchId = m.MatchId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
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
        DROP TABLE #Match;
        DROP TABLE #Data;
        DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Sportsbook_Site] TO [vnteam];
GO
USE [bodb02];
GO
IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14]
       @StartDate SMALLDATETIME,
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
- 20170720@Franklin: Add Betradar Virtual Sports (78495)
- 20180323@Franklin: Betradar Virtual Sports (phase 2) (91098)
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 190, @BetType = 2700
*/

     SET NOCOUNT ON;
	 BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
                                   ExtraPT DECIMAL(9, 8));
        INSERT INTO #ExtraPT_Sel
               ( SuperID,
                 ExtraPT
               )
               SELECT SuperId,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = 27
               GROUP BY SuperId;
    END;
    BEGIN
        CREATE TABLE #Data( LeagueId      INT,
                            MatchId       INT,
                            MatchCode     NVARCHAR(50),
                            HomeId        INT,
                            AwayId        INT,
                            MemberWinLoss MONEY,
                            SMAWinLoss    MONEY,
                            Commission    MONEY,
                            RealIncome    MONEY,
                            RealTurnover  MONEY );
        INSERT INTO #Data
               SELECT m.leagueid,
                      m.matchid,
                      m.matchcode,
                      m.homeid,
                      m.awayid,
                      SUM(( winlost - actual_stake ) * actualrate),
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate),
                      SUM(scomm * actualrate),
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                END ) * ISNULL(e.ExtraPT, 0)) * actualrate),
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                       WHEN virtualrate / actualrate - 1 > 0
                                                                                                       THEN virtualrate
                                                                                                       ELSE actualrate
                                                                                                   END
                          END)
               FROM bettrans14 AS b WITH ( nolock )
                    INNER JOIN match14 AS m WITH ( nolock ) ON b.MatchId = m.MatchId
					LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
               WHERE b.winlostdate = @StartDate
                 AND b.bettype = @BetType
                 AND m.sporttype = @SportType
                 AND b.matchid > 0
                 AND b.ruben = 1
                 AND statusID IN( 111, 112, 113 )
               GROUP BY m.matchid,
                        m.matchcode,
                        m.homeid,
                        m.awayid,
                        m.leagueid
               ORDER BY m.leagueid,
                        m.matchcode,
                        m.homeid,
                        m.awayid;
    END;
    BEGIN -- Query
        SELECT d.MatchId,
               d.MatchCode,
               d.HomeId,
               d.AwayId,
               d.LeagueId,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.RealTurnover AS RealTurnover
        FROM #Data d;
    END;
	    DROP TABLE #ExtraPT_Sel;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_14] TO [vnteam];
GO
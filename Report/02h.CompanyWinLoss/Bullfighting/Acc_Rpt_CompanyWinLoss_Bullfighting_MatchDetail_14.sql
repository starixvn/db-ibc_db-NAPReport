USE [bodb02];
GO
IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @SportType SMALLINT,
       @BetType   INT
AS

/*
Creator: Franklin
Date: 2017-11-02
Task:  Bullfighting - Implement Company Winloss By Products report [#85382]
DB: DBACC/bodb02

Revisions:
- 20171102@Franklin: Bullfighting(#85382)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14] @SportType=207, @BetType=1004, @StartDate='2017-11-01', @EndDate='2018-12-31'
*/

     SET NOCOUNT ON;
    BEGIN
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
                 AND a.ProductId = 30
                 AND a.Sporttype = @SportType
               GROUP BY SuperId;
        CREATE TABLE #Data( LeagueId      INT,
                            LeagueCode    NVARCHAR(50),
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
               SELECT m.League3rdId,
                      l.LeagueCode,
                      m.Match3rdId,
                      m.MatchNo,
                      m.HomeId,
                      m.AwayId,
                      SUM(( winlost - actual_stake ) * actualrate),
                      SUM(( awinlost + mwinlost + swinlost ) * actualrate),
                      SUM(scomm * actualrate),
                      SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                                    WHEN tpositiontaking = 1
                                                                                                    THEN 0
                                                                                                    ELSE winlost - actual_stake + b.scomm / 1 - b.tpositiontaking
                                                                                                END ) * e.ExtraPT ) * actualrate),
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
                    INNER JOIN Match3rd AS m WITH ( nolock ) ON b.MatchId = m.Match3rdId
                    INNER JOIN dbo.League3rd AS l WITH ( NOLOCK ) ON m.League3rdId = l.League3rdId
                    LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
               WHERE b.winlostdate = @StartDate
                 AND b.BetType = @BetType
                 AND m.SportType = @SportType
                 AND b.MatchId > 0
                 AND b.ruben = 1
                 AND statusID IN( 111, 112, 113 )
               GROUP BY m.Match3rdId,
                        m.MatchNo,
                        m.League3rdId,
                        l.LeagueCode,
                        m.HomeId,
                        m.AwayId
               ORDER BY m.League3rdId,
                        m.MatchNo;
    END;
    BEGIN -- Query
        SELECT d.LeagueId AS LeagueId,
               d.LeagueCode AS LeagueCode,
               d.MatchId AS MatchId,
               d.MatchCode AS MatchCode,
               d.HomeId AS HomeId,
               d.AwayId AS AwayId,
               d.MemberWinLoss AS MemberWinLoss,
               d.SMAWinLoss AS SMAWinLoss,
               d.Commission AS Commission,
               d.RealIncome AS RealIncome,
               d.RealTurnover AS RealTurnover
        FROM #Data d;
    END;
        DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Bullfighting_MatchDetail_14] TO [vnteam];
GO
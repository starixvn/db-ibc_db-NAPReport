/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] @StartDate SMALLDATETIME, 
                                                                      @EndDate   SMALLDATETIME, 
                                                                      @LeagueId  INT, 
                                                                      @BetType   INT
AS

/*
Creator: Jacob
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20181217@Robert: #104253 - NAP Report - Add new sporttype for Happy 5
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Example:
    EXEC [Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail] @BetType=81, @LeagueId=15223, @StartDate='2016-01-01', @EndDate='2020-01-01'
*/

	SET NOCOUNT ON;
    
    BEGIN -- #Data

        CREATE TABLE #Data
                     (LeagueId      INT, 
                      MatchCode     NVARCHAR(50), 
                      MemberWinLoss MONEY, 
                      SMAWinLoss    MONEY, 
                      ExtraPT       MONEY, 
                      Commission    MONEY, 
                      RealIncome    MONEY, 
                      RealTurnover  MONEY
                     );
    END;
    BEGIN -- Insert Into #Data

        INSERT INTO #Data
               SELECT m.LeagueId, 
                      m.MatchCode, 
                      SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
                      SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                      SUM((CASE
                               WHEN b.tpositiontaking = 1
                               THEN 0
                               ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                           END) * ISNULL(b.epositiontaking, 0) * actualrate) AS ExtraPT, 
                      SUM(scomm * actualrate) Commission, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                  WHEN tpositiontaking = 1
                                                                                                  THEN 0
                                                                                                  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                              END) * ISNULL(b.epositiontaking, 0)) * actualrate) AS RealIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * b.stake * CASE
                                                                                                 WHEN virtualrate > actualrate
                                                                                                 THEN virtualrate
                                                                                                 ELSE actualrate
                                                                                             END
                          END) AS RealTurnover
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND m.leagueid = @LeagueId
                     AND b.BetType = @BetType
                     AND b.MatchId > 0
                     AND b.ruben = 1
                     AND statusID IN(111, 112, 113)
               GROUP BY m.MatchCode, 
                        m.LeagueId;
    END;
    BEGIN -- Query      

        SELECT l.leaguename AS GroupName, 
               d.MatchCode AS RowName, 
               d.MemberWinLoss, 
               d.SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission, 
               d.RealIncome, 
               d.RealTurnover
        FROM #Data AS d
             INNER JOIN league AS l WITH(NOLOCK) ON l.LeagueId = d.LeagueId
        ORDER BY GroupName, 
                 RowName;
    END;
    
	DROP TABLE #Data;
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14] @StartDate SMALLDATETIME,
                                                                      @EndDate   SMALLDATETIME,
                                                                      @ProductId SMALLINT,
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
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 181
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
                FROM dbo.f_SportBetTypeMatrix_Sel(@ProductId, @SportType, 0, 2, '', '', @isTest) s
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
     IF EXISTS -- Virtual Sportsbook
     (
         SELECT 1
         FROM #SportBetType
         WHERE EventType = 1
     )
         BEGIN
             SELECT sb.BetType AS GroupId,
                    sb.BetTypeName AS GroupName,
                    CASE
                        WHEN dep.CustId IS NULL
                        THEN 'Credit'
                        ELSE 'Deposit'
                    END AS RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    SUM(scomm * actualrate) Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                    SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  INNER JOIN match14 AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
             WHERE b.winlostdate = @StartDate
                   AND m.sporttype = @SportType
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
     ELSE -- Virtual Racing
         BEGIN
             SELECT sb.BetType AS GroupId,
                    sb.BetTypeName AS GroupName,
                    CASE
                        WHEN dep.CustId IS NULL
                        THEN 'Credit'
                        ELSE 'Deposit'
                    END AS RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    SUM(scomm * actualrate) Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                    SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
             FROM bettrans14 AS b WITH (NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  INNER JOIN VSRaceInfo AS r WITH (NOLOCK) ON r.EventId = b.MatchId
             WHERE b.winlostdate = @StartDate
                   AND r.sporttype = @SportType
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
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_14] TO [vnteam];
GO
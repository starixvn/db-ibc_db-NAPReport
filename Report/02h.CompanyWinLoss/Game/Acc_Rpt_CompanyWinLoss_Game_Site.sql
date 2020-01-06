/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Game_Site @StartDate SMALLDATETIME, 
                                                     @EndDate   SMALLDATETIME, 
                                                     @BetType   INT, 
                                                     @Site      VARCHAR(50)
AS

/*
Creator: Franklin
Date: 2016-02-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report
- 20160720@Sophia: . Revise SP. Not use @EndDate because we get only one day on (bettrans/bettrans14 range)
- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 2018.06.04@Dominic: Force to recompile (#96143)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190326@Robert: #109981 - NAP Report - Integrate Promotion Prize
- 20190925@Jacob: Group By CN88 (#118824)
- 20191118@Ned.Le: Integrate Pragmatic Tournament Prize (#123685)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_Site] @BetType = 2101,@EndDate='2020-01-01',@Site = 'Credit',@StartDate='2016-01-01'
*/

     SET NOCOUNT ON;
	BEGIN --#PrizeBettypeGroup
		CREATE TABLE #PrizeBettypeGroup (Bettype SMALLINT)
		INSERT INTO #PrizeBettypeGroup
		SELECT Bettype FROM DBWH.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID=6
	END;
    BEGIN -- #SportBetType

        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
        (ProductID INT, 
         BetType   INT, 
         RefTable  INT
        );
        INSERT INTO #SportBetType
               SELECT ProductID, 
                      BetType, 
                      RefTable
               FROM bodb02.dbo.f_SportBetTypeMatrix_Sel(0, 0, @BetType, 2, '', '', @isTest);
    END;
    BEGIN -- #Agent
        CREATE TABLE #Agent
        (CustId INT
         PRIMARY KEY, 
         Site   VARCHAR(50)
        );
        IF @Site = 'CN88'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId, 
                              c.Site
                       FROM customer AS c WITH(NOLOCK)
                            INNER JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                       WHERE c.RoleID = 2;
        END;
            ELSE
            IF @Site = 'Deposit'
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                INNER JOIN Dep_CustSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545);
                    INSERT INTO #Agent
                           SELECT 5707545, 
                                  'BEST-ODDS';
            END;
                ELSE
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                LEFT JOIN Dep_CustSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                                LEFT JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545)
                                AND dep.CustId IS NULL
                                AND cn88.CustId IS NULL;
                    INSERT INTO #Agent
                           SELECT 52466, 
                                  'XYZBET';--8RM;
            END;
    END;
    BEGIN -- #Data
        CREATE TABLE #Data
        (RowName       NVARCHAR(50), 
         MemberWinLoss MONEY, 
         SMAWinLoss    MONEY, 
         ExtraPT       MONEY, 
         Commission    MONEY, 
         RealIncome    MONEY, 
         RealTurnover  MONEY
        );
    END;
     IF EXISTS
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable NOT IN(1, 2)
         AND BetType = @BetType
     )
         BEGIN -- bettrans
             INSERT INTO #Data
                    SELECT dep.Site AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                           SUM(CASE
                                   WHEN b.tpositiontaking = 1
                                   THEN 0
                                   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                               END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
                           SUM(scomm * actualrate) AS Commission, 
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                      WHEN tpositiontaking = 1
                                                                                                      THEN 0
                                                                                                      ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                  END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) AS RealTurnover
                    FROM bettrans AS b WITH(NOLOCK)
                         INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                    WHERE b.winlostdate = @StartDate
                          AND b.BetType = @BetType
                          AND b.ruben = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site OPTION(RECOMPILE);
     END;
     IF EXISTS
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 1
               AND BetType = @BetType
     )
         BEGIN -- bettransRNG
             INSERT INTO #Data
                    SELECT dep.Site AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                           SUM(CASE
                                   WHEN b.gameId IN(2198, 2398, 2998)
                                   THEN CASE
                                            WHEN tpositiontaking = 1
                                            THEN 0
                                            ELSE b.ContributionRate * b.BetStake + b.scomm / (1 - b.tpositiontaking)
                                        END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                   WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
                                   ELSE CASE
                                            WHEN tpositiontaking = 1
                                            THEN 0
                                            ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                        END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                               END * actualrate) AS ExtraPT, 
                           SUM(scomm * actualrate) AS Commission, 
                           SUM(CASE
                                   WHEN b.gameId IN(2198, 2398, 2998)
                                   THEN b.ContributionRate * b.BetStake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                                       WHEN tpositiontaking = 1
                                                                                                                       THEN 0
                                                                                                                       ELSE b.ContributionRate * b.BetStake + b.scomm / (1 - b.tpositiontaking)
                                                                                                                   END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                   WHEN bg.Bettype IS NOT NULL THEN 0 /*Progressive Jackpot, PP Promotion Prize, PP Tournament Prize*/
                                   ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                              WHEN tpositiontaking = 1
                                                                                                              THEN 0
                                                                                                              ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                          END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                               END * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) AS RealTurnover
                    FROM bettransRNG AS b WITH(NOLOCK)
                         INNER JOIN #Agent AS dep ON b.recommend = dep.custid
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.gameId
						 LEFT JOIN #PrizeBettypeGroup bg ON b.gameID = bg.Bettype
                    WHERE b.winlostdate = @StartDate
                          AND b.gameId = @BetType
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site OPTION(RECOMPILE);
     END;
     IF EXISTS
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 2
               AND BetType = @BetType
     )
         BEGIN -- bettransLC
             INSERT INTO #Data
                    SELECT dep.Site AS RowName, 
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
                           SUM(CASE
                                   WHEN b.tpositiontaking = 1
                                   THEN 0
                                   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                               END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
                           SUM(scomm * actualrate) AS Commission, 
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                      WHEN tpositiontaking = 1
                                                                                                      THEN 0
                                                                                                      ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                                  END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
                           SUM(CASE
                                   WHEN tpositiontaking = 1
                                   THEN 0
                                   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                               END) AS RealTurnover
                    FROM bettransLC AS b WITH(NOLOCK)
                         INNER JOIN #Agent AS dep ON b.recommend = dep.custid
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.gameId
                    WHERE b.winlostdate = @StartDate
                          AND b.gameId = @BetType
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY dep.Site OPTION(RECOMPILE);
     END;
    BEGIN -- Query

        SELECT d.RowName AS RowName, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.RealTurnover AS RealTurnover
        FROM #Data AS d
        ORDER BY RowName;
    END;
    
	DROP TABLE #SportBetType;
    DROP TABLE #Agent;
    DROP TABLE #Data;
	DROP TABLE #PrizeBettypeGroup;
GO
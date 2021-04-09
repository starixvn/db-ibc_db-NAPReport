/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Sportsbook_Site @StartDate SMALLDATETIME, 
                                                           @EndDate   SMALLDATETIME, 
                                                           @SportType SMALLINT, 
                                                           @BetType   INT, 
                                                           @IsHedge   INT           = 2, 
                                                           @IsLive    INT           = 2,
														   @IsSabaSport TINYINT = 0,
														   @IsNoDraw BIT = 0, 
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
- 20180419@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190401@Kean: Improve performance for House Win Loss by Product (#106315)
- 20190313@Jacob: Integrate BetBuilder (#109822)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20201222@Kean: Support to filter NoDraw and separate the SABA sports - NAP Report (#147451)
- 20210323@Kean: Daily Win Loss (2h) Soccer Minor Bet Types do not use @IsSabaSport parameter (#152100)
- 20210326@Kean: HotFix, Missing data when league.LeagueGroupId is NULL - NAP Report (#152390)
- 20212203@Jaden: Support SABA789 (#151326)

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
@IsHedge: 2 - ALL. 0 - Non-Hedge. 1 - Hedge
@IsSabaSport: 2 - ALL. 0 - Non-SABA. 1 - SABA 

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Sportsbook_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 1, @BetType = 1, @IsHedge=0, @IsLive=2,  @Site = 'Credit'
*/

     SET NOCOUNT ON;
    BEGIN -- #Agent
        CREATE TABLE #Agent
        (CustId INT
         PRIMARY KEY, 
         Site   VARCHAR(50)
        );
    
        CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
        INSERT INTO #DepositSuper
            SELECT custid FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);

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
                                INNER JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
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
                                LEFT JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
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
	BEGIN -- #SABALeagueGroup
		DECLARE @LeagueGroupStr VARCHAR(500);
		CREATE TABLE #SABALeagueGroup(LeagueGroupID INT)
		SELECT @LeagueGroupStr = [VValue] FROM DBWH.[bodb_Account].[dbo].[SystemSettings] WHERE VID = 5

		INSERT INTO #SABALeagueGroup
		SELECT val FROM dbo.strSplit(@LeagueGroupStr,',')
	END;
    BEGIN -- Match
        CREATE TABLE #Match
        (MatchId INT
         PRIMARY KEY
        );
        IF @BetType = 10
            BEGIN
                INSERT INTO #Match
                       SELECT DISTINCT 
                              m.MatchId
                       FROM
                       (
                           SELECT orid AS MatchId, 
                                  LeagueId
                           FROM outright WITH(NOLOCK)
                           WHERE @BetType = 10
                                 AND EventDate = @StartDate
                       ) AS m
                       INNER JOIN league AS l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
                       WHERE l.sporttype = @sporttype
						   AND (@IsSabaSport = 2
						   OR (@IsSabaSport = 0 AND (l.LeagueGroupID NOT IN (SELECT LeagueGroupID FROM #SABALeagueGroup) OR l.LeagueGroupID IS NULL) ) 
							OR (@IsSabaSport = 1 AND l.LeagueGroupID IN (SELECT LeagueGroupID FROM #SABALeagueGroup))
						);
        END;
            ELSE
            BEGIN
                INSERT INTO #Match
                       SELECT DISTINCT 
                              m.MatchId
                       FROM
                       (
                           SELECT MatchId, 
                                  LeagueId
                           FROM Match WITH(NOLOCK)
                           WHERE @BetType <> 10
                                 AND EventDate = @StartDate
                                 AND (@IsHedge = 2
                                      OR @IsHedge = 1
                                      AND MatchCode LIKE '%Hedge%'
                                      OR @IsHedge = 0
                                      AND MatchCode NOT LIKE '%Hedge%')
                       ) AS m
                       INNER JOIN league AS l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
                       WHERE l.sporttype = @sporttype
						   AND (@IsSabaSport = 2
						    OR (@IsSabaSport = 0 AND (l.LeagueGroupID NOT IN (SELECT LeagueGroupID FROM #SABALeagueGroup) OR l.LeagueGroupID IS NULL) ) 
							OR (@IsSabaSport = 1 AND l.LeagueGroupID IN (SELECT LeagueGroupID FROM #SABALeagueGroup))
						);
        END;
    END;
    BEGIN  --#Data
        CREATE TABLE #Data
        (RowName         NVARCHAR(50), 
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
               SELECT ag.site AS RowName, 
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
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END) * virtualrate + (scomm - CASE
                                                                                                                       WHEN tpositiontaking = 1
                                                                                                                       THEN 0
                                                                                                                       ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                                   END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                                  WHEN virtualrate < actualrate
                                                                                                                                                                  THEN virtualrate / actualrate
                                                                                                                                                                  ELSE 1
                                                                                                                                                              END) AS VirtualIncome, 
                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                     END + CASE
                                                                                               WHEN virtualrate < actualrate
                                                                                               THEN b.scomm - CASE
                                                                                                                  WHEN tpositiontaking = 1
                                                                                                                  THEN 0
                                                                                                                  ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                              END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                                               ELSE 0
                                                                                           END) * (actualrate - virtualrate)) AS VarianceIncome, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                                      WHEN virtualrate > actualrate
                                                                                                      THEN virtualrate
                                                                                                      ELSE actualrate
                                                                                                  END
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) AS RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END *
							CASE WHEN @IsNoDraw = 1 
								THEN CASE WHEN (b.bettype < 999 OR b.bettype BETWEEN 1301 AND 1399 OR b.bettype BETWEEN 9001 AND 9399) --SportBooks
												AND b.bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
												AND b.bettype NOT BETWEEN 81 AND 120 --exclude number game
												AND ABS(modds) = 0.25 --to identify Half won/lost tickets
										THEN 0.5
									ELSE 1 END
								ELSE 1 END) AS VirtualTurnover
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN #Agent AS ag ON b.recommend = ag.custid
                    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.BetType = @BetType
                     AND (@IsLive > 1
                          OR b.liveindicator = @IsLive)
                     AND b.ruben = 1
                     AND ((@IsNoDraw = 0 AND b.statusID IN(111, 112, 113)) OR (@IsNoDraw = 1 AND statusID IN (112, 113)))
               GROUP BY ag.site OPTION(RECOMPILE);
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
	DROP TABLE #SABALeagueGroup;
    DROP TABLE #DepositSuper;
GO
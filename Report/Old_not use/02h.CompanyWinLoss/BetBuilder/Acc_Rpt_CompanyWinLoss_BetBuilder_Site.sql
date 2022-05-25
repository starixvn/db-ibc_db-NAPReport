USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_BetBuilder_Site @StartDate SMALLDATETIME, 
                                                           @EndDate   SMALLDATETIME, 
                                                           @SportType   INT,
                                                           @BetType     INT           = 38, 
                                                           @IsHedge     INT           = 2, -- Dummy Parameter
                                                           @IsCorners INT             = 2, -- Dummy Parameter
                                                           @IsLive      INT           = 2, -- Dummy Parameter
														   @IsSabaSport BIT           = 0, -- Dummy Parameter
														   @IsNoDraw    BIT           = 0, -- Dummy Parameter
                                                           @Site        VARCHAR(20)
AS

/*
Creator: Jacob
Date: 2019-03-13
Task:  Integrate BetBuilder (#109822)
DB: DBACC/bodb02

Revisions:
- 20190313@Jacob: Integrate BetBuilder (#109822)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200722@Roy: Incorporate New Basketball Sport for BetBuilder Product - NAP Report (#138082)
- 20210223@Ned.Le: Nap Reports - House Winloss By Product - HotFix (#150511)
- 20212203@Jaden: Support SABA789 (#151326)
- 20220415@Ned.Le: Missing parameter @isCorners in House WL by product report (HotFix #171542)

Parameters:

Example:
EXEC [Acc_Rpt_CompanyWinLoss_BetBuilder_Site] @EndDate='2019-03-03',@StartDate='2019-03-12', @Site = 'Credit'

*/

     SET NOCOUNT ON;
    BEGIN -- #Agent

        CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
        INSERT INTO #DepositSuper
            SELECT custid FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);

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
	BEGIN -- #Match
        CREATE TABLE #Match
                     ( MatchId INT )
        INSERT INTO #Match
               SELECT DISTINCT m.MatchId
               FROM Match m WITH(NOLOCK)
					INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid
               WHERE m.EventDate = @StartDate
					AND l.sporttype = @SportType
			   OPTION (RECOMPILE)
    END;
    BEGIN -- #Data

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
                          END) AS RealTurnover, 
                      SUM(CASE
                              WHEN tpositiontaking = 1
                              THEN 0
                              ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                          END) AS VirtualTurnover
               FROM bettrans AS b WITH(NOLOCK)
                    INNER JOIN #Agent AS ag ON b.recommend = ag.custid
					INNER JOIN #Match m ON b.MatchId = m.MatchId
               WHERE b.winlostdate = @StartDate
                     AND b.bettype = @BetType
                     AND b.ruben = 1
                     AND b.statusID IN(111, 112, 113)
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
    DROP TABLE #Data;
	DROP TABLE #Match;
    DROP TABLE #DepositSuper;
GO
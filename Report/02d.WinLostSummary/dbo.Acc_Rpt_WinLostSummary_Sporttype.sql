USE [bodb_Report];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostSummary_Sporttype] @fromdate DATETIME,
                                                         @todate   DATETIME
AS
    

    /*

        Created: Johnson
        Date: 2013-06-20
        Task: summary winlost by sporttype
        DB: DBRPT/bodb_Report
        Revisions:
            - 20130822@Johnson: change to use rptWinlost instead rptWinlost2
            - 20131206@Kathy: Add HR Fixed Odds (154) [Redmine:#6505]
		  - 20140327@Dom: Add Keno
		  - 20150525@Jim: apply sport& bettype matrix and also support GoldDeluxe & Metric Gaming (#35359 & #28309 )
		  - 20150710@Jim: Super Balance fix and Microgaming integration (feature #38168 )
		  - 20150723@Jim: Apply Bettrade [#38815]
		  - 20150828@Jim: support Colossus Bet (#42608)
		  - 20150921@Jim: support MO (#41935)
		  - 20151020@Sophia: Fix bug missing Outright data [#30661]
		  - 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
		  - 20151210@Percy: Add new product: Cockfighting Sabong [Redmine: #49027]
		  - 20160112@Percy: Expand new bettype for RNG Casino [Redmine: #49134]
		  - 20160225@Jim: offer  Allbet Live Casino [Redmine:#50921)]
		  - 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sporttype, bettye matrix function, change the way to get data Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
		  - 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		  - 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
		  - 20160913@Percy: [RedmineID: #59840]
			 1. Include hedge match of 8RM account 
			 2. Left join #TempMatch to include data bettrade
		  - 20160916@Robert: Integrate new product NG2 [RedmindID: #63460]
		  - 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
		  - 20170323@Robert: NAP Reports - Integrate Cash out [RedmindID: #73419]
		  - 20170615@Tom: NAP Reports - Integrate Keno Lottery [RedmindID: #78184] 
					   NAP Reports - Integrate Betradar Virtual Sports[RedmindID: #78495] 
		  - 20170816@Logan:  NAP Reports - Integrate Lucky 3 [RedmindID: #81733]
		  - 20171110@Robert: NAP Reports - Integrate Bullfighting [RedmindID: #85383]



        Parameter's Explanation:

    */



     BEGIN
         SET NOCOUNT ON;

         ----Get Sport Bettype Matrix------

         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         DECLARE @SportBettype TABLE
         (ProductID     INT,
          Bettype       INT,
          EventType     INT,
          SubProduct    VARCHAR(500),
          SortKey       INT,
          liveindicator BIT
         );
         INSERT INTO @SportBettype
         (ProductID,
          Bettype,
          EventType,
          SubProduct
         )
                SELECT ProductID,
                       Bettype,
                       EventType,
                       SubProduct
                FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);
         UPDATE @SportBettype
           SET
               liveindicator = 0;
         INSERT INTO @SportBettype
         (ProductID,
          Bettype,
          EventType,
          SubProduct,
          liveindicator
         )
                SELECT ProductID,
                       Bettype,
                       EventType,
                       SubProduct,
                       1 AS liveindicator
                FROM @SportBettype
                WHERE liveindicator = 0;
         UPDATE @SportBettype
           SET
               SortKey = CASE
                             WHEN Bettype = 1
                                  AND liveindicator = 0
                             THEN 1
                             WHEN Bettype = 301
                                  AND liveindicator = 0
                             THEN 2
                             WHEN Bettype = 1
                                  AND liveindicator = 1
                             THEN 3
                             WHEN Bettype = 301
                                  AND liveindicator = 1
                             THEN 4
                             WHEN Bettype = 3
                                  AND liveindicator = 0
                             THEN 5
                             WHEN Bettype = 302
                                  AND liveindicator = 0
                             THEN 6
                             WHEN Bettype = 3
                                  AND liveindicator = 1
                             THEN 7
                             WHEN Bettype = 302
                                  AND liveindicator = 1
                             THEN 8
                             WHEN Bettype = 7
                                  AND liveindicator = 0
                             THEN 9
                             WHEN Bettype = 303
                                  AND liveindicator = 0
                             THEN 10
                             WHEN Bettype = 7
                                  AND liveindicator = 1
                             THEN 11
                             WHEN Bettype = 303
                                  AND liveindicator = 1
                             THEN 12
                             WHEN Bettype = 8
                                  AND liveindicator = 0
                             THEN 13
                             WHEN Bettype = 304
                                  AND liveindicator = 0
                             THEN 14
                             WHEN Bettype = 8
                                  AND liveindicator = 1
                             THEN 15
                             WHEN Bettype = 304
                                  AND liveindicator = 1
                             THEN 16
                             ELSE 17
                         END;
         DECLARE @_fromdate DATETIME, @_todate DATETIME;
         SELECT @_fromdate = @fromdate,
                @_todate = @todate;
         CREATE TABLE #TempMatch
         (matchid   INT,
          matchcode VARCHAR(50),
          EventType TINYINT
         --0: Can't join with any table 
         --1: Match
         --2: Outright
         --3: VSOutright/VSRaceInfo
         --4: DW
         --5: Match3rd
         );
         CREATE TABLE #TempData
         (sporttype        INT,
          bettype          INT,
          liveindicator    BIT,
          ibc              INT,
          IsHedge          BIT,
          status           VARCHAR(10),
          OrderKey         INT,
          SortKey          INT,
          realWinlost      MONEY,
          realPosition     MONEY,
          realCommission   MONEY,
          realLineTotal    MONEY,
          virtualLineTotal MONEY,
          realTurnover     MONEY,
          virtualTurnover  MONEY
         );
         DECLARE @movebetdate DATETIME, @balanceupdate DATETIME, @f_date DATETIME, @t_date DATETIME;
         SELECT TOP 1 @balanceupdate = winlostdate
         FROM bodb02.dbo.Bettrans WITH (NOLOCK)
         WHERE bettype = 20000
               AND matchid = 0
               AND custid = 3;
         SELECT @movebetdate = MAX(eventdate)
         FROM bodb02.dbo.match14 WITH (NOLOCK);
         IF @_todate > @movebetdate
             BEGIN
                 IF @_fromdate < @movebetdate
                     SELECT @f_date = @movebetdate;
                 ELSE
                 SELECT @f_date = @_fromdate;
                 SELECT @t_date = @_todate;
                 INSERT INTO #TempMatch
                        SELECT m.matchid,
                               m.matchcode,
                               1
                        FROM bodb02.dbo.match(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT m.orid AS matchid,
                               m.matchcode,
                               2
                        FROM bodb02.dbo.Outright(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT Match3rdId,
                               MatchNo,
                               5
                        FROM bodb02.dbo.Match3rd(nolock)
                        WHERE EventDate BETWEEN @f_date AND @t_date;
             END;
         IF @_fromdate <= @movebetdate
             BEGIN
                 IF @_todate < @movebetdate
                     SELECT @t_date = @_todate;
                 ELSE
                 SELECT @t_date = @movebetdate;
                 SELECT @f_date = @_fromdate;
                 INSERT INTO #TempMatch
                        SELECT m.matchid,
                               m.matchcode,
                               1
                        FROM bodb02.dbo.match14(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT m.orid AS matchid,
                               m.matchcode,
                               2
                        FROM bodb02.dbo.Outright14(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT Match3rdId,
                               MatchNo,
                               5
                        FROM bodb02.dbo.Match3rd14(nolock)
                        WHERE EventDate BETWEEN @f_date AND @t_date;
             END;
         IF @_fromdate < @balanceupdate
             BEGIN
                 IF @_todate < @balanceupdate
                     SELECT @t_date = @_todate;
                 ELSE
                 SELECT @t_date = @balanceupdate - 1;
                 SELECT @f_date = @_fromdate;
                 INSERT INTO #TempMatch
                        SELECT m.matchid,
                               m.matchcode,
                               1
                        FROM bodb_archive.dbo.match_bk(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT m.orid AS matchid,
                               m.matchcode,
                               2
                        FROM bodb_archive.dbo.Outright_bk(nolock) m
                        WHERE m.eventdate BETWEEN @f_date AND @t_date
                        UNION ALL
                        SELECT Match3rdId,
                               MatchNo,
                               5
                        FROM bodb_Archive.dbo.Match3rd_bk(nolock)
                        WHERE EventDate BETWEEN @f_date AND @t_date;
             END;
         WITH CTE_bettype_eventtype(BetTypeID,
                                    EventType)
              AS (SELECT DISTINCT
                         BetType BetTypeID,
                         EventType
                  FROM bodb02.dbo.SportBettypeMatrix(NOLOCK))
              INSERT INTO #TempData
                     SELECT CASE s.SubProduct
                                WHEN 'MG-SuperLive'
                                THEN-1
                                ELSE b.sporttype
                            END sporttype,
                            CASE
                                WHEN(b.bettype IN(1, 3, 7, 8, 301, 302, 303, 304)
                            OR (b.bettype BETWEEN 801 AND 899))
                                THEN b.bettype
                                ELSE 19999
                            END AS bettype,
                            b.liveindicator,
                            ibc,
                            CASE
                                WHEN m.matchcode LIKE '%Hedge%'
                                THEN 1
                                ELSE 0
                            END IsHedge,
                            '' status,
                            CASE s.SubProduct
                                WHEN 'MG-SuperLive'
                                THEN 2
                                ELSE 1
                            END AS OrderKey,
                            s.SortKey,
                            ISNULL(SUM(realWinlost), 0) AS realWinlost,
                            ISNULL(SUM(realPosition), 0) AS realPosition,
                            ISNULL(SUM(realcommission), 0) AS realCommission,
                            ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                            ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                            ISNULL(SUM(realTurnover), 0) AS realTurnover,
                            ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                     FROM dbo.rptWinlost b WITH (NOLOCK)
                          INNER JOIN CTE_bettype_eventtype ON CTE_bettype_eventtype.BetTypeID = b.bettype
                          INNER JOIN #TempMatch m ON m.matchid = b.matchid
                                                     AND m.EventType = CTE_bettype_eventtype.EventType
                          INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                        AND b.liveindicator = s.liveindicator
                     WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                           AND ((s.ProductID = 1
                                 AND s.SubProduct NOT IN('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss'))
                     OR s.ProductID = 3) -- SB or NG, exclude bettrade

                     GROUP BY CASE s.SubProduct
                                  WHEN 'MG-SuperLive'
                                  THEN-1
                                  ELSE b.sporttype
                              END,
                              CASE
                                  WHEN(b.bettype IN(1, 3, 7, 8, 301, 302, 303, 304)
                              OR (b.bettype BETWEEN 801 AND 899))
                                  THEN b.bettype
                                  ELSE 19999
                              END,
                              b.liveindicator,
                              ibc,
                              CASE
                                  WHEN b.bettype IN(1, 3, 7, 8)
                                  THEN b.bettype
                                  ELSE 19999
                              END,
                              CASE
                                  WHEN m.matchcode LIKE '%Hedge%'
                                  THEN 1
                                  ELSE 0
                              END,
                              CASE s.SubProduct
                                  WHEN 'MG-SuperLive'
                                  THEN 2
                                  ELSE 1
                              END,
                              s.SortKey;
         WITH CTE_bettype_eventtype(BetTypeID,
                                    EventType)
              AS (SELECT DISTINCT
                         BetType BetTypeID,
                         EventType
                  FROM bodb02.dbo.SportBettypeMatrix(NOLOCK))
              INSERT INTO #TempData

                     -- bettrade

                     SELECT-2 sporttype,
                           903 bettype,
                           1 liveindicator,
                           ibc,
                           CASE
                               WHEN ISNULL(m.matchcode, '') LIKE '%Hedge%'
                               THEN 1
                               ELSE 0
                           END IsHedge,
                           '' status,
                           15 OrderKey,
                           s.SortKey,
                           ISNULL(SUM(realWinlost), 0) AS realWinlost,
                           ISNULL(SUM(realPosition), 0) AS realPosition,
                           ISNULL(SUM(realcommission), 0) AS realCommission,
                           ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                           ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                           ISNULL(SUM(realTurnover), 0) AS realTurnover,
                           ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                     FROM dbo.rptWinlost b WITH (NOLOCK)
                          INNER JOIN CTE_bettype_eventtype ON CTE_bettype_eventtype.BetTypeID = b.bettype
                          LEFT JOIN #TempMatch m ON m.matchid = b.matchid
                                                    AND m.EventType = CTE_bettype_eventtype.EventType
                          INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                        AND b.liveindicator = s.liveindicator
                     WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                           AND s.ProductID = 1
                           AND s.SubProduct IN('BT-Comm', 'BT-Winloss')
                     GROUP BY ibc,
                              CASE
                                  WHEN ISNULL(m.matchcode, '') LIKE '%Hedge%'
                                  THEN 1
                                  ELSE 0
                              END,
                              s.SortKey;
         INSERT INTO #TempData

                --Casino

                SELECT 251 AS sporttype,
                       71 AS bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       '' status,
                       5 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(realLineTotal), 0) AS virtualLineTotal, --copy data from actual value

                       ISNULL(SUM(CASE
                                      WHEN b.bettype = 71
                                      THEN 0
                                      ELSE realTurnover
                                  END), 0) AS realTurnover,
                       ISNULL(SUM(CASE
                                      WHEN b.bettype = 71
                                      THEN 0
                                      ELSE realTurnover
                                  END), 0) AS virtualTurnover
                FROM dbo.rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 6;
         INSERT INTO #TempData

                --Bingo

                SELECT 252 AS sporttype,
                       b.bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       '' status,
                       6 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(realLineTotal), 0) AS virtualLineTotal,
                       0 AS realTurnover,
                       NULL AS virtualTurnover
                FROM dbo.rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 7
                GROUP BY b.bettype;
         INSERT INTO #TempData

                --Live casino

                SELECT 162 AS sporttype,
                       b.bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       '' status,
                       8 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(realLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0),
                       ISNULL(SUM(realTurnover), 0) AS virtualTurnover
                FROM dbo.rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 4
                GROUP BY b.bettype;
         INSERT INTO #TempData
                SELECT 97, -- mix parlay

                       9 AS bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       status,
                       3 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(virtualLineTotal), 0),
                       ISNULL(SUM(realTurnover), 0),
                       ISNULL(SUM(virtualTurnover), 0)
                FROM dbo.rptWinlost b WITH (NOLOCK)
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND (bettype = 9
                           OR (bettype = 29
                               AND exrisk = 1))
                GROUP BY status;
         INSERT INTO #TempData
                SELECT 98, --system parlay

                       29 AS bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       status,
                       4 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(virtualLineTotal), 0),
                       ISNULL(SUM(realTurnover), 0),
                       ISNULL(SUM(virtualTurnover), 0)
                FROM dbo.rptWinlost b WITH (NOLOCK)
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND bettype = 29
                      AND exrisk <> 1
                GROUP BY status;
         INSERT INTO #TempData

                --racing

                SELECT sporttype,
                       0 AS bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       '' AS status,
                       14 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(realLineTotal), 0) AS virtualLineTotal,
                       0 AS realTurnover,
                       0 AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 2
                GROUP BY sporttype;
         INSERT INTO #TempData

                --virtual sports

                SELECT sporttype,
                       0 AS bettype,
                       0 AS liveindicator,
                       0 AS ibc,
                       0 AS IsHedge,
                       '' AS status,
                       15 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0),
                       ISNULL(SUM(realPosition), 0),
                       ISNULL(SUM(realCommission), 0),
                       ISNULL(SUM(realLineTotal), 0),
                       ISNULL(SUM(realLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0),
                       ISNULL(SUM(realTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 5
                GROUP BY sporttype;
         INSERT INTO #TempData

                -- HR Fixed Odds

                SELECT sporttype,
                       bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       1 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND sporttype = 154
                GROUP BY sporttype,
                         bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                -- GD

                SELECT 255 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       9 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 12
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                -- Micro Gaming LC

                SELECT 203 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       10 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 13
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                -- Micro Gaming RNG

                SELECT 205 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       10 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 17
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                --- AG Casino

                SELECT 250 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       11 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 11
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                --	VegasGame aka Macau

                SELECT 249 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       12 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 14
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                -- allbet section 

                SELECT 211 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       13 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 21
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;	

	   

         -- Macau Games section 

         INSERT INTO #TempData
                SELECT 212 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       13 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 22
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                --	ColossusBet

                SELECT 204 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       16 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 15
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc;
         INSERT INTO #TempData
                SELECT sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       17 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId IN(23)
                GROUP BY sporttype,
                         b.bettype,
                         b.liveindicator,
                         ibc	

                --Fish World

                UNION ALL
                SELECT 219 sporttype,
                       b.bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       17 AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId IN(24)
                GROUP BY b.bettype,
                         b.liveindicator,
                         ibc
                ORDER BY OrderKey ASC;
         INSERT INTO #TempData

                --	Cashout

                SELECT-3 sporttype,
                      913 AS bettype,
                      b.liveindicator,
                      ibc,
                      0 AS IsHedge,
                      '' status,
                      18000 AS OrderKey,
                      17 AS SortKey,
                      ISNULL(SUM(realWinlost), 0) AS realWinlost,
                      ISNULL(SUM(realPosition), 0) AS realPosition,
                      ISNULL(SUM(realcommission), 0) AS realCommission,
                      ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                      ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                      ISNULL(SUM(realTurnover), 0) AS realTurnover,
                      ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId = 25
                      AND b.bettype IN(913, 914)
                GROUP BY b.liveindicator,
                         ibc;
         INSERT INTO #TempData

                -- Keno and others

                SELECT CASE
                           WHEN s.ProductId = 8
                           THEN 202
                           WHEN s.ProductId = 28
                           THEN 220
                           ELSE b.SportType
                       END sporttype,
                       CASE
                           WHEN s.ProductId = 27
                           THEN 0
                           ELSE b.bettype
                       END bettype,
                       b.liveindicator,
                       ibc,
                       0 AS IsHedge,
                       '' status,
                       CASE
                           WHEN s.ProductId = 8
                           THEN 7
                           ELSE s.ProductId
                       END AS OrderKey,
                       17 AS SortKey,
                       ISNULL(SUM(realWinlost), 0) AS realWinlost,
                       ISNULL(SUM(realPosition), 0) AS realPosition,
                       ISNULL(SUM(realcommission), 0) AS realCommission,
                       ISNULL(SUM(realLineTotal), 0) AS realLineTotal,
                       ISNULL(SUM(virtualLineTotal), 0) AS virtualLineTotal,
                       ISNULL(SUM(realTurnover), 0) AS realTurnover,
                       ISNULL(SUM(virtualTurnover), 0) AS virtualTurnover
                FROM dbo.rptWinlost b WITH (NOLOCK)
                     INNER JOIN @SportBettype s ON s.Bettype = b.bettype
                                                   AND b.liveindicator = s.liveindicator
                WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
                      AND s.ProductId NOT IN(1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15, 17, 19, 21, 22, 23, 24, 25)
                GROUP BY CASE
                             WHEN s.ProductId = 8
                             THEN 202
                             WHEN s.ProductId = 28
                             THEN 220
                             ELSE b.SportType
                         END,
                         CASE
                             WHEN s.ProductId = 8
                             THEN 7
                             ELSE s.ProductId
                         END,
                         b.liveindicator,
                         ibc,
                         CASE
                             WHEN s.ProductId = 27
                             THEN 0
                             ELSE b.bettype
                         END;			  

         -- Result --

         CREATE TABLE #Result
         (sporttype        INT,
          bettype          INT,
          liveindicator    BIT,
          ibc              TINYINT,
          IsHedge          BIT,
          status           NVARCHAR(20),
          OrderKey         INT,
          SortKey          INT,
          realWinlost      MONEY,
          realPosition     MONEY,
          realCommission   MONEY,
          realLineTotal    MONEY,
          virtualLineTotal MONEY,
          realTurnover     MONEY,
          virtualTurnover  MONEY
         );



         -- 8RM, BARM

         INSERT INTO #Result
                SELECT sporttype,
                       bettype,
                       liveindicator,
                       ibc,
                       0 AS IsHedge,
                       status,
                       OrderKey,
                       SortKey,
                       SUM(realWinlost) AS realWinlost,
                       SUM(realPosition) AS realPosition,
                       SUM(realCommission) AS realCommission,
                       SUM(realLineTotal) AS realLineTotal,
                       SUM(virtualLineTotal) AS virtualLineTotal,
                       SUM(realTurnover) AS realTurnover,
                       SUM(virtualTurnover) AS virtualTurnover
                FROM #TempData
                WHERE ibc IN(1, 2)
                GROUP BY sporttype,
                         bettype,
                         liveindicator,
                         ibc,
                         status,
                         OrderKey,
                         SortKey;



         -- Hegde match, Normal match

         INSERT INTO #Result
                SELECT sporttype,
                       bettype,
                       liveindicator,
                       0 AS ibc,
                       IsHedge,
                       status,
                       OrderKey,
                       SortKey,
                       SUM(realWinlost) AS realWinlost,
                       SUM(realPosition) AS realPosition,
                       SUM(realCommission) AS realCommission,
                       SUM(realLineTotal) AS realLineTotal,
                       SUM(virtualLineTotal) AS virtualLineTotal,
                       SUM(realTurnover) AS realTurnover,
                       SUM(virtualTurnover) AS virtualTurnover
                FROM #TempData
                GROUP BY sporttype,
                         bettype,
                         liveindicator,
                         IsHedge,
                         status,
                         OrderKey,
                         SortKey;
         SELECT sporttype,
                bettype,
                liveindicator,
                ibc,
                IsHedge,
                status,
                OrderKey,
                SortKey,
                SUM(realWinlost) AS realWinlost,
                SUM(realPosition) AS realPosition,
                SUM(realCommission) AS realCommission,
                SUM(realLineTotal) AS realLineTotal,
                SUM(virtualLineTotal) AS virtualLineTotal,
                SUM(realTurnover) AS realTurnover,
                SUM(virtualTurnover) AS virtualTurnover
         FROM #Result
         GROUP BY sporttype,
                  bettype,
                  liveindicator,
                  ibc,
                  IsHedge,
                  status,
                  OrderKey,
                  SortKey
         ORDER BY OrderKey,
                  SortKey,
                  liveindicator;
         DROP TABLE #TempMatch;
         DROP TABLE #TempData;
         DROP TABLE #Result;
     END;
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [vnteam];
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [bodbAdminNet];
GO
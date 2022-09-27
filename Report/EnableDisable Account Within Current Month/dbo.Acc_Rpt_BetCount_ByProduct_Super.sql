/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_BetCount_ByProduct_Super @MoveBetsDay  SMALLDATETIME,
                                                     @BalanceUpDay SMALLDATETIME,
                                                     @CustID       INT,
                                                     @SportType    INT
AS
/*
    Created: Dominic
    Date: 2014-06-02
    Task : Total settled/running bets count per Product by super within current month
    DB: DBAGE/bodb02

    Revisions:
        - 20140701@Dominic: Get running Keno bets from table Translog
        - 20150617@Elodie: Migrate CustDB to DBCUST (call CustGameType by link server DBACC)
        - 20150828@Jim: support GoldDeluxe & Metric Gaming(#40262)
        - 20150828@Jim: support Colossus Bet (#42608)
        - 20151215@Percy: suport Cockfighting [Redmine: #49027]
        - 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
        - 20160203@Sophia: . Change the way to get report
                           . Apply RNG Casino [Redmine: #49134]
                           . Appy Metric gaming - Superlive
        - 20160229@Jim: Offer Allbet [Redmine #50921]
        - 20160407@Sophia: Fix bug low performance - need to call Openquery [redmine: #55623]
        - 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
        - 20160916@Robert:
            1. Integrate new product NG2 [RedmindID: #63460]
            2. Clean code of Cockfighting
        - 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
        - 20170627@Cherry: Integrate Lottery and Betradar Virtual Sports (#78184, 78495)
        - 20170808@Cherry: Integrate RNG Tablet Games (#78424)
        - 20170825@Cherry: Integrate Lucky 3 (#78214)
        - 20171030@Kean: Integrate Bullfighting (#85712)
        - 20171110@Kean: Should count the running tickets from translogs table (#86319)
        - 20171113@Kean:  (#86319) Include GoldDeluxe for counting of running tickets from translog table(#86319)
        - 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
        - 20180411@Franklin: Integrate Pragmatic (#92642)
        - 20180816@Cherry: Integrate Poker Games (#97830)
        - 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253)
        - 20190128@Robert: Video Poker - Integrate into NAP Reports[#107706]
        - 20190308@Robert: #109822 - NAP Report - Integrate Bet Builder
        - 20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
        - 20190917@Dominic: Remove inactive products [#120215]
        - 20191225@Cherry: Integrate Spadegaming (#125788)
        - 20200313@Ned.Le: NAP Report - Incorporate Virtual Games (#130326)
        - 20200317@Ned.Le: Hotfix - Miss get data Card Club From bodb_account.dbo.mcCustBettingDaily table (#130535)
        - 20200323@Ned.Le: NAP Report - Incorprorate SA Gaming (#129349) | Saba.club (#130776) | Sexy Gaming (#130853)
        - 20200331@Ned.Le: NAP Report - Incorporate new Table Games (#131095)
        - 20200409@Ned.Le: NAP Report - Incorporate BBIN Live Casino (#131357)
        - 20200422@Ned.Le: NAP Report - Incorporate IBCBet Live Casino (#132961)
        - 20200521@Cherry: Missing running betcount for sports: Saba, SA Gaming, Sexy Gaming, IBCBet Live Casino (#134571)
        - 20200522@Cherry: Nap Report - Integrate ION Live Casino (#132324) & RNG War (#132009)
        - 20200713@Ned.Le: NAP Report - Incorporate Jackpot Games (#137271)
        - 20200723@Jaden.Tang: NAP Report - Add new range for lottery (#137715)
        - 20200814@Roy: NAP Report - Integrate PG Soft (#137770)
        - 20200921@Jaden.Tang: NAP Report - Incorporate Joker Gaming (#131611) & WM (#131583)
        - 20200930@Ned.Le: NAP Reports - Licensee Odds Spread (#141750)
        - 20201126@Cherry: Integrate Virtual Sports 3 (#146010) & GDG (#146008)
        - 20201225@Ned.Le: NAP Reports - Integrate Linked Games (Number Game) (#147573)
        - 20201225@Ned.Le: NAP Reports - Integrate Big Gaming (#142481)
        - 20201225@Ned.Le: NAP Reports - Integrate MaxGame (#147570)
        - 20210303@Cherry: Integrate Habanero (#151070)
        - 20210303@Cherry: Integrate Sports Lottery (#151071)
        - 20210325@Jaden: Change bettype range from [3101 - 3199] to [3101 - 3150] (#151869)
        - 20210325@Jaden: Integrate PP Live Casino (#133731)
        - 20210420@Jaden: Include CG into Macau Games (#152781)
        - 20210428@Ned.Le: NAP Report - Implement VGaming (#154072)
        - 20210506@Ned.Le: NAP Report - Implement Advantplay (#154677)
        - 20210517@Ned.Le: NAP Reports - Integrate AdvantPlay Mini (#155174)
        - 20210811@Jaden: Integrate Bitcoin (#159046)
        - 20211203@Ned.Le: NAP Report - Tune report "Total Credit Accounts" (#165615)
        - 20210224@Cherry: Incorporate ONE RNG DCS (#168917)
		- 20220826@Cherry: Integrate SEAL Entertainment (#176391)
		- 20220927@Cherry: Integrate MG-RNG product (#177504)

    Param's Explanation:
        + @MoveBetsDay:  The day of moving bets to battrans14
        + @BalanceUpDay: The day of moving bets to battransbk
        + @CustID:       SuperID
        + @SportType:    Sporttype that be define at WEB stage
*/

BEGIN

    SET NOCOUNT ON


    -----------------------
    -- DECLARE VARIABLES --
    -----------------------

    DECLARE @CurrentDate  SMALLDATETIME
    DECLARE @FirstDate    SMALLDATETIME
    DECLARE @TempFromDate SMALLDATETIME
    DECLARE @TempToDate   SMALLDATETIME

    SELECT @CurrentDate = CAST(GETDATE() AS DATE)
    SELECT @FirstDate   = CONVERT(VARCHAR(25) ,DATEADD(dd, -(DAY(@CurrentDate) -1), @CurrentDate), 101)

    DECLARE @SQLQuery VARCHAR(MAX)
    DECLARE @ListBettype VARCHAR(MAX)


    ---------------
    -- META DATA --
    ---------------

    ---------------
    -- #BitmapOrder

    CREATE TABLE #BitmapOrder (bitmapOrder INT)

    INSERT INTO #BitmapOrder (bitmapOrder)
    SELECT bitmapOrder
    FROM bodb02.dbo.ProductStatusProfile WITH (NOLOCK)
    WHERE Sporttype = @SportType

    -----------------------
    -- #SpecialBettypeGroup

    -- Create temp table
    CREATE TABLE #SpecialBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)

    -- Get data of BettypeGroupID=12 [No BetCount]
    INSERT INTO #SpecialBettypeGroup (BettypeGroupID, Bettype)
    SELECT BettypeGroupID, Bettype
    FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
    WHERE BettypeGroupID IN (12)

    ----------------------
    -- #SportGroupSettings

    -- Create temp table
    CREATE TABLE #SportGroupSettings (
        SportGroupID   INT,
        SportGroupName VARCHAR(100),
        SportType      INT
    )

    -- Number Game group
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (161, 'Number Game',    161)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (161, 'Number Game',    164)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (161, 'Number Game',    168)

    -- Saba Casino group
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (208, 'Saba Casino',     208)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (208, 'Saba Casino',     209)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (208, 'Saba Casino',     210)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (208, 'Saba Casino',     251)

    -- Virtual Sports group
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 180)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 181)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 182)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 183)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 184)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 185)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 186)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 190)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 191)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 192)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 193)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 194)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 195)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 196)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 197)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (180, 'Virtual Sports', 231)

    -- Macau Games group
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    165)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    167)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    172)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    174)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    212)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    232)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    234)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    237)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    238)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    247)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    248)
	INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    156)
	INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    155)

    ---------------
    -- #SportFilter

    -- Create temp table
    CREATE TABLE #SportFilter (SportGroupID INT, SportType INT)

    -- Gen data to temp table
    IF EXISTS (SELECT TOP 1 1 FROM #SportGroupSettings WHERE SportGroupID = @SportType)
    BEGIN
        INSERT INTO #SportFilter (SportGroupID, SportType)
        SELECT SportGroupID, SportType
        FROM #SportGroupSettings
        WHERE SportGroupID = @SportType
    END
    ELSE
    BEGIN
        INSERT INTO #SportFilter (SportGroupID, SportType) VALUES (@SportType, @SportType)
    END

    ----------------
    -- #SportBettype

    -- Create temp table
    CREATE TABLE #SportBettype (
        SportGroupID INT,
        SportType    INT,
        Bettype      INT,
        RefTable     INT
    )

    -- Gen data to temp table
    IF (@SportType = -1)
    BEGIN
        INSERT INTO #SportBettype (SportGroupID, SportType, Bettype, RefTable)
        SELECT DISTINCT
              -1         SportGroupID,
               SportType SportType,
               BetType   Bettype,
               RefTable  RefTable
        FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
        WHERE SubProduct = 'MG-SuperLive'
    END
    ELSE
    BEGIN
        INSERT INTO #SportBettype (SportGroupID, SportType, Bettype, RefTable)
        SELECT DISTINCT sf.SportGroupID, sbm.SportType, sbm.BetType, sbm.RefTable
        FROM bodb02.dbo.SportBettypeMatrix sbm WITH (NOLOCK)
             INNER JOIN #SportFilter sf ON sbm.SportType = sf.SportType
    END

    -- Update data for column RefTable
    UPDATE sb
    SET sb.RefTable = 3
    FROM #SportBettype sb
    WHERE sb.SportGroupID IN (202, 204, 220, 255, -1, 245, 222, 180, 161, 169)
          OR sb.SportType IN (202, 204, 220, 255, -1, 245, 222, 180, 161, 169)


    ---------------
    -- MAIN DATA --
    ---------------

    -------------------
    -- #AvailableMember

    -- Create temp table
    CREATE TABLE #AvailableMember (
        CustID    INT,
        BetStatus NVARCHAR(10),
        BetCount  INT
    )

    -- Get data from translog
    BEGIN
        INSERT INTO #AvailableMember (CustID, BetStatus, BetCount)
        SELECT tl.custid   CustID,
               tl.[status] BetStatus,
               COUNT(1)    BetCount
        FROM bodb02.dbo.translog tl WITH (NOLOCK)
        WHERE EXISTS (SELECT TOP 1 1
                      FROM #SportBettype sb
                      WHERE sb.RefTable IN (3) AND sb.Bettype = tl.gameID)
              AND tl.srecommend = @CustID
              AND tl.StatusId = 0
        GROUP BY tl.custid,
                 tl.[status]
        OPTION (RECOMPILE)
    END

    -- Get data from bettrans table group
    IF (@CurrentDate > @MoveBetsDay)
    BEGIN
        -- + Settings time range
        IF (@FirstDate <= @MoveBetsDay)
        BEGIN
            SET @TempFromDate =  DATEADD(DAY, 1, @MoveBetsDay)
        END
        ELSE
        BEGIN
            SET @TempFromDate = @FirstDate
        END

        -- + Get data from bettrans
        BEGIN
            INSERT INTO #AvailableMember (CustID, BetStatus, BetCount)
            SELECT b.custid                                                                      CustID,
                   b.[status]                                                                    BetStatus,
                   CASE WHEN b.bettype BETWEEN 1401 AND 1499 THEN SUM(b.betid) ELSE COUNT(1) END BetCount
            FROM dbo.bettrans b WITH (NOLOCK)
            WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
                  AND EXISTS (SELECT TOP 1 1
                              FROM #SportBettype sb
                              WHERE sb.RefTable IN (0, 3) AND sb.Bettype = b.bettype)
                  AND b.statusId IN (111, 112, 113, 0)
                  AND b.srecommend = @CustID
                  AND b.bettype NOT IN (38)
                  AND b.bettype NOT IN (SELECT Bettype FROM #SpecialBettypeGroup)
            GROUP BY b.custid,
                     b.[status],
                     b.bettype
            OPTION (RECOMPILE)
        END

        -- Get data from bettransRnG
        BEGIN
            INSERT INTO #AvailableMember (CustID, BetStatus, BetCount)
            SELECT b.custid   CustID,
                   b.[status] BetStatus,
                   COUNT(1)   BetCount
            FROM dbo.bettransRNG b WITH (NOLOCK)
            WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
                  AND EXISTS (SELECT TOP 1 1
                              FROM #SportBettype sb
                              WHERE sb.RefTable IN (1) AND sb.Bettype = b.gameID)
                  AND b.statusId IN (111, 112, 113, 0)
                  AND b.srecommend = @CustID
                  AND b.gameID NOT IN (SELECT Bettype FROM #SpecialBettypeGroup)
            GROUP BY b.custid,
                     b.[status]
            OPTION (RECOMPILE)
        END

        -- Get data from bettransLC
        BEGIN
            INSERT INTO #AvailableMember (CustID, BetStatus, BetCount)
            SELECT b.custid   CustID,
                   b.[status] BetStatus,
                   COUNT(1)   BetCount
            FROM dbo.bettransLC b WITH (NOLOCK)
            WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
                  AND EXISTS (SELECT TOP 1 1
                              FROM #SportBettype sb
                              WHERE sb.RefTable IN (2) AND sb.Bettype = b.gameID)
                  AND b.statusId IN (111, 112, 113, 0)
                  AND b.srecommend = @CustID
                  AND b.gameID NOT IN (SELECT Bettype FROM #SpecialBettypeGroup)
            GROUP BY b.custid,
                     b.[status]
            OPTION (RECOMPILE)
        END
    END

    -- Get data from mcCustBettingDaily
    IF (@FirstDate <= @MoveBetsDay)
    BEGIN
        -- + Settings time range
        IF (@CurrentDate >= @MoveBetsDay)
        BEGIN
            SET @TempToDate = @MoveBetsDay
        END
        ELSE
        BEGIN
            SET @TempToDate = @CurrentDate
        END

        -- + Get list bettype
        SELECT @ListBettype = COALESCE(@ListBettype + ', ' + CAST(Bettype AS VARCHAR(10)), CAST(Bettype AS VARCHAR(10))) FROM #SportBettype

        -- + Get data
        SET @SQLQuery =
        '
        SELECT b.CustID        CustID,
               ''SETTLED''     BetStatus,
               SUM(b.BetCount) BetCount
        FROM bodb_account.dbo.mcCustBettingDaily b WITH (NOLOCK)
        WHERE b.rptDate BETWEEN ''' + CONVERT(VARCHAR(10), @FirstDate, 121) + ''' AND ''' + CONVERT(VARCHAR(10), @TempToDate, 121) + '''
              AND b.bettype IN (' + @ListBettype + ')
              AND b.bettype NOT IN (38)
              AND b.status IN (3, 4, 8, 12, 13)
              AND b.CustID IN (SELECT custid
                               FROM bodb02.dbo.CustInfo WITH (NOLOCK)
                               WHERE srecommend = ' + CONVERT(VARCHAR(50), @CustID) + ' AND RoleID = 1)
        GROUP BY b.CustID
        '

        INSERT INTO #AvailableMember (CustID, BetStatus, BetCount)
        EXEC (@SQLQuery) AT DBWH
    END

    ---------------------
    -- #FiltedDownlineAcc

    -- Create temp table
    CREATE TABLE #FiltedDownlineAcc (
        CustID    INT,
        IsDisable BIT,
        BetStatus NVARCHAR(10),
        BetCount  INT
    )

    -- Gen data to temp table
    -- + [161] Number Game
    IF (@sportType IN (161))
    BEGIN
        INSERT INTO #FiltedDownlineAcc (CustID, IsDisable, BetStatus, BetCount)
        SELECT ci.custid,
               ci.DisableNumber,
               av.BetStatus,
               av.BetCount
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #AvailableMember av ON av.CustID = ci.custid
    END   
    -- + [202] RNG Keno
    ELSE IF (@sportType IN (202))
    BEGIN
        ;WITH CustEnableKeno (CustID) AS (
            SELECT gt.CustID
            FROM DBACC.bodb02.dbo.CustGameType gt WITH (NOLOCK)
                 INNER JOIN #AvailableMember av ON av.CustID = gt.CustID
            WHERE gt.IsDisabled = 0
            GROUP BY gt.CustID
        )
        INSERT INTO #FiltedDownlineAcc (CustID, IsDisable, BetStatus, BetCount)
        SELECT av.custid,
               0,
               av.BetStatus,
               av.BetCount
        FROM #AvailableMember av
             INNER JOIN CustEnableKeno ce ON ce.CustID = av.custid
        UNION ALL
        SELECT av.custid,
               1,
               av.BetStatus,
               av.BetCount
        FROM #AvailableMember av
             LEFT JOIN CustEnableKeno ce ON ce.CustID = av.custid
        WHERE ce.CustID IS NULL
    END
    -- + [-1] Metric Gamming | [255] Gold Deluxe | [204] Colossus
    ELSE IF (@sportType IN (-1, 255, 204))
    BEGIN
        INSERT INTO #FiltedDownlineAcc (CustID, IsDisable, BetStatus, BetCount)
        SELECT ci.custid,
               CASE WHEN @sportType = -1  THEN ci.DisableSuperLive
                    WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
                    WHEN @sportType = 204 THEN ci.DisableColossusBet END,
               av.BetStatus,
               av.BetCount
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #AvailableMember av ON av.CustID = ci.custid
    END
    ELSE
    BEGIN
        INSERT INTO #FiltedDownlineAcc (CustID, IsDisable, BetStatus, BetCount)
        SELECT ci.custid,
               (SELECT CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END
                FROM bodb02.dbo.CustProductStatus cps WITH (NOLOCK)
                     CROSS APPLY #BitmapOrder b
                     CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
                WHERE custid = ci.custid),
               av.BetStatus,
               av.BetCount
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #AvailableMember av ON av.CustID = ci.custid
    END


    -------------------
    -- RETURN RESULT --
    -------------------

    SELECT cs.custid,
           cs.username,
           rs.IsDisable,
           SUM(CASE WHEN rs.BetStatus <> 'running' THEN rs.BetCount ELSE 0 END) SettledBets,
           SUM(CASE WHEN rs.BetStatus =  'running' THEN rs.BetCount ELSE 0 END) RunningBets
    FROM #FiltedDownlineAcc rs
         INNER JOIN bodb02.dbo.Customer cs ON cs.custid = rs.CustID
    GROUP BY cs.custid, cs.username, rs.IsDisable
    ORDER BY cs.username


    ----------------------
    -- DROP TEMP TABLES --
    ----------------------

    DROP TABLE #BitmapOrder
    DROP TABLE #SpecialBettypeGroup
    DROP TABLE #SportGroupSettings
    DROP TABLE #SportFilter
    DROP TABLE #SportBettype
    DROP TABLE #AvailableMember
    DROP TABLE #FiltedDownlineAcc

END
GO

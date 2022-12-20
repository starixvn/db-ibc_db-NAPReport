/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="1"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_Credit @FromDate    DATE,
                                                  @ToDate      DATE,
                                                  @ProductList VARCHAR(MAX) = 'ALL'
AS

/*
    Created: 20201102@Ned.Le
    Task:    Get all necessary credit data for House Net Income report
    DB:      DBWH/bodb_dwrs

    Revisions:
        20201102@Ned.Le: DHWL Email/Letstalk - Restructure source code to improve performance & Separate House Income into Credit Income and Licensee Income (#143208)
        20210112@Ned.Le: Email/Letstalk Reports - Integrate Linked Games (Number Game) (#146539)
        20211201@Ned.Le: DHWL Email/Letstalk - Margin Charts - Restructure code (#148604)
        20210122@Ned.Le: DHWL Email/Letstalk - Adjustment Letstalk (#149267)
        20210322@Ned.Le: Email/Letstalk Reports - Integrate PP Live Casino (#133734)
        20210401@Ned.Le: Email/Letstalk Reports - AE Casino - Support Lucky Draw (#151870)
        20210414@Ned.Le: Email/Letstalk Reports - Arcadia Gaming - Add 2 new games: Marble Mini and RPS (#153419)
        20210519@Ned.Le: Email/Letstalk Reports - Incorporate Saba Soccer PinGoal (#155373)
        20210726@Ned.Le: Letstalk Reports - Apply monthly formula for MTD value like LA Reports (#157953)
        20210726@Ned.Le: HNI Email/Letstalk - Change the formula to calculate House Income, Pay To Supplier for Arcadia Gaming/PP Promotion tickets (#158971)
        20210815@Ned.Le: Email/Letstalk Reports - Change Data Source to retrieve yesterday data from DW into Bettrans table (#151993)
        20220110@Kean.Nguyen: Email/Letstalk Reports - Integrate Spadegaming Jackpot (#166684)
        20220210@Kean.Nguyen: Email/Letstalk Reports - Incorporate Saba Basketball Soccer PinGoal (#168373)
        20220310@Ned.Le: Email/Letstalk Reports - Include 8RM/BARM into Bet Count, member turnover, member win loss, Margin except House Income (#169768)
        20220801@Ned.Le: Email/Letstalk Reports - Scale out DB - Modify SPs to retrieve yesterday data in Data warehouse in case in-house replicator got problem (#176077)
        20220612@Ned.Le: Email/Letstalk Reports - Incorporate Saba E-Sports PinGoal (#181261)

    Param's Explanation:
        @FromDate   : Begin date to get data for report
        @ToDate     : End date to get data fore report
        @ProductList: 'ALL' - Get data of all product
                      'SB'  - Get data of Sportsbook
                      Other - References to column ProductPrefix of table HNISettings

    Example:
        EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Credit '20200901', '20200930', 'ALL'
        EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Credit '20200901', '20200930', 'KN,LT'
        EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Credit '20200901', '20200930', 'SB,NG,H5,H5LG,CS,JP,PP,PP-JP'
*/

BEGIN

    SET NOCOUNT ON


    -------------------------------------------------------------
    -- CODE LAYOUT                                             --
    -------------------------------------------------------------
    --                                                         --
    -- 1. Declare variables                                    --
    --                                                         --
    -- 2. Product Bettype                                      --
    --    -> #tmpBettypeGroup                                  --
    --    -> #tmpProductList                                   --
    --    -> #tmpHNISettings                                   --
    --    -> #tmpProductBettype                                --
    --                                                         --
    -- 3. Other Metadata tables                                --
    --    -> #tmpExchangeSystem                                --
    --    -> #tmpExchangeOANDA                                 --
    --    -> #tmpLeague                                        --
    --    -> #tmpPTSProducts                                   --
    --    -> #tmpPTSVendorGlobalSetting                        --
    --    -> #tmpPTSMainData                                   --
    --                                                         --
    -- 4. Getting source data                                  --
    --    -> #tmpSourceData                                    --
    --                                                         --
    -- 5. Getting raw data                                     --
    --    -> #tmpRawData                                       --
    --                                                         --
    -- 6. Getting detail data                                  --
    --    -> #tmpDetailData                                    --
    --                                                         --
    -- 7. Pivot detail data to get the final expected data set --
    --    -> #tmpFinalData                                     --
    --                                                         --
    -- 8. Select data                                          --
    --                                                         --
    -- 9. Drop temp tables                                     --
    --                                                         --
    -------------------------------------------------------------


    --------------------------
    -- 1. Declare variables --
    --------------------------

    -- General variables
    DECLARE @isTest BIT = 0
    SELECT  @isTest = bodb_dwrs.dbo.f_CheckSPVersion(@@PROCID)

    DECLARE @sqlQuery    VARCHAR(MAX)
    DECLARE @bettypeList VARCHAR(MAX)

    DECLARE @yesterday           DATE = DATEADD(DAY, -1, CAST(GETDATE() AS DATE))
    DECLARE @OANDA_ExchangeDate  DATE
    DECLARE @OANDA_LastMonthDate DATE
    DECLARE @finalDataDate       DATE

    DECLARE @InHouseReplicationWorkingStatus INT
    SELECT  @InHouseReplicationWorkingStatus = CAST(VValue AS INT) FROM bodb_account.dbo.SystemSettings (NOLOCK) WHERE VID = 16

    DECLARE @loop_FromDate DATE
    DECLARE @loop_ToDate DATE
    DECLARE @loop_Interval INT = 6

    DECLARE @SabaLeagueGroupAll     VARCHAR(500)
    DECLARE @SabaLeagueGroupNormal  VARCHAR(500)
    DECLARE @SabaLeagueGroupPinGoal VARCHAR(500)
    SELECT  @SabaLeagueGroupAll     = VValue FROM bodb_Account.dbo.SystemSettings (NOLOCK) WHERE VID = 5
    SELECT  @SabaLeagueGroupNormal  = VValue FROM bodb_Account.dbo.SystemSettings (NOLOCK) WHERE VID = 11
    SELECT  @SabaLeagueGroupPinGoal = REPLACE(@SabaLeagueGroupAll, @SabaLeagueGroupNormal + ',', '')

    -- Special variables
    DECLARE @FromDate_DW           DATE
    DECLARE @ToDate_DW             DATE
    DECLARE @FromDate_OLTP         DATE
    DECLARE @ToDate_OLTP           DATE
    DECLARE @isGetDataFromBettrans BIT

    IF ((@ToDate < @yesterday) OR (@InHouseReplicationWorkingStatus = 0))
    BEGIN
        SET @isGetDataFromBettrans = 0
        SET @FromDate_DW = @FromDate
        SET @ToDate_DW = @ToDate
    END

    IF ((@ToDate = @yesterday) AND (@InHouseReplicationWorkingStatus = 1))
    BEGIN
        SET @isGetDataFromBettrans = 1
        SET @FromDate_DW = @FromDate
        SET @ToDate_DW = DATEADD(DAY, -1, @ToDate)
        SET @FromDate_OLTP = @ToDate
        SET @ToDate_OLTP = @ToDate
    END

    ------------------------
    -- 2. Product Bettype --
    ------------------------

    -- #tmpBettypeGroup
    CREATE TABLE #tmpBettypeGroup (
        BettypeGroupID SMALLINT,
        Bettype        INT,
        BettypeName    VARCHAR(500),
        ProductID      INT
    )

    INSERT INTO #tmpBettypeGroup (BettypeGroupID, Bettype, BettypeName, ProductID)
    SELECT bg.BettypeGroupID, bg.Bettype, b.typenamee BettypeName, pb.ProductID
    FROM bodb_Account.dbo.BettypeGroup bg (NOLOCK)
         LEFT JOIN bodb_Account.dbo.Product_Bettype pb (NOLOCK) ON bg.Bettype = pb.Bettype
         LEFT JOIN bodb_Account.dbo.Bettype b (NOLOCK) ON bg.Bettype = b.typeid
    WHERE bg.BettypeGroupID IN (6, 10, 11, 14, 15)

    CREATE CLUSTERED INDEX CIX_#tmpBettypeGroup ON #tmpBettypeGroup(BettypeGroupID, Bettype)

    -- #tmpProductList
    CREATE TABLE #tmpProductList (ProductPrefix VARCHAR(20))

    INSERT INTO #tmpProductList (ProductPrefix)
    SELECT val ProductPrefix
    FROM bodb_dwrs.dbo.strSplit(@ProductList, ',')
    WHERE LEN(val) > 0

    CREATE CLUSTERED INDEX CIX_tmpProductList ON #tmpProductList(ProductPrefix)

    -- #tmpHNISettings
    CREATE TABLE #tmpHNISettings (
        isDeposit        BIT,
        OrderByProduct   INT,
        OrderByFigure    INT,
        ProductID        INT,
        AliasProductID   INT,    
        ProductPrefix    VARCHAR(50),
        ProductCategory  VARCHAR(50),
        ProductGroup     VARCHAR(50),
        ProductName      VARCHAR(50),
        ProductShortName VARCHAR(50),
        Figure           VARCHAR(200),
        SubFigure        VARCHAR(200),
        isEnable         BIT,
        EndOfSupportDate DATE,
        LogicCode        SMALLINT
    )

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'ALL')
    BEGIN
        INSERT INTO #tmpHNISettings (isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode)
        SELECT DISTINCT isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode
        FROM bodb_Account.dbo.HNISettings (NOLOCK)
        WHERE (isTest = 0 OR isTest = @isTest)
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'SB')
    BEGIN
        INSERT INTO #tmpHNISettings (isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode)
        SELECT DISTINCT isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode
        FROM bodb_Account.dbo.HNISettings (NOLOCK)
        WHERE ProductName = 'Sportsbook'
              AND (isTest = 0 OR isTest = @isTest)
    END

    BEGIN
        INSERT INTO #tmpHNISettings (isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode)
        SELECT DISTINCT isDeposit, OrderByProduct, OrderByFigure, ProductID, AliasProductID, ProductPrefix, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, isEnable, EndOfSupportDate, LogicCode
        FROM bodb_Account.dbo.HNISettings (NOLOCK)
        WHERE ProductPrefix IN (SELECT ProductPrefix FROM #tmpProductList)
              AND (isTest = 0 OR isTest = @isTest)
    END

    CREATE CLUSTERED INDEX CIX_tmpHNISettings ON #tmpHNISettings(isDeposit, ProductID, AliasProductID)

    -- #tmpProductBettype
    CREATE TABLE #tmpProductBettype (
        ProductID INT,
        Bettype   INT
    )

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'ALL')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID IN (SELECT DISTINCT ProductID FROM #tmpHNISettings (NOLOCK) WHERE isDeposit = 0 AND isEnable = 1)
              AND SubProduct NOT IN ('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'SB')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID IN (1) AND SubProduct NOT IN ('BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'NG')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID = 3 AND SportType = 161
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'H5')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID = 3 AND SportType = 164
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'H5LG')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID = 3 AND SportType = 168
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'JP')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 6 AND BettypeGroupID = 10 AND BettypeName LIKE '%Jackpot%')
              OR BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 6 AND BettypeGroupID = 6 AND BettypeName LIKE '%Jackpot%')
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'PP-JP')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 32 AND BettypeGroupID = 10 AND BettypeName LIKE '%Jackpot%')
              OR BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 32 AND BettypeGroupID = 6 AND BettypeName LIKE '%Jackpot%')
    END

    IF EXISTS (SELECT TOP 1 1 FROM #tmpProductList WHERE ProductPrefix = 'SG-JP')
    BEGIN
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT ProductID, BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 36 AND BettypeGroupID = 10 AND BettypeName LIKE '%Jackpot%')
              OR BetType IN (SELECT Bettype FROM #tmpBettypeGroup WHERE ProductID = 36 AND BettypeGroupID = 6 AND BettypeName LIKE '%Jackpot%')
    END

    BEGIN
        ;WITH CTE_Normal AS (
            SELECT DISTINCT hni.ProductID, hni.ProductPrefix
            FROM #tmpHNISettings hni (NOLOCK)
            WHERE hni.isDeposit = 0
                  AND hni.isEnable = 1
                  AND hni.AliasProductID > 0
                  AND EXISTS (SELECT TOP 1 1
                              FROM #tmpProductList pl
                              WHERE pl.ProductPrefix = hni.ProductPrefix)
        )
        INSERT INTO #tmpProductBettype (ProductID, Bettype)
        SELECT DISTINCT
               ProductID,
               BetType
        FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
        WHERE ProductID IN (SELECT ProductID FROM CTE_Normal)
              AND BetType NOT IN (SELECT BetType FROM #tmpProductBettype)
    END

    CREATE UNIQUE CLUSTERED INDEX CIX_tmpProductBettype ON #tmpProductBettype(ProductID, Bettype)


    ------------------------------
    -- 3. Other Metadata tables --
    ------------------------------

    -- #tmpExchangeSystem
    CREATE TABLE #tmpExchangeSystem (
        ExchangeDate DATE,
        ExchangeID   INT,
        Rate         FLOAT
    )

    INSERT INTO #tmpExchangeSystem (ExchangeDate, ExchangeID, Rate)
    SELECT ExchangeDate, Currency, Rate
    FROM bodb_Account.dbo.tbl_Currency_Daily (NOLOCK)
    WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

    CREATE CLUSTERED INDEX CIX_#tmpExchangeSystem ON #tmpExchangeSystem(ExchangeDate, ExchangeID)

    -- #tmpExchangeOANDA
    CREATE TABLE #tmpExchangeOANDA (
        ExchangeID INT,
        Rate       FLOAT
    )

    SELECT @OANDA_ExchangeDate = MAX(ExchangeDate) FROM bodb02.dbo.ExchangeDailyOanda (NOLOCK)
    SELECT @OANDA_LastMonthDate = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, -1, @ToDate), 0))
    IF (@OANDA_ExchangeDate > @OANDA_LastMonthDate) SELECT @OANDA_ExchangeDate = @OANDA_LastMonthDate
    
    INSERT INTO #tmpExchangeOANDA (ExchangeID, Rate)
    SELECT ExchangeId ExchangeID, MYR Rate
    FROM bodb02.dbo.ExchangeDailyOanda (NOLOCK)
    WHERE ExchangeDate = @OANDA_ExchangeDate

    CREATE CLUSTERED INDEX CIX_tmpExchangeOANDA ON #tmpExchangeOANDA(ExchangeID)

    -- #tmpLeague
    CREATE TABLE #tmpLeague (
        LeagueGroupType INT,
        LeagueGroupID   INT,
        LeagueID        INT
    )

    ;WITH
    CTE_All AS (
        SELECT val LeagueGroupID
        FROM bodb02.dbo.strSplit(@SabaLeagueGroupAll, ',')
    ),
    CTE_PinGoal AS (
        SELECT val LeagueGroupID
        FROM bodb02.dbo.strSplit(@SabaLeagueGroupPinGoal, ',')
    ),
    CTE_Final AS (
        SELECT a.LeagueGroupID,
               CASE WHEN p.LeagueGroupID IS NOT NULL THEN 1 ELSE 0 END isPinGoal
        FROM CTE_All a
             LEFT JOIN CTE_PinGoal p ON a.LeagueGroupID = p.LeagueGroupID
    )
    INSERT INTO #tmpLeague (LeagueGroupType, LeagueGroupID, LeagueID)
    SELECT CASE WHEN f.isPinGoal = 1 THEN 2 ELSE 1 END LeagueGroupType,
           l.LeagueGroupID,
           l.leagueid LeagueID
    FROM bodb02.dbo.League l (NOLOCK)
         LEFT JOIN CTE_Final f ON l.LeagueGroupID = f.LeagueGroupID
    WHERE f.LeagueGroupID IS NOT NULL

    CREATE CLUSTERED INDEX CIX_tmpLeague ON #tmpLeague(LeagueID)

    -- #tmpPTSProducts
    CREATE TABLE #tmpPTSProducts (
        ProductID     INT,
        ProductPrefix VARCHAR(100),
        VendorID      INT,
        Sporttype     INT
    )

    INSERT INTO #tmpPTSProducts (ProductID, ProductPrefix, VendorID, Sporttype)
    SELECT DISTINCT p.ProductID, p.ProductPrefix, p.VendorID, sbm.SportType
    FROM bodb02.dbo.Products p (NOLOCK)
         INNER JOIN bodb02.dbo.SportBettypeMatrix sbm (NOLOCK) ON p.ProductID = sbm.ProductID
    WHERE p.ProductID IN (SELECT DISTINCT ProductID FROM #tmpHNISettings (NOLOCK) WHERE isDeposit = 0 AND isEnable = 1 AND LogicCode = 1 AND Figure = 'Pay to Supplier')

    CREATE CLUSTERED INDEX CIX_tmpPTSProducts ON #tmpPTSProducts (VendorID, Sporttype)

    -- #tmpPTSVendorGlobalSetting
    CREATE TABLE #tmpPTSVendorGlobalSetting (
        ProductID INT,
        VName VARCHAR(50),
        NumberValue DECIMAL(19, 8),
        Sporttype INT,
        Bettype INT
    )

    INSERT INTO #tmpPTSVendorGlobalSetting (ProductID, VName, NumberValue, Sporttype, Bettype)
    SELECT p.ProductID,
           v.VName,
           v.NumberValue,
           v.sporttype,
           v.bettype
    FROM DBCUST.CustDB.dbo.VendorGlobalSetting v WITH (NOLOCK)
         INNER JOIN #tmpPTSProducts p ON v.[VendorId] = p.VendorID AND v.Sporttype = p.Sporttype
    WHERE v.VName IN ('3rdCreditWLShareRate',        -- All Product
                      '3rdCreditWLShareRateION')    -- ION Product
    
    CREATE CLUSTERED INDEX CIX_tmpPTSVendorGlobalSetting ON #tmpPTSVendorGlobalSetting(ProductID, Sporttype, Bettype)

    -- #tmpPTSMainData
    CREATE TABLE #tmpPTSMainData (
        ProductID INT,
        Rate MONEY
    )

    DECLARE @productPrefix VARCHAR(MAX);
    SELECT @productPrefix = COALESCE(@productPrefix + ',' + b.ProductPrefix, b.ProductPrefix) 
    FROM (SELECT DISTINCT ProductPrefix FROM #tmpPTSProducts) b

    SET @sqlQuery = N'SELECT ProductID, DI_Rate ' 
                      + N'FROM OPENQUERY(DBLIC, '
                      + N'''SELECT DISTINCT ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.Todate, c.MinAmount, c.MaxAmount, c.BaseCurrencyId '
                      + N'FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd('''''
                      + CAST(@FromDate AS NVARCHAR(50)) + ''''''
                      + N','''''
                      + CAST(@ToDate AS NVARCHAR(50)) + ''''''
                      + N','''''+ @productPrefix + ''''''
                      + N',''''OA'''''    
                      + N') ci '
                      + N'INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON ci.ChargeID = c.ChargeID '
                      + N'WHERE ci.ChargeType = 1 AND ci.IsDeposit = 0'
                      + N''')'

    INSERT INTO #tmpPTSMainData (ProductID, Rate)
    EXECUTE (@sqlQuery)

    INSERT INTO #tmpPTSMainData (ProductID, Rate)
    SELECT v.ProductID, v.NumberValue
    FROM #tmpPTSVendorGlobalSetting v
    WHERE v.ProductID NOT IN (SELECT ProductID FROM #tmpPTSMainData)
          AND v.VName IN ('3rdCreditWLShareRate', '3rdCreditWLShareRateION')

    CREATE CLUSTERED INDEX CIX_tmpPTSMainData ON #tmpPTSMainData(ProductID)


    ------------------------------------------------------------------------------
    -- 4. Getting source data                                                   --
    ------------------------------------------------------------------------------
    --                                                                          --
    -- Time period: After MoveBetsDay [bodb02.dbo.bettrans]                     --
    --              From MoveBetsDay onwards [bodb_Account.dbo.FactSiteWinloss] --
    --                                                                          --
    -- Dimension: RptDate                                                       --
    --            SiteID                                                        --
    --            CurrencyID                                                    --
    --            Sporttype                                                     --
    --            Bettype                                                       --
    --            LeagueID                                                      --
    --            TicketStatus                                                  --
    --            VarianceVR                                                    --
    --                                                                          --
    -- Measure:   TurnoverIBC                                                   --
    --            WinlossIBC                                                    --
    --            WinlossP                                                      --
    --            WinlossS                                                      --
    --            WinlossM                                                      --
    --            WinlossA                                                      --
    --            CommissionS                                                   --
    --            ExtraTO                                                       --
    --            ExtraWL                                                       --
    --            ExtraComm                                                     --
    --            NetStake                                                      --
    --                                                                          --
    ------------------------------------------------------------------------------

    CREATE TABLE #tmpSourceData (
        RptDate      DATE,
        SiteID       INT,
        CurrencyID   INT,
        Sporttype    INT,
        Bettype      INT,
        LeagueID     INT,
        TicketStatus INT,
        VarianceVR   DECIMAL (19, 4),
        TurnoverIBC  DECIMAL (19, 4),
        WinlossIBC   DECIMAL (19, 4),
        WinlossP     DECIMAL (19, 4),
        WinlossS     DECIMAL (19, 4),
        WinlossM     DECIMAL (19, 4),
        WinlossA     DECIMAL (19, 4),
        CommissionS  DECIMAL (19, 4),
        ExtraTO      DECIMAL (19, 6),
        ExtraWL      DECIMAL (19, 6),
        ExtraComm    DECIMAL (19, 6),
        NetStake     DECIMAL (19, 4)
    )

    SELECT @bettypeList = COALESCE(@bettypeList + ',', '') + CONVERT(VARCHAR(20), Bettype)
    FROM #tmpProductBettype
    ORDER BY Bettype

    IF (@isGetDataFromBettrans = 1)
    BEGIN
        WHILE (@FromDate_OLTP <= @ToDate_OLTP)
        BEGIN
            INSERT INTO #tmpSourceData (RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR,
                                        TurnoverIBC, WinlossIBC, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, ExtraTO, ExtraWL, ExtraComm, NetStake)
            EXEC DBACC.bodb02.dbo.Acc_Rpt_HouseNetIncome_Credit_Bettrans @FromDate_OLTP, @bettypeList

            SET @FromDate_OLTP = DATEADD(DAY, 1, @FromDate_OLTP)
        END
    END

    SET @loop_FromDate = @FromDate_DW
    SET @loop_ToDate = DATEADD(DAY, @loop_Interval, @loop_FromDate)
    IF (@loop_ToDate > @ToDate_DW) SET @loop_ToDate = @ToDate_DW

    WHILE @loop_ToDate <= @ToDate_DW
    BEGIN
        
        INSERT INTO #tmpSourceData (RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR,
                                    TurnoverIBC, WinlossIBC, WinlossP, WinlossS, WinlossM, WinlossA, CommissionS, ExtraTO, ExtraWL, ExtraComm, NetStake)
        SELECT -- *** DIMENSION *** --
               f.RptDate          RptDate,
               f.SiteID           SiteID,
               f.CurrencyID       CurrencyID,
               f.SportType        Sporttype,
               f.BetType          Bettype,
               f.LeagueID         LeagueID,
               f.TicketStatus     TicketStatus,
               f.VarianceVR       VarianceVR,
               -- *** MEASURE *** --
               SUM(f.TurnoverIBC) TurnoverIBC,
               SUM(f.WinlossIBC)  WinlossIBC,
               SUM(f.WinlossP)    WinlossP,
               SUM(f.WinlossS)    WinlossS,
               SUM(f.WinlossM)    WinlossM,
               SUM(f.WinlossA)    WinlossA,
               SUM(f.CommissionS) CommissionS,
               SUM(f.ExtraTO)     ExtraTO,
               SUM(f.ExtraWL)     ExtraWL,
               SUM(f.ExtraComm)   ExtraComm,
               SUM(f.NetStake)    NetStake
        FROM bodb_Account.dbo.FactSiteWinloss f (NOLOCK)
        WHERE f.RptDate >= @loop_FromDate AND f.RptDate <= @loop_ToDate
              AND f.BetType IN (SELECT Bettype FROM #tmpProductBettype)
        GROUP BY f.RptDate,
                 f.SiteID,
                 f.CurrencyID,
                 f.SportType,
                 f.BetType,
                 f.LeagueID,
                 f.TicketStatus,
                 f.VarianceVR
        OPTION(RECOMPILE)

        IF (@loop_ToDate = @ToDate_DW) BREAK

        SELECT @loop_FromDate = DATEADD(DAY, 1, @loop_ToDate)
        SELECT @loop_ToDate = DATEADD(DAY, @loop_Interval, @loop_FromDate)
        IF (@loop_ToDate > @ToDate_DW) SET @loop_ToDate = @ToDate_DW
    END

    CREATE CLUSTERED INDEX CIX_tmpSourceData ON #tmpSourceData(RptDate, SiteID, CurrencyID, Sporttype, Bettype, LeagueID, TicketStatus, VarianceVR)


    ---------------------------------------------------------------------------------------------
    -- 5. Getting raw data                                                                     --
    ---------------------------------------------------------------------------------------------
    --                                                                                         --
    -- Dimension: RptDate                                                                      --
    --            Site                                                                         --
    --            ProductID                                                                    --
    --            Sporttype                                                                    --
    --            Bettype                                                                      --
    --            LeagueID                                                                     --
    --                                                                                         --
    -- Measure:   HouseWL [(WinlossIBC + CommissionS) * SystemRate]                            --
    --            HouseWLOANDA [(WinlossIBC + CommissionS) * OANDARate]                        --
    --            HouseTO [(CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END) * --
    --                     (CASE WHEN VarianceVR > 0 THEN (VarianceVR + 1) ELSE 1 END) *       --
    --                     (CASE WHEN TicketStatus IN (12, 13) THEN 0.5 ELSE 1 END) *          --
    --                     (CASE WHEN TicketStatus = 3 THEN 0 ELSE 1 END) *                    --
    --                     (SystemRate)]                                                       --
    --            ExtraPT [(ExtraWL + ExtraComm) * SystemRate]                                 --
    --            ExtraPTOANDA [(ExtraWL + ExtraComm) * OANDARate]                             --
    --            MemberWL [WinlossP * SystemRate]                                             --
    --            MemberWLOANDA [WinlossP * OANDARate]                                         --
    --            ScommOANDA [CommissionS * OANDARate]                                         --
    --            Contribution [(WinlossIBC - WinlossS - WinlossM - WinlossA) * SystemRate]    --
    --            NetStakeOANDA [NetStake * OANDARate]                                         --
    --                                                                                         --
    ---------------------------------------------------------------------------------------------

    CREATE TABLE #tmpRawData (
        RptDate       DATE,
        Site          VARCHAR(200),
        ProductID     INT,
        Sporttype     INT,
        Bettype       INT,
        LeagueID      INT,
        HouseWL       DECIMAL(19, 4),
        HouseWLOANDA  DECIMAL(19, 4),
        HouseTO       DECIMAL(19, 4),
        ExtraPT       DECIMAL(19, 4),
        ExtraPTOANDA  DECIMAL(19, 4),
        MemberWL      DECIMAL(19, 4),
        MemberWLOANDA DECIMAL(19, 4),
        ScommOANDA    DECIMAL(19, 4),
        Contribution  DECIMAL(19, 4),
        NetStakeOANDA DECIMAL(19, 4)
    )

    SET @loop_FromDate = @FromDate
    SET @loop_ToDate = DATEADD(DAY, @loop_Interval, @loop_FromDate)
    IF (@loop_ToDate > @ToDate) SET @loop_ToDate = @ToDate

    WHILE @loop_ToDate <= @ToDate
    BEGIN
        INSERT INTO #tmpRawData (RptDate, Site, ProductID, Sporttype, Bettype, LeagueID,
                                 HouseWL, HouseWLOANDA,
                                 HouseTO,
                                 ExtraPT, ExtraPTOANDA,
                                 MemberWL, MemberWLOANDA,
                                 ScommOANDA,
                                 Contribution,
                                 NetStakeOANDA)
        SELECT -- *** DIMENSION *** --
               b.RptDate,
               s.site Site,
               CASE WHEN b.Bettype IN (9, 29)                       THEN -10 --Parlay
                    WHEN b.SportType = 1  AND l.LeagueGroupType = 1 THEN -3  --Saba Soc
                    WHEN b.SportType = 1  AND l.LeagueGroupType = 2 THEN -14 --Saba Soc PGoal
                    WHEN b.SportType = 2  AND l.LeagueGroupType = 1 THEN -5  --Saba Bas
                    WHEN b.SportType = 2  AND l.LeagueGroupType = 2 THEN -15 --Saba Bas PGoal
                    WHEN b.Sporttype = 43 AND l.LeagueGroupType = 2 THEN -16 --Saba E-S PGoal
                    WHEN b.SportType = 50 AND l.LeagueGroupType = 1 THEN -8  --Saba Cric
                    WHEN b.SportType = 1                            THEN -2  --Real Soc
                    WHEN b.SportType = 2                            THEN -4  --Real Bas
                    WHEN b.SportType = 5                            THEN -6  --Tennis
                    WHEN b.SportType = 43                           THEN -7  --E-Sports
                    WHEN pb.ProductID = 1                           THEN -9  --OtherSp
                    WHEN pb.ProductID = 3 AND b.Sporttype = 161     THEN -11 --NumG
                    WHEN pb.ProductID = 3 AND Sporttype = 164       THEN -12 --Happy5
                    WHEN pb.ProductID = 3 AND Sporttype = 168       THEN -13 --Happy5 LG
                    ELSE ISNULL(pb.ProductID, -1) END ProductID,             --Unknown
               b.SportType,
               b.BetType,
               b.LeagueID,
               -- *** MEASURE *** --
               SUM((CASE WHEN b.SiteID IN (-2, -4) THEN 0 ELSE (b.WinlossIBC + b.CommissionS) END) * ISNULL(es.Rate, 0)) HouseWL,
               SUM((CASE WHEN b.SiteID IN (-2, -4) THEN 0 ELSE (b.WinlossIBC + b.CommissionS) END) * ISNULL(eo.Rate, 0)) HouseWLOANDA,
               SUM((CASE WHEN b.TurnoverIBC = 0 THEN 0 ELSE b.TurnoverIBC - b.ExtraTO END) *
                   (CASE WHEN b.VarianceVR > 0 THEN (b.VarianceVR + 1) ELSE 1 END) *
                   (CASE WHEN b.TicketStatus IN (12, 13) THEN 0.5 ELSE 1 END) *
                   (CASE WHEN b.TicketStatus = 3 THEN 0 ELSE 1 END) *
                   ISNULL(es.Rate, 0)) HouseTO,
               SUM((CASE WHEN b.SiteID IN (-2, -4) THEN 0 ELSE (b.ExtraWL + b.ExtraComm) END) * ISNULL(es.Rate, 0)) ExtraPT,
               SUM((CASE WHEN b.SiteID IN (-2, -4) THEN 0 ELSE (b.ExtraWL + b.ExtraComm) END) * ISNULL(eo.Rate, 0)) ExtraPTOANDA,
               SUM(b.WinlossP * ISNULL(es.Rate, 0)) MemberWL,
               SUM(b.WinlossP * ISNULL(eo.Rate, 0)) MemberWLOANDA,
               SUM(b.CommissionS * ISNULL(eo.Rate, 0)) ScommOANDA,
               SUM((b.WinlossIBC - b.WinlossS - b.WinlossM - b.WinlossA) * ISNULL(es.Rate, 0)) Contribution,
               SUM(b.NetStake * ISNULL(eo.Rate, 0)) NetStakeOANDA
        FROM #tmpSourceData b (NOLOCK)
             INNER JOIN bodb_Account.dbo.tbl_Site s (NOLOCK) ON s.isDeposit = 0 AND CASE WHEN b.SiteID = -2 THEN 10
                                                                                         WHEN b.SiteID = -4 THEN 3
                                                                                         ELSE b.SiteID END = s.siteid
             LEFT JOIN #tmpProductBettype pb (NOLOCK) ON b.Bettype = pb.Bettype
             LEFT JOIN #tmpExchangeSystem es ON b.rptdate = es.ExchangeDate AND b.CurrencyID = es.ExchangeID
             LEFT JOIN #tmpExchangeOANDA eo ON b.CurrencyID = eo.ExchangeID
             LEFT JOIN #tmpLeague l ON b.LeagueID = l.LeagueID
        WHERE RptDate >= @loop_FromDate AND RptDate <= @loop_ToDate
              AND b.TicketStatus NOT IN (-1, 18, 9, 10, 14)
              AND b.CurrencyID <> 20
              AND b.BetType IN (SELECT Bettype FROM #tmpProductBettype)
        GROUP BY b.RptDate,
                 s.site,
                 CASE WHEN b.Bettype IN (9, 29)                       THEN -10 --Parlay
                      WHEN b.SportType = 1  AND l.LeagueGroupType = 1 THEN -3  --Saba Soc
                      WHEN b.SportType = 1  AND l.LeagueGroupType = 2 THEN -14 --Saba Soc PGoal
                      WHEN b.SportType = 2  AND l.LeagueGroupType = 1 THEN -5  --Saba Bas
                      WHEN b.SportType = 2  AND l.LeagueGroupType = 2 THEN -15 --Saba Bas PGoal
                      WHEN b.Sporttype = 43 AND l.LeagueGroupType = 2 THEN -16 --Saba E-S PGoal
                      WHEN b.SportType = 50 AND l.LeagueGroupType = 1 THEN -8  --Saba Cric
                      WHEN b.SportType = 1                            THEN -2  --Real Soc
                      WHEN b.SportType = 2                            THEN -4  --Real Bas
                      WHEN b.SportType = 5                            THEN -6  --Tennis
                      WHEN b.SportType = 43                           THEN -7  --E-Sports
                      WHEN pb.ProductID = 1                           THEN -9  --OtherSp
                      WHEN pb.ProductID = 3 AND b.Sporttype = 161     THEN -11 --NumG
                      WHEN pb.ProductID = 3 AND Sporttype = 164       THEN -12 --Happy5
                      WHEN pb.ProductID = 3 AND Sporttype = 168       THEN -13 --Happy5 LG
                      ELSE ISNULL(pb.ProductID, -1) END,                       --Unknown
                 b.SportType,
                 b.BetType,
                 b.LeagueID
        OPTION(RECOMPILE)

        IF (@loop_ToDate = @ToDate) BREAK

        SELECT @loop_FromDate = DATEADD(DAY, 1, @loop_ToDate)
        SELECT @loop_ToDate = DATEADD(DAY, @loop_Interval, @loop_FromDate)
        IF (@loop_ToDate > @ToDate) SET @loop_ToDate = @ToDate
    END

    CREATE CLUSTERED INDEX CIX_tmpRawData ON #tmpRawData(RptDate, Site, ProductID, Sporttype, Bettype, LeagueID)


    ----------------------------
    -- 5. Getting detail data --
    ----------------------------

    CREATE TABLE #tmpDetailData (
        RptDate DATE,
        isDeposit BIT,
        OrderByProduct INT,
        OrderByFigure INT,
        SiteGroup VARCHAR(20),
        ProductCategory VARCHAR(50),
        ProductGroup VARCHAR(50),
        ProductName VARCHAR(50),
        ProductShortName VARCHAR(50),
        Figure VARCHAR(200),
        SubFigure VARCHAR(200),
        DataValue DECIMAL(19, 4)
    )

    ;WITH CTE_DetailData AS (
        SELECT b.RptDate,
               hni.isDeposit,
               hni.OrderByProduct,
               hni.OrderByFigure,
               b.Site,
               hni.ProductCategory,
               hni.ProductGroup,
               hni.ProductName,
               hni.ProductShortName,
               hni.Figure,
               hni.SubFigure,
               CASE WHEN hni.Figure = 'Credit House Income' THEN SUM(CASE WHEN bg2.BettypeGroupID = 14 THEN -(b.MemberWL)
                                                                          ELSE -(b.HouseWL) END)
                    WHEN hni.Figure = 'House Turnover' THEN SUM(b.HouseTO)
                    WHEN hni.Figure = 'Extra PT' THEN SUM(b.ExtraPT)
                    WHEN hni.Figure = 'Pay to Supplier' THEN CASE WHEN hni.ProductShortName = 'Arcadia' THEN SUM(b.MemberWLOANDA * (CASE WHEN bg2.BettypeGroupID = 14 THEN 1
                                                                                                                                         WHEN bg1.BettypeGroupID = 15 THEN 0.025
                                                                                                                                         ELSE 0.035 END))
                                                                  WHEN hni.ProductShortName = 'MacauG' THEN SUM(b.MemberWLOANDA * (CASE WHEN bg1.BettypeGroupID = 11 THEN 0.03 ELSE 0.02 END))
                                                                  WHEN hni.ProductShortName = 'NG2' THEN SUM((-b.HouseWLOANDA + (CASE WHEN b.RptDate >= '2020-11-01' THEN 0 ELSE b.ExtraPTOANDA END)) * (-0.5))
                                                                  WHEN hni.ProductShortName = 'TableG' THEN SUM(b.MemberWLOANDA * (CASE WHEN b.RptDate >= '2020-07-01' THEN 0.036 ELSE 0.03 END))
                                                                  WHEN hni.ProductShortName IN ('MKeno', 'MLotte') THEN SUM(b.MemberWLOANDA * (CASE WHEN b.Site = 'CN88' THEN 0.015 ELSE (CASE WHEN b.RptDate >= '2020-07-01' THEN 0.036 ELSE 0.03 END) END))
                                                                  WHEN hni.ProductShortName IN ('VirtSpo2', 'VirtSpo') THEN SUM(b.MemberWLOANDA * 0.01)
                                                                  WHEN hni.ProductShortName IN ('NumG', 'Happy5', 'Happy5 LG') THEN CASE WHEN b.Site = 'CN88' THEN SUM(b.MemberWLOANDA * 0.015)
                                                                                                                                         WHEN b.Site IN ('IBCIndo', '76666b') THEN SUM((-b.HouseWLOANDA + b.ExtraPTOANDA) * (-0.5))
                                                                                                                                         ELSE SUM((-b.HouseWLOANDA + (CASE WHEN b.RptDate >= '2020-11-01' THEN 0 ELSE b.ExtraPTOANDA END)) * (-0.5)) END
                                                                  WHEN hni.ProductShortName IN ('GDG LC') THEN SUM((b.MemberWLOANDA + (b.NetStakeOANDA * 0.01)) * ISNULL( pts.Rate, 0))
                                                                  ELSE SUM(b.MemberWLOANDA * ISNULL( pts.Rate, 0)) END
                    WHEN hni.Figure = 'Pay to Bet Genius' THEN SUM((b.MemberWLOANDA + b.ScommOANDA) * 0.04 * (CASE WHEN b.Bettype = 38 THEN 1 ELSE 0 END))
                    WHEN hni.Figure = 'Contribution Amount' THEN SUM(b.Contribution * (CASE WHEN bg1.BettypeGroupID = 10 AND bg1.BettypeName LIKE '%Jackpot%' THEN 1 ELSE 0 END))
                    WHEN hni.Figure = 'Mega Prize'  THEN -SUM(b.MemberWL * (CASE WHEN bg1.BettypeGroupID = 6 AND bg1.BettypeName LIKE '%Jackpot%' THEN 1 ELSE 0 END))
                    WHEN hni.Figure = 'Jackpot Prize'  THEN -SUM(b.MemberWL * (CASE WHEN bg1.BettypeGroupID = 6 AND bg1.BettypeName LIKE '%Jackpot%' THEN 1 ELSE 0 END))
                    ELSE NULL END DataValue
        FROM #tmpRawData b (NOLOCK)
             INNER JOIN #tmpHNISettings hni (NOLOCK) ON hni.isDeposit = 0 AND hni.isEnable = 1 AND hni.LogicCode = 1 AND b.ProductID = hni.AliasProductID
             LEFT JOIN #tmpPTSMainData pts  ON b.ProductID = pts.ProductID
             LEFT JOIN #tmpBettypeGroup bg1 ON bg1.BettypeGroupID IN (6, 10, 11, 15) AND b.Bettype = bg1.Bettype
             LEFT JOIN #tmpBettypeGroup bg2 ON bg2.BettypeGroupID IN (14) AND b.Bettype = bg2.Bettype
        GROUP BY b.RptDate,
                 hni.isDeposit,
                 hni.OrderByProduct,
                 hni.OrderByFigure,
                 b.Site,
                 hni.ProductCategory,
                 hni.ProductGroup,
                 hni.ProductName,
                 hni.ProductPrefix,
                 hni.ProductShortName,
                 hni.Figure,
                 hni.SubFigure
    )
    INSERT INTO #tmpDetailData (RptDate, isDeposit, OrderByProduct, OrderByFigure, SiteGroup, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure, DataValue)
    SELECT RptDate,
           isDeposit,
           OrderByProduct,
           OrderByFigure,
           CASE WHEN Site = 'CN88' THEN 'CN88'
                WHEN Site = '789Y' THEN '789Y'
                ELSE 'MBC' END SiteGroup,
           ProductCategory,
           ProductGroup,
           ProductName,
           ProductShortName,
           Figure,
           SubFigure,
           SUM(DataValue) DataValue
    FROM CTE_DetailData
    GROUP BY RptDate,
             isDeposit,
             OrderByProduct,
             OrderByFigure,
             CASE WHEN Site = 'CN88' THEN 'CN88'
                       WHEN Site = '789Y' THEN '789Y'
                       ELSE 'MBC' END,
             ProductCategory,
             ProductGroup,
             ProductName,
             ProductShortName,
             Figure,
             SubFigure
    OPTION(RECOMPILE)


    -------------------------------------------------------------
    -- 6. Pivot detail data to get the final expected data set --
    -------------------------------------------------------------

    -- Create table #tmpFinalData
    CREATE TABLE #tmpFinalData (
        [isDeposit]        BIT,
        [OrderByProduct]   INT,
        [OrderByFigure]    INT,
        [SiteGroup]        VARCHAR(20),
        [ProductCategory]  VARCHAR(50),
        [ProductGroup]     VARCHAR(50),
        [ProductName]      VARCHAR(50),
        [ProductShortName] VARCHAR(50), 
        [Figure]           VARCHAR(200),
        [SubFigure]        VARCHAR(200),
        [Monthly]          DECIMAL(19, 4) DEFAULT 0,
        [MTD]              DECIMAL(19, 4) DEFAULT 0,
        [01]               DECIMAL(19, 4) DEFAULT 0,
        [02]               DECIMAL(19, 4) DEFAULT 0,
        [03]               DECIMAL(19, 4) DEFAULT 0,
        [04]               DECIMAL(19, 4) DEFAULT 0,
        [05]               DECIMAL(19, 4) DEFAULT 0,
        [06]               DECIMAL(19, 4) DEFAULT 0,
        [07]               DECIMAL(19, 4) DEFAULT 0,
        [08]               DECIMAL(19, 4) DEFAULT 0,
        [09]               DECIMAL(19, 4) DEFAULT 0,
        [10]               DECIMAL(19, 4) DEFAULT 0,
        [11]               DECIMAL(19, 4) DEFAULT 0,
        [12]               DECIMAL(19, 4) DEFAULT 0,
        [13]               DECIMAL(19, 4) DEFAULT 0,
        [14]               DECIMAL(19, 4) DEFAULT 0,
        [15]               DECIMAL(19, 4) DEFAULT 0,
        [16]               DECIMAL(19, 4) DEFAULT 0,
        [17]               DECIMAL(19, 4) DEFAULT 0,
        [18]               DECIMAL(19, 4) DEFAULT 0,
        [19]               DECIMAL(19, 4) DEFAULT 0,
        [20]               DECIMAL(19, 4) DEFAULT 0,
        [21]               DECIMAL(19, 4) DEFAULT 0,
        [22]               DECIMAL(19, 4) DEFAULT 0,
        [23]               DECIMAL(19, 4) DEFAULT 0,
        [24]               DECIMAL(19, 4) DEFAULT 0,
        [25]               DECIMAL(19, 4) DEFAULT 0,
        [26]               DECIMAL(19, 4) DEFAULT 0,
        [27]               DECIMAL(19, 4) DEFAULT 0,
        [28]               DECIMAL(19, 4) DEFAULT 0,
        [29]               DECIMAL(19, 4) DEFAULT 0,
        [30]               DECIMAL(19, 4) DEFAULT 0,
        [31]               DECIMAL(19, 4) DEFAULT 0
    )

    -- Initialize data for #tmpFinalData
    INSERT INTO #tmpFinalData ([isDeposit], [OrderByProduct], [OrderByFigure], [SiteGroup], [ProductCategory], [ProductGroup], [ProductName], [ProductShortName], [Figure], [SubFigure])
    SELECT isDeposit, OrderByProduct, OrderByFigure, 'CN88' SiteGroup, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure
    FROM #tmpHNISettings (NOLOCK)
    WHERE isDeposit = 0 AND isEnable = 1 AND LogicCode = 1
          AND ((EndOfSupportDate IS NULL) OR (EndOfSupportDate IS NOT NULL AND EndOfSupportDate >= @FromDate))
          AND ProductName IN ('Sportsbook','Number Game', 'Happy 5', 'Virtual Sports', 'RNG Keno', 'Virtual Sports 2', 'Lottery')
    UNION ALL
    SELECT isDeposit, OrderByProduct, OrderByFigure, '789Y' SiteGroup, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure
    FROM #tmpHNISettings (NOLOCK)
    WHERE isDeposit = 0 AND isEnable = 1 AND LogicCode = 1
          AND ((EndOfSupportDate IS NULL) OR (EndOfSupportDate IS NOT NULL AND EndOfSupportDate >= @FromDate))
    UNION ALL
    SELECT isDeposit, OrderByProduct, OrderByFigure, 'MBC' SiteGroup, ProductCategory, ProductGroup, ProductName, ProductShortName, Figure, SubFigure
    FROM #tmpHNISettings (NOLOCK)
    WHERE isDeposit = 0 AND isEnable = 1 AND LogicCode = 1
          AND ((EndOfSupportDate IS NULL) OR (EndOfSupportDate IS NOT NULL AND EndOfSupportDate >= @FromDate))

    -- Insert detail data to table #tmpFinalData
    SET @finalDataDate = @FromDate

    WHILE (@finalDataDate <= @ToDate)
    BEGIN
        SET @sqlQuery =
        '
        ;WITH CTE_Detail AS (
            SELECT detail.isDeposit,
                   detail.OrderByProduct,
                   detail.OrderByFigure,
                   detail.SiteGroup,
                   detail.ProductCategory,
                   detail.ProductGroup,
                   detail.ProductName,
                   detail.ProductShortName,
                   detail.Figure,
                   detail.SubFigure,
                   detail.DataValue
            FROM #tmpDetailData detail
            WHERE detail.RptDate = ''' + CONVERT(VARCHAR(10), @finalDataDate, 112) + ''')' + CHAR(13) +
        'UPDATE main
        SET main.[' + LEFT(CONVERT(VARCHAR(10), @finalDataDate, 106), 2) + ']' + '= cte.DataValue
        FROM #tmpFinalData main
             INNER JOIN CTE_Detail cte ON main.[OrderByProduct] = cte.OrderByProduct
                                          AND main.[OrderByFigure] = cte.OrderByFigure
                                          AND main.[SiteGroup] = cte.SiteGroup
                                          AND main.[ProductShortName] = cte.ProductShortName
                                          AND main.[Figure] = cte.Figure
                                          AND main.[SubFigure] = cte.SubFigure'

        EXEC (@sqlQuery)

        SET @finalDataDate = DATEADD(DAY, 1, @finalDataDate)
    END

    -- Calculate for MTD column in #tmpFinalData
    UPDATE f
    SET f.[MTD] = f.[01] + f.[02] + f.[03] + f.[04] + f.[05] + f.[06] + f.[07] + f.[08] + f.[09] + f.[10] +
                  f.[11] + f.[12] + f.[13] + f.[14] + f.[15] + f.[16] + f.[17] + f.[18] + f.[19] + f.[20] + 
                  f.[21] + f.[22] + f.[23] + f.[24] + f.[25] + f.[26] + f.[27] + f.[28] + f.[29] + f.[30] + 
                  f.[31]
    FROM #tmpFinalData f

    -- Calculate for Monthly column in #tmpFinalData
    UPDATE f
    SET f.[Monthly] = f.[MTD]
    FROM #tmpFinalData f
    WHERE (f.ProductShortName NOT IN ('VirtSpo2', 'VirtSpo', 'MacauG') AND f.Figure NOT IN ('Pay to Bet Genius'))
          OR (f.ProductShortName IN ('VirtSpo2', 'VirtSpo', 'MacauG') AND f.Figure NOT IN ('Pay to Supplier'))

    UPDATE f
    SET f.[Monthly] = (f.[MTD] * (CASE WHEN f.[MTD] > 0 THEN 0 ELSE 1 END))
    FROM #tmpFinalData f
    WHERE f.ProductShortName IN ('VirtSpo2', 'VirtSpo')
          AND f.Figure IN ('Pay to Supplier')
          AND f.SiteGroup = 'CN88'

    ;WITH
    CTE_SumUpData AS (
        SELECT f.ProductShortName,
               f.Figure,
               SUM(f.[MTD]) [MTD]
        FROM #tmpFinalData f
        WHERE (f.ProductShortName IN ('VirtSpo2', 'VirtSpo', 'MacauG') AND f.Figure IN ('Pay to Supplier') AND f.SiteGroup <> 'CN88')
              OR (f.Figure IN ('Pay to Bet Genius'))
        GROUP BY f.ProductShortName,
                 f.Figure
    )
    UPDATE f
    SET f.[Monthly] = (f.[MTD] * (CASE WHEN cte.[MTD] > 0 THEN 0 ELSE 1 END))
    FROM #tmpFinalData f
         LEFT JOIN CTE_SumUpData cte ON f.ProductShortName = cte.ProductShortName AND f.Figure = cte.Figure
    WHERE (f.ProductShortName IN ('VirtSpo2', 'VirtSpo', 'MacauG') AND f.Figure IN ('Pay to Supplier') AND f.SiteGroup <> 'CN88')
          OR (f.Figure IN ('Pay to Bet Genius'))


    --------------------
    -- 7. Select data --
    --------------------

    SELECT f.[isDeposit], f.[OrderByProduct], f.[OrderByFigure], f.[SiteGroup], f.[ProductCategory], f.[ProductGroup], f.[ProductName], f.[ProductShortName], f.[Figure], f.[SubFigure],
           f.[Monthly], f.[MTD],
           f.[01], f.[02], f.[03], f.[04], f.[05], f.[06], f.[07], f.[08], f.[09], f.[10], f.[11], f.[12], f.[13], f.[14], f.[15], f.[16], f.[17], f.[18], f.[19], f.[20], f.[21], f.[22], f.[23], f.[24], f.[25], f.[26], f.[27], f.[28], f.[29], f.[30], f.[31]
    FROM #tmpFinalData f
    ORDER BY f.[isDeposit], f.[SiteGroup], f.[OrderByProduct], f.[OrderByFigure]


    -------------------------
    -- 8. Drop temp tables --
    -------------------------

    DROP TABLE #tmpBettypeGroup
    DROP TABLE #tmpProductList
    DROP TABLE #tmpHNISettings
    DROP TABLE #tmpProductBettype

    DROP TABLE #tmpExchangeSystem
    DROP TABLE #tmpExchangeOANDA
    DROP TABLE #tmpLeague
    DROP TABLE #tmpPTSProducts
    DROP TABLE #tmpPTSVendorGlobalSetting
    DROP TABLE #tmpPTSMainData

    DROP TABLE #tmpSourceData

    DROP TABLE #tmpRawData

    DROP TABLE #tmpDetailData

    DROP TABLE #tmpFinalData

END
GO
/*<info serverAlias="DBWH-bodb_dwrs" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_SBCustPerfByDangerLevel
	@FromDate DATE
	,@ToDate DATE
	,@Divisions VARCHAR(MAX) = 'ALL'
	,@DangerLevels VARCHAR(MAX) = '1_50'
	,@SportBettypes VARCHAR(MAX) = 'ALL'
	,@LeagueName NVARCHAR(500) = 'All Leagues'
	,@LeagueGroupIDs VARCHAR(MAX) = 'ALL'
	,@LiveStatus VARCHAR(10) = 'ALL'
	,@TopUsers INT = 10
AS
/*
	Created: 20210105@Roy
	Task : Get SB Customer Performance filtered by ABI danger level
	DB: DBDW.bodb_dwrs

	Revisions:
		20210105@Roy: NAP Report - Implement Top Punter report (#145833)
		20210413@Kean: Add More DangerLevel Filter (#153264)
		20210818@Roy: NAP Report - SB Customer Performance By Dangers Report - Support filter multiple days (#160348)
		202109001@Jaden: Add 2 more Dangerous types (#159779)
		20230809@Jaden: Parlay boost bonus (#191900)
		20230914@Jaden: Add column Given Credit (#193974)
		20231024@Jaden: NAP Report - SB Customer Performance By Dangers - Support to query the data to 1 week (#195876)

	Param's Explanation:
		@Divisions: List of site names
		@DangerLevels: List of DangerType and DangerLevel with format: DangerType_DangerLevel (ex: 1_0,2_30,3_20)
						DangerType: 1(Original Level), 2(ABI Level), 3(O.Sports Level)
						DangerLevel: From 1 to 50
		@SportBettypes: List of Sporttypes and Bettypes with format: Sport_Bettype (ex: 43_2,29_9)
		@LeagueName: exactly league name - 'All Leagues' for all
		@LeagueGroupIDs: List of LeagueGroups by IDs
		@LiveStatus: ALL, Non-Live, Live
		@TopUsers: No. of user order by member winlost
	
	Script: EXEC Acc_Rpt_SBCustPerfByDangerLevel
											@WinlostDate = '2020-12-06'
											,@Divisions = 'ALL'
											,@DangerLevels = ''
											,@SportBettypes = 'ALL'
											,@LeagueName = 'All Leagues'
											,@LeagueGroupIDs = 'ALL'
											,@LiveStatus = 'All'
											,@TopUsers = 9999
*/
BEGIN

    SET NOCOUNT ON
    
    IF @TopUsers < 0
        SET @TopUsers = 0

    DECLARE @IsLive BIT
    IF @LiveStatus = 'Live'
        SET @IsLive = 1
    ELSE IF @LiveStatus = 'Non-Live'
        SET @IsLive = 0 

    DECLARE @FactRangeMax DATE = DATEADD(DAY, -2, CAST(GETDATE() AS DATE))

    ---Create temp tables---
    CREATE TABLE #tmpSportBettypes (
        SportType SMALLINT
        ,Bettype SMALLINT
    )
    ;WITH CTE_SportBettype AS (
        SELECT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS SportType
            ,CAST(SUBSTRING(val, CHARINDEX('_', val) + 1, LEN(val)) AS SMALLINT) AS BetType
        FROM bodb_dwrs.dbo.strSplit_str(@SportBettypes, ',')
        WHERE val <> 'ALL'
            AND LEN(val) > 0
    )
    INSERT INTO #tmpSportBettypes (
        SportType
        ,BetType
    )
    SELECT DISTINCT sbm.SportType
        ,sbm.BetType
    FROM bodb02.dbo.SportBettypeMatrix sbm(NOLOCK)
        INNER JOIN bodb02.dbo.bettype b(NOLOCK) ON sbm.BetType = b.typeid
    WHERE sbm.ProductID = 1
        AND sbm.SportType <> 27 --Cricket (use 50)
        AND sbm.SubProduct NOT IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
        AND sbm.BetType NOT IN (9, 29, 999, 998) --Parlay & Odds Spread Adjustment & Parlay boost bonus
        AND (
            @SportBettypes = 'ALL'
            OR EXISTS (
                SELECT 1
                FROM CTE_SportBettype psb
                WHERE sbm.SportType = psb.SportType
                    AND sbm.BetType = psb.BetType
                )
            )
    OPTION (RECOMPILE)
    CREATE CLUSTERED INDEX [CIX_tmpsb] ON #tmpSportBettypes( SportType, BetType )

    CREATE TABLE #tmpLeague (
        LeagueID INT,
        SportType INT
    )
    INSERT INTO #tmpLeague
    SELECT l.leagueid, l.sporttype
    FROM bodb02.dbo.League l(NOLOCK)
        LEFT JOIN bodb02.dbo.LeagueGroup lg(NOLOCK) ON l.LeagueGroupID = lg.GroupID
    WHERE l.isTest = 0 AND l.leagueid >= 0
        AND (@LeagueName = 'All Leagues' OR l.leaguename = @LeagueName)
        AND (@LeagueGroupIDs = 'ALL' OR l.LeagueGroupID IN (SELECT val FROM bodb_dwrs.dbo.strSplit_str(@LeagueGroupIDs, ',')))

    CREATE TABLE #tmpDangerLevel (
        DangerType INT
        ,DangerLevel INT
    )
    IF LEN(@DangerLevels) > 0 AND @DangerLevels <> 'ALL'
    BEGIN
        INSERT INTO #tmpDangerLevel(DangerType,DangerLevel)
        SELECT CAST(LEFT(val, CHARINDEX('_', val) - 1) AS SMALLINT) AS DangerType
            ,CAST(SUBSTRING(val, CHARINDEX('_', val) + 1, LEN(val)) AS SMALLINT) AS DangerLevel
        FROM bodb_dwrs.dbo.strSplit_str(@DangerLevels, ',')
        WHERE val <> 'ALL'
            AND LEN(val) > 0

        CREATE UNIQUE INDEX [CIX_tmpDangerLevel] ON #tmpDangerLevel(DangerType,DangerLevel)
    END
    ELSE
    BEGIN
        SET @DangerLevels = 'ALL'
    END

    CREATE TABLE #tmpSite (
        DwSiteID INT
        ,SiteName VARCHAR(100)
    )
    INSERT INTO #tmpSite
    SELECT [siteid], [site]
    FROM bodb_Account.dbo.tbl_Site
    WHERE [site] IN (SELECT val FROM bodb_dwrs.dbo.strSplit_str(@Divisions, ','))

    CREATE TABLE #tmpRawData (
        CustID INT
        ,SiteID INT
        ,AgentID INT
        ,MasterID INT
        ,SuperID INT
        ,SportType SMALLINT
        ,Bettype SMALLINT
        ,Currency INT
        ,BetCount INT
        ,MemberTO DECIMAL(25, 8)
        ,MemberWL DECIMAL(25, 8)
        ,RealIncome DECIMAL(25, 8)
        ,RealTurnover DECIMAL(25, 8)
    )
    CREATE TABLE #tmpFiltered (
        CustID INT
        ,SiteID INT
        ,danger  INT
        ,danger2 INT
        ,danger3 INT
        ,danger4 INT
        ,danger5 INT
        ,AgentID INT
        ,MasterID INT
        ,SuperID INT
        ,Currency NVARCHAR(50)
        ,GivenCredit MONEY
        ,BetCount INT
        ,MemberTO DECIMAL(19, 2)
        ,MemberWL DECIMAL(19, 2)
        ,RealIncome DECIMAL(19, 2)
        ,RealTurnover DECIMAL(19, 2)
    )

    INSERT INTO #tmpRawData WITH(TABLOCK)(
        CustID
        ,SiteID
        ,AgentID
        ,MasterID
        ,SuperID
        ,SportType
        ,Bettype
        ,Currency
        ,BetCount
        ,MemberTO
        ,MemberWL
        ,RealIncome
        ,RealTurnover
    )
    SELECT b.CustID
        ,b.SiteID
        ,b.recommend
        ,b.mrecommend
        ,b.srecommend
        ,b.SportType
        ,b.Bettype
        ,b.currency
        ,SUM(CASE WHEN co.VendorID = 14 THEN 0 ELSE 1 END) AS BetCount --exclude dummy cashout accounts
        ,SUM(ABS(b.Stake) * b.actualrate) AS MemberTO
        ,SUM((winlost-actual_stake) * b.actualrate) MemberWL
        ,-SUM((b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm - (CASE WHEN b.tpositiontaking = 1 THEN 0
                                                                                                ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                            END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(10, 8)), 0)) * b.actualrate) AS RealIncome
        ,SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
                ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(10, 8)), 0))
                        * ABS(stake)
                        * (CASE WHEN b.virtualrate > b.actualrate THEN b.virtualrate
                            ELSE b.actualrate END)
            END) AS RealTurnover
    FROM bodb_ODS.dbo.ODS_bettrans b WITH (NOLOCK)
        LEFT JOIN bodb02.dbo.TradeCust AS co WITH (NOLOCK) ON b.CustID = co.CustID
    WHERE b.Currency NOT IN (20, 27, 28)
        AND b.TicketStatusID IN (8, 4, 3, 12, 13)
        and b.Bettype IN ( SELECT DISTINCT BetType FROM #tmpSportBettypes )
        AND ISNULL(b.liveindicator, 0) = COALESCE(@IsLive, b.Liveindicator, 0)
        AND ('ALL' = @Divisions OR b.SiteID IN (SELECT DwSiteID FROM #tmpSite))
        AND ('ALL' = @LeagueGroupIDs OR b.LeagueID IN (SELECT LeagueID FROM #tmpLeague))
        AND ('All Leagues' = @LeagueName OR b.LeagueID IN (SELECT LeagueID FROM #tmpLeague))
        AND @TopUsers > 0
        AND b.winlostdate BETWEEN @FromDate AND @ToDate
        and b.winlostdate >= @FactRangeMax
    GROUP BY b.CustID
        ,b.SiteID
        ,b.recommend
        ,b.mrecommend
        ,b.srecommend
        ,b.SportType
        ,b.Bettype
        ,b.Currency
    OPTION (RECOMPILE, MAX_GRANT_PERCENT=25)

    INSERT INTO #tmpRawData WITH(TABLOCK)(
        CustID
        ,SiteID
        ,AgentID
        ,MasterID
        ,SuperID
        ,SportType
        ,Bettype
        ,Currency
        ,BetCount
        ,MemberTO
        ,MemberWL
        ,RealIncome
        ,RealTurnover
    )
    SELECT b.CustID
        ,b.SiteID
        ,b.AgentID
        ,b.MasterID
        ,b.SuperID
        ,b.SportType
        ,b.Bettype
        ,b.CurrencyID
        ,SUM(CASE WHEN co.VendorID = 14 THEN 0 ELSE b.BetCount END) AS BetCount --exclude dummy cashout accounts
        ,SUM(abs(Stake) * e.Rate) AS MemberTO
        ,SUM(WinlossP * e.Rate) MemberWL
        ,-SUM((WinlossIBC - ExtraWL + CommissionS - ExtraComm) * e.Rate) AS RealIncome
        ,SUM((CASE WHEN TurnoverIBC = 0 THEN 0 ELSE TurnoverIBC - ExtraTO END)
                               * (CASE WHEN VarianceVR > 0 THEN (VarianceVR + 1) ELSE 1 END)*e.Rate) RealTurnover
    FROM bodb_Account.dbo.FactCustWinloss b WITH (NOLOCK)
        LEFT JOIN bodb02.dbo.TradeCust AS co WITH (NOLOCK) ON b.CustID = co.CustID
        LEFT JOIN bodb_Account.dbo.tbl_Currency_Daily AS e WITH (NOLOCK) ON b.CurrencyID = e.Currency AND b.RptDate = CONVERT(DATE,e.ExchangeDate)
    WHERE b.CurrencyID NOT IN (20, 27, 28)
        AND b.TicketStatus IN (8, 4, 3, 12, 13) --(won/lose/draw/half won/half lose)
        AND b.Bettype IN ( SELECT DISTINCT BetType FROM #tmpSportBettypes )
        AND (@IsLive IS NULL OR (@IsLive IS NOT NULL AND b.LiveStatus = @IsLive))
        AND ('ALL' = @Divisions OR b.SiteID IN (SELECT DwSiteID FROM #tmpSite))
        AND ('ALL' = @LeagueGroupIDs OR b.LeagueID IN (SELECT LeagueID FROM #tmpLeague))
        AND ('All Leagues' = @LeagueName OR b.LeagueID IN (SELECT LeagueID FROM #tmpLeague))
        AND @TopUsers > 0
        AND b.RptDate BETWEEN @FromDate AND @ToDate
        AND b.RptDate < @FactRangeMax
    GROUP BY b.CustID
        ,b.SiteID
        ,b.AgentID
        ,b.MasterID
        ,b.SuperID
        ,b.SportType
        ,b.Bettype
        ,b.CurrencyID
    OPTION (RECOMPILE, MAX_GRANT_PERCENT=25)
    
    CREATE CLUSTERED INDEX [CIX_tmpRawData] ON #tmpRawData(
        Bettype
        ,SportType
        ,CustID
        ,AgentID
        ,MasterID
        ,SuperID
        ,Currency
    )
    

    INSERT INTO #tmpFiltered (
        CustID
        ,SiteID
        ,danger
        ,danger2
        ,danger3
        ,danger4
        ,danger5
        ,AgentID
        ,MasterID
        ,SuperID
        ,Currency
        ,GivenCredit
        ,BetCount
        ,MemberTO
        ,MemberWL
        ,RealIncome
        ,RealTurnover
    )
    SELECT TOP (@TopUsers) CustID
        ,SiteID
        ,DangerLevelOriginal
        ,DangerLevelABI
        ,DangerLevelOtherSport
        ,DangerLevelBasketball
        ,DangerLevelESport
        ,AgentID
        ,MasterID
        ,SuperID
        ,Currency
        ,GivenCredit
        ,BetCount
        ,MemberTO
        ,MemberWL
        ,RealIncome
        ,RealTurnover
    FROM (
        SELECT d.CustID
            ,d.SiteID
            ,ISNULL(CONVERT(INT, c.danger), -1) AS DangerLevelOriginal
            ,ISNULL(CONVERT(INT, c.danger2), -1) AS DangerLevelABI
            ,ISNULL(CONVERT(INT, c.danger3), -1) AS DangerLevelOtherSport
            ,ISNULL(CONVERT(INT, c.danger4), -1) AS DangerLevelBasketball
            ,ISNULL(CONVERT(INT, c.danger5), -1) AS DangerLevelESport
            ,d.AgentID
            ,d.MasterID
            ,d.SuperID
            ,e.Currency
            ,MAX(c.credit) AS GivenCredit
            ,SUM(d.BetCount) BetCount
            ,SUM(d.MemberTO) MemberTO
            ,SUM(d.MemberWL) MemberWL
            ,SUM(d.RealIncome) RealIncome
            ,SUM(d.RealTurnover) RealTurnover
        FROM #tmpRawData AS d
            INNER JOIN #tmpSportBettypes AS sb ON d.Bettype = sb.Bettype AND sb.SportType = d.SportType
            INNER JOIN bodb02.dbo.Exchange AS e WITH (NOLOCK) ON d.Currency = e.ExchangeId
            LEFT JOIN bodb02.dbo.custInfo AS c WITH (NOLOCK) ON (c.roleid = 1 AND d.CustID = c.CustID)
        WHERE 'ALL' = @DangerLevels 
             OR ISNULL(CONVERT(INT, c.danger), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 1)
             OR ISNULL(CONVERT(INT, c.danger2), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 2)
             OR ISNULL(CONVERT(INT, c.danger3), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 3)
             OR ISNULL(CONVERT(INT, c.danger4), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 4)
             OR ISNULL(CONVERT(INT, c.danger5), -1) IN (SELECT DangerLevel FROM #tmpDangerLevel where DangerType = 5)
        GROUP BY d.CustID
            ,d.SiteID
            ,ISNULL(CONVERT(INT, c.danger), -1)
            ,ISNULL(CONVERT(INT, c.danger2), -1)
            ,ISNULL(CONVERT(INT, c.danger3), -1)
            ,ISNULL(CONVERT(INT, c.danger4), -1)
            ,ISNULL(CONVERT(INT, c.danger5), -1)
            ,d.AgentID
            ,d.MasterID
            ,d.SuperID
            ,e.Currency
    ) tmp
    ORDER BY MemberWL DESC
            ,DangerLevelOriginal DESC
            ,DangerLevelABI DESC
            ,DangerLevelOtherSport DESC
    OPTION (RECOMPILE)
    
    CREATE CLUSTERED INDEX [CIX_tmpFiltered] ON #tmpFiltered (
        SuperID
        ,MasterID
        ,AgentID
        ,CustID
    )

    CREATE TABLE #tmpNoAssocByCust (
        CustID INT
        ,NoAssoc INT
    )
    CREATE TABLE #custAsso (CustID INT, AssoCustID INT)
    
    INSERT INTO #custAsso (CustID, AssoCustID)
    select custid, assoCustID
    FROM bodb_Account.dbo.CTS_Association AS a WITH (NOLOCK)
    WHERE CustID IN (SELECT CustID FROM #tmpFiltered)
    OPTION (RECOMPILE, MAX_GRANT_PERCENT=20)
    
    INSERT INTO #tmpNoAssocByCust ( CustID, NoAssoc )
    select custid, count(distinct assoCustID) 
    from #custAsso
    group by custid
    OPTION (RECOMPILE, MAX_GRANT_PERCENT=20)

    ---Return result---
    ;WITH CTE_Filtered AS (
        SELECT *, 
            REPLACE(LTRIM(RTRIM(
                CASE WHEN d.danger > 0 AND EXISTS (SELECT 1 FROM #tmpDangerLevel WHERE DangerType = 1 AND DangerLevel = d.danger)
                        THEN 'Ori@' + cast(d.danger as varchar(3)) ELSE '' END
                + CASE WHEN d.danger2 > 0 AND EXISTS (SELECT 1 FROM #tmpDangerLevel WHERE DangerType = 2 AND DangerLevel = d.danger2)
                        THEN ' ABI@' + cast(d.danger2 as varchar(3)) ELSE '' END
                + CASE WHEN d.danger4 > 0 AND EXISTS (SELECT 1 FROM #tmpDangerLevel WHERE DangerType = 4 AND DangerLevel = d.danger4)
                        THEN ' Basket@' + cast(d.danger4 as varchar(3)) ELSE '' END 
                + CASE WHEN d.danger5 > 0 AND EXISTS (SELECT 1 FROM #tmpDangerLevel WHERE DangerType = 5 AND DangerLevel = d.danger5)
                        THEN ' E-Sport@' + cast(d.danger5 as varchar(3)) ELSE '' END 
                + CASE WHEN d.danger3 > 0 AND EXISTS (SELECT 1 FROM #tmpDangerLevel WHERE DangerType = 3 AND DangerLevel = d.danger3)
                        THEN ' O.Sport@' + cast(d.danger3 as varchar(3)) ELSE '' END 
            )), ' ', ', ') [DangerLevel]
        FROM #tmpFiltered AS d
    )
    SELECT c.UserName
        ,a.UserName AgentName
        ,m.UserName MasterName
        ,s.UserName SuperName
        ,st.site Division
        ,d.Currency
        ,MAX(d.GivenCredit) GivenCredit
        ,[DangerLevel]
        ,SUM(d.BetCount) BetCount
        ,SUM(d.MemberTO) MemberTO
        ,SUM(d.MemberWL) MemberWL
        ,SUM(d.RealTurnover) HouseTO
        ,SUM(d.RealIncome)  HouseIncome     
        ,SUM(ISNULL(assoc.NoAssoc, 0)) AS NumberOfAssociatedAccount 
    FROM CTE_Filtered AS d
        LEFT JOIN bodb_Account.dbo.Customer AS c WITH (NOLOCK) ON (c.roleid = 1 AND d.CustID = c.custid)
        LEFT JOIN bodb_Account.dbo.Customer AS s WITH (NOLOCK) ON ( s.roleid = 4 AND d.SuperID = s.CustID )
        LEFT JOIN bodb_Account.dbo.Customer AS m WITH (NOLOCK) ON ( m.roleid = 3 AND d.MasterID = m.CustID )
        LEFT JOIN bodb_Account.dbo.Customer AS a WITH (NOLOCK) ON ( a.roleid = 2 AND d.AgentID = a.CustID )
        LEFT JOIN bodb_Account.dbo.tbl_Site AS [st] WITH (NOLOCK) ON d.SiteID = st.siteid
        LEFT JOIN #tmpNoAssocByCust AS assoc ON d.CustID = assoc.CustID
    GROUP BY d.CustID
        ,c.UserName
        ,a.UserName
        ,m.UserName
        ,s.UserName
        ,st.site
        ,d.Currency
        ,[DangerLevel]
    ORDER BY SUM(d.MemberWL) DESC
        ,c.UserName

    DROP TABLE #tmpSportBettypes
    DROP TABLE #tmpSite
    DROP TABLE #tmpLeague
    DROP TABLE #tmpDangerLevel
    DROP TABLE #tmpRawData
    DROP TABLE #tmpFiltered
    DROP TABLE #tmpNoAssocByCust
    DROP TABLE #custAsso
END
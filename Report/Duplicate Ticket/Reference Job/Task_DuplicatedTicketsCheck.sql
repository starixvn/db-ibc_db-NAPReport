/*<info serverAlias="DBRPT-bodb_report" executers="wsv_nap" viewers="vnteam" isFunction="0"></info>*/
use bodb_report
GO
ALTER PROCEDURE [dbo].[Task_DuplicatedTicketsCheck]
    @TransRangeSec SMALLINT = 3
    ,@TransDiffMillisec INT = 1000
    ,@Site NVARCHAR(MAX) = NULL
AS
/*
    Created: 20150211@Sophia
    Task : Job run to check duplicate tickets on bettrans table and insert the result into DuplicateTicket table to view report later
    DB: DBRPT/bodb_report
    Original: Acc_CheckDuplicateTickets
    
    Param's Explanation:
        @TransRangeSec: TransID range in second
        @TransDiffMillisec: TransDate diff in milliseconds
    
    Revisions:
        - 20151009@Sophia: group by IP [#45176]
        - 20151021@Sophia: Modify the SPs to only cover the tickets of the following products [#45898] 
						1	Sportsbook [inclusive of : Metric Gaming - Superlive and BetTrade tickets (check the refno)]
						3	Number Game
						4	SLI - Live Casino
						5	Virtual Sports
        - 20170323@Sophia: Fix Parlay issue ( can't detect Parlay ticket if checking RefNo) [Redmine: #73884]
						1	Sportsbook
						2	Number Game
						3	SLI - Live Casino
						4	Virtual Sports
                        5   Metric Gaming - Superlive
                        6   BetTrade (check the refno)
        - 20170424@Percy: Don't check dummy account of Cash Out [RedmineID: #73419]
        - 20170518@Percy:
            1. New request of Cash Out - Check bettype 911 [RedmineID: #73419]
            2. Remove SLI
         - 20170704@Tom: Integrate Betradar Virtual Sports(#78495)
         - 20170828@Kean: Integrate Lucky 3(#82191)
         - 20180115@Tom:  Cashout tickets from separated original tickets are considered as dupplicated tickets (#89256)
         - 20181129@Dominic: Check WalletType (HotFix #105532)
         - 20200515@Dominic: Check betteam
         - 20200518@Ned.Le: Exclude tickets that have betfrom='v'
         - 20210416@Ned.Le: NAP Report - Duplicate Tickets - Exclude refund tickets (#153616)
         - 20220321@Ned.Le: NAP Report - Integrate FGG & new bettypes Cricket (#170213)
         - 20220726@Roy: NAP Report - Scale out & new transid (#175707)
         - 20220829@Roy: NAP Report - Enhancement for duplicated ticket (#177204)
         - 20230719@Roy: NAP Report - Integrate product Leap Gaming VS (VS3) (#189510)
         - 20240126@Jaden.Tang: Merge VS1, VS2, VS3 and VS4 (#199896)
         - 20240622@Dominic.Dao: Exclude single wallet
         - 20241004@Jaden.Tang: Pass @Site from parameter, data from DBCUST.Acc_Site_SiteDBGroupID_Select (#206895)
                @Site = '[{"Site": NVARCHAR(100), "SiteDBGroupID": SMALLINT, "IsSpecial": BIT}]'
                This only contain licensee sites, and excluded Single Wallet sites
        - 20250306@Jaden.Tang: Hotfix, missed data of Credit sites (#219382)
*/

BEGIN
    SET NOCOUNT ON

    DECLARE @LastSequenceID BIGINT
        ,@MaxSequenceID BIGINT
        ,@Min_Transid BIGINT
        ,@Max_Transid BIGINT
        ,@SiteDBGroupID SMALLINT
    
    CREATE TABLE #tmpSiteDBTrans (
        SiteDBGroupID SMALLINT NOT NULL
        ,Min_Transid BIGINT
        ,Max_Transid BIGINT
        ,Max_SequenceID BIGINT
    )
    
    CREATE TABLE #tmpDupValue (
        DupValueID INT IDENTITY(1,1)
        ,SiteDBGroupID SMALLINT NOT NULL
        ,custid INT NOT NULL
        ,odds SMALLMONEY
        ,stake MONEY NOT NULL
        ,balance MONEY
        ,bettype SMALLINT
        ,winlostdate SMALLDATETIME
        ,matchid INT
        ,ip VARCHAR(45)
        ,SpecialCol BIGINT
        ,WalletType SMALLINT
        ,betteam NVARCHAR(10)
        ,oddsid INT NOT NULL
    )
    
    CREATE TABLE #tmpDupTransID (
        DupValueID INT
        ,SiteDBGroupID SMALLINT
        ,TransID BIGINT     
        ,TransDate DATETIME
        ,WinlostDate SMALLDATETIME
    )
    
    CREATE TABLE #tmpTransDateDiff (
        TransID BIGINT
        ,TransIDDiff BIGINT
        ,DiffInMillisec INT
    )
    
    CREATE TABLE #tmpLicenseeSite(SiteID INT)

    ;WITH CTE AS
    (
        SELECT *
        FROM OPENJSON(@Site)
        WITH (
            SiteName NVARCHAR(100) '$.Site',
            SiteDBGroupID SMALLINT '$.SiteDBGroupID',
            IsSpecial BIT '$.IsSpecial'
        )
    )
    INSERT INTO #tmpLicenseeSite (SiteID)
    SELECT s.siteid
    FROM bodb02.dbo.[Site] S WITH (NOLOCK)
    INNER JOIN cte vp on s.site = vp.SiteName;

    CREATE UNIQUE CLUSTERED INDEX CX_SiteID ON #tmpLicenseeSite(SiteID)
    
    SELECT @LastSequenceID = CONVERT(BIGINT,VValue) FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastID'
    SELECT @LastSequenceID = ISNULL(@LastSequenceID,-1)
    
    INSERT INTO #tmpSiteDBTrans (
        SiteDBGroupID
        ,Min_Transid
        ,Max_Transid
        ,Max_SequenceID
    )
    SELECT ISNULL(SiteDBGroupID,0) AS SiteDBGroupID
        ,MIN(Transid) AS Min_Transid
        ,MAX(Transid) AS Max_Transid
        ,MAX(SequenceID) AS SequenceID
    FROM bodb02.dbo.bettrans WITH (NOLOCK)
    WHERE ISNULL(SequenceID,-1) > @LastSequenceID
    GROUP BY ISNULL(SiteDBGroupID,0)
    OPTION (RECOMPILE)
    
    SELECT @MaxSequenceID = ISNULL(MAX(Max_SequenceID),@LastSequenceID)
    FROM #tmpSiteDBTrans
    
    --Upd max/min transid by second--
    UPDATE #tmpSiteDBTrans
    SET Min_Transid = Min_Transid - (CAST(@TransRangeSec AS BIGINT) * 4294967296) --TransID - (Second * 2^32)
        ,Max_Transid = Max_Transid + (CAST(@TransRangeSec AS BIGINT) * 4294967296)
    
    ------Get Sport Bettype Matrix------
    -- Check SP Version  
    DECLARE @isTest BIT = 0
    SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

    DECLARE @VSProductIDs VARCHAR(200) 
    SELECT @VSProductIDs = VValue FROM DBWH.bodb_Account.dbo.SystemSettings WITH (NOLOCK) WHERE VID = 31
 
    DECLARE @bettype TABLE (bettype INT)
    INSERT INTO @bettype (bettype)
    SELECT bettype
    FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)
    WHERE (ProductID IN (1, 3, 25, 26)
            OR ProductID IN (SELECT val FROM bodb02.dbo.strSplit(@VSProductIDs, ',')))
        AND BetType NOT IN (500, 912, 913, 914)
    GROUP BY BetType
    --- End Sport Bettype Matrix------
    
    IF ISNULL(@MaxSequenceID,-1) > -1 AND @MaxSequenceID > @LastSequenceID
    BEGIN
        WHILE (1=1)
        BEGIN
            SELECT @SiteDBGroupID = MIN(SiteDBGroupID)
            FROM #tmpSiteDBTrans
            WHERE SiteDBGroupID > ISNULL(@SiteDBGroupID, -1)
            
            IF @SiteDBGroupID IS NULL
                BREAK
            
            ---Set variable
            SELECT @Min_Transid = Min_Transid
                ,@Max_Transid = Max_Transid
            FROM #tmpSiteDBTrans
            WHERE SiteDBGroupID = @SiteDBGroupID
            
            ;WITH AllTicket AS (
                SELECT  b.custid, 
                        b.odds, 
                        b.stake, 
                        b.balance, 
                        b.bettype,
                        b.winlostdate, 
                        b.matchid,
                        b.ip,
                        CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo WHEN b.Bettype = 29 THEN b.hdp1 ELSE 0 END AS SpecialCol, --only check RefNo for Bettrade and Old Cashout Model; --only check hdp1 for Parlay
                        ISNULL(CAST(b.WalletType AS SMALLINT),-1) WalletType,
                        b.betteam,
                        b.oddsid
                FROM bodb02.dbo.bettrans b WITH (NOLOCK , Index = PK_bettrans)
                    INNER JOIN @bettype s ON s.bettype = b.bettype
                WHERE	b.TransID BETWEEN @Min_Transid AND @Max_Transid
                    AND ISNULL(b.SiteDBGroupID,0) = @SiteDBGroupID
                    ----AND b.bettype < 19000
                    AND b.matchid > 0
                    AND b.custid NOT IN (50057, 879241, 103873, 851668, 878902) --betdaq
                    AND b.custid NOT IN (1077687) -- Betfair
                    AND b.recommend NOT IN (11196380) -- foobet
                    AND b.betfrom <> 'v'
                    AND b.recommend NOT IN (5707545, 52466) -- exclude members under BARM,8RM
                    AND b.currency NOT IN (20, 27, 28)
                    AND b.statusID NOT IN (101, 102, 103) 
                    AND NOT EXISTS (SELECT TOP 1 1 FROM bodb02.dbo.TradeCust t WITH (NOLOCK) WHERE b.custid = t.custid AND t.VendorID = 14)
            )
            INSERT INTO #tmpDupValue (
                -- DupValueID IDENTITY(1,1)
                SiteDBGroupID
                ,custid
                ,odds
                ,stake
                ,balance
                ,bettype
                ,winlostdate
                ,matchid
                ,ip
                ,SpecialCol
                ,WalletType
                ,betteam
                ,oddsid
            )
            SELECT @SiteDBGroupID AS SiteDBGroupID
                ,b.custid
                ,b.odds
                ,b.stake
                ,b.balance
                ,b.bettype
                ,b.winlostdate
                ,b.matchid
                ,b.ip
                ,b.SpecialCol
                ,b.WalletType
                ,b.betteam
                ,b.oddsid
            FROM AllTicket b
            GROUP BY b.custid
                ,b.odds
                ,b.stake
                ,b.balance
                ,b.bettype
                ,b.winlostdate
                ,b.matchid
                ,b.ip
                ,b.SpecialCol
                ,b.WalletType
                ,b.betteam
                ,b.oddsid
            HAVING COUNT(*) > 1
        END-- END WHILE
        
        CREATE CLUSTERED INDEX tmpDupValue ON #tmpDupValue (SiteDBGroupID, matchid, custid, bettype)
        -----------------
        DELETE b
        FROM #tmpDupValue b
        INNER JOIN bodb02.dbo.customer c (NOLOCK) ON b.custid = c.custid
        INNER JOIN bodb02.dbo.site s (NOLOCK) ON s.site = c.site AND s.isLicensee = 1
        WHERE s.siteid NOT IN (SELECT SiteID FROM #tmpLicenseeSite) --exclude single wallet
        --------------------------------------------------------
        INSERT INTO #tmpDupTransID (DupValueID, SiteDBGroupID, TransID, TransDate, WinlostDate)
        SELECT t.DupValueID, ISNULL(b.SiteDBGroupID,0) AS SiteDBGroupID, b.TransID, b.TransDate, b.WinlostDate
		FROM	bodb02.dbo.bettrans b WITH(NOLOCK)
            INNER JOIN #tmpDupValue t 
				ON	ISNULL(b.SiteDBGroupID,0) = t.SiteDBGroupID
                AND b.custid = t.custid 
                AND b.odds = t.odds
                AND b.stake = t.stake
                AND ISNULL(b.balance,0) = ISNULL(t.balance,0) 
                AND b.bettype = t.bettype
                AND b.winlostdate = t.winlostdate
                AND b.matchid = t.matchid
                AND b.ip = t.ip
                AND (CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo WHEN b.Bettype = 29 THEN b.hdp1 ELSE 0 END) = t.SpecialCol
                AND t.WalletType = ISNULL(CAST(b.WalletType AS SMALLINT),-1)
                AND b.betteam = t.betteam
                AND b.oddsid = t.oddsid
        -- WHERE NOT EXISTS (SELECT 1 FROM dbo.DuplicatedTicket d WITH (NOLOCK) WHERE d.TransID = b.TransId)
        
        --delete if dirty read (page split) make data have the same transid
        ;WITH CTE_DR AS (
            SELECT ROW_NUMBER() OVER ( PARTITION BY transid ORDER BY TransDate ) AS rn
                ,transid
            FROM #tmpDupTransID
        )
        DELETE FROM CTE_DR
        WHERE rn > 1
        
        CREATE CLUSTERED INDEX tmpDupTransID ON #tmpDupTransID (DupValueID, SiteDBGroupID, TransID)
        
        --re-check to get transids which TransDate diff lower @TransDiffMillisec
        ;WITH CTE_Diff AS (
            SELECT dp1.TransID
                ,dp2.TransID AS TransIDDiff
                ,ABS(DATEDIFF(MILLISECOND, dp2.TransDate, dp1.TransDate)) AS DiffInMillisec
            FROM #tmpDupTransID AS dp1 WITH (NOLOCK)
                INNER JOIN #tmpDupTransID AS dp2 WITH (NOLOCK)
                    ON dp2.SiteDBGroupID = dp1.SiteDBGroupID
                    AND dp2.DupValueID = dp1.DupValueID
                    AND dp2.TransID <> dp1.TransID
        )
        INSERT INTO #tmpTransDateDiff ( TransID )
        SELECT di.TransID
        FROM CTE_Diff AS di
        WHERE di.DiffInMillisec <= @TransDiffMillisec
        GROUP BY di.TransID

        --insert final result--
        INSERT INTO dbo.DuplicatedTicket (transid, transdate, winlostdate)
        SELECT DISTINCT b.transid, b.transdate, b.winlostdate
        FROM #tmpDupTransID AS b WITH (NOLOCK)
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DuplicatedTicket d WITH (NOLOCK) WHERE d.TransID = b.TransId)
            AND b.transid IN (SELECT TransID FROM #tmpTransDateDiff)
        
        --update LastSequenceID
        UPDATE bodb02.dbo.SystemSettings WITH (UPDLOCK, ROWLOCK) 
		SET	   VValue = @MaxSequenceID
        WHERE  VName = 'DuplTicketLastID'
    END
    -- NOT use - removed code for it in Acc_Rpt_DuplicatedTicketsSel
    -- UPDATE bodb02.dbo.SystemSettings WITH (UPDLOCK, ROWLOCK)
	-- SET	   VValue = CURRENT_TIMESTAMP
    -- WHERE  VName = 'DuplTicketLastDate'

    DROP TABLE #tmpDupValue
    DROP TABLE #tmpSiteDBTrans
    DROP TABLE #tmpDupTransID
    DROP TABLE #tmpTransDateDiff
    DROP TABLE #tmpLicenseeSite
END

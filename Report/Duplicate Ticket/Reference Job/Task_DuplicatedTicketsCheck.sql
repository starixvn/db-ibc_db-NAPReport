/*<info serverAlias="DBRPT-bodb_report" executers="wsv_nap" viewers="vnteam" isFunction="0"></info>*/
use bodb_report
GO

ALTER PROCEDURE [dbo].[Task_DuplicatedTicketsCheck]
    @TransDiffMillisec INT = 1000
    ,@Site NVARCHAR(MAX) = NULL
AS
/*
    Created: 20150211@Sophia
    Task : Job run to check duplicate tickets on bettrans table and insert the result into DuplicateTicket table to view report later
    DB: DBRPT/bodb_report
    Original: Acc_CheckDuplicateTickets
    
    Param's Explanation:
        @TransDiffMillisec: The upper bound of time difference between two transactions to be considered as duplicate
                            Web service does not pass in this parameter, set to 1000ms by default
        @Site = '[{"Site": NVARCHAR(100), "SiteDBGroupID": SMALLINT, "IsSpecial": BIT}]'
                This only contain licensee sites, and excluded Single Wallet sites
    
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
         - 20250306@Jaden.Tang: Hotfix, missed data of Credit sites (#219382)
         - 20250328@Jaden.Tang: Refactor, performance improvement (#219382)
*/

BEGIN
    SET NOCOUNT ON

    DECLARE @LastSequenceID BIGINT
    SELECT @LastSequenceID = CONVERT(BIGINT, VValue) 
    FROM bodb02.dbo.SystemSettings WITH (NOLOCK) WHERE VName = 'DuplTicketLastID'

    -- Licensee sites (WITHOUT single wallet)
    CREATE TABLE #tmpLicenseeSite(SiteID INT)

    ;WITH SiteJsonCTE AS (
        SELECT 
            SiteName,
            SiteDBGroupID,
            IsSpecial
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
    INNER JOIN SiteJsonCTE sjc ON s.site = sjc.SiteName;

    CREATE UNIQUE CLUSTERED INDEX CX_SiteID ON #tmpLicenseeSite(SiteID)

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

    CREATE TABLE #tmpDupGroup (
        transid BIGINT,
        transdate DATETIME,
        winlostdate SMALLDATETIME,
        custid INT
    )

    DECLARE @NewLastSequenceID BIGINT;
    SELECT @NewLastSequenceID = MAX(b.sequenceid)
    FROM bodb02.dbo.bettrans b WITH (NOLOCK)
    WHERE b.sequenceid > @LastSequenceID;
    SET @NewLastSequenceID = ISNULL(@NewLastSequenceID, @LastSequenceID); -- Handle no new rows case

    -- SET STATISTICS TIME ON
    -- SET STATISTICS IO ON
    -- SET STATISTICS XML ON

    ;WITH FilteredBetTrans AS (
        SELECT
            b.transid,
            b.transdate,
            b.winlostdate,
            b.tstamp,
            b.custid,
            b.odds,
            b.stake,
            b.balance,
            b.bettype,
            b.matchid,
            b.ip,
            CASE WHEN b.Bettype IN (901,902,903,904,911) THEN b.RefNo WHEN b.Bettype = 29 THEN b.hdp1 ELSE 0 END as SpecialCol,
            b.WalletType,
            b.betteam,
            b.oddsid
        FROM bodb02.dbo.bettrans b WITH (NOLOCK, INDEX(IX_sequenceid)) -- Index seek
        WHERE b.statusID not in (101, 102, 103)
            AND b.matchid > 0
            AND b.custid NOT IN (50057, 879241, 103873, 851668, 878902) --betdaq
            AND b.custid NOT IN (1077687) -- Betfair
            AND b.recommend NOT IN (11196380) -- foobet
            AND b.betfrom <> 'v'
            AND b.recommend NOT IN (5707545, 52466)
            AND b.bettype IN (SELECT bettype FROM @bettype)
            AND b.currency NOT IN (20, 27, 28)
            AND b.sequenceid > @LastSequenceID
    )
    , LagLeadCalculations AS (
        SELECT
            fbt.transid,
            fbt.transdate,
            fbt.winlostdate,
            fbt.tstamp,
            fbt.custid,
            LAG(fbt.transdate) OVER (
                PARTITION BY fbt.custid, fbt.odds, fbt.stake, fbt.balance, fbt.bettype, fbt.winlostdate, fbt.matchid, fbt.ip, fbt.SpecialCol, fbt.WalletType, fbt.betteam, fbt.oddsid
                ORDER BY fbt.transdate, fbt.transid
            ) AS PrevTransDate,
            LEAD(fbt.transdate) OVER (
                PARTITION BY fbt.custid, fbt.odds, fbt.stake, fbt.balance, fbt.bettype, fbt.winlostdate, fbt.matchid, fbt.ip, fbt.SpecialCol, fbt.WalletType, fbt.betteam, fbt.oddsid
                ORDER BY fbt.transdate, fbt.transid
            ) AS NextTransDate,
            COUNT(*) OVER (
                PARTITION BY fbt.custid, fbt.odds, fbt.stake, fbt.balance, fbt.bettype, fbt.winlostdate, fbt.matchid, fbt.ip, fbt.SpecialCol, fbt.WalletType, fbt.betteam, fbt.oddsid
            ) AS GroupCount
        FROM FilteredBetTrans fbt
    )
    INSERT INTO #tmpDupGroup (transid, transdate, winlostdate, custid)
    SELECT DISTINCT
        llc.transid,
        llc.transdate,
        llc.winlostdate,
        llc.custid
    FROM LagLeadCalculations llc
    WHERE llc.GroupCount > 1 -- Must belong to a group with more than one member
      AND (
            (llc.PrevTransDate IS NOT NULL AND DATEDIFF(MILLISECOND, llc.PrevTransDate, llc.transdate) <= @TransDiffMillisec)
         OR (llc.NextTransDate IS NOT NULL AND DATEDIFF(MILLISECOND, llc.transdate, llc.NextTransDate) <= @TransDiffMillisec)
      )
      AND NOT EXISTS (SELECT 1 FROM dbo.DuplicatedTicket d WITH (NOLOCK) WHERE d.TransID = llc.transid)
    OPTION (RECOMPILE); -- add recompile reduces memory grant

    -- SET STATISTICS TIME OFF
    -- SET STATISTICS IO OFF
    -- SET STATISTICS XML OFF

    -- Remove single wallet customers
    -- #tmpLicenseeSite contains licensee sites (WITHOUT single wallet)
    -- [Site].isLicensee = 1: all licensee sites
    DELETE b
    FROM #tmpDupGroup b
    INNER JOIN bodb02.dbo.vw_customer c WITH (NOLOCK) ON b.custid = c.custid
    INNER JOIN bodb02.dbo.[Site] s WITH (NOLOCK) ON c.site = s.site
    WHERE s.isLicensee = 1
      AND s.siteid NOT IN (SELECT SiteID FROM #tmpLicenseeSite);

    INSERT INTO dbo.DuplicatedTicket (transid, transdate, winlostdate)
    SELECT transid, transdate, winlostdate
    FROM #tmpDupGroup;

    -- Update the watermark if new data was processed
    IF @NewLastSequenceID > @LastSequenceID
    BEGIN
        UPDATE bodb02.dbo.SystemSettings WITH (ROWLOCK)
        SET VValue = @NewLastSequenceID
        WHERE VName = 'DuplTicketLastID';
    END

    DROP TABLE #tmpLicenseeSite
    DROP TABLE #tmpDupGroup
END

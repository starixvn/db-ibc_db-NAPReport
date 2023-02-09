/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_EnableDisableAccount_ByProduct @ListCurrency VARCHAR(8000) = 'all',
                                                           @SportType    INT,
                                                           @ShowEnabled  BIT           = 1,
                                                           @ShowDisabled BIT           = 1
AS
/*
    Created: Dominic
    Date: 2014-06-02
    Task : Total Credit Accounts Enabled/Disabled per Product
    DB: DBACC/bodb02

    Revisions:
        - 20140627@Dominic: Exclude special super with username  LIKE '3rdSuper%','STEST%','%ACCSuper%'
        - 20140707@Dominic: Add Param @ShowEnabled/@ShowDisabled #18655
        - 20150609@Kos: Separate CustDB to DBCUST server (Move SP to DBACC.bodb02)
        - 20150828@Jim: support GoldDeluxe & Metric Gaming(#40262)
        - 20150828@Jim: support Colossus Bet (#42608)
        - 20151215@Percy: support Cockfighting [Redmine: #49027]
        - 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
        - 20160229@Jim: Offer Allbet [Redmine #50921]
        - 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
        - 20160916@Robert:
            1. Integrate new product NG2 [RedmindID: #63460]
            2. Clean code of Cockfighting
        - 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
        - 20170627@Cherry: Integrate Lottery and Betradar Virtual Sports (#78184, 78495)
        - 20170825@Cherry: Integrate Lucky 3 (#78214)
        - 20171030@Kean: Integrate Bullfighting (#85712)
        - 20171109@Kean: HotFix #86404 - List of Currencies is passed incorrectly
        - 20180411@Franklin: Integrate Pragmatic (#92642)
        - 20180831@Cherry: Integrate Poker Games into NAP Report (#97830)
        - 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253)
        - 20190128@Robert: Video Poker - Integrate into NAP Reports[#107706]
        - 20190917@Dominic: Remove inactive products [#120215]
        - 20200313@Ned.Le: NAP Report - Incorporate Virtual Games (#130326)
        - 20200323@Ned.Le: NAP Report - Incorprorate SA Gaming (#129349) | Saba.club (#130776) | Sexy Gaming (#130853)
        - 20200331@Ned.Le: NAP Report - Incorporate new Table Games (#131095)
        - 20200409@Ned.Le: NAP Report - Incorporate BBIN Live Casino (#131357)
        - 20200422@Ned.Le: NAP Report - Incorporate IBCBet Live Casino (#132961)
        - 20200522@Cherry: Nap Report - Integrate ION Live Casino (#132324) & RNG War (#132009)
        - 20200921@Jaden.Tang: NAP Report - Incorporate Joker Gaming (#131611) & WM (#131583)
        - 20201125@Cherry: Integrate GDG (#146008)
        - 20201225@Ned.Le: NAP Reports - Integrate Big Gaming (#142481)
        - 20210303@Cherry: Integrate Sports Lottery (#151071)
        - 20210325@Jaden: Integrate PP Live Casino (#133731)
        - 20210428@Ned.Le: NAP Report - Implement VGaming (#154072)
        - 20210811@Jaden: Integrate Bitcoin (#159046)
        - 20211203@Ned.Le: NAP Report - Tune report "Total Credit Accounts" (#165615)
        - 20210224@Cherry: Incorporate ONE RNG DCS (#168917)
		- 20230206@Roy: NAP Report - Change the sport type of Macau (#183404)

    Param's Explanation:
        + @ListCurrency: The specified date used as one of the filter criterias, if its value is 'all' then no need to be filtered by currency
        + @SportType:    Sporttype that be define at WEB stage
*/

BEGIN

    SET NOCOUNT ON

    -----------------
    -- DCS setting --

    CREATE TABLE #BitmapOrder (bitmapOrder INT) --Using for sporttype that has many settings
    DECLARE @bitmap    TINYINT                  --Using for sporttype that has 1 setting

    IF (@SportType IN (211))
    BEGIN
        INSERT INTO #BitmapOrder (bitmapOrder)
        SELECT bitmapOrder
        FROM bodb02.dbo.ProductStatusProfile WITH (NOLOCK)
        WHERE Sporttype = @SportType
    END
    ELSE
    BEGIN
        SELECT @bitmap = bitmapOrder
        FROM bodb02.dbo.ProductStatusProfile WITH (NOLOCK)
        WHERE Sporttype = @SportType
    END

    -----------------------
    -- REAL CREDIT SUPER --

    -- #DepositDummySuper
    CREATE TABLE #DepositDummySuper (CustID INT)

    INSERT INTO #DepositDummySuper (CustID)
    SELECT custid FROM bodb02.dbo.Dep_CustSuper WITH (NOLOCK)
    UNION
    SELECT custid FROM bodb02.dbo.Acc_CustDirect WITH (NOLOCK) WHERE roleid = 4

    -- #FiltedCreditSuper
    CREATE TABLE #FiltedCreditSuper (
        CustID      INT,
        SuperStatus BIT
    )

    INSERT INTO #FiltedCreditSuper(CustID, SuperStatus)
    SELECT ci.custid,
           CASE WHEN @sportType = 161 THEN ci.DisableNumber               
                WHEN @sportType = 202 THEN CASE WHEN EXISTS(SELECT TOP 1 1
                                                            FROM bodb02.dbo.CustGameType gt WITH (NOLOCK, INDEX = PK_CustGameType)
                                                            WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0) THEN 0 ELSE 1 END
                WHEN @sportType = -1  THEN ci.DisableSuperLive
                WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
                WHEN @sportType = 204 THEN ci.DisableColossusBet
                WHEN @SportType = 211 THEN (SELECT CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END
                                            FROM bodb02.dbo.CustProductStatus cps WITH (NOLOCK)
                                                 CROSS APPLY #BitmapOrder b
                                                 CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
                                            WHERE custid = ci.custid)
                ELSE (SELECT CASE(SELECT value FROM dbo.f_CustSetting_ProductStatusSel(bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END
                      FROM bodb02.dbo.CustProductStatus WITH (NOLOCK)
                      WHERE custid = ci.custid)
           END
    FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
         INNER JOIN bodb02.dbo.CustSuper cs WITH (NOLOCK) ON ci.custid = cs.custid AND cs.IsInternal = 0
		 INNER JOIN bodb02.dbo.vw_Customer c WITH (NOLOCK) ON ci.custid = c.custid
    WHERE ci.roleid = 4
          AND ci.Enabled = 1
          AND(@ListCurrency = 'all' OR ci.currency IN (SELECT val FROM dbo.strSplit(@ListCurrency, ',')))
          AND ci.currency NOT IN(20, 27, 28)
          AND ci.custid   NOT IN (SELECT custid FROM bodb02.dbo.Dep_CustSuper WITH (NOLOCK))
          AND ci.custid   NOT IN (SELECT CustID FROM #DepositDummySuper)
          AND ci.username NOT LIKE '3rdSuper%'
          AND ci.username NOT LIKE 'STEST%'
          AND ci.username NOT LIKE '%ACCSuper%'
		  AND c.site NOT IN ('CN88') --exclude site

    IF (@ShowEnabled = 1 AND @ShowDisabled = 0)
    BEGIN
        DELETE FROM #FiltedCreditSuper WHERE ISNULL(SuperStatus,0) = 1
    END

    IF (@ShowEnabled = 0 AND @ShowDisabled = 1)
    BEGIN
        DELETE FROM #FiltedCreditSuper WHERE ISNULL(SuperStatus,0) = 0
    END

    IF (@ShowEnabled = 0 AND @ShowDisabled = 0)
    BEGIN
        DELETE FROM #FiltedCreditSuper
    END

    ---------------------------------------------------------
    -- SUPER/MASTER/MEMBER THAT BELONG TO REAL SUPER ABOVE --

    -- Create temp table
    CREATE TABLE #FiltedDownlineAcc (
        SuperID     INT,
        CustID      INT,
        RoleID      INT,
        IsDisable   BIT
    )

    -- Gen data to temp table
    -- + [161] Number Game
    IF (@sportType IN (161))
    BEGIN
        -- -> Master
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               ci.DisableNumber
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustMaster cm WITH (NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
             INNER JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 3
        -- -> Agent
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               ci.DisableNumber
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustAgent ca WITH (NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 2
        -- -> Member
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               ci.DisableNumber
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 1
    END    
    -- + [202] RNG Keno
    ELSE IF (@sportType IN (202))
    BEGIN
        -- -> Master
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN EXISTS (SELECT TOP 1 1
                                 FROM bodb02.dbo.CustGameType gt WITH (NOLOCK, INDEX = PK_CustGameType)
                                 WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0) THEN 0 ELSE 1 END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustMaster cm WITH (NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 3
        -- -> Agent
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN EXISTS (SELECT TOP 1 1
                                 FROM dbo.CustGameType gt WITH (NOLOCK, INDEX = PK_CustGameType)
                                 WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0) THEN 0 ELSE 1 END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN dbo.CustAgent ca WITH (NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 2
        -- -> Member
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN EXISTS (SELECT TOP 1 1
                                 FROM dbo.CustGameType gt WITH (NOLOCK, INDEX = PK_CustGameType)
                                 WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0) THEN 0 ELSE 1 END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 1
    END
    -- + [-1] Metric Gamming | [255] Gold Deluxe | [204] Colossus
    ELSE IF (@sportType IN (-1, 255, 204))
    BEGIN
        -- -> Master
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN @sportType = -1  THEN ci.DisableSuperLive
                    WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
                    WHEN @sportType = 204 THEN ci.DisableColossusBet END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustMaster cm WITH (NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 3
        -- -> Agent
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN @sportType = -1  THEN ci.DisableSuperLive
                    WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
                    WHEN @sportType = 204 THEN ci.DisableColossusBet END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN dbo.CustAgent ca WITH (NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
             INNER JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 2
        -- -> Member
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               ci.roleid,
               CASE WHEN @sportType = -1  THEN ci.DisableSuperLive
                    WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
                    WHEN @sportType = 204 THEN ci.DisableColossusBet END
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 1
    END
    -- + [211] Allbet
    ELSE IF @sportType IN (211)
    BEGIN
        -- -> Master
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               3,
               1
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustMaster cm WITH (NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 3
        -- -> Agent
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               2,
               1
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN dbo.CustAgent ca WITH (NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 2
        -- -> Member
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               1,
               1
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 1
        -- -> Update status
        UPDATE fda
        SET fda.IsDisable = A.IsDisable
        FROM #FiltedDownlineAcc fda
             INNER JOIN (SELECT fda.CustID,
                                CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END IsDisable
                         FROM bodb02.dbo.CustProductStatus cps WITH (NOLOCK)
                              INNER JOIN #FiltedDownlineAcc fda ON cps.CustID = fda.CustID
                              CROSS APPLY #BitmapOrder b
                              CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
                         GROUP BY fda.CustID) A ON fda.CustID = A.CustID
    END
    -- + The rest
    ELSE
    BEGIN
        -- -> Master
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               3,
               (SELECT CASE(SELECT value FROM bodb02.dbo.f_CustSetting_ProductStatusSel (bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END
                FROM bodb02.dbo.CustProductStatus WITH (NOLOCK)
                WHERE custid = ci.custid)
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustMaster cm WITH (NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 3
        -- -> Agent
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               2,
               (SELECT CASE(SELECT value FROM bodb02.dbo.f_CustSetting_ProductStatusSel (bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END
                FROM bodb02.dbo.CustProductStatus WITH (NOLOCK)
                WHERE custid = ci.custid)
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN bodb02.dbo.CustAgent ca WITH (NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 2
        -- -> Member
        INSERT INTO #FiltedDownlineAcc (SuperID, CustID, RoleID, IsDisable)
        SELECT sup.CustID,
               ci.custid,
               1,
               (SELECT CASE(SELECT value FROM bodb02.dbo.f_CustSetting_ProductStatusSel (bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END
                FROM bodb02.dbo.CustProductStatus WITH (NOLOCK)
                WHERE custid = ci.custid)
        FROM bodb02.dbo.custInfo ci WITH (NOLOCK)
             INNER JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID
        WHERE ci.Enabled = 1
              AND ci.roleid = 1
    END

    -------------------
    -- RETURN RESULT --

    SELECT cust.custid                  custid,
           cust.username                username,
           ISNULL(sp.SuperStatus,0)     IsDisable,
           e.currency                   currency,
           ISNULL(rs.MasterEnabled,  0) MasterEnabled,
           ISNULL(rs.MasterDisabled, 0) MasterDisabled,
           ISNULL(rs.AgentEnabled,   0) AgentEnabled,
           ISNULL(rs.AgentDisabled,  0) AgentDisabled,
           ISNULL(rs.MemberEnabled,  0) MemberEnabled,
           ISNULL(rs.MemberDisabled, 0) MemberDisabled
    FROM #FiltedCreditSuper sp
         INNER JOIN dbo.Customer cust WITH (NOLOCK) ON cust.custid = sp.CustID
         INNER JOIN dbo.Exchange e WITH (NOLOCK) ON e.exchangeid = cust.currency
         LEFT  JOIN (SELECT dl.SuperID,
                            SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 3 THEN 1 ELSE 0 END) AS MasterEnabled,
                            SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 3 THEN 1 ELSE 0 END) AS MasterDisabled,
                            SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 2 THEN 1 ELSE 0 END) AS AgentEnabled,
                            SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 2 THEN 1 ELSE 0 END) AS AgentDisabled,
                            SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 1 THEN 1 ELSE 0 END) AS MemberEnabled,
                            SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 1 THEN 1 ELSE 0 END) AS MemberDisabled
                     FROM #FiltedDownlineAcc dl
                     GROUP BY dl.SuperID) rs ON sp.CustID = rs.SuperID
    ORDER BY cust.username,
             e.currency

    ----------------------
    -- DROP TEMP TABLES --

    DROP TABLE #BitmapOrder
    DROP TABLE #DepositDummySuper
    DROP TABLE #FiltedCreditSuper
    DROP TABLE #FiltedDownlineAcc

END
GO

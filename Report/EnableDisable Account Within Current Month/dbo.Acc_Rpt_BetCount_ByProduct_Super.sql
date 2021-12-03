/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_BetCount_ByProduct_Super] @MoveBetsDay  SMALLDATETIME,
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


    ---------------
    -- META DATA --
    ---------------

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

    -- RNG Casino group
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (251, 'RNG Casino',     208)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (251, 'RNG Casino',     209)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (251, 'RNG Casino',     210)

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
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    224)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    225)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    232)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    234)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    236)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    237)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    238)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    247)
    INSERT INTO #SportGroupSettings (SportGroupID, SportGroupName, SportType) VALUES (212, 'Macau Games',    248)

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

    -- Get data from OLTP System
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

	-- Get data from DW System
	IF @FirstDate <= @MoveBetsDay
	BEGIN
		IF @CurrentDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @CurrentDate

		DECLARE @sql VARCHAR(MAX) 
		SET @sql = 	'
				SELECT * FROM  OPENQUERY ( DBWH ,''
				SELECT b.custid,''''SETTLED'''',SUM(b.BetCount)
				FROM bodb_account.dbo.mcCustBettingDaily b WITH (NOLOCK)					 
				WHERE	b.rptDate BETWEEN '''''+ CONVERT(VARCHAR(10),@FirstDate, 121)+ ''''' AND '''''+  CONVERT(VARCHAR(10),@TempToDate, 121)  + '''''
						AND 
						(
							b.bettype BETWEEN 81 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'       = 161 THEN 120 ELSE 0 END)	 -- Number Game
							OR b.bettype BETWEEN 8101 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 161 THEN 8120 ELSE 0 END)  -- Happy 5
							OR b.bettype BETWEEN 3601 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 161 THEN 3610 ELSE 0 END)  -- Happy 5 Linked Games
							OR (' + CONVERT(VARCHAR(5),@sportType) +' = 251 AND (b.bettype BETWEEN 2101 AND 2399 OR b.bettype BETWEEN 2901 AND 2999)) -- RNG Casino
							OR b.bettype BETWEEN 801 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = -1 THEN 806 ELSE 0 END)
							OR b.bettype BETWEEN 1501 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 202 THEN 1599 ELSE 0 END)
							OR b.bettype BETWEEN 4601 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 245 THEN 4900 ELSE 0 END)  -- Virtual Games
							OR b.bettype BETWEEN 4901 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 222 THEN 5000 ELSE 0 END)  -- Table Games
							OR b.bettype BETWEEN 1701 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 255 THEN 1703 ELSE 0 END)  -- GoldDeluxe
							OR b.bettype BETWEEN 3300 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 241 THEN 3300 ELSE 0 END)  -- BBIN
							OR b.bettype BETWEEN 18000 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 204 THEN 18005 ELSE 0 END) -- Colossus Bet
							OR b.bettype BETWEEN 2401 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 211 THEN 2499 ELSE 0 END)  -- AllBet
							OR b.bettype BETWEEN 3001 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 244 THEN 3099 ELSE 0 END)  -- SA Gaming
							OR b.bettype BETWEEN 3101 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 243 THEN 3150 ELSE 0 END)  -- AE Casino
							OR b.bettype BETWEEN 3201 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 242 THEN 3299 ELSE 0 END)  -- IBCBet Live Casino
							OR (' + CONVERT(VARCHAR(5),@sportType) +' = 212 AND (b.bettype BETWEEN 4001 AND 4600 OR b.bettype BETWEEN 7001 AND 7600))
							OR b.bettype BETWEEN 2501 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 213 THEN 2699 ELSE 0 END)  -- NG2
							OR b.bettype BETWEEN 1011 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 219 THEN 1020 ELSE 0 END)  -- Fishing World
							OR b.bettype BETWEEN 1021 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 220 THEN 1099 ELSE 0 END   -- Loterry
							OR (' + CONVERT(VARCHAR(5),@sportType) +' =180 AND (b.bettype BETWEEN 1201 AND 1299 OR b.bettype BETWEEN 2700 AND 2899 OR b.bettype BETWEEN 5301 AND 5399)) -- Virtual Sports
							OR b.bettype BETWEEN 1901 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 1999 ELSE 0 END   -- Card Club [Video Poker]
							OR b.bettype BETWEEN 1611 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 200 THEN 1699 ELSE 0 END)  -- Saba.club
							OR b.bettype BETWEEN 5601 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 225 THEN 5699 ELSE 0 END)  -- ION Live Casino
							OR b.bettype BETWEEN 3701 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 170 THEN 3799 ELSE 0 END)  -- PP Live Casino
							OR b.bettype BETWEEN 5500 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 224 THEN 5599 ELSE 0 END)  -- RNG War
							OR b.bettype BETWEEN 6001 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 6300 ELSE 0 END   -- PG Soft
							OR b.bettype BETWEEN 6401 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 6700 ELSE 0 END   -- Joker Gaming
							OR b.bettype BETWEEN 5401 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 6499 ELSE 0 END   -- MaxGame
							OR b.bettype BETWEEN 7701 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 7799 ELSE 0 END   -- AdvantPlay
							OR b.bettype BETWEEN 7801 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 212 THEN 7899 ELSE 0 END   -- AdvantPlay Mini
							OR b.bettype BETWEEN 3401 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 233 THEN 3499 ELSE 0 END   -- WM
							OR b.bettype BETWEEN 5701 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 236 THEN 5799 ELSE 0 END   -- GDG
							OR b.bettype BETWEEN 3501 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 239 THEN 3599 ELSE 0 END   -- BG
							OR b.bettype BETWEEN 3611 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 169 THEN 3620 ELSE 0 END   -- Sports Lottery
							OR b.bettype BETWEEN 3801 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 171 THEN 3899 ELSE 0 END   -- VGaming
							OR b.bettype BETWEEN 7901 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'   = 175 THEN 7999 ELSE 0 END   -- Bitcoin
						) 
						AND b.bettype NOT IN (38)
						AND b.status IN (3  ---DRAW
										,12	---HALF LOSE
										,13	---HALF WON
										,4	---LOSE
										,8	---WON								 
										)	
						AND CustID IN ( 
										SELECT	CustID 
										FROM	bodb02.dbo.CustInfo WITH(NOLOCK)
										WHERE	srecommend = '+ CONVERT(VARCHAR(50),@CustID) +' AND RoleID = 1 )
						GROUP BY b.custid '' )'		 
		
				
		INSERT INTO #AvailableMember 
		EXEC (@sql)	
	END
	
	--Get data for downline list 
	-- #FiltedDownlineAcc
	CREATE TABLE #FiltedDownlineAcc (
        CustID    INT,
        IsDisable BIT,
        BetStatus NVARCHAR(10), 
        BetCount  INT
    )

	IF @sportType IN (161)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			ci.DisableNumber,
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                  
	END

	IF @sportType IN (-1,255,204)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			CASE WHEN @sportType = -1  THEN  ci.DisableSuperLive
				 WHEN @sportType = 255 THEN  ci.DisableGoldDeluxe
				 WHEN @sportType = 204 THEN  ci.DisableColossusBet
				 END ,
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid               
	END
	IF @sportType IN (251) -----251, 208, 209, 210
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			(~ci.SyncCasino |(ci.DisableCasino)),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid             
	END

	IF @sportType = 202
    BEGIN      
		WITH CustEnableKeno (CustID)
		AS(
			SELECT gt.CustID
			FROM DBACC.bodb02.dbo.CustGameType gt WITH (NOLOCK) 
				JOIN #AvailableMember av ON av.CustID = gt.CustID
			WHERE gt.IsDisabled = 0
			GROUP BY gt.CustID
		)
		INSERT INTO #FiltedDownlineAcc
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
	IF @sportType IN (211,212,213,219,220,180,245,244,200,243,222,241,242,224,225,233,236,239,169,170,171,175)
    BEGIN
		DECLARE @bitmapOrder TABLE (bitmapOrder TINYINT)
		INSERT INTO @bitmapOrder (bitmapOrder)
		SELECT bitmapOrder 
		FROM dbo.ProductStatusProfile WITH(NOLOCK) 
		WHERE Sporttype = @SportType 
	    
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
				(SELECT CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END
			FROM CustProductStatus cps WITH(NOLOCK)
				CROSS APPLY @bitmapOrder b
				CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
			WHERE custid = ci.custid),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                   
	END
	
	--Return result
	SELECT cs.custid,cs.username,rs.IsDisable,
			SUM(CASE WHEN rs.BetStatus <> 'running' THEN rs.BetCount ELSE 0 END) SettledBets,
			SUM(CASE WHEN rs.BetStatus = 'running' THEN rs.BetCount ELSE 0 END)  RunningBets
	FROM #FiltedDownlineAcc rs
	JOIN dbo.Customer cs ON cs.custid = rs.CustID
	GROUP BY cs.custid,cs.username,rs.IsDisable
	ORDER BY cs.username
	
	--Drop temp tables
	DROP TABLE #FiltedDownlineAcc
	DROP TABLE #AvailableMember
	DROP TABLE #SpecialBettypeGroup

END
GO 

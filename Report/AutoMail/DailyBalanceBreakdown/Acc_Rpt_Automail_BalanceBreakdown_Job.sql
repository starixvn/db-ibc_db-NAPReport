
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_BalanceBreakdown_Job]
@IsMonthly BIT  = 0
, @ToDate  DATE = NULL
AS
/*
    Created	: 20240426@Jaden
	Task	: Balance report of customers, for Finance team to backup (#204276)
	DB		: DBRPT/bodb02
	
	Revision:		
		20240426@Jaden: Initial (#204276)
		20250409@Jaden: Update Currency from tinyint to smallint (#222187)

	Param's Explanation:

    Remarks:
        This is called twice on 4th of each month, with different @IsMonthly parameter
*/
BEGIN
    IF @IsMonthly = 0
        TRUNCATE TABLE bodb_Report.dbo.AutomailBalanceBreakdown_Daily
    IF @IsMonthly = 1
        TRUNCATE TABLE bodb_Report.dbo.AutomailBalanceBreakdown_Monthly

    IF @ToDate IS NULL
    BEGIN
        IF @IsMonthly = 0
            SET @ToDate = CAST(GETDATE() AS DATE)
        IF @IsMonthly = 1
            SET @ToDate = CAST(DATEADD(DAY, 1, EOMONTH(GETDATE(), -1)) AS DATE) --set @ToDate to begin of current month
    END

    CREATE TABLE #tmp
    (
        srecommend  INT
      , mrecommend  INT
      , recommend   INT
      , custid      INT
      , SuperAmt    MONEY
      , MasterAmt   MONEY
      , AgentAmt    MONEY
      , MemberAmt   MONEY
      , SuperAmtRM  MONEY
      , MasterAmtRM MONEY
      , AgentAmtRM  MONEY
      , MemberAmtRM MONEY
    )

    CREATE CLUSTERED INDEX tmp_idx1 ON #tmp (srecommend, mrecommend, recommend, custid)

    CREATE TABLE #tmp_agg
    (
        srecommend  INT
      , [Super]     VARCHAR(30)
            DEFAULT '   -   '
      , mrecommend  INT
      , [Master]    VARCHAR(30)
            DEFAULT '   -   '
      , recommend   INT
      , [Agent]     VARCHAR(30)
            DEFAULT '    -    '
      , custid      INT
      , [Member]    VARCHAR(30)
            DEFAULT '        -        '
      , [Currency]  NVARCHAR(100)
            DEFAULT '---'
      , SuperAmt    MONEY
      , MasterAmt   MONEY
      , AgentAmt    MONEY
      , MemberAmt   MONEY
      , SuperAmtRM  MONEY
      , MasterAmtRM MONEY
      , AgentAmtRM  MONEY
      , MemberAmtRM MONEY
    )

    CREATE CLUSTERED INDEX tmp_agg_idx ON #tmp_agg ([srecommend], [mrecommend], [recommend], [custid]) WITH (FILLFACTOR = 95)

    /*bettrans data*/
    -- use bettran's clustered index, batch by matchid to use index seek and reduce memory consumption

    DECLARE @MinMatchID INT;
    DECLARE @MaxMatchID INT;

    DECLARE matchid_cursor CURSOR FOR
    SELECT MIN(matchid) AS min_matchid
         , MAX(matchid) AS max_matchid
    FROM (SELECT matchid, NTILE(5) OVER (ORDER BY matchid) AS tile FROM bettrans (nolock) WHERE winlostdate < @ToDate) AS t
    GROUP BY tile;

    OPEN matchid_cursor;
    FETCH NEXT FROM matchid_cursor
    INTO @MinMatchID
       , @MaxMatchID;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #tmp
        SELECT b.srecommend
             , b.mrecommend
             , b.recommend
             , b.custid
             , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN winlost - actual_stake ELSE swinlost + scomm - acomm END), 0)                   SuperAmt
             , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN winlost - actual_stake ELSE mwinlost + acomm - comm END), 0)                    MasterAmt
             , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN winlost - actual_stake ELSE awinlost + comm - playercomm END), 0)                AgentAmt
             , ISNULL(SUM(CASE WHEN b.custid <> b.recommend
                                AND b.custid <> b.mrecommend
                                AND b.custid <> b.srecommend
                                AND b.ruben = 1 THEN winlost - actual_stake + playercomm
                              ELSE 0
                          END
                         )
                    , 0
                     )                                                                                                                           MemberAmt
             , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN winlost - actual_stake ELSE swinlost + scomm - acomm END * b.actualrate), 0)    SuperAmtRM
             , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN winlost - actual_stake ELSE mwinlost + acomm - comm END * b.actualrate), 0)     MasterAmtRM
             , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN winlost - actual_stake ELSE awinlost + comm - playercomm END * b.actualrate), 0) AgentAmtRM
             , ISNULL(SUM(CASE WHEN b.custid <> b.recommend
                                AND b.custid <> b.mrecommend
                                AND b.custid <> b.srecommend
                                AND b.ruben = 1 THEN winlost - actual_stake + playercomm
                              ELSE 0
                          END * b.actualrate
                         )
                    , 0
                     )                                                                                                                           MemberAmtRM
        FROM bodb02.dbo.bettrans b WITH (nolock)
        WHERE ruben = 1
          AND statusID NOT IN ( 101, 102, 103 )
          AND b.currency NOT IN ( 20, 27, 28 )
          AND winlostdate < @ToDate
          AND matchid >= @MinMatchID
          AND matchid < @MaxMatchID
        GROUP BY b.srecommend
               , b.mrecommend
               , b.recommend
               , b.custid
        OPTION (RECOMPILE)

        FETCH NEXT FROM matchid_cursor
        INTO @MinMatchID
           , @MaxMatchID;
    END;

    CLOSE matchid_cursor;
    DEALLOCATE matchid_cursor;

    /*transfer data*/

    INSERT INTO #tmp
    SELECT b.srecommend
         , b.mrecommend
         , b.recommend
         , b.custid
         , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN winlost - actual_stake ELSE swinlost + scomm - acomm END), 0)                   SuperAmt
         , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN winlost - actual_stake ELSE mwinlost + acomm - comm END), 0)                    MasterAmt
         , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN winlost - actual_stake ELSE awinlost + comm - playercomm END), 0)                AgentAmt
         , ISNULL(SUM(CASE WHEN b.custid <> b.recommend
                            AND b.custid <> b.mrecommend
                            AND b.custid <> b.srecommend THEN winlost - actual_stake + playercomm
                          ELSE 0
                      END
                     )
                , 0
                 )                                                                                                                           MemberAmt
         , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN winlost - actual_stake ELSE swinlost + scomm - acomm END * b.actualrate), 0)    SuperAmtRM
         , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN winlost - actual_stake ELSE mwinlost + acomm - comm END * b.actualrate), 0)     MasterAmtRM
         , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN winlost - actual_stake ELSE awinlost + comm - playercomm END * b.actualrate), 0) AgentAmtRM
         , ISNULL(SUM(CASE WHEN b.custid <> b.recommend
                            AND b.custid <> b.mrecommend
                            AND b.custid <> b.srecommend THEN winlost - actual_stake + playercomm
                          ELSE 0
                      END * b.actualrate
                     )
                , 0
                 )                                                                                                                           MemberAmtRM
    FROM bodb02.dbo.[Transfer] b WITH (nolock)
    WHERE WinlostDate < @ToDate
    -- AND b.currency NOT IN ( 20, 27, 28 ) -- exclude currency at later step to let engine uses the index IX_recommend (sort merge aggregate)
    GROUP BY b.srecommend
           , b.mrecommend
           , b.recommend
           , b.custid
    OPTION (RECOMPILE)

    /*TransferExtra data*/  
  
    INSERT INTO #tmp  
	SELECT b.srecommend  
         , b.mrecommend  
         , b.recommend  
         , b.custid  
         , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN Credit-Debit ELSE 0 END), 0)                  SuperAmt  
         , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN Credit-Debit ELSE 0 END), 0)                  MasterAmt  
         , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN Credit-Debit ELSE 0 END), 0)                   AgentAmt  
         , ISNULL(SUM(CASE WHEN b.custid <> b.recommend  
                            AND b.custid <> b.mrecommend  
                            AND b.custid <> b.srecommend THEN Credit-Debit
                          ELSE 0  
                      END  
                     )  
                , 0  
                 )                                                                                          MemberAmt  
         , ISNULL(SUM(CASE WHEN b.custid = b.srecommend THEN Credit-Debit ELSE 0 END * b.actualrate), 0)    SuperAmtRM  
         , ISNULL(SUM(CASE WHEN b.custid = b.mrecommend THEN Credit-Debit ELSE 0 END * b.actualrate), 0)    MasterAmtRM  
         , ISNULL(SUM(CASE WHEN b.custid = b.recommend THEN Credit-Debit ELSE 0 END * b.actualrate), 0)     AgentAmtRM  
         , ISNULL(SUM(CASE WHEN b.custid <> b.recommend  
                            AND b.custid <> b.mrecommend  
                            AND b.custid <> b.srecommend THEN Credit-Debit  
                          ELSE 0  
                      END * b.actualrate  
                     )  
                , 0  
                 )                                                                                           MemberAmtRM  
    FROM bodb02.dbo.[TransferExtra] b WITH (nolock)  
    WHERE WinlostDate < @ToDate   
    GROUP BY b.srecommend  
           , b.mrecommend  
           , b.recommend  
           , b.custid  
    OPTION (RECOMPILE)  

    DELETE FROM #tmp WHERE srecommend IN ( SELECT CustID FROM vw_Customer v (NOLOCK) WHERE v.currency IN ( 20, 27, 28 ))

    /*update usernames separately to prevent too much memory usage*/
    INSERT INTO #tmp_agg
    (
        srecommend
      , mrecommend
      , recommend
      , custid
      , SuperAmt
      , MasterAmt
      , AgentAmt
      , MemberAmt
      , SuperAmtRM
      , MasterAmtRM
      , AgentAmtRM
      , MemberAmtRM
    )
    SELECT srecommend
         , mrecommend
         , recommend
         , custid
         , SUM(SuperAmt)
         , SUM(MasterAmt)
         , SUM(AgentAmt)
         , SUM(MemberAmt)
         , SUM(SuperAmtRM)
         , SUM(MasterAmtRM)
         , SUM(AgentAmtRM)
         , SUM(MemberAmtRM)
    FROM #tmp
    GROUP BY srecommend
           , mrecommend
           , recommend
           , custid;

    DROP TABLE #tmp;

    CREATE TABLE #cust (custid INT, currency SMALLINT, username VARCHAR(30))

    INSERT INTO #cust (custid, currency, username)
    SELECT custid, currency, username FROM vw_Customer WITH (NOLOCK) WHERE roleid = 4

    UPDATE #tmp_agg
    SET [Super] = v.username
      , [Currency] = e.currency
    FROM #tmp_agg
    INNER JOIN #cust               v (NOLOCK) ON v.custid = #tmp_agg.srecommend
    INNER JOIN bodb02.dbo.Exchange e (NOLOCK) ON v.currency = e.exchangeid

    TRUNCATE TABLE #cust
    INSERT INTO #cust (custid, currency, username)
    SELECT custid, currency, username FROM vw_Customer WITH (NOLOCK) WHERE roleid = 3

    UPDATE #tmp_agg
    SET [Master] = ISNULL(v.username, '-')
    FROM #tmp_agg
    INNER JOIN #cust v (NOLOCK) ON v.custid = #tmp_agg.mrecommend;

    TRUNCATE TABLE #cust
    INSERT INTO #cust (custid, currency, username)
    SELECT custid, currency, username FROM vw_Customer WITH (NOLOCK) WHERE roleid = 2

    UPDATE #tmp_agg
    SET [Agent] = ISNULL(v.username, '-')
    FROM #tmp_agg
    INNER JOIN #cust v (NOLOCK) ON v.custid = #tmp_agg.recommend;

    UPDATE #tmp_agg
    SET [Member] = v.username
      , [Currency] = CASE WHEN #tmp_agg.Currency IS NULL THEN e.currency ELSE #tmp_agg.Currency END
    FROM #tmp_agg
    INNER JOIN vw_Customer         v (NOLOCK) ON v.custid = #tmp_agg.custid
    INNER JOIN bodb02.dbo.Exchange e (NOLOCK) ON v.currency = e.exchangeid
    WHERE #tmp_agg.custid <> #tmp_agg.srecommend
      AND #tmp_agg.custid <> #tmp_agg.mrecommend
      AND #tmp_agg.custid <> #tmp_agg.recommend;

    /*insert data*/
    IF @IsMonthly = 0
    BEGIN
        INSERT INTO bodb_Report.dbo.AutomailBalanceBreakdown_Daily
        (
            [Super]
          , [Master]
          , [Agent]
          , [Member]
          , [Currency]
          , SuperAmt
          , MasterAmt
          , AgentAmt
          , MemberAmt
          , SuperAmtRM
          , MasterAmtRM
          , AgentAmtRM
          , MemberAmtRM
          , [RowNumber]
        )
        SELECT [Super]
             , [Master]
             , [Agent]
             , [Member]
             , [Currency]
             , SuperAmt
             , MasterAmt
             , AgentAmt
             , MemberAmt
             , SuperAmtRM
             , MasterAmtRM
             , AgentAmtRM
             , MemberAmtRM
             , ROW_NUMBER() OVER (ORDER BY [Super], [Master], [Agent], [Member])
        FROM #tmp_agg
    END

    IF @IsMonthly = 1
        INSERT INTO bodb_Report.dbo.AutomailBalanceBreakdown_Monthly
        (
            [Super]
          , [Master]
          , [Agent]
          , [Member]
          , [Currency]
          , SuperAmt
          , MasterAmt
          , AgentAmt
          , MemberAmt
          , SuperAmtRM
          , MasterAmtRM
          , AgentAmtRM
          , MemberAmtRM
          , [RowNumber]
        )
        SELECT [Super]
             , [Master]
             , [Agent]
             , [Member]
             , [Currency]
             , SuperAmt
             , MasterAmt
             , AgentAmt
             , MemberAmt
             , SuperAmtRM
             , MasterAmtRM
             , AgentAmtRM
             , MemberAmtRM
             , ROW_NUMBER() OVER (ORDER BY [Super], [Master], [Agent], [Member])
        FROM #tmp_agg

    DROP TABLE #cust
    DROP TABLE #tmp_agg
END

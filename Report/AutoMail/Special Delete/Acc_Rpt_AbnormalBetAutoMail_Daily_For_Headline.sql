/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_For_Headline
	@RptDate      DATETIME 
   , @GroupName    VARCHAR(50)
   , @IsTest       BIT         = 0
AS
/*
	Creator: Robert
	Date: 2020-03-12
	DB: DBACC.bodb02
	Task: [Special Delete] - Implement Daily Auto Mail for Abnormal Bets
	Revisions:				
		- 20200312@Robert: NAP Report - Daily Abnormal Bet Report for Headline - [130183]
		- 20211013@Jaden: Change datatype for ipv6 (#162587)
		- 20211105@Cherry: Support void mix parlay (#164192)
        - 20220308@Ned.Le: Automail - Enhance performance of sp on DB061 (#169615)

	Param's Explanation:
        EXEC bodb02.dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_For_Headline @RptDate   = '20220306',
                                                                       @GroupName = 'ACCTHAI',
                                                                       @IsTest    = 0
*/

    BEGIN
	   SET NOCOUNT ON;

       -- #TmpCustGroup
	   CREATE TABLE #TmpCustGroup(
		   SuperID           INT
         , MasterID          INT
         , AgentID           INT
		 , CustID            INT);

	   INSERT INTO #TmpCustGroup(SuperID, MasterID, AgentID, CustID)
	   SELECT g.CustID     SuperID,
              c.mrecommend MasterID,
              c.recommend  AgentID,
              c.custid     CustID
	   FROM dbo.Acc_CustGroup AS g WITH (NOLOCK)
            LEFT JOIN dbo.Customer AS c WITH (NOLOCK) ON g.CustID = c.srecommend
       WHERE g.GroupName = @GroupName
             AND g.CustID <> c.custid
        
       CREATE CLUSTERED INDEX CIX_TmpCustGroup ON #TmpCustGroup(CustID)

       -- #TmpVoidedTransaction
	   CREATE TABLE #TmpVoidedTransaction(
		   TransId           BIGINT
		 , SubIssueTypeId    TINYINT
		 , CustId            INT);
       
	   DECLARE @RptDate_From    DATETIME = @RptDate
		    , @RptDate_To      DATETIME;

	   SELECT @RptDate_From = CONVERT(VARCHAR(10), @RptDate_From, 101)
		   , @RptDate_To = DATEADD(d, 1, @RptDate_From);

	   INSERT INTO #TmpVoidedTransaction(TransId
								, SubIssueTypeId
								, CustId)
			SELECT b.TransId
				, b.SubIssueTypeId
				, b.CustID
			FROM bodb02.dbo.TicketVoiding_VoidedTransaction AS b WITH(NOLOCK)
			WHERE EXISTS (SELECT TOP 1 1
                          FROM #TmpCustGroup g
                          WHERE g.CustID = b.CustID)
				 AND b.CreatedDate >= @RptDate_From
				 AND b.CreatedDate < @RptDate_To
				 AND b.IssueTypeID = 11;

	   CREATE CLUSTERED INDEX CIX_TmpVoidedTransaction ON #TmpVoidedTransaction(TransId);

       -- #TmpCustInfo
       CREATE TABLE #TmpCustInfo(
           CustID            INT
         , Super             VARCHAR(100)
         , Master            VARCHAR(100)
         , Agent             VARCHAR(100));

       ;WITH CTE_CustID AS (
            SELECT DISTINCT CustID
            FROM #TmpVoidedTransaction
       )
       INSERT INTO #TmpCustInfo (CustID, Super, Master, Agent)
       SELECT cte.CustID CustID,
              s.username Super,
              m.username Master,
              a.username Agent
       FROM CTE_CustID cte
            INNER JOIN #TmpCustGroup g ON cte.CustID = g.CustID
		    INNER JOIN dbo.Customer AS s WITH (NOLOCK) ON s.custid = g.SuperID AND s.roleid = 4
		    INNER JOIN dbo.Customer AS m WITH (NOLOCK) ON m.custid = g.MasterID AND m.roleid = 3
		    INNER JOIN dbo.Customer AS a WITH (NOLOCK) ON a.custid = g.AgentID AND a.roleid = 2

       CREATE CLUSTERED INDEX CIX_TmpCustInfo ON #TmpCustInfo(CustID)

       -- #TmpBettype
	   CREATE TABLE #TmpBettype(
		   bettype                INT
		 , SupportMultipleOdds    BIT);

	   INSERT INTO #TmpBettype(bettype
						, SupportMultipleOdds)
			SELECT typeid
				, SupportMultipleOdds
			FROM DBWH.bodb_Account.dbo.Bettype WITH(NOLOCK);

	   CREATE CLUSTERED INDEX CIX_TmpBettype ON #TmpBettype(bettype);

       -- #Data
	   CREATE TABLE #Data(
		   TransId           BIGINT
		 , sporttype         TINYINT
		 , leagueid          INT
		 , homeid            INT
		 , awayid            INT
		 , kickofftime       DATETIME
		 , liveindicator     TINYINT
		 , bettype           SMALLINT
		 , betteam           VARCHAR(10)
		 , SubIssueTypeId    TINYINT
		 , finalhomescore    INT
		 , finalawayscore    INT
		 , site              VARCHAR(50)
		 , Username          NVARCHAR(50)
		 , odds              SMALLMONEY
		 , CurrencyName      NVARCHAR(50)
		 , stake             MONEY
		 , HDP               SMALLMONEY
		 , livehomescore     SMALLINT
		 , liveawayscore     SMALLINT
		 , transdate         DATETIME
		 , oddstype          SMALLINT
		 , ip                VARCHAR(45)
		 , CustId            INT
		 , Super             VARCHAR(100)
		 , Master            VARCHAR(100)
		 , Agent             VARCHAR(100));

	   INSERT INTO #Data(TransId
				    , sporttype
				    , leagueid
				    , homeid
				    , awayid
				    , kickofftime
				    , liveindicator
				    , bettype
				    , betteam
				    , SubIssueTypeId
				    , finalhomescore
				    , finalawayscore
				    , site
				    , Username
				    , odds
				    , CurrencyName
				    , stake
				    , HDP
				    , livehomescore
				    , liveawayscore
				    , transdate
				    , oddstype
				    , ip
				    , CustId
				    , Super
				    , Master
				    , Agent)
			SELECT tmp.TransId
				, l.sporttype
				, l.leagueid
				, m.homeid
				, m.awayid
				, m.GlobalShowTime
				, CASE WHEN b.bettype = 29 THEN b.livehomescore ELSE b.liveindicator END
				, b.bettype
				, b.betteam
				, tmp.SubIssueTypeId
				, m.finalhomescore
				, m.finalawayscore
				, c.site
				, b.Username
				, b.odds
				, b.CurrencyName
				, b.stake
				, b.hdp1 - b.hdp2 AS HDP
				, b.livehomescore
				, b.liveawayscore
				, b.transdate
				, b.oddstype
				, b.ip
				, b.custid
				, mem.Super
				, mem.Master
				, mem.Agent
			FROM bodb02.dbo.bettrans AS b WITH(NOLOCK)
			    INNER JOIN #TmpVoidedTransaction AS tmp ON b.transid = tmp.TransId
			    INNER JOIN #TmpCustInfo AS mem ON mem.CustID = tmp.CustId
			    LEFT JOIN bodb02.dbo.match AS m WITH(NOLOCK) ON b.matchid = m.matchid
			    LEFT JOIN bodb02.dbo.league AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			    LEFT JOIN bodb02.dbo.Customer AS c WITH(NOLOCK) ON b.srecommend = c.custid
			WHERE 1 = CASE
					    WHEN @IsTest = 0
						    AND b.Currency <> 20
					    THEN 1
					    WHEN @IsTest = 1
						    AND b.Currency = 20
					    THEN 1
					    ELSE 0
					END
			ORDER BY m.kickofftime DESC
				  , b.liveindicator DESC
				  , b.bettype DESC;

	   CREATE CLUSTERED INDEX IX_CustId ON #Data(CustId ASC);

	   UPDATE d
			SET 
			    d.odds = d.odds + CASE
								 WHEN d.oddstype = 1
									 AND bt.SupportMultipleOdds = 1
								 THEN 1
								 ELSE 0
							  END
	   FROM #Data d
		  INNER JOIN #TmpBettype bt ON d.bettype = bt.bettype;

	   SELECT CASE WHEN d.bettype = 29 THEN NULL ELSE d.sporttype END sporttype
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.leagueid END leagueid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.homeid END homeid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.awayid END awayid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.kickofftime END kickofftime
		   , d.liveindicator
		   , CASE WHEN d.bettype = 29 AND d.betteam = '1' THEN 9 ELSE d.bettype END bettype
		   , CASE WHEN d.bettype = 29 THEN '-' ELSE d.betteam END betteam
		   , ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS AS Reason
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalhomescore END finalhomescore
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalawayscore END finalawayscore
		   , COUNT(DISTINCT site) AS NumberOfLicensees
		   , COUNT(TransId) AS NumberOfTickets
	   FROM #Data AS d
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON d.SubIssueTypeID = ss.SubIssueTypeId
	   GROUP BY CASE WHEN d.bettype = 29 THEN NULL ELSE d.sporttype END
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.leagueid END
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.homeid END
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.awayid END
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.kickofftime END
			, d.liveindicator
			, CASE WHEN d.bettype = 29 AND d.betteam = '1' THEN 9 ELSE d.bettype END
			, CASE WHEN d.bettype = 29 THEN '-' ELSE d.betteam END
			, ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalhomescore END
			, CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalawayscore END

	   SELECT d.TransId
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.sporttype END sporttype
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.leagueid END leagueid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.homeid END homeid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.awayid END awayid
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.kickofftime END kickofftime
		   , d.liveindicator
		   , CASE WHEN d.bettype = 29 AND d.betteam = '1' THEN 9 ELSE d.bettype END bettype
		   , CASE WHEN d.bettype = 29 THEN '-' ELSE d.betteam END betteam
		   , ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS AS Reason
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalhomescore END finalhomescore
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.finalawayscore END finalawayscore
		   , d.site
		   , d.Username
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.odds END odds
		   , d.CurrencyName
		   , d.stake
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.HDP END HDP
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.livehomescore END livehomescore
		   , CASE WHEN d.bettype = 29 THEN NULL ELSE d.liveawayscore END liveawayscore
		   , d.transdate
		   , d.ip
		   , d.Super
		   , d.Master
		   , d.Agent
	   FROM #Data AS d
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON d.SubIssueTypeID = ss.SubIssueTypeId;

	   SELECT DISTINCT 
			c.username
		   , c.iplogin
		   , TicketIPs = STUFF(
			(
			    SELECT DISTINCT 
					 N',' + a.ip
			    FROM #Data AS a
			    WHERE a.CustId = d.CustId FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 1, N'')
		   , d.Super
		   , d.Master
		   , d.Agent
	   FROM #Data AS d
		  INNER JOIN dbo.Customer AS c WITH(NOLOCK) ON d.CustId = c.custid;

	   DROP TABLE #TmpCustGroup;
       DROP TABLE #TmpCustInfo;
	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
	   DROP TABLE #TmpBettype;
    END;
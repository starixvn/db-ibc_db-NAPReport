/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail 
	@RptDate    DATETIME 
   , @Site       VARCHAR(50) = 'All'
   , @IsTest     BIT         = 0 
AS
/*
	Creator: Robert
	Date: 2019-11-07
	DB: DBACC.bodb02
	Task: [Special Delete] - Implement Daily Auto Mail for Abnormal Bets
	Revisions:		
		- 20191107@Robert: [Special Delete] - Implement Daily Auto Mail for Abnormal Bets - [#121920]
		- 20191226@Robert: NAP Report - Automate daily abnormal bets report for CSD [122800] - change request
		- 20200312@Robert: NAP Report - Daily Abnormal Bet Report for Headline - [130183]
		- 20200325@Robert: [NAP] - Implement Daily Auto Mail for Abnormal Bets - [121920] - add more ExternalID
		- 20200615@Robert: NAP Report - Adjustment CN88's Abnormal Bet report - [135393]
		- 20211013@Jaden: Change datatype for ipv6 (#162587)
		- 2021105@Cherry: Support void mix parlay (#164192)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #TmpVoidedTransaction(
		   TransId           BIGINT
		 , SubIssueTypeId    TINYINT);

	   CREATE TABLE #TmpBettype(
		   bettype                INT
		 , SupportMultipleOdds    BIT);

	   CREATE TABLE #Data(
		   TransId           BIGINT
		 , sporttype         TINYINT
		 , leagueid          INT
		 , homeid            INT
		 , awayid            INT
		 , kickofftime       DATETIME
		 , liveindicator     BIT
		 , bettype           SMALLINT
		 , betteam           VARCHAR(10)
		 , SubIssueTypeId    TINYINT
		 , finalhomescore    INT
		 , finalawayscore    INT
		 , site              VARCHAR(50)
		 , Username          NVARCHAR(50)
		 , Username2         NVARCHAR(50)
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
		 , AfterPT			 MONEY
		 );

	   DECLARE @RptDate_From    DATETIME = @RptDate
		    , @RptDate_To      DATETIME;

	   SELECT @RptDate_From = CONVERT(VARCHAR(10), @RptDate_From, 101)
		   , @RptDate_To = DATEADD(d, 1, @RptDate_From);

	   INSERT INTO #TmpVoidedTransaction(TransId
								, SubIssueTypeId)
			SELECT b.TransId
				, b.SubIssueTypeId
			FROM bodb02.dbo.TicketVoiding_VoidedTransaction AS b WITH(NOLOCK)
			WHERE b.CustID > 0
				 AND b.CreatedDate >= @RptDate_From
				 AND b.CreatedDate < @RptDate_To
				 AND b.IssueTypeID = 11;

	   INSERT INTO #TmpBettype(bettype
						, SupportMultipleOdds)
			SELECT typeid
				, SupportMultipleOdds
			FROM DBWH.bodb_Account.dbo.Bettype WITH(NOLOCK);

	   CREATE CLUSTERED INDEX IX_TransId ON #TmpVoidedTransaction(TransId ASC);
	   CREATE CLUSTERED INDEX IX_Bettype ON #TmpBettype(bettype ASC);

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
				    , Username2
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
					, AfterPT)
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
				, s.site
				, b.Username
				, CASE
					 WHEN s.site = 'CN88'
					 THEN 'N/A'
					 ELSE REPLACE(c1.username2, s.site + '$', '')
				  END AS username2
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
				, (1 - b.tpositiontaking) * b.stake AfterPT
			FROM bodb02.dbo.bettrans AS b WITH(NOLOCK)
			    INNER JOIN #TmpVoidedTransaction AS tmp ON b.transid = tmp.TransId
			    LEFT JOIN bodb02.dbo.match AS m WITH(NOLOCK) ON b.matchid = m.matchid
			    LEFT JOIN bodb02.dbo.league AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			    LEFT JOIN bodb02.dbo.Customer AS c WITH(NOLOCK) ON b.srecommend = c.custid
			    LEFT JOIN bodb02.dbo.Site AS s WITH(NOLOCK) ON c.site = s.site
			    LEFT JOIN bodb02.dbo.Customer AS c1 WITH(NOLOCK) ON c1.custid = b.custid
			WHERE s.isDeposit = CASE
							    WHEN @Site = 'CN88'
							    THEN 0
							    ELSE 1
							END
				 AND s.site = CASE
							   WHEN @Site = 'All'
							   THEN s.site
							   ELSE @Site
						    END
				 AND 1 = CASE
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

	   SELECT CASE WHEN d.bettype = 29 THEN 0 ELSE d.sporttype END
		   , CASE WHEN d.bettype = 29 THEN 0 ELSE d.leagueid END
		   , d.homeid
		   , d.awayid
		   , d.kickofftime
		   , d.liveindicator
		   , d.bettype
		   , d.betteam
		   , ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS AS Reason
		   , d.finalhomescore
		   , d.finalawayscore
		   , COUNT(DISTINCT site) AS NumberOfLicensees
		   , COUNT(TransId) AS NumberOfTickets
	   FROM #Data AS d
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON d.SubIssueTypeID = ss.SubIssueTypeId
	   GROUP BY CASE WHEN d.bettype = 29 THEN 0 ELSE d.sporttype END
			, CASE WHEN d.bettype = 29 THEN 0 ELSE d.leagueid END
			, d.homeid
			, d.awayid
			, d.kickofftime
			, d.liveindicator
			, d.bettype
			, d.betteam
			, ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS
			, d.finalhomescore
			, d.finalawayscore;

	   SELECT TransId
		   , CASE WHEN d.bettype = 29 THEN 0 ELSE sporttype END
		   , CASE WHEN d.bettype = 29 THEN 0 ELSE leagueid END
		   , homeid
		   , awayid
		   , kickofftime
		   , liveindicator
		   , bettype
		   , betteam
		   , ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS AS Reason
		   , finalhomescore
		   , finalawayscore
		   , site
		   , Username
		   , Username2
		   , odds
		   , CurrencyName
		   , stake
		   , HDP
		   , livehomescore
		   , liveawayscore
		   , transdate
		   , ip
		   , AfterPT
	   FROM #Data AS d
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON d.SubIssueTypeID = ss.SubIssueTypeId;

	   SELECT DISTINCT 
			c.username
		   , d.Username2
		   , c.iplogin
		   , TicketIPs = STUFF(
			(
			    SELECT DISTINCT 
					 N',' + a.ip
			    FROM #Data AS a
			    WHERE a.CustId = d.CustId FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 1, N'')
	   FROM #Data AS d
		  INNER JOIN dbo.Customer AS c WITH(NOLOCK) ON d.CustId = c.custid;

	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
	   DROP TABLE #TmpBettype;
    END;
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_For_Headline 
	@RptDate      DATETIME
   , @GroupName    VARCHAR(50) = 'INDOWIN'
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

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #TmpMember(
		   CustId      INT
		 , MemberId    INT
		 , Super       VARCHAR(30)
		 , Master      VARCHAR(30)
		 , Agent       VARCHAR(30));

	   CREATE TABLE #TmpVoidedTransaction(
		   TransId           BIGINT
		 , SubIssueTypeId    TINYINT
		 , CustId            INT);

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
		 , Super             VARCHAR(30)
		 , Master            VARCHAR(30)
		 , Agent             VARCHAR(30));

	   DECLARE @RptDate_From    DATETIME = @RptDate
		    , @RptDate_To      DATETIME;

	   SELECT @RptDate_From = CONVERT(VARCHAR(10), @RptDate_From, 101)
		   , @RptDate_To = DATEADD(d, 1, @RptDate_From);

	   INSERT INTO #TmpMember(CustId
					    , MemberId
					    , Super
					    , Master
					    , Agent)
	   EXEC dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_SelectMember_By_Headline 
		   @GroupName = @GroupName;

	   INSERT INTO #TmpVoidedTransaction(TransId
								, SubIssueTypeId
								, CustId)
			SELECT b.TransId
				, b.SubIssueTypeId
				, b.CustID
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

	   CREATE CLUSTERED INDEX IX_TmpMember_MemberId ON #TmpMember(MemberId);
	   CREATE CLUSTERED INDEX IX_TmpVoidedTransaction_TransId_CustId ON #TmpVoidedTransaction(TransId ASC, CustId);
	   CREATE CLUSTERED INDEX IX_TmpBettype_Bettype ON #TmpBettype(bettype ASC);

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
				, b.liveindicator
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
			    INNER JOIN #TmpMember AS mem ON mem.MemberId = tmp.CustId
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

	   SELECT d.sporttype
		   , d.leagueid
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
	   GROUP BY d.sporttype
			, d.leagueid
			, d.homeid
			, d.awayid
			, d.kickofftime
			, d.liveindicator
			, d.bettype
			, d.betteam
			, ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS
			, d.finalhomescore
			, d.finalawayscore;

	   SELECT d.TransId
		   , d.sporttype
		   , d.leagueid
		   , d.homeid
		   , d.awayid
		   , d.kickofftime
		   , d.liveindicator
		   , d.bettype
		   , d.betteam
		   , ss.SubIssueTypeName + ' ' + ss.SubIssueTypeNameCS AS Reason
		   , d.finalhomescore
		   , d.finalawayscore
		   , d.site
		   , d.Username
		   , d.odds
		   , d.CurrencyName
		   , d.stake
		   , d.HDP
		   , d.livehomescore
		   , d.liveawayscore
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

	   DROP TABLE #TmpMember;
	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
	   DROP TABLE #TmpBettype;
    END;
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
		 , odds              SMALLMONEY
		 , CurrencyName      NVARCHAR(50)
		 , stake             MONEY
		 , HDP               SMALLMONEY
		 , livehomescore     SMALLINT
		 , liveawayscore     SMALLINT
		 , transdate         DATETIME
		 , oddstype          SMALLINT);

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
				    , odds
				    , CurrencyName
				    , stake
				    , HDP
				    , livehomescore
				    , liveawayscore
				    , transdate
				    , oddstype)
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
				, s.site
				, b.Username
				, b.odds
				, b.CurrencyName
				, b.stake
				, b.hdp1 - b.hdp2 AS HDP
				, b.livehomescore
				, b.liveawayscore
				, b.transdate
				, b.oddstype
			FROM bodb02.dbo.bettrans AS b WITH(NOLOCK)
			    INNER JOIN #TmpVoidedTransaction AS tmp ON b.transid = tmp.TransId
			    LEFT JOIN bodb02.dbo.match AS m WITH(NOLOCK) ON b.matchid = m.matchid
			    LEFT JOIN bodb02.dbo.league AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			    LEFT JOIN bodb02.dbo.Customer AS c WITH(NOLOCK) ON b.srecommend = c.custid
			    LEFT JOIN bodb02.dbo.Site AS s WITH(NOLOCK) ON c.site = s.site
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

	   SELECT TransId
		   , sporttype
		   , leagueid
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
		   , odds
		   , CurrencyName
		   , stake
		   , HDP
		   , livehomescore
		   , liveawayscore
		   , transdate
	   FROM #Data AS d
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON d.SubIssueTypeID = ss.SubIssueTypeId;

	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
	   DROP TABLE #TmpBettype;
    END;
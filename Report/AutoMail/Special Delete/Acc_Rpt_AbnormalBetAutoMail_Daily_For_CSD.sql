/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_For_CSD 
	@RptDate    DATETIME
   , @IsTest     BIT      = 0
AS
/*
	Creator: Robert
	Date: 2019-12-05
	DB: DBACC.bodb02
	Task: NAP Report - Automate daily abnormal bets report for CSD
	Revisions:		
		- 20191205@Robert: NAP Report - Automate daily abnormal bets report for CSD [122800]

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #TmpVoidedTransaction(
		   TransId           BIGINT
		 , SubIssueTypeId    TINYINT);

	   CREATE TABLE #Data(
		   TransId           BIGINT
		 , sporttype         TINYINT
		 , leagueid          INT
		 , homeid            INT
		 , awayid            INT
		 , kickofftime       DATETIME
		 , liveindicator     BIT
		 , bettype           SMALLINT
		 , SubIssueTypeId    TINYINT
		 , hthomescore       INT
		 , htawayscore       INT
		 , finalhomescore    INT
		 , finalawayscore    INT
		 , site              VARCHAR(50)
		 , AffectedSite      VARCHAR(50)
		 , Username          NVARCHAR(50));

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

	   CREATE CLUSTERED INDEX IX_TransId ON #TmpVoidedTransaction(TransId ASC);

	   INSERT INTO #Data(TransId
				    , sporttype
				    , leagueid
				    , homeid
				    , awayid
				    , kickofftime
				    , liveindicator
				    , bettype
				    , SubIssueTypeId
				    , hthomescore
				    , htawayscore
				    , finalhomescore
				    , finalawayscore
				    , site
				    , AffectedSite
				    , Username)
			SELECT tmp.TransId
				, l.sporttype
				, l.leagueid
				, m.homeid
				, m.awayid
				, m.kickofftime
				, b.liveindicator
				, b.bettype
				, tmp.SubIssueTypeId
				, m.hthomescore
				, m.htawayscore
				, m.finalhomescore
				, m.finalawayscore
				, CASE
					 WHEN s.isDeposit = 1
						 OR s.site IN('CN88', '789Y')
					 THEN s.site
					 ELSE 'Nova88'
				  END AS Site
				, CASE
					 WHEN s.isDeposit = 1
					 THEN 'Licensee'
					 WHEN s.site IN('CN88', '789Y')
					 THEN s.site
					 ELSE 'Nova88'
				  END AS AffectedSite
				, c2.username
			FROM bodb02.dbo.bettrans AS b WITH(NOLOCK)
			    INNER JOIN #TmpVoidedTransaction AS tmp ON b.transid = tmp.TransId
			    LEFT JOIN bodb02.dbo.match AS m WITH(NOLOCK) ON b.matchid = m.matchid
			    LEFT JOIN bodb02.dbo.league AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			    LEFT JOIN bodb02.dbo.Customer AS c WITH(NOLOCK) ON b.srecommend = c.custid
			    LEFT JOIN bodb02.dbo.Customer AS c2 WITH(NOLOCK) ON b.creator = c2.custid
			    LEFT JOIN bodb02.dbo.Site AS s WITH(NOLOCK) ON c.site = s.site
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

	   SELECT @RptDate AS Date
		   , b.sporttype
		   , b.leagueid
		   , b.homeid
		   , b.awayid
		   , b.kickofftime
		   , b.hthomescore
		   , b.htawayscore
		   , b.finalhomescore
		   , b.finalawayscore
		   , b.Username
		   , SUM(CASE
				   WHEN b.liveindicator = 1
				   THEN 1
				   ELSE 0
			    END) AS Live
		   , SUM(CASE
				   WHEN b.liveindicator = 0
				   THEN 1
				   ELSE 0
			    END) AS NonLive
		   , COUNT(TransId) AS TotalOfTickets
		   , ss.SubIssueTypeName AS Reason
		   , b.AffectedSite
		   , Sites = STUFF(
			(
			    SELECT DISTINCT 
					 N', ' + site
			    FROM #Data AS a
			    WHERE a.sporttype = b.sporttype
					AND a.leagueid = b.leagueid
					AND a.homeid = b.homeid
					AND a.awayid = b.awayid
					AND a.SubIssueTypeId = b.SubIssueTypeId
					AND a.kickofftime = b.kickofftime
					AND a.AffectedSite = b.AffectedSite FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 2, N'')
		   , Bettypes = STUFF(
			(
			    SELECT DISTINCT 
					 N',' + CAST(bettype AS VARCHAR(MAX))
			    FROM #Data AS a
			    WHERE a.sporttype = b.sporttype
					AND a.leagueid = b.leagueid
					AND a.homeid = b.homeid
					AND a.awayid = b.awayid
					AND a.SubIssueTypeId = b.SubIssueTypeId
					AND a.kickofftime = b.kickofftime
					AND a.Username = b.Username
					AND a.AffectedSite = b.AffectedSite FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 1, N'')
	   FROM #Data AS b
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON b.SubIssueTypeID = ss.SubIssueTypeId
	   GROUP BY b.sporttype
			, b.leagueid
			, b.homeid
			, b.awayid
			, b.kickofftime
			, b.SubIssueTypeId
			, ss.SubIssueTypeName
			, b.hthomescore
			, b.htawayscore
			, b.finalhomescore
			, b.finalawayscore
			, b.Username
			, b.AffectedSite
	   ORDER BY b.sporttype
			, b.leagueid
			, b.homeid
			, b.awayid;

	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
    END;
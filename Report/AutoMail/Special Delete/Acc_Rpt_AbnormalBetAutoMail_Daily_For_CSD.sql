/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_For_CSD 
	@RptDate    DATETIME
   , @IsTest     BIT      = 1
AS
/*
	Creator: Robert
	Date: 2019-12-05
	DB: DBACC.bodb02
	Task: NAP Report - Automate daily abnormal bets report for CSD
	Revisions:		
		- 20191205@Robert: NAP Report - Automate daily abnormal bets report for CSD [122800]
		- 20191226@Robert: NAP Report - Automate daily abnormal bets report for CSD [122800] - change request
		- 20211105@Cherry: Support void mix parlay (#164192)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #TmpVoidedTransaction(
		   RequestId         INT
		 , TransId           BIGINT
		 , SubIssueTypeId    TINYINT
		 , CreatedDate       DATETIME);

	   CREATE TABLE #Data(
		   RequestId         INT
		 , TransId           BIGINT
		 , sporttype         TINYINT
		 , leagueid          INT
		 , homeid            INT
		 , awayid            INT
		 , GlobalShowTime    DATETIME
		 , liveindicator     TINYINT
		 , bettype           SMALLINT
		 , SubIssueTypeId    TINYINT
		 , hthomescore       INT
		 , htawayscore       INT
		 , finalhomescore    INT
		 , finalawayscore    INT
		 , site              VARCHAR(50)
		 , AffectedSite      VARCHAR(50)
		 , Username          NVARCHAR(50)
		 , CreatedDate       DATETIME);

	   DECLARE @RptDate_From    DATETIME = @RptDate
		    , @RptDate_To      DATETIME;

	   SELECT @RptDate_From = CONVERT(VARCHAR(10), @RptDate_From, 101)
		   , @RptDate_To = DATEADD(d, 1, @RptDate_From);

	   INSERT INTO #TmpVoidedTransaction(RequestId
								, TransId
								, SubIssueTypeId
								, CreatedDate)
			SELECT tvh.RequestId
				, tv.TransId
				, tv.SubIssueTypeID
				, tv.CreatedDate
			FROM dbo.TicketVoiding_VoidedTransaction AS tv WITH(NOLOCK)
			    INNER JOIN dbo.TicketVoiding_VoidingHistory AS tvh WITH(NOLOCK) ON tv.reasonid = tvh.reasonid
			    INNER JOIN dbo.bettrans AS bt WITH(NOLOCK) ON tv.TransId = bt.transid
			    INNER JOIN dbo.match AS m WITH(NOLOCK) ON m.matchid = bt.matchid
			WHERE tv.IssueTypeID = 11
				 AND m.eventdate >= @RptDate_From
				 AND m.eventdate < @RptDate_To OPTION(MAXDOP 1);

	   CREATE CLUSTERED INDEX IX_TransId_RequestId ON #TmpVoidedTransaction(TransId ASC, RequestId ASC);

	   UPDATE t1
			SET 
			    t1.CreatedDate = t2.MaxCreatedDate
	   FROM #TmpVoidedTransaction AS t1
		  INNER JOIN
		   (
			  SELECT t.RequestId
				  , MAX(t.CreatedDate) AS MaxCreatedDate
			  FROM #TmpVoidedTransaction AS t
			  GROUP BY t.RequestId
		   ) AS t2 ON t1.RequestId = t2.RequestId;

	   INSERT INTO #Data(RequestId
				    , TransId
				    , sporttype
				    , leagueid
				    , homeid
				    , awayid
				    , GlobalShowTime
				    , liveindicator
				    , bettype
				    , SubIssueTypeId
				    , hthomescore
				    , htawayscore
				    , finalhomescore
				    , finalawayscore
				    , site
				    , AffectedSite
				    , Username
				    , CreatedDate)
			SELECT tmp.RequestId
				, tmp.TransId
				, l.sporttype
				, l.leagueid
				, m.homeid
				, m.awayid
				, m.GlobalShowTime
				, CASE WHEN b.bettype = 29 THEN b.livehomescore ELSE b.liveindicator END
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
				, tmp.CreatedDate
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

	   SELECT b.RequestId
		   , @RptDate AS Date
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.sporttype END sporttype
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.leagueid END leagueid
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.homeid END homeid
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.awayid END awayid
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.GlobalShowTime END GlobalShowTime
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.CreatedDate END CreatedDate
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.hthomescore END hthomescore
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.htawayscore END htawayscore
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.finalhomescore END finalhomescore
		   , CASE WHEN b.bettype = 29 THEN NULL ELSE b.finalawayscore END finalawayscore
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
			    WHERE a.RequestId = b.RequestId
					AND a.AffectedSite = b.AffectedSite FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 2, N'')
		   , Bettypes = STUFF(
			(
			    SELECT DISTINCT 
					 N',' + CAST(bettype AS VARCHAR(MAX))
			    FROM #Data AS a
			    WHERE a.RequestId = b.RequestId
					AND a.AffectedSite = b.AffectedSite FOR XML PATH(''), TYPE
			).value
			(N'.[1]', N'nvarchar(max)'), 1, 1, N'')
	   FROM #Data AS b
		  INNER JOIN bodb02.dbo.TicketVoiding_SubIssueType AS ss WITH(NOLOCK) ON b.SubIssueTypeID = ss.SubIssueTypeId
	   GROUP BY b.RequestId
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.sporttype END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.leagueid END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.homeid END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.awayid END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.GlobalShowTime END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.CreatedDate END
			, b.SubIssueTypeId
			, ss.SubIssueTypeName
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.hthomescore END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.htawayscore END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.finalhomescore END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.finalawayscore END
			, b.Username
			, b.AffectedSite
	   ORDER BY CASE WHEN b.bettype = 29 THEN NULL ELSE b.sporttype END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.leagueid END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.homeid END
			, CASE WHEN b.bettype = 29 THEN NULL ELSE b.awayid END

	   DROP TABLE #TmpVoidedTransaction;
	   DROP TABLE #Data;
    END;
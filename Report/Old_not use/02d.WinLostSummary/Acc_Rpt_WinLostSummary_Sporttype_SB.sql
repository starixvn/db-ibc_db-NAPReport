/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_WinlostSummary_Sporttype_SB
	@fromdate           DATETIME
   , @todate             DATETIME
   , @sporttype          INT         = 0
   , @bettype            INT         = 0
   , @liveindicator      BIT         = 0
   , @drilldownbytype    TINYINT
   , @SubProduct         VARCHAR(50) = ''
AS
BEGIN
/*
        Created: Johnson
        Date: 2013-06-24
        Task: Get winlost summary details by match for sportbook
        DB: DBRPT/bodb_Report
        
        Revisions:
            20130822@Johnson: change to use rptWinlost instead rptWinlost2]
            20131204@Johnson: get @movebetday base on match14
			20140327@Dom: Add Hedge Field
			20140804@Dom: [Feature #19394] Remove Hedge match
			20150924@Jim: Offer MO
			20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product, using sporttype bettype matrix function [RedmineID: #55584]
			20160504@Robert: Win Loss Summary (2d) - Cannot drilldown to match win loss detail from Number Game product [RedmineID: #56989]
			20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
			20170323@Robert: NAP Reports - Integrate Cash out [RedmindID: #73419]
			20180618@Tom: Fix Duplicate data when match have hedge (#97073)
			20190308@Cherry: Integrate Bet Builder (#109822)
			20200813@Ned.Le: HotFix - Soccer data is included data Bet Builder and Metric Gaming in Win Loss Summary (2d) report (#139454)
			20210420@Cherry: Renovation, change source table to DW (#153530)

        Parameter's Explanation:
		@type = 1 drilldown for sport
		@type = 2 drilldown for bettype
    */

    SET NOCOUNT ON;
    SELECT @SubProduct = ISNULL(@SubProduct, '');
    DECLARE @RPT TABLE(
	    eventdate           DATETIME
	  , matchid             INT
	  , matchcode           NVARCHAR(50) COLLATE SQL_Latin1_General_CP1_CS_AS
	  , HomeId              INT
	  , AwayId              INT
	  , liveindicator       BIT
	  , bettype             SMALLINT
	  , leagueid            INT
	  , realWinLost         MONEY
	  , realPosition        MONEY
	  , realCommission      MONEY
	  , realTurnover        MONEY
	  , realLineTotal       MONEY
	  , virtualTurnover     MONEY
	  , virtualLineTotal    MONEY
	  , isNeutral           BIT
	  , orderkey            TINYINT);
    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @SportBettype TABLE(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));
    INSERT INTO @SportBettype
		 SELECT ProductID
			 , Bettype
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.f_SportBettypeMatrix_Sel
			 (0, 0, 0, 2, '', '', @isTest);
    DELETE FROM @SportBettype
    WHERE Bettype IN(901, 902, 903, 904, 911, 912, 913, 914);
	IF ((@drilldownbytype = 1 AND @sporttype > 0 AND @sporttype <= 99 AND @SubProduct = '')
	    OR
		(@drilldownbytype = 2 AND @bettype=19999))
	BEGIN
		DELETE 
		FROM @SportBettype
		WHERE SubProduct IN ('MG-SuperLive', 'Bet Builder')
	END
    DECLARE @movebetdate    DATETIME
		, @f_date         DATETIME
		, @t_date         DATETIME;
	SELECT @f_date = @fromdate,
			@t_date = @todate    
	
	CREATE TABLE #tmpmatch
		(matchid INT, 
		leagueid INT, 
		homeid INT,
		awayid INT,
		eventdate DATETIME, 
		matchcode NVARCHAR(50),
		IsNeutral BIT)
		
	CREATE TABLE #tmpoutright
		(orid INT, 
		leagueid INT, 
		teamid INT,
		eventdate DATETIME, 
		matchcode VARCHAR(10))
		
	INSERT INTO #tmpmatch
		(matchid, 
		leagueid, 
		homeid,
		awayid,
		eventdate, 
		matchcode ,
		IsNeutral)
	SELECT matchid, 
		leagueid, 
		homeid,
		awayid,
		eventdate, 
		matchcode ,
		IsNeutral
	FROM bodb_Account.dbo.match WITH (NOLOCK) 
    WHERE eventdate BETWEEN @f_date AND @t_date
    UNION
    SELECT matchid, 
		leagueid, 
		homeid,
		awayid,
		eventdate, 
		matchcode ,
		IsNeutral
	FROM bodb_archive.dbo.match WITH (NOLOCK) 
    WHERE eventdate BETWEEN @f_date AND @t_date
    
    INSERT INTO #tmpoutright
		(orid, 
		leagueid, 
		teamid,
		eventdate, 
		matchcode)
	SELECT matchid, 
		leagueid, 
		homeid,
		eventdate, 
		matchcode
	FROM bodb_Account.dbo.outright WITH (NOLOCK) 
    WHERE eventdate BETWEEN @f_date AND @t_date
    UNION
    SELECT orid, 
		leagueid, 
		teamid,
		eventdate, 
		matchcode
	FROM bodb_archive.dbo.outright WITH (NOLOCK) 
    WHERE eventdate BETWEEN @f_date AND @t_date
    
    CREATE CLUSTERED INDEX IX_Matchid ON #tmpmatch (matchid) 
    CREATE CLUSTERED INDEX IX_orid ON #tmpoutright (orid)
    
    IF @drilldownbytype = 2
	BEGIN
		INSERT INTO @RPT(eventdate
					, matchid
					, matchcode
					, homeid
					, awayid
					, liveindicator
					, bettype
					, leagueid
					, realWinlost
					, realPosition
					, realCommission
					, realTurnover
					, realLineTotal
					, virtualTurnover
					, virtualLineTotal
					, isNeutral)
		SELECT m.eventdate
		  , b.matchid
		  , matchcode
		  , homeid
		  , awayid
		  , b.liveindicator
		  , b.bettype
		  , m.leagueid
		  , ISNULL(SUM(realWinlost), 0)
		  , ISNULL(SUM(realPosition), 0)
		  , ISNULL(SUM(realCommission), 0)
		  , ISNULL(SUM(realTurnover), 0)
		  , ISNULL(SUM(realLineTotal), 0)
		  , ISNULL(SUM(virtualTurnover), 0)
		  , ISNULL(SUM(virtualLineTotal), 0)
		  , m.isNeutral
		 FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
			 INNER JOIN @SportBettype AS sb ON b.bettype = sb.Bettype
			 INNER JOIN #tmpmatch AS m ON b.matchid = m.matchid
		WHERE winlostdate BETWEEN @f_date AND @t_date
		   AND b.sporttype = CASE
							WHEN @sporttype = -38
							THEN b.sporttype
							ELSE @sporttype
						 END --Bet Builder
		   AND CASE
				 WHEN @bettype = 0
				 THEN 1
				 WHEN @bettype = b.bettype
				 THEN 1
				 WHEN @bettype = 19999
					 AND b.bettype NOT IN(1, 3, 7, 8, 301, 302, 303, 304)
				 THEN 1
				 ELSE 0
			  END = 1
		   AND CASE
				 WHEN @bettype = 0
				 THEN 1
				 WHEN liveindicator = @liveindicator
				 THEN 1
				 ELSE 0
			  END = 1
		   AND m.matchcode NOT LIKE '%hedge%'
		   AND B.IBC = 0
		   AND b.bettype NOT IN(901, 902, 903, 904, 911, 912, 913, 914)
	  GROUP BY eventdate
		    , b.matchid
		    , matchcode
		    , homeid
		    , awayid
		    , liveindicator
		    , b.bettype
		    , leagueid
		    , isNeutral;
		    
		IF @bettype IN(0, 19999) AND @sporttype <= 99
		BEGIN
		   INSERT INTO @RPT(eventdate
					   , matchid
					   , matchcode
					   , homeid
					   , awayid
					   , liveindicator
					   , bettype
					   , leagueid
					   , realWinlost
					   , realPosition
					   , realCommission
					   , realTurnover
					   , realLineTotal
					   , virtualTurnover
					   , virtualLineTotal
					   , isNeutral)
			SELECT m.eventdate
				, b.matchid
				, m.matchcode
				, m.teamid AS homeid
				, 0 AS awayid
				, 0 AS liveindicator
				, b.bettype
				, m.leagueid
				, ISNULL(SUM(realWinlost), 0)
				, ISNULL(SUM(realPosition), 0)
				, ISNULL(SUM(realCommission), 0)
				, ISNULL(SUM(realTurnover), 0)
				, ISNULL(SUM(realLineTotal), 0)
				, ISNULL(SUM(virtualTurnover), 0)
				, ISNULL(SUM(virtualLineTotal), 0)
				, CONVERT(BIT, 0) AS IsNeutral
			FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
				INNER JOIN #tmpoutright AS m ON b.matchid = m.orid
			WHERE winlostdate BETWEEN @f_date AND @t_date
				 AND b.sporttype = @sporttype
				 AND b.bettype = 10
				 AND CASE
						WHEN @bettype = 0
						THEN 1
						WHEN liveindicator = @liveindicator
						THEN 1
						ELSE 0
					END = 1
				 AND m.matchcode NOT LIKE '%hedge%'
				 AND B.IBC = 0
			GROUP BY eventdate
				  , b.matchid
				  , m.matchcode
				  , m.teamid
				  , b.bettype
				  , m.leagueid;
		END;
	END;
			 
	IF @drilldownbytype = 1
	BEGIN
		INSERT INTO @RPT(eventdate
					, matchid
					, matchcode
					, homeid
					, awayid
					, liveindicator
					, bettype
					, leagueid
					, realWinlost
					, realPosition
					, realCommission
					, realTurnover
					, realLineTotal
					, virtualTurnover
					, virtualLineTotal
					, isNeutral)
		  SELECT m.eventdate
			  , b.matchid
			  , matchcode
			  , homeid
			  , awayid
			  , b.liveindicator
			  , b.bettype
			  , m.leagueid
			  , ISNULL(SUM(realWinlost), 0)
			  , ISNULL(SUM(realPosition), 0)
			  , ISNULL(SUM(realCommission), 0)
			  , ISNULL(SUM(realTurnover), 0)
			  , ISNULL(SUM(realLineTotal), 0)
			  , ISNULL(SUM(virtualTurnover), 0)
			  , ISNULL(SUM(virtualLineTotal), 0)
			  , m.isNeutral
		  FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
			 INNER JOIN @SportBettype AS sb ON b.bettype = sb.Bettype
			 INNER JOIN #tmpmatch AS m ON b.matchid = m.matchid
		  WHERE winlostdate BETWEEN @f_date AND @t_date
			   AND b.sporttype = @sporttype
			   AND CASE
					 WHEN @bettype = 0
					 THEN 1
					 WHEN @bettype = b.bettype
					 THEN 1
					 WHEN @bettype = 19999
						 AND b.bettype NOT IN(1, 3, 7, 8, 301, 302, 303, 304)
					 THEN 1
					 ELSE 0
				  END = 1
			   AND CASE
					 WHEN @bettype = 0
					 THEN 1
					 WHEN liveindicator = @liveindicator
					 THEN 1
					 ELSE 0
				  END = 1
			   AND CASE
					 WHEN @bettype = 0
						 AND @SubProduct <> ''
					 THEN sb.SubProduct
					 ELSE @SubProduct
				  END = @SubProduct
		  GROUP BY eventdate
				, b.matchid
				, matchcode
				, homeid
				, awayid
				, liveindicator
				, b.bettype
				, leagueid
				, isNeutral;
				
		IF @bettype IN(0, 19999) AND @sporttype <= 99
	    BEGIN
		   INSERT INTO @RPT(eventdate
					   , matchid
					   , matchcode
					   , homeid
					   , awayid
					   , liveindicator
					   , bettype
					   , leagueid
					   , realWinlost
					   , realPosition
					   , realCommission
					   , realTurnover
					   , realLineTotal
					   , virtualTurnover
					   , virtualLineTotal
					   , isNeutral)
			SELECT m.eventdate
				, b.matchid
				, m.matchcode
				, m.teamid AS homeid
				, 0 AS awayid
				, 0 AS liveindicator
				, b.bettype
				, m.leagueid
				, ISNULL(SUM(realWinlost), 0)
				, ISNULL(SUM(realPosition), 0)
				, ISNULL(SUM(realCommission), 0)
				, ISNULL(SUM(realTurnover), 0)
				, ISNULL(SUM(realLineTotal), 0)
				, ISNULL(SUM(virtualTurnover), 0)
				, ISNULL(SUM(virtualLineTotal), 0)
				, CONVERT(BIT, 0) AS IsNeutral
			FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
			    INNER JOIN @SportBettype AS sb ON b.bettype = sb.Bettype
			    INNER JOIN #tmpoutright AS m ON b.matchid = m.orid
			WHERE winlostdate BETWEEN @f_date AND @t_date
				 AND b.sporttype = @sporttype
				 AND b.bettype = 10
				 AND CASE
					    WHEN @bettype = 0
					    THEN 1
					    WHEN liveindicator = @liveindicator
					    THEN 1
					    ELSE 0
					END = 1
				 AND CASE
					    WHEN @bettype = 0
						    AND @SubProduct <> ''
					    THEN sb.SubProduct
					    ELSE @SubProduct
					END = @SubProduct
			GROUP BY eventdate
				  , b.matchid
				  , m.matchcode
				  , m.teamid
				  , b.bettype
				  , m.leagueid;
		END
	END;

    DECLARE @HedgeMatch TABLE(
	    evendate     DATETIME
	  , matchid      INT
	  , matchcode    NVARCHAR(50)
	  , leagueid     INT
	  , homeid       INT
	  , awayid       INT);
    INSERT INTO @HedgeMatch
		 SELECT DISTINCT
			   eventdate
			 , matchid
			 , matchcode
			 , leagueid
			 , HomeId
			 , AwayId
		 FROM @RPT
		 WHERE matchcode LIKE '%hedge%';
    UPDATE @RPT
		 SET
			orderkey = CASE
						WHEN Bettype = 1
							AND liveindicator = 0
						THEN 1
						WHEN Bettype = 301
							AND liveindicator = 0
						THEN 2
						WHEN Bettype = 1
							AND liveindicator = 1
						THEN 3
						WHEN Bettype = 301
							AND liveindicator = 1
						THEN 4
						WHEN Bettype = 3
							AND liveindicator = 0
						THEN 5
						WHEN Bettype = 302
							AND liveindicator = 0
						THEN 6
						WHEN Bettype = 3
							AND liveindicator = 1
						THEN 7
						WHEN Bettype = 302
							AND liveindicator = 1
						THEN 8
						WHEN Bettype = 7
							AND liveindicator = 0
						THEN 9
						WHEN Bettype = 303
							AND liveindicator = 0
						THEN 10
						WHEN Bettype = 7
							AND liveindicator = 1
						THEN 11
						WHEN Bettype = 303
							AND liveindicator = 1
						THEN 12
						WHEN Bettype = 8
							AND liveindicator = 0
						THEN 13
						WHEN Bettype = 304
							AND liveindicator = 0
						THEN 14
						WHEN Bettype = 8
							AND liveindicator = 1
						THEN 15
						WHEN Bettype = 304
							AND liveindicator = 1
						THEN 16
						ELSE 17
					 END;
    SELECT CASE
			WHEN d.matchcode LIKE '%hedge%'
				OR r.matchcode LIKE '%hedge%'
			THEN ISNULL(d.matchcode, r.matchcode)
		 END AS HedgeGroup
	    , CASE
			WHEN r.matchcode LIKE '%hedge%'
			THEN 1
			ELSE 0
		 END AS IsHedge
		,l.sporttype
	    , r.*
    FROM @RPT AS r
	     LEFT JOIN bodb02.dbo.league l (NOLOCK) ON r.leagueid = l.leagueid
	   OUTER APPLY
	    (
		   SELECT *
		   FROM @HedgeMatch AS h
		   WHERE h.leagueid = r.leagueid
			    AND h.homeid = r.HomeId
			    AND h.awayid = r.AwayId
			    AND h.evendate = r.eventdate
			    AND h.matchid <> r.matchid
	    ) AS D
    ORDER BY r.orderkey
		 , r.HomeId
		 , r.AwayId
		 , r.leagueid
		 , r.matchcode
		 , r.bettype;
END;
GO
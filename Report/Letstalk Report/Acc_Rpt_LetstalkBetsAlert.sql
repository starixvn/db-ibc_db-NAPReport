
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250402@Robert
	Task: #222345 - Letstalk - Bets Alert [ReportID 48]
	Database:	DBACC.bodb02 
	
	Revisions:
		- 20250402@Robert: #222345 - Letstalk - Bets Alert [ReportID 48]		
		- 20250704@Robert: #231786 - Notify when product has a bet ticket.
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
	   106	VSRaceInfo	                eventid,sporttype
	   27	Match or VSRaceInfo		  	 matchid,sporttype OR eventid, sporttype
	   5	  	match		                matchid,sporttype
	   88	match3rd	 	                match3rdid,sporttype
	   77	match		                matchid,sporttype
	   83	match		                matchid,sporttype
*/

CREATE PROC [dbo].[Acc_Rpt_LetstalkBetsAlert] 
	@StartDate   DATETIME, 
	@EndDate     DATETIME, 
	@TimeSetting VARCHAR(10)
AS
    BEGIN

	   DECLARE 
		   @tblSports TABLE
						(
		   ProductId   TINYINT, 
		   SportType   SMALLINT, 
		   TimeSetting VARCHAR(10)
						);
	   CREATE TABLE #match
				 (
		   matchid INT
				 );
	   INSERT INTO @tblSports
		 (
			ProductId, 
			SportType, 
			TimeSetting
		 )
			SELECT 
				  s.ProductId, 
				  s.SportType, 
				  s.TimeSetting
			FROM f_GetLetstalkAlertSports() s
			WHERE s.IsTest = 1
				 AND s.TimeSetting = @TimeSetting;

	   INSERT INTO #match
		 (
			matchid
		 )
			SELECT 
				  b.matchid
			FROM bettrans b WITH(NOLOCK)
				LEFT JOIN match m WITH(NOLOCK) ON b.matchid = m.matchid
										    AND m.sporttype < 99 -- exclude sportsbook
			WHERE b.transdate BETWEEN @StartDate AND @EndDate
				 AND m.matchid IS NULL
			GROUP BY 
				    b.matchid;

	   WITH cte
		   AS (SELECT DISTINCT 
				    s.ProductId
			  FROM #match m
				  INNER JOIN @tblSports s ON s.SportType = m.matchid
			  UNION ALL
			  SELECT DISTINCT 
				    s.ProductID
			  FROM bettransLC b WITH(NOLOCK)
				  INNER JOIN @tblSports s ON s.SportType = b.ProductID
			  WHERE b.transdate BETWEEN @StartDate AND @EndDate
			  UNION ALL
			  SELECT DISTINCT 
				    s.ProductID
			  FROM bettransRNG b WITH(NOLOCK)
				  INNER JOIN @tblSports s ON s.SportType = b.ProductID
			  WHERE b.transdate BETWEEN @StartDate AND @EndDate
			  --- for products that matchid in bettrans is real match, not sporttype
			  UNION ALL
			  SELECT DISTINCT 
				    s.ProductId
			  FROM #match b WITH(NOLOCK)
				  INNER JOIN match m WITH(NOLOCK) ON b.matchid = m.matchid
				  INNER JOIN @tblSports s ON m.sporttype = s.SportType
			  UNION ALL
			  SELECT DISTINCT 
				    s.ProductId
			  FROM #match b WITH(NOLOCK)
				  INNER JOIN match3rd m WITH(NOLOCK) ON b.matchid = m.Match3rdId
				  INNER JOIN @tblSports s ON m.sporttype = s.SportType
			  UNION ALL
			  SELECT DISTINCT 
				    s.ProductId
			  FROM #match b WITH(NOLOCK)
				  INNER JOIN VSRaceInfo m WITH(NOLOCK) ON b.matchid = m.EventID
				  INNER JOIN @tblSports s ON m.sporttype = s.SportType)
		   SELECT DISTINCT 
				p.ProductName, 
				s.TimeSetting
		   FROM @tblSports s
			   INNER JOIN Products p WITH(NOLOCK) ON s.ProductId = p.ProductID
			   INNER JOIN cte p2 ON s.ProductId = p2.ProductId
		   ORDER BY 
				  s.TimeSetting;

	   DROP TABLE #match;
    END;
GO

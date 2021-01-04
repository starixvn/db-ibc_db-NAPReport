/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02];
GO

ALTER PROCEDURE dbo.Acc_Rpt_NumberGame
	@winlostdate      DATETIME
   , @SiteID           VARCHAR(8000) = ''
   , @Currency         VARCHAR(8000) = ''
   , @LiveIndicator    BIT           = NULL
   , @TrialData        BIT           = 0 /* 1 : Get trial data, 0 Don't get trial data*/
AS
/*	Creator: Viet
	Date: 2010-12-10
	Task: Number Game WinLost Summary report
	DB: DBACC/bodb02
	
	Revisions:		
		- 16Dec2010@Viet: Correct Turnover's value
		- 18Dec2010@Viet: Add Virtual Line Total
		- 23June2011@Daniel: support filter by sites and currency
		- 01Aug2011@Johnson: Add more bettype for number game
		- 18Oct2011@Johnson: Filter more sites and currency
		- 20121024@Elodie: Filter more LiveIndicator
		- 20121112@Jamie: Create #tmpAge instead of @tmpAg 
		- 20121120@Dan: optimize performance (use index when searching agent, create index after inserting) 
		- 20130123@Daniel: Change link server alias
		- 20130815@Viet: enhance sp
		- 20130917@Kathy: Fix currency's value
		- 20150319@Tom: Get Data by Effective Licensee (#31687)
		- 20180301@Kean: Missing number game data of some licensee (91266)
		- 20181031@Percy: Remove linked-server DBLIC [RedmineID: #103660]
		- 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 
		
    Param usage:
		- @SiteID:
			+ =0: No Site filter
			+ >0: Filter by specific Licensee's ID
			+ -1: Filter by IBC sites (Non-Licensee sites)

		- @Currency:
			+ =0: No currency filter
			+ >0: Filter by specific CurrencyID
			
		- @LiveIndicator:
			+ Null: All (default)
			+ 0: Non-Live
			+ 1: Live	  		
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @tmpCurrency TABLE(
	    currency    INT);
    DECLARE @tmpSite TABLE(
	    siteid    INT);
    DECLARE @licenseeCnt_db    INT
		, @licencseeCnt      INT;

    INSERT INTO @tmpCurrency
		 SELECT DISTINCT
			   val
		 FROM strSPlit
			 (@currency, ',');

    INSERT INTO @tmpSite
		 SELECT val
		 FROM strSPlit
			 (@siteid, ',');

    IF @siteid = ''
	   INSERT INTO @tmpSite
			SELECT-1;

    DECLARE @tmpLscActive TABLE(
	    LicenseeID      INT
	  , LicenseeName    VARCHAR(100)
	  , FromDate        SMALLDATETIME
	  , ToDate          SMALLDATETIME);

    INSERT INTO @tmpLscActive(LicenseeID
					   , LicenseeName
					   , FromDate
					   , ToDate)
		 SELECT LicenseeID
			 , LicenseeName
			 , FromDate
			 , ToDate
		 FROM dbo.NAP_f_GetAffectedDateLicensee
			 (1, @siteid, 1, @winlostdate, @winlostdate, 1, 18, 3, 'NG', @TrialData);

    CREATE TABLE #Bettype(
	    SportType    SMALLINT
	  , Bettype      SMALLINT);

    INSERT INTO #Bettype(SportType
				   , Bettype)
		 SELECT DISTINCT
			   sb.SportType
			 , sb.BetType
		 FROM SportBettypeMatrix AS sb WITH (NOLOCK)
		 WHERE ProductID = 3;

    CREATE NONCLUSTERED INDEX IX_Bettype ON #Bettype(Bettype);

    CREATE TABLE #supers(
	    custID    INT);

    IF EXISTS
		    (
			   SELECT 1
			   FROM @tmpSite
			   WHERE siteid = -1
		    ) /*IBCGroup   */


	   BEGIN
		  INSERT INTO #supers(custID)
			    SELECT s.custid
			    FROM CustSuper AS s WITH (NOLOCK)
				   INNER JOIN custInfo AS c WITH (NOLOCK) ON s.custid = c.custid
			    WHERE s.custid NOT IN
								 (
									SELECT custid
									FROM Dep_CustSuper WITH (NOLOCK)
								 )
					AND
					    (@currency = ''
						OR c.currency IN
									  (
										 SELECT t.currency
										 FROM @tmpCurrency AS t
									  ));
	   END;

    IF EXISTS
		    (
			   SELECT TOP 1 1
			   FROM @tmpLscActive
			   WHERE licenseeID > 0
		    )
	   BEGIN
		  INSERT INTO #supers(custID)
			    SELECT s.custid
			    FROM dbo.Dep_CustSuper AS s WITH (NOLOCK)
				   INNER JOIN bodb_Licensee.dbo.Licensees AS l WITH (NOLOCK) ON s.site = l.licenseename
			    WHERE
				    (@currency = ''
					OR currency IN
								(
								    SELECT t.currency
								    FROM @tmpCurrency AS t
								))
				    AND l.licenseeID IN
								    (
									   SELECT licenseeID
									   FROM @tmpLscActive
								    );
	   END;

    SELECT bt.SportType
	    , b.bettype AS                                                                            bettype
	    , SUM((winlost - actual_stake) * actualrate) AS                                           WinLost
	    , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                   Position
	    , SUM(scomm * actualrate) AS                                                              Commission
	    , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS  LineTotal
	    , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS VirtualLineTotal
	    , SUM((1 - tpositiontaking) * stake * actualrate) AS                                      Turnover
    FROM dbo.bettrans AS b WITH (NOLOCK)
	   INNER JOIN #Bettype AS bt ON b.bettype = bt.Bettype
	   INNER JOIN (
		   	select matchid, matchcode, sporttype, leagueid from match with (nolock) 
	   		union -- add dummy row to not losing out happy 5 linked games data
			select 168, 'refer bettrans.betcheck', 168, -1
		) AS m
	   	ON b.matchid = m.matchid AND b.winlostdate = @winlostdate
    WHERE b.ruben = 1
		AND b.statusID NOT IN(101, 102, 103, 121)
		AND b.liveindicator = CASE
							 WHEN @LiveIndicator IS NULL
							 THEN b.liveindicator
							 ELSE @LiveIndicator
						  END
		AND b.srecommend IN
						(
						    SELECT custid FROM #supers
						)
    GROUP BY b.Bettype
		 , bt.SportType
    ORDER BY bt.SportType
		 , b.Bettype;

    DROP TABLE #supers;

    DROP TABLE #Bettype;
END;
GO

GRANT EXECUTE ON dbo.Acc_Rpt_NumberGame TO [bodbAdminNet];
GO
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02];
GO

ALTER PROCEDURE dbo.Acc_Rpt_NumberGame_Details14
	@winlostdate      DATETIME
   , @liveindicator    BIT           = NULL
   , @bettype          INT
   , @SiteID           VARCHAR(8000) = ''
   , @Currency         VARCHAR(8000) = ''
   , @TrialData        BIT           = 0 /* 1 : Get trial data, 0 Don't get trial data	*/
AS
/*	Creator: Viet
	Date: 10 Dec 2010
	Task: Detailed Winloss Summary History
	DB: DBRPT/bodb02
	
	Revisions:			
		- 16Dec2010@Viet: Correct Turnover's value
		- 18Dec2010@Viet: Add Virtual Line Total
		- 23June2011@Daniel: support filter by sites and currency
		- 18Oct2011@Johnson: - Filter more sites and currency 
							 - Remove check winlostdate to calculate turnover
		- 20121024@Elodie: Filter more LiveIndicator
		- 20121121@Dan: optimize performance (create #tmpAge instead of @tmpAg, use index when searching agent, create index after inserting) 
        - 20130123@Daniel: Change link server alias
		- 20150319@Tom: Get Data by Effective Licensee (#31687)
		- 20180301@Kean: Missing number game data of some licensee (91266)
		- 20181031@Percy: Remove linked-server DBLIC [RedmineID: #103660]
		- 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 
		- 20201225@Jaden: Add new sporttype for Happy 5 Linked games (#147573)

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
	Remarls:
		- refer to SP Acc_Rpt_NumberGame_Details
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @tmpCurrency TABLE(
	    currency    INT);
    DECLARE @tmpSite TABLE(
	    siteid    INT);

    CREATE TABLE #tmpAg(
	    custID    INT);

    INSERT INTO @tmpCurrency
		 SELECT val
		 FROM strSPlit
			 (@currency, ',');

    UPDATE @tmpCurrency
		 SET
			currency = NULL
    WHERE currency = 0; /* ALL currency*/


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

    CREATE TABLE #Bettype(
	    Bettype    SMALLINT);

    INSERT INTO #Bettype(Bettype)
		 SELECT DISTINCT
			   sb.BetType
		 FROM bodb02.dbo.SportBettypeMatrix AS sb WITH (NOLOCK)
		 WHERE ProductID = 3
			  AND bettype = @bettype;
    CREATE NONCLUSTERED INDEX IX_Bettype ON #Bettype(Bettype);

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

    IF EXISTS
		    (
			   SELECT 1
			   FROM @tmpSite
			   WHERE siteid = -1
		    )/*IBCGroup   */

	   BEGIN
		  INSERT INTO #tmpAg
			    SELECT custID
			    FROM customer AS ci WITH (NOLOCK)
			    WHERE ci.custid NOT IN
								  (
									 SELECT custid
									 FROM bodb_Licensee.dbo.LicenseeCust WITH (NOLOCK)
								  )
					AND ci.roleid = 2
					AND
					    (@Currency = ''
						OR ci.Currency IN
									   (
										  SELECT ISNULL(t.currency, ci.currency)
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
		  INSERT INTO #tmpAg
			    SELECT custID
			    FROM bodb_Licensee.dbo.LicenseeCust AS lc WITH (nolock)
			    WHERE LicenseeID IN
							    (
								   SELECT licenseeID
								   FROM @tmpLscActive
								   WHERE licenseeID > 0
							    )
					AND roleid = 2
					AND
					    (@Currency = ''
						OR lc.Currency IN
									   (
										  SELECT ISNULL(t.currency, lc.currency)
										  FROM @tmpCurrency AS t
									   ));
	   END;
/* only create index after inserting data to not affect performance when inserting*/

    CREATE INDEX IX_tmpAg_CustID ON #tmpAg(CustID);

    SELECT
		case when m.matchid != 168 then m.matchcode
			 else left(right(b.betcheck, charindex('-', reverse(b.betcheck)) - 1), 
					charindex('-', reverse(b.betcheck)) - charindex(';', reverse(b.betcheck)) - 1)
		end as matchcode
	    , b.BetType AS                                                                            bType
	    , m.leagueid
	    , SUM((winlost - actual_stake) * actualrate) AS                                           WinLost
	    , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                   Position
	    , SUM(scomm * actualrate) AS                                                              Commission
	    , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS  LineTotal
	    , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS VirtualLineTotal
	    , SUM((1 - tpositiontaking) * stake * actualrate) AS                                      Turnover
    FROM bettrans14 AS b WITH (nolock)
	   INNER JOIN #Bettype AS bt ON b.bettype = bt.Bettype
	   INNER JOIN (
		   	select matchid, matchcode, sporttype, leagueid from match14 with (nolock) 
	   		union -- add dummy row to not losing out happy 5 linked games data
			select 168, 'refer bettrans.betcheck', 168, -1
		) AS m
		ON b.matchid = m.matchid
    WHERE b.winlostdate = @winlostdate
		AND statusID NOT IN(102, 101, 103, 121)
		AND b.matchid > 0
		AND b.ruben = 1
		AND b.liveindicator = CASE
							 WHEN @LiveIndicator IS NULL
							 THEN b.liveindicator
							 ELSE @LiveIndicator
						  END
		AND recommend IN
					  (
						 SELECT custid FROM #tmpAg
					  )
    GROUP BY
		 case when m.matchid != 168 then m.matchcode
			 else left(right(b.betcheck, charindex('-', reverse(b.betcheck)) - 1), 
					charindex('-', reverse(b.betcheck)) - charindex(';', reverse(b.betcheck)) - 1)
		 end
		 , b.bettype
		 , m.leagueid
    ORDER BY m.leagueid , matchcode;

    DROP TABLE #Bettype;
    DROP TABLE #tmpAg;
END;
GO

GRANT EXECUTE ON dbo.Acc_Rpt_NumberGame_Details14 TO [bodbAdminNet];
GO
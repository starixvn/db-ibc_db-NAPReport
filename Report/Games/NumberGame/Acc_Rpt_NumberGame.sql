/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGame]
	@winlostdate datetime,
    @SiteID	VARCHAR(8000) = '',
    @Currency VARCHAR(8000) = '',
    @LiveIndicator bit = NULL,
	@TrialData	BIT = 0 -- 1 : Get trial data, 0 Don't get trial data
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
SET NOCOUNT ON

DECLARE	@tmpCurrency TABLE(currency INT)
DECLARE	@tmpSite TABLE(siteid INT)

DECLARE @licenseeCnt_db int, @licencseeCnt int

INSERT INTO @tmpCurrency
	SELECT distinct(val)
	FROM strSPlit(@currency,',')

INSERT INTO @tmpSite
	SELECT val 
	FROM strSPlit(@siteid,',')

IF @siteid = ''
	INSERT INTO @tmpSite
		SELECT -1 	

DECLARE @tmpLscActive TABLE (
		LicenseeID INT
		,LicenseeName VARCHAR(100)
		,FromDate SMALLDATETIME
		,ToDate SMALLDATETIME
		)

INSERT INTO @tmpLscActive (
	LicenseeID
	,LicenseeName
	,FromDate
	,ToDate
	)
SELECT LicenseeID
	,LicenseeName
	,FromDate
	,ToDate
FROM dbo.[NAP_f_GetAffectedDateLicensee](1,@siteid,1, @winlostdate, @winlostdate, 1, 18, 3, 'NG', @TrialData)

BEGIN
	CREATE TABLE #supers(custID INT)
	IF EXISTS (SELECT 1 FROM @tmpSite WHERE siteid = -1)--IBCGroup   
	BEGIN  	
		INSERT INTO #supers (custID)
		SELECT s.custid
		FROM CustSuper s WITH(NOLOCK)
			INNER JOIN custInfo c WITH(NOLOCK) on s.custid = c.custid
		WHERE s.custid not in (SELECT custid FROM Dep_CustSuper WITH(NOLOCK))
			AND (@currency = '' OR c.currency IN (SELECT t.currency FROM @tmpCurrency t))
	END  
	
	IF EXISTS( SELECT TOP 1 1 FROM @tmpLscActive WHERE licenseeID > 0)
	BEGIN
		--IF EXISTS( SELECT 1 FROM @tmpSite WHERE siteid > 0)--Licensee
		BEGIN  
			INSERT INTO #supers (custID)
			SELECT s.custid
			FROM dbo.Dep_CustSuper s with(nolock)
				INNER JOIN bodb_Licensee.dbo.Licensees l with(nolock) on s.site = l.licenseename
			WHERE (@currency = '' OR currency in (SELECT t.currency FROM @tmpCurrency t))
				--AND l.licenseeID in (SELECT siteid FROM @tmpSite)
				AND l.licenseeID in (SELECT licenseeID FROM @tmpLscActive)
		END  
	END
	
    SELECT			        
	        b.bettype bettype,
	        sum((winlost-actual_stake)*actualrate) WinLost,
	        sum((awinlost+mwinlost+swinlost)*actualrate) Position,
	        sum(scomm*actualrate) Commission,	
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
	        sum((1-tpositiontaking)*stake*actualrate) Turnover
    FROM dbo.bettrans b WITH (NOLOCK)
		INNER JOIN dbo.match m with(nolock) on b.matchid = m.matchid and m.sporttype = 161 and m.eventdate = @winlostdate
    WHERE b.bettype BETWEEN 81 AND 120		
		AND b.ruben = 1		
		AND b.statusID not in (101,102,103,121)	        
		AND b.liveindicator = CASE  WHEN @LiveIndicator IS NULL THEN b.liveindicator ELSE @LiveIndicator END	      
		AND b.srecommend IN (SELECT custid FROM #supers)		
    GROUP BY b.Bettype
    ORDER BY b.Bettype
    
    DROP TABLE #supers
END
    



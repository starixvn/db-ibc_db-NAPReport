ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGame14]
	@winlostdate datetime,
    @SiteID	VARCHAR(500) = '',
    @Currency VARCHAR(500) = '',
	@LiveIndicator bit = NULL
AS
/*
	Creator: Viet
	Date: 2010-12-10
	Task: Number Game WinLost Summary report
	DB: DBRPT/bodb02
		
	Revisions:
		- 16Dec2010@Viet: Correct Turnover's value
		- 18Dec2010@Viet: Add Virtual Line Total
    	- 23June2011@Daniel: support filter by sites and currency
		- 02Aug2011@Johnson: Add more bettype 
		- 18Oct2011@Johnson: Filter more sites and more currency
		- 20121024@Elodie: Filter more LiveIndicator
		- 20121112@Jamie: Create #tmpAge instead of @tmpAg 
		- 20121121@Dan: optimize performance (use index when searching agent, create index after inserting) 
        - 20130123@Daniel: Change link server alias
		- 20150319@Tom: Get Data by Effective Licensee (#31687)

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

--DECLARE @tmpAg TABLE(custID INT PRIMARY KEY) 
DECLARE	@tmpCurrency TABLE(currency INT)
DECLARE	@tmpSite TABLE(siteid INT)

CREATE TABLE #tmpAg(custID INT)

--CREATE INDEX IX_tmpAg_CustID ON #tmpAg(CustID)


INSERT INTO @tmpCurrency
	SELECT val
	FROM strSPlit(@currency,',')
	
UPDATE @tmpCurrency
SET currency = NULL
WHERE currency = 0 -- ALL currency

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
FROM dbo.[NAP_f_GetAffectedDateLicensee](1,@siteid,1, @winlostdate, @winlostdate, 1, 18, 3, 'NG')

IF EXISTS (SELECT 1 FROM @tmpSite WHERE siteid = -1)--IBCGroup   
BEGIN  	
		INSERT INTO #tmpAg
		SELECT custID FROM customer ci WITH (NOLOCK)
		WHERE ci.custid NOT IN(SELECT custid from DBLIC.bodb_Licensee.dbo.LicenseeCust WITH (NOLOCK))
			AND ci.roleid = 2
			AND (@currency = '' OR ci.Currency IN (SELECT ISNULL(t.currency,ci.currency) FROM @tmpCurrency t))
END  

IF EXISTS( SELECT TOP 1 1 FROM @tmpLscActive WHERE licenseeID > 0)
--IF EXISTS( SELECT 1 FROM @tmpSite WHERE siteid > 0)--Licensee   
BEGIN
    INSERT INTO #tmpAg
    SELECT custID FROM DBLIC.bodb_Licensee.dbo.LicenseeCust lc with (nolock) 
    WHERE LicenseeID IN (SELECT licenseeID FROM @tmpLscActive WHERE licenseeID > 0)
        AND roleid = 2
        AND (@currency = '' OR lc.Currency IN (SELECT ISNULL(t.currency,lc.currency) FROM @tmpCurrency t))
END    
-- only create index after inserting data to not affect performance when inserting
CREATE INDEX IX_tmpAg_CustID ON #tmpAg(CustID)

/*
IF EXISTS (SELECT 1 FROM @tmpSite WHERE SiteID = 0)-- ALL Site
    SELECT		
	        b.bettype bettype,
	        sum((winlost-actual_stake)*actualrate) WinLost,
	        sum((awinlost+mwinlost+swinlost)*actualrate) Position,
	        sum(scomm*actualrate) Commission,	
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
	        sum((1-tpositiontaking)*stake*actualrate) Turnover
    FROM	bettrans14 b WITH (NOLOCK)
    WHERE	b.winlostdate = @winlostdate
	        AND b.bettype BETWEEN 81 AND 120	
	        AND b.ruben = 1		
	        AND b.statusID not in (101,102,103,121)
            AND b.Currency IN (SELECT ISNULL(t.currency,b.currency) FROM @tmpCurrency t)
            and b.liveindicator = CASE  WHEN @LiveIndicator IS NULL THEN b.liveindicator ELSE @LiveIndicator END									
    GROUP BY b.Bettype
    ORDER BY b.Bettype
ELSE
*/
    SELECT		
	        b.bettype bettype,
	        sum((winlost-actual_stake)*actualrate) WinLost,
	        sum((awinlost+mwinlost+swinlost)*actualrate) Position,
	        sum(scomm*actualrate) Commission,	
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
	        sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
	        sum((1-tpositiontaking)*stake*actualrate) Turnover
    FROM	bettrans14 b WITH (NOLOCK)
    WHERE	b.winlostdate = @winlostdate
	        AND b.bettype BETWEEN 81 AND 120		
	        AND b.ruben = 1		
	        AND b.statusID not in (101,102,103,121)
	        AND recommend IN(SELECT custid FROM #tmpAg)
	        and b.liveindicator = CASE  WHEN @LiveIndicator IS NULL THEN b.liveindicator ELSE @LiveIndicator END									
    GROUP BY b.Bettype
    ORDER BY b.Bettype
    
DROP TABLE #tmpAg

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGame14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGame14] TO [vnteam]
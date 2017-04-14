ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGame_Details]
	@winlostdate	datetime,
	@liveindicator	bit = NULL,
	@bettype		int,
    @SiteID	VARCHAR(500) = '',
    @Currency VARCHAR(500) = ''	
AS
/*	
	Creator: Viet
	Date: 10 Dec 2010
	Task: Detailed Winloss Summary History
	DB: DBRPT/bodb02
		
	Revisions:			
		- 16Dec2010@Viet: Correct Turnover's value
		- 18Dec2010@Viet: Add Virtual Line Total
		- 23June2011@Daniel: support filter by sites and currency	
		- 18Oct2011@Johnson: Filter more sites and more currency		
		- 20121024@Elodie: Filter more LiveIndicator
		- 20121121@Dan: optimize performance (create #tmpAge instead of @tmpAg, use index when searching agent, create index after inserting) 
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

DECLARE	@tmpCurrency TABLE(currency INT)
DECLARE	@tmpSite TABLE(siteid INT)
CREATE TABLE #tmpAg(custID INT) 

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
			AND (@Currency = '' OR ci.Currency IN (SELECT ISNULL(t.currency,ci.currency) FROM @tmpCurrency t)	)
END  

IF EXISTS( SELECT TOP 1 1 FROM @tmpLscActive WHERE licenseeID > 0)
--IF EXISTS( SELECT 1 FROM @tmpSite WHERE siteid > 0)--Licensee   
BEGIN  
    INSERT INTO #tmpAg
    SELECT custID FROM DBLIC.bodb_Licensee.dbo.LicenseeCust lc with (nolock) 
    WHERE LicenseeID IN (SELECT licenseeID FROM @tmpLscActive WHERE licenseeID > 0)
        AND roleid = 2
        AND (@Currency = '' OR lc.Currency IN (SELECT ISNULL(t.currency,lc.currency) FROM @tmpCurrency t))
END    

-- only create index after inserting data to not affect performance when inserting
CREATE INDEX IX_tmpAg_CustID ON #tmpAg(CustID)
/*
IF EXISTS (SELECT 1 FROM @tmpSite WHERE SiteID = 0)-- ALL Site
    SELECT
	    m.matchcode,
	    b.BetType bType, 
	    m.leagueid,					
	    sum((winlost-actual_stake)*actualrate) WinLost,
	    sum((awinlost+mwinlost+swinlost)*actualrate) Position,
	    sum(scomm*actualrate) Commission,
	    sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
	    sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
	    sum((1-tpositiontaking)*stake*actualrate) Turnover
    FROM 
	    bettrans b with (nolock)
	    INNER JOIN match m with (nolock) ON b.matchid = m.matchid
    WHERE
	    b.winlostdate = @winlostdate		
	    AND statusID NOT IN (102, 101, 103, 121) 
	    AND b.matchid > 0 
	    AND b.ruben = 1			
	    AND m.SportType = 161
	    AND b.BetType = @Bettype
	    and b.liveindicator = CASE  WHEN @LiveIndicator IS NULL THEN b.liveindicator ELSE @LiveIndicator END									
        AND b.Currency IN (SELECT ISNULL(t.currency,b.currency) FROM @tmpCurrency t)
    GROUP BY
	    m.matchcode,
	    m.HomeId,
	    m.AwayId,
	    b.bettype, 
	    m.leagueid,
	    m.isNeutral
    ORDER BY 
	    m.leagueid,--leaguename,
	    m.matchcode	
ELSE
*/
    SELECT
	    m.matchcode,
	    b.BetType bType, 
	    m.leagueid,					
	    sum((winlost-actual_stake)*actualrate) WinLost,
	    sum((awinlost+mwinlost+swinlost)*actualrate) Position,
	    sum(scomm*actualrate) Commission,
	    sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
	    sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
	    sum((1-tpositiontaking)*stake*actualrate) Turnover
    FROM 
	    bettrans b with (nolock)
	    INNER JOIN match m with (nolock) ON b.matchid = m.matchid
    WHERE
	    b.winlostdate = @winlostdate		
	    AND statusID NOT IN (102, 101, 103, 121) 
	    AND b.matchid > 0 
	    AND b.ruben = 1			
	    AND m.SportType = 161
	    AND b.BetType = @Bettype
	    and b.liveindicator = CASE  WHEN @LiveIndicator IS NULL THEN b.liveindicator ELSE @LiveIndicator END									
        AND recommend IN(SELECT custid FROM #tmpAg)	    			
    GROUP BY
	    m.matchcode,
	    m.HomeId,
	    m.AwayId,
	    b.bettype, 
	    m.leagueid,
	    m.isNeutral
    ORDER BY 
	    m.leagueid,--leaguename,
	    m.matchcode	

GO
GRANT EXECUTE ON dbo.[Acc_Rpt_NumberGame_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGame_Details] TO [vnteam]
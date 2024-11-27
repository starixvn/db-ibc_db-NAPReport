/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistic_CurrencySel]
	@SiteId VARCHAR(MAX) = 'All',
	@ExcludeTest BIT = 0
AS
/*
	Created by: 20201020@Cherry
	Task: Get Currency dropdown by Site [Redmine: #140386]
	DB: DBACC.bodb02
	
	Revisions:
		20201020@Cherry: Get Currency dropdown by Site [Redmine: #140386]
		20210324@Cherry: Consider Saba789 as Credit site (#152124)
		20210428@Cherry: Add LicenseeGroup (#153736)
		20231114@Roy: NAP Reports - Move SEAL8888 into Credit Group (#195730)
		20241128@Cherry: Add NovaCasino in Credit Group (#214333)
		
	Param: 
		@SiteId = -1: Credit, >0: Deposit, 'All': Credit + Deposit

*/

BEGIN
	SET NOCOUNT ON
	CREATE TABLE #tmpSite (SiteID INT)
	CREATE TABLE #Currency (ExchangeId INT, Currency NVARCHAR(50))
	CREATE TABLE #tmpLicensees (LicenseeID INT, LicenseeName VARCHAR(50))
	DECLARE @IsCredit BIT = 0
	
	IF @SiteId <> 'All'
	BEGIN 
		INSERT INTO #tmpSite (SiteID)
		SELECT
			val
		FROM [dbo].strSplit(@SiteId, ',')
		
		IF EXISTS(SELECT TOP 1 1 FROM #tmpSite WHERE SiteID = -1)
		BEGIN
			SELECT @IsCredit = 1
			DELETE FROM #tmpSite WHERE SiteID = -1
		END
	END 
	
	IF @SiteId = 'All' OR @IsCredit = 1
	BEGIN
		INSERT INTO #Currency (ExchangeId, Currency)
		SELECT DISTINCT ExchangeId, Currency 
		FROM dbo.exchange WITH(NOLOCK) 
		WHERE IsActive = 1
			AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND exchangeid <> 20))
			AND (@SiteId = 'All'
				OR (@IsCredit = 1 AND (
										OfferSite IN (0,1) 
										OR exchangeid IN (
											SELECT currency
											FROM bodb02.dbo.Dep_CustSuper WITH (NOLOCK)
											WHERE site IN ('Saba789','SEAL888','NovaCasino')
										)) 
				))
	END
	
	INSERT INTO #tmpLicensees (LicenseeID, LicenseeName)
	SELECT LicenseeID, LicenseeName
	FROM DBWH.bodb_Account.dbo.vw_Licensees WITH(NOLOCK)
	
	IF EXISTS(SELECT TOP 1 1 FROM #tmpSite WHERE SiteID > 0) -- Deposit
	BEGIN
		INSERT INTO #Currency (ExchangeId, Currency)
		SELECT DISTINCT ex.ExchangeId, ex.Currency
        FROM bodb_licensee.dbo.LicenseeCust lc WITH (NOLOCK)
              INNER JOIN #tmpLicensees l ON l.LicenseeID = lc.LicenseeID
              INNER JOIN dbo.exchange ex WITH (NOLOCK) ON lc.Currency = ex.exchangeid
              INNER JOIN dbo.site s WITH (NOLOCK) ON s.site = l.LicenseeName AND s.isActive = 1
              LEFT JOIN #Currency c ON ex.exchangeid = c.ExchangeId
        WHERE l.LicenseeID IN (SELECT SiteID FROM #tmpSite)
			   AND ex.IsActive = 1
               AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND ex.exchangeid <> 20))
               AND c.exchangeid IS NULL
	END
	
	SELECT ExchangeId, Currency
	FROM #Currency
	ORDER BY Currency
	
	DROP TABLE #tmpSite
	DROP TABLE #Currency
	DROP TABLE #tmpLicensees
	
END 

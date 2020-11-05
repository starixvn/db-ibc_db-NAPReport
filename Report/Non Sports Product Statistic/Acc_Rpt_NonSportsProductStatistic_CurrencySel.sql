/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistic_CurrencySel]
	@SiteId VARCHAR(MAX) = '-1',
	@ExcludeTest BIT = 0
AS
/*
	Created by: 20201020@Cherry
	Task: Get Currency dropdown by Site [Redmine: #140386]
	DB: DBACC.bodb02
	
	Revisions:
		20201020@Cherry: Get Currency dropdown by Site [Redmine: #140386]
		
	Param: 
		@SiteId = -1 : All, 0: Credit, >0: Deposit

*/

BEGIN
	SET NOCOUNT ON
	CREATE TABLE #tmpSite (SiteID INT)
	CREATE TABLE #Currency (ExchangeId INT, Currency NVARCHAR(50))
	DECLARE @IsCredit BIT = 0
	
	IF @SiteId <> '-1'
	BEGIN 
		INSERT INTO #tmpSite (SiteID)
		SELECT
			val
		FROM [dbo].strSplit(@SiteId, ',')
		
		IF EXISTS(SELECT TOP 1 1 FROM #tmpSite WHERE SiteID = 0)
		BEGIN
			SELECT @IsCredit = 1
			DELETE FROM #tmpSite WHERE SiteID = 0
		END
	END 
	
	IF @SiteId = '-1' OR @IsCredit = 1
	BEGIN
		INSERT INTO #Currency (ExchangeId, Currency)
		SELECT ExchangeId, Currency 
		FROM dbo.exchange WITH(NOLOCK) 
		WHERE IsActive = 1
			AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND exchangeid <> 20))
			AND (@SiteId = '-1'
				OR (@IsCredit = 1 AND OfferSite IN (0,1)) 
				)
	END
	
	IF EXISTS(SELECT TOP 1 1 FROM #tmpSite WHERE SiteID > 0) -- Deposit
	BEGIN
		INSERT INTO #Currency (ExchangeId, Currency)
		SELECT DISTINCT ex.ExchangeId, ex.Currency
        FROM bodb_licensee.dbo.LicenseeCust lc WITH (NOLOCK)
              INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = lc.LicenseeID
              INNER JOIN dbo.exchange ex WITH (NOLOCK) ON lc.Currency = ex.exchangeid
              INNER JOIN dbo.site s WITH (NOLOCK) ON s.site = l.LicenseeName AND s.isActive = 1
        WHERE s.siteid IN (SELECT SiteID FROM #tmpSite)
			   AND ex.IsActive = 1
               AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND exchangeid <> 20))
	END
	
	SELECT ExchangeId, Currency
	FROM #Currency
	ORDER BY Currency
	
	DROP TABLE #tmpSite
	DROP TABLE #Currency
	
END 
GO
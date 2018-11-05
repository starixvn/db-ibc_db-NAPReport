/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistic_SiteSel]
	@ProductID VARCHAR(MAX) = ''
AS
/*
	Created by: 20160908@Sophia.Nguyen
	Task: Get Company dropdown by ProductId [Redmine: #62430]
	DB: DBACC.bodb02
	
	Revisions:
		- 20170215@Percy: Integrate Fishing World [RedmineID: #71616]
		- 20181031@Percy: Remove linked-server DBLIC [RedmineID: #103660]
*/

BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #tmpProductID (
			ProductID int
		)
	
	IF @ProductID <> ''
	BEGIN 
		INSERT INTO #tmpProductID (ProductID)
		SELECT
			val
		FROM [dbo].strSplit(@ProductID, ',')
	END 
	ELSE 
	BEGIN 
		INSERT INTO #tmpProductID (ProductID)
		SELECT	ProductID
		FROM	dbo.Products WITH (NOLOCK)
		WHERE   CasinoType IN (1,2) 
				OR ProductID IN (3, 5, 8, 24)
	END 

	
	----Get Site

	SELECT 'MBC Group' as Site,  0 AS OrderId, 0 AS SortID  --- Credit only
	UNION
	SELECT DISTINCT l.Licenseename as Site, l.LicenseeId As OrderId,  1 AS SortID 				
	FROM
		dbo.Products b WITH (NOLOCK) 
		INNER JOIN bodb_Licensee.dbo.Product3rd p WITH (NOLOCK) ON p.ProductPrefix = b.ProductPrefix
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON lp.productid = p.productid
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (NOLOCK) ON l.licenseeid = lp.licenseeid
		INNER JOIN bodb_Licensee.dbo.SystemLicensee s WITH (NOLOCK) ON s.licenseeid = l.licenseeid
		INNER JOIN #tmpProductID m ON b.ProductID=m.ProductID
	WHERE s.systemId = 3 AND l.IsDeposit = 1
	GROUP BY l.LicenseeID, l.Licenseename
	ORDER BY SortID, [Site]

	DROP TABLE #tmpProductID
END 
GO
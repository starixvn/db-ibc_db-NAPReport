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
		- 20200601@Cherry: Add Credit Site (#135009)
		- 20210324@Cherry: Consider Saba789 as Credit site (#152124)
		- 20210428@Cherry: Add LicenseeGroup (#153736)
*/

BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #tmpProductID (
			ProductID int
		)
	CREATE TABLE #tmpDep_CustSuper (CustID INT)
	CREATE TABLE #tmpLicensees (LicenseeID INT, LicenseeName VARCHAR(50), IsDeposit BIT)
	
	INSERT INTO #tmpDep_CustSuper (CustID)
	SELECT custid
	FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH(NOLOCK)
	
	INSERT INTO #tmpLicensees (LicenseeID, LicenseeName, IsDeposit)
	SELECT LicenseeID, LicenseeName, IsDeposit
	FROM DBWH.bodb_Account.dbo.vw_Licensees WITH(NOLOCK)
	
	IF @ProductID <> ''
	BEGIN 
		INSERT INTO #tmpProductID (ProductID)
		SELECT
			val
		FROM [dbo].strSplit(@ProductID, ',')
	END 
	
	----Get Site

	--SELECT DISTINCT c.site, 0 AS OrderId, 0 AS SortId
	--FROM dbo.Customer c WITH(NOLOCK)
	--	LEFT JOIN #tmpDep_CustSuper d ON c.srecommend = d.custid
	--WHERE c.roleid = 2 AND d.custid IS NULL AND c.site IS NOT NULL
	--UNION
	--SELECT DISTINCT l.Licenseename as Site, l.LicenseeId As OrderId,  1 AS SortId 				
	--FROM
	--	dbo.Products b WITH (NOLOCK) 
	--	INNER JOIN bodb_Licensee.dbo.Product3rd p WITH (NOLOCK) ON p.ProductPrefix = b.ProductPrefix
	--	INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON lp.productid = p.productid
	--	INNER JOIN #tmpLicensees l ON l.licenseeid = lp.licenseeid
	--	INNER JOIN bodb_Licensee.dbo.SystemLicensee s WITH (NOLOCK) ON s.licenseeid = l.licenseeid
	--	INNER JOIN #tmpProductID m ON b.ProductID=m.ProductID
	--WHERE s.systemId = 3 AND l.IsDeposit = 1
	--GROUP BY l.LicenseeID, l.Licenseename
	--ORDER BY SortID, [Site]
	
	--1.Get group of licensees
	SELECT c.GroupId, c.GroupName, ISNULL(p.GroupId, 0) AS ParentId

	FROM DBCUST.bodb_Licensee.dbo.LA_CombinedGroup c WITH(NOLOCK)

	LEFT JOIN DBCUST.bodb_Licensee.dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')

	WHERE c.PathCode = '/'			-- top level

		OR p.GroupId IS NOT NULL	-- any child has valid parent id

	--2.Get licensee and direct groups
	SELECT p.OldRefId LicenseeID, l.LicenseeName, ISNULL(a.GroupId, 0) AS GroupId

	FROM DBCUST.bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK)

		INNER JOIN DBCUST.bodb_Licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID=pd.PartyID
		INNER JOIN DBCUST.bodb_Licensee.dbo.Licensees l (NOLOCK) ON l.LicenseeID = p.OldRefID

		LEFT JOIN DBCUST.bodb_Licensee.dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId

	WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1
	order by l.LicenseeName

	----3.Get terminated license
	--SELECT p.OldRefId LicenseeID, p.PartyID, p.PartyName, d.BrandName
	--FROM DBCUST.bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK)

	--INNER JOIN DBCUST.bodb_Licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID

	--WHERE   p.PartyID IN (

	--	SELECT FromParty FROM DBCUST.bodb_Licensee.dbo.OAS_ChargeInfo WITH(NOLOCK)

	--	WHERE FromParty > 0 AND ChargeType NOT IN (2, 3) -- Old type & No longer used

	--	GROUP BY FromParty HAVING MAX(ToDate) < CONVERT(DATE, GETDATE())

	--) AND p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1

	DROP TABLE #tmpProductID
	DROP TABLE #tmpDep_CustSuper
	DROP TABLE #tmpLicensees
END 
GO
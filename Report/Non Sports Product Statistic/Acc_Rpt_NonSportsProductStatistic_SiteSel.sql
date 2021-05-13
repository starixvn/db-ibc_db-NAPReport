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
	CREATE TABLE #tmpSite (LicenseeID INT, LicenseeName VARCHAR(50))
	CREATE TABLE #tmpGroup (GroupId INT, GroupName VARCHAR(50), ParentId INT)
	CREATE TABLE #tmpLicensee (LicenseeId INT, LicenseeName VARCHAR(50), GroupId INT)
	
	INSERT INTO #tmpDep_CustSuper (CustID)
	SELECT custid
	FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH(NOLOCK)
	
	INSERT INTO #tmpSite (LicenseeID, LicenseeName)
	SELECT LicenseeID, LicenseeName
	FROM DBWH.bodb_Account.dbo.vw_Licensees WITH(NOLOCK)
	WHERE IsDeposit = 1
	
	IF @ProductID <> ''
	BEGIN 
		INSERT INTO #tmpProductID (ProductID)
		SELECT
			val
		FROM [dbo].strSplit(@ProductID, ',')
	END 		
	
	-- Get group of licensees
	INSERT INTO #tmpGroup (GroupId, GroupName, ParentId)
	SELECT c.GroupId, c.GroupName, ISNULL(p.GroupId, 0) AS ParentId
	FROM bodb_Licensee.dbo.LA_CombinedGroup c WITH(NOLOCK)
		LEFT JOIN bodb_Licensee.dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
	WHERE c.PathCode = '/'			-- top level
		OR p.GroupId IS NOT NULL	-- any child has valid parent id
		
	INSERT INTO #tmpGroup (GroupId, GroupName, ParentId) VALUES
	(-1, 'Credit Group', 0),
	(-2, 'Terminated Licensees', 0),
	(-3, 'Others', 0)
	
	-- Get terminated licensee
	INSERT INTO #tmpLicensee (LicenseeId, LicenseeName, GroupId)
	SELECT s.LicenseeID, s.LicenseeName, -2 GroupId
	FROM bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
		INNER JOIN #tmpSite s ON p.OldRefId = s.LicenseeID
	WHERE   p.PartyID IN (
		SELECT FromParty FROM bodb_Licensee.dbo.OAS_ChargeInfo WITH(NOLOCK)
		WHERE FromParty > 0 AND ChargeType NOT IN (2, 3) -- Old type & No longer used
		GROUP BY FromParty HAVING MAX(ToDate) < CONVERT(DATE, GETDATE())
	) AND p.PartyType = 1 AND d.IsDeposit = 1 AND d.StatusId = 1
	
	-- Get licensee and direct groups
	INSERT INTO #tmpLicensee (LicenseeId, LicenseeName, GroupId)
	SELECT s.LicenseeID, s.LicenseeName, a.GroupId 
	FROM #tmpSite s 
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK) ON s.LicenseeID = p.OldRefID
		INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
		INNER JOIN bodb_Licensee.dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId
	WHERE p.PartyType = 1 AND pd.IsDeposit = 1 AND pd.StatusId = 1	
		AND s.LicenseeID NOT IN (SELECT LicenseeID FROM #tmpLicensee WHERE GroupId = -2)
		
	INSERT INTO #tmpLicensee (LicenseeId, LicenseeName, GroupId)
	SELECT LicenseeID, LicenseeName, -3 GroupId
	FROM #tmpSite
	WHERE LicenseeID NOT IN (SELECT LicenseeID FROM #tmpLicensee)
	
	-- Get Group
	SELECT GroupId, GroupName, ParentId
	FROM #tmpGroup 
	
	-- Get Site
	SELECT DISTINCT -1 LicenseeID, c.site LicenseeName, -1 AS GroupId
	FROM bodb02.dbo.Customer c WITH(NOLOCK)
		LEFT JOIN #tmpDep_CustSuper d ON c.srecommend = d.custid
	WHERE c.roleid = 2 AND d.custid IS NULL AND c.site IS NOT NULL
	UNION
	SELECT DISTINCT l.LicenseeId, l.LicenseeName, l.GroupId 			
	FROM
		dbo.Products b WITH (NOLOCK) 
		INNER JOIN bodb_Licensee.dbo.Product3rd p WITH (NOLOCK) ON p.ProductPrefix = b.ProductPrefix
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON lp.productid = p.productid
		INNER JOIN #tmpLicensee l ON l.licenseeid = lp.licenseeid
		INNER JOIN bodb_Licensee.dbo.SystemLicensee s WITH (NOLOCK) ON s.licenseeid = l.licenseeid
		INNER JOIN #tmpProductID m ON b.ProductID=m.ProductID
	WHERE s.systemId = 3 

	DROP TABLE #tmpProductID
	DROP TABLE #tmpDep_CustSuper
	DROP TABLE #tmpLicensee
	DROP TABLE #tmpSite
	
END 
GO
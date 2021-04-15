/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGame_LicenseesSel]
AS
	/*
		Created: Johnson
		Date: 25Oct2011
		Task: Get list licensees offered number game
		DB: DB052.bodb02
		
		Revisions:
		- 20120913@Henry: Using ProductPrefix instead of ProductName
		- 20121006@Daniel: Only get deposit licensees
		- 20130624@Jim: support to show licensee Active only
		- 20210329@Roy: NAP Report - Support Saba789 (#151326)
		
		
		Parameters Explanation:
	*/
BEGIN
	SET NOCOUNT ON 
	
	CREATE TABLE #tmpLicensees ( LicenseeID INT, LicenseeName VARCHAR(50) )
	INSERT INTO #tmpLicensees ( LicenseeID, LicenseeName )
	SELECT LicenseeID
		,LicenseeName
	FROM DBWH.bodb_Account.dbo.vw_Licensees WITH (NOLOCK)
	WHERE IsDeposit = 1
	GROUP BY LicenseeID
		,LicenseeName
	
	SELECT l.LicenseeID, l.Licenseename
	FROM bodb_Licensee.dbo.Product3rd p WITH (nolock)
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (nolock) ON lp.productid = p.productid
		INNER JOIN #tmpLicensees l WITH (nolock) ON l.licenseeid = lp.licenseeid
		INNER JOIN bodb_licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON sl.LicenseeID=l.LicenseeID AND sl.SystemID=3
	WHERE  p.ProductPrefix = 'NG'
		   AND sl.isActive=1
	
	DROP TABLE #tmpLicensees
END

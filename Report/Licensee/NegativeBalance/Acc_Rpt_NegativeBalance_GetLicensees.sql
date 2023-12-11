/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO
ALTER PROCEDURE dbo.Acc_Rpt_NegativeBalance_GetLicensees
AS
/*	Creator: 20231211@Jaden
	Task : Get list of licensees
	DB: DB052/bodb02

	Param's Explanation:
		
	Revisions:	
		20231211@Jaden: Creation
			Separated from DBEXT's Acc_LicenseeSelAll to exclude some special licensees like SEAL8888 (for #195730)
*/

BEGIN
	SET NOCOUNT ON

    SELECT   
    	l.LicenseeID, l.LicenseeName, ISNULL(ba.EnableBA,0) as EnableBA,l.brandname  
    FROM 
    	bodb_Licensee.dbo.Licensees l WITH (NOLOCK)  
    	INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
    	INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID 
    	LEFT JOIN bodb_Licensee.dbo.LicenseeBAConfig ba WITH (NOLOCK) ON l.LicenseeID = ba.LicenseeID
    WHERE 
    	LicenseeName <> 'IBC' AND
    	IsDeposit = 1
    	AND sl.IsActive = 1
    	AND s.SystemName='Accounting'
		--exclude some specials lic like SEAL8888 and SABA789
		AND (l.LicenseeName IN (SELECT [site] FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper))
    ORDER BY l.LicenseeName ASC
END
GO

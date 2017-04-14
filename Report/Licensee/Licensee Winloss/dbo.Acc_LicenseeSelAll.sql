ALTER  PROCEDURE [dbo].[Acc_LicenseeSelAll]
AS

/*
	Created by: [20110428@Henry]
	Task: Get List of all licensee 
	DB: DB052.bodb02
	Revisions:
	- 20110622@Henry: add column EnableBA
	- 20111117@Henry: only list licensees which have isDeposit = 1
	- 20120510@Henry: get licensees which have IsActive = 1
	- 20120704@Henry: Map Licensee with System
	- 20130219@Scott: add column brandname
	
*/

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
ORDER BY l.LicenseeName ASC

GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeSelAll] TO [bodbLicenseeNet]
GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeSelAll] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_LicenseeSelAll] TO [vnteam]


USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_LiveCasino_GameStatistics_LicenseeSel]
AS
/*
	Created: Daniel
	Date: 2012-02-27
	Task: Get list licensees offered Live Casino
	DB: DB052.bodb02
	
	Revisions:
	- 20120913@Henry: Using ProductPrefix instead of ProductName
	- 20121006@Daniel: Only get deposit licensees
	- 20130624@Jim: support to show licensee Active only
	
	Parameters Explanation:
*/
SET NOCOUNT ON 

	SELECT l.LicenseeID, l.Licenseename
	FROM bodb_Licensee.dbo.Product3rd p WITH (nolock)
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (nolock) ON lp.productid = p.productid
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (nolock) ON l.licenseeid = lp.licenseeid
		INNER JOIN bodb_licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON l.LicenseeID=sl.LicenseeID AND sl.SystemID=3 --- Accounting
	WHERE ProductPrefix = 'LC' 
		AND IsDeposit = 1
		AND sl.isActive=1
	ORDER BY l.LicenseeID	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics_LicenseeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics_LicenseeSel] TO [vnteam]
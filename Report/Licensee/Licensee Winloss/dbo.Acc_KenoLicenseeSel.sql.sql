USE [bodb_Licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Acc_KenoLicenseeSel]
AS
/*
Created: Kyan
Task : Get Licensee list for Keno
DB: DBLIC.bodb_licensee
	*Revision :
		20140602@Jim: +add (NOLOCK) and move sp into DBLIC
					  +fix bug #17074	
*/
SET NOCOUNT ON

SELECT DISTINCT 
	   l.LicenseeID
	  ,CASE  l.licenseeId WHEN 13 THEN 'FDL'
						  WHEN 18 THEN 'PIH'	
						  ELSE 
							  l.LicenseeName 
						  END LicenseeName	
FROM dbo.Licensees l WITH (NOLOCK)
	INNER JOIN dbo.LicenseeProduct3rd lp3rd WITH (NOLOCK) ON l.LicenseeID = lp3rd.LicenseeID
WHERE lp3rd.productId = 8

GO
GRANT EXECUTE ON [dbo].[Acc_KenoLicenseeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_KenoLicenseeSel] TO [vnteam]
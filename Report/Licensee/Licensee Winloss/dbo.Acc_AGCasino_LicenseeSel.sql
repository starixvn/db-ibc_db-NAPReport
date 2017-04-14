USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[Acc_AGCasino_LicenseeSel_xtest]    Script Date: 09/25/2014 09:49:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[Acc_AGCasino_LicenseeSel]
AS

/*
	Created by:  20140916@Jim
	Task: Get List of all licensees offerred AG Casino
	DB: DBLIC.bodb_licensee
	Revisions:
		+20140925: add Launchdate column in the result
*/

SET NOCOUNT ON
DECLARE @ProductId INT
SELECT  @ProductId = ProductId
FROM dbo.Product3rd WITH (NOLOCK)
WHERE ProductName = 'AG Casino'

SELECT   
	l.LicenseeID
	, l.LicenseeName
	,CASE WHEN ISNULL(l.Brandname,'')='' THEN  l.LicenseeName ELSE  l.Brandname END Brandname
	,lpd.EffectiveDate AS Launchdate
FROM 
	dbo.Licensees l WITH (NOLOCK)  
	INNER JOIN dbo.SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID 
	INNER JOIN dbo.LicenseeProduct3rd lpd WITH (NOLOCK) ON l.licenseeId = lpd.LicenseeId
WHERE 
	lpd.ProductID = @ProductId
	AND sl.IsActive = 1
	AND s.SystemName='Accounting'
ORDER BY l.LicenseeName ASC

GO
GRANT EXECUTE ON [dbo].[Acc_AGCasino_LicenseeSel] TO [bodbAdminNet]  
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_AGCasino_LicenseeSel] TO [vnteam]  
set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

ALTER  PROCEDURE [dbo].[Acc_LicenseeProduct3rdSel]
	@LicenseeID INT = 0,
	@ProductPrefix VARCHAR(10) = '',
	@Langkey VARCHAR(10)='en-US'
	
AS
/*
Created: Jim@20130624
Task: Get Product3rd of a Licensee
DB: DB052.bodb_licensee
Original:  
		Lrf_LicenseeProduct3rdSel
Revisions:

*/
SET NOCOUNT ON

SET @ProductPrefix = LTRIM(RTRIM(@ProductPrefix))

SELECT 
	lp.LicenseeID,
	l.LicenseeName,
	p.ProductName,
	p.ProductPrefix,
	lp.Comm,
	lp.Winloss 

from
	LicenseeProduct3rd lp (nolock)
	inner join Licensees l (nolock) on lp.LicenseeID = l.LicenseeID
	inner join Product3rd p (nolock) on lp.Productid = p.ProductID
	inner join dbo.SystemLicensee sl (nolock) on l.licenseeid=sl.licenseeid and sl.systemid=3
WHERE 
	(@LicenseeID=0 OR (@LicenseeID<>0 AND l.LicenseeID = @LicenseeID))
	AND
	(@ProductPrefix='' OR (@ProductPrefix<>'' AND p.ProductPrefix = @ProductPrefix))
	AND sl.isActive=1


GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeProduct3rdSel] TO [bodbLicenseeNet]
GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeProduct3rdSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_LicenseeProduct3rdSel] TO [vnteam]

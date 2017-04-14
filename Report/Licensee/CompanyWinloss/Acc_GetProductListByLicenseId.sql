USE bodb02
GO
ALTER PROCEDURE dbo.Acc_GetProductListByLicenseId @LicenseeId INT
	
AS
/*	Creator: 20150612@Patrick
	Task : Get list of currency by licenseeId
	DB: DB052/bodb02

	Param's Explanation:
		
	Revisions:	
*/

BEGIN
	SET NOCOUNT ON
	SELECT ProductPrefix, ProductName
	FROM (
		SELECT 'SB' AS ProductPrefix, 'Sportsbook' AS ProductName
		UNION
		SELECT p.ProductPrefix, p.ProductName
		FROM bodb_licensee.dbo.Product3rd p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd lp WITH(NOLOCK) ON p.Productid = lp.ProductID
		WHERE lp.LicenseeID = @LicenseeId
	)tmp
	ORDER BY ProductName
END
GO
GRANT EXECUTE ON [dbo].[Acc_GetProductListByLicenseId] TO [bodbLicenseeNet] AS [dbo]
GO

GRANT EXECUTE ON [dbo].[Acc_GetProductListByLicenseId] TO [bodbAdminNet] AS [dbo]
GO

GRANT EXECUTE ON [dbo].[Acc_GetProductListByLicenseId] TO [vnteam] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_GetProductListByLicenseId] TO [vnteam] AS [dbo]
GO

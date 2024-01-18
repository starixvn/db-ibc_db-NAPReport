/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO
ALTER PROCEDURE dbo.Acc_GetProductListByLicenseId @LicenseeId INT
	
AS
/*	Creator: 20150612@Patrick
	Task : Get list of currency by licenseeId
	DB: DB052/bodb02

	Param's Explanation:
		
	Revisions:	
		20240125@Jaden: Merge virtual sports (#199931)
			Product prefixes VS1, VS2, VS3, VS4 are removed in table bodb_licensee.dbo.LicenseeProduct3rd, and
			only VS is kept (productid = 5), added a step to insert back VS1 -> VS4 for report use
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #original_products (ProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(50))

	INSERT INTO #original_products (ProductID, ProductPrefix, ProductName)
	SELECT ProductID, ProductPrefix, ProductName
	FROM (
		SELECT 1 AS ProductID, 'SB' AS ProductPrefix, 'Sportsbook' AS ProductName
		UNION
		SELECT p.ProductID, p.ProductPrefix, p.ProductName
		FROM bodb_licensee.dbo.Product3rd p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd lp WITH(NOLOCK) ON p.Productid = lp.ProductID
		WHERE lp.LicenseeID = @LicenseeId
	) tmp

	IF EXISTS (SELECT 1 FROM #original_products WHERE ProductID = 5) 
	BEGIN
		DECLARE @VSProducts VARCHAR(100)
		SELECT @VSProducts = VValue FROM DBWH.bodb_Account.dbo.SystemSettings WITH (NOLOCK) where vid = 31

		INSERT INTO #original_products (ProductPrefix, ProductName)
		SELECT ProductPrefix, ProductName
		FROM bodb_licensee.dbo.Product3rd WITH(NOLOCK)
		WHERE ProductID IN (SELECT val 
								FROM bodb02.dbo.strSplit(@VSProducts, ',') 
								WHERE NOT EXISTS (SELECT 1 FROM #original_products o WHERE o.ProductID = val))
		  
	END

	SELECT ProductPrefix, ProductName FROM #original_products ORDER BY ProductName

	DROP TABLE #original_products
END
GO

ALTER PROCEDURE  [dbo].[Acc_SelCurrencyByLicensee]		
	@LicenseeID int = 0,
	@excludeTest BIT=0
AS	
/*
Created: 20110423@Henry
Task : Get all the currency by a licensee
DB: DB052.bodb02

 
Revisions:
    - 20111028@Henry: Order by currency name
    - 20111111@Henry: allow to choose all currency
	- 20141205@Winnie: change from LicenseeCust to f_SelLicenseeCust ( task change currency KeenOcean)
Param's Explanation:
*/

SET NOCOUNT ON
BEGIN
	declare @temp as table (currency int)

	insert into @temp
		SELECT 
			distinct Currency 
		FROM bodb_Licensee.dbo.f_SelLicenseeCust(@LicenseeID)--LicenseeCust lc (nolock)
		WHERE 
			--(@LicenseeID = 0 OR LicenseeID = @LicenseeID) AND
			 (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	
	
	SELECT 
		t.currency, 
		CASE 
			WHEN t.currency = 20 THEN 'UUS' 
			WHEN t.currency = 51 THEN 'INH'
			ELSE e.Code 
		END AS CurrencyName
	FROM 
		@temp t
	INNER JOIN exchange e with (nolock) ON t.currency = e.exchangeid
	ORDER BY 
		CASE 
			WHEN t.currency = 20 THEN 'UUS' 
			WHEN t.currency = 51 THEN 'INH'
			ELSE e.Code 
		END

END

GO
GRANT EXECUTE ON [dbo].[Acc_SelCurrencyByLicensee] TO [bodbLicenseeNet]
GO
GRANT EXECUTE ON [dbo].[Acc_SelCurrencyByLicensee] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_SelCurrencyByLicensee] TO [vnteam] 
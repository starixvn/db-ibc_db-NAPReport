ALTER FUNCTION [dbo].[f_DepSuperAllowedHR]
(	@site VARCHAR(10))
RETURNS @custList TABLE(	custid INT PRIMARY KEY)
AS
/*	Created: Jamie
	Date: 2009-10-08 
	Task: Get the super list allowed to bet on 12BET/Mansion88/Asiabet88  
	DB: DB02.BODB02, DB06.BODB02 
	Revisions:
		- 20100528@Phuc: Remove GBP currency.

	Param's Explanation: 
		+ @site: 12BET, Mansion88, Asiabet88, ALL  
		+ superIDs: 
			---=== 12BET Super ===---------
				12BETSuperRM	836218
				12BETSuperRMB	836226
				12BETSuperUS$	791080
				12BETSuperEURO	791081
				12BETSuperTB    836203	
				12BETSuperIN	1813575
			-------------------------------
			-- === Mansion88 Super  ===---
				MS88SuperEURO	1573960
				MS88SuperHK$	1574024
				MS88SuperRM		1574028
				MS88SuperRMB	1574008
				MS88SuperSD$	1574036
				MS88SuperTB		1573967
				MS88SuperUS$	1573954
				MS88SuperIN     1574102
			----======================----
			-- === Fun88 Super  ===-------
				AB88SuperEURO	932167
				AB88SuperRMB	932253
				AB88SuperTB		932181
				AB88SuperUS$	932063
			---====================-------

*/
BEGIN
	IF @site ='12BET' OR @site='ALL'
	BEGIN
		INSERT INTO @custList(custid)
		SELECT	836218
		UNION ALL SELECT 836226
		UNION ALL SELECT 791080
		UNION ALL SELECT 791081
		UNION ALL SELECT 836203
		UNION ALL SELECT 1813575
	END
	IF @site ='Mansion88' OR @site='ALL'
	BEGIN
		INSERT INTO @custList(custid)
		SELECT	1573960	
		UNION ALL SELECT 1574024
		UNION ALL SELECT 1574028
		UNION ALL SELECT 1574008
		UNION ALL SELECT 1574036
		UNION ALL SELECT 1573967
		UNION ALL SELECT 1573954
		UNION ALL SELECT 1574102
	END
	IF @site='Asiabet88' OR @site='ALL'
	BEGIN
		INSERT INTO @custList(custid)
		SELECT	932167	
		UNION ALL SELECT 932253
		UNION ALL SELECT 932181
		UNION ALL SELECT 932063
	END 
	RETURN
END 
GO
GRANT VIEW DEFINITION ON [dbo].[f_DepSuperAllowedHR] TO [vnteam] 
ALTER PROCEDURE [dbo].[Task_Exchange_HistoryIns]
	@winlostdate	DATETIME
AS
/*	Created: Jamie
	Date: 2009-11-10
	Task: Job for storing currency daily 
	DB: DB052.BODB02 
	
	Revisions:
		- 20100417@Jamie: Add ALog   
		- 20100511@Jamie: Insert all currencies 
		- 20101105@Henry: Add DELA and Spondemo site
		- 20101118@Henry: Add TLC site
		- 20110121@Johnson: Add Zzun88, Suncity, 
		- 20110224@Henry: Add Bezbet
*/
BEGIN
	SET NOCOUNT ON
	IF EXISTS (SELECT winlostdate FROM Exchange_History WITH (NOLOCK) WHERE winlostdate = @winlostdate)
	BEGIN
		DELETE FROM Exchange_History WHERE winlostdate = @winlostdate 
	END

	DECLARE	@USDRate FLOAT 
	DECLARE @tmpCurrency TABLE(	currency INT, actualrate FLOAT, USDRate FLOAT)
	SELECT	@USDRate = actualrate FROM Exchange WITH (NOLOCK) WHERE exchangeid = 3;

	INSERT INTO Exchange_History( 
		winlostdate, 
		currency, 
		actualrate, 
		USDRate,
		srecommendM88, 
		srecommend12BET, 
		srecommendAB88,
		srecommendALOG,
		srecommendDELA,
		srecommendSPON,
		srecommendTLC,
		srecommendZ88,
		srecommendMF,
		srecommendSC,
		srecommendBEZBET
	)
	SELECT	@winlostdate, 
			e.exchangeID, 
			e.actualrate, 
			(e.actualrate/@USDRate) USDRate,
			ISNULL(m.custid,0) AS sM88 , 
			ISNULL(o.custid,0) AS s12BET, 
			ISNULL(a.custid,0) AS sAB88,
			ISNULL(g.custid,0) AS sALOG,
			ISNULL(dela.custid,0) as sDELA,
			ISNULL(spon.custid,0) as sSPON,
			ISNULL(tlc.custid,0) as sTLC,
			ISNULL(z88.custid,0) as sZ88,
			ISNULL(mf.custid,0) as sMF,
			ISNULL(sc.custid,0) as sSC,
			ISNULL(bb.custid,0) as sBB						
			
	FROM	Exchange e WITH (NOLOCK) 
			LEFT JOIN dbo.f_DepSuperByCurrency('Mansion88') m ON e.exchangeID = m.currency 
			LEFT JOIN dbo.f_DepSuperByCurrency('12BET') o ON e.exchangeID = o.currency 
			LEFT JOIN dbo.f_DepSuperByCurrency('Asiabet88') a ON e.exchangeID = a.currency 
			LEFT JOIN dbo.f_DepSuperByCurrency('ALog') g ON e.exchangeID = g.currency 
			LEFT JOIN dbo.f_DepSuperByCurrency('DELA') dela ON e.exchangeID = dela.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('SPONDEMO') spon ON e.exchangeID = spon.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('TLC') tlc ON e.exchangeID = tlc.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('Zzun88') z88 ON e.exchangeID = z88.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('MayFair') mf ON e.exchangeID = mf.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('SunCity') sc ON e.exchangeID = sc.currency
			LEFT JOIN dbo.f_DepSuperByCurrency('Bezbet') bb ON e.exchangeID = bb.currency
			
END
GO
GRANT EXECUTE ON [dbo].[Task_Exchange_HistoryIns] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_Exchange_HistoryIns] TO [vnteam]
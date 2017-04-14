ALTER FUNCTION [dbo].[f_DepSuperbyCurrency]
(
	@site varchar(10)
)
/*	Created by: Jamie
	Date: 2009-11-17
	Task: Get superid and currency for Deposit Site's WinLoss 
	DB: DB052.BODB02 

	Revisions: 
		- 20100420@Jamie: Add ALog Supers
		- 20100421@Jamie: Add two currencies: JPY and WON 
		- 20100608@Henry: Add SuperID for currency IN for asiabet88 (2564717 - AB88SuperIN)
		- 20100702@Henry: Add SuperID for new currency (RM, SD$, THB) for ALog
		- 20101004@Kiwi: Add SuperID for new currency EURO for ALog.
		- 20101019@Henry: Add SuperID for new currency VND for 12BET
		- 20101105@Henry: Add Dela & Spondemo site
		- 20101117@Henry: Add SuperID for new currency VND for Mansion88, new currency JPY + WON for ALOG
		- 20101118@Henry: Add SuperID for new site TLC
		- 20101125@Johnson: Add SuperID for DELA site include currency US$,GBP,EURO
		- 20101216@Johnson: Add superid for ALog site for new currency VND
		- 20110120@Johnson: Add SuperID for Zzun88, SunCity, MayFair
		- 20110127@Jamie: Change SuperID for Suncity - RM
		- 20110213@Henry: Add more Super for Dela (DKK, SEK, NOK, RUB, PLN, CZK, RON, CHF, SD$, RM, THB, HK$, AUD, RMB, IN, JPY, WON, BND, MXN, VND)
		- 20110224@Henry: Add SuperID for Bezbet
		- 20110315@Henry: Add new currencies for Mayfair and Zzun88 
			+ Mayfair: RMB, US$, and JPY 
			+ Zzun88: RMB and US$ 
		- 20110318@Henry: Add new currency Indonesia Rupiah (IN) for Alog
		- 20110419@Henry: Add new currency Russian Ruble (RUB) for Asian Logic
		- 20111017@Kiwi: Add SuperID for new currency INH for Fun88
*/ 

RETURNS @returntable TABLE 
(
	CustID		INT,
	Currency	INT
)
AS
BEGIN
	if @site in ('ALL', '12Bet')
	BEGIN
		INSERT INTO @returntable( custid, currency)
		SELECT	custid, currency
		FROM	custinfo ci WITH (NOLOCK)
		WHERE	custid IN(
					1015419,--	12BETSuperAUD
					1015427,--	12BETSuperCHF
					791081,--	12BETSuperEURO
					836212,--	12BETSuperGBP
					1813575,--	12BETSuperIN
					836218,--	12BETSuperRM
					836226,--	12BETSuperRMB
					1752415,--	12BETSuperSD$
					836203,--	12BETSuperTB
					791080,--	12BETSuperUS$
					916498, --	12BETSuperUUS
					3167631 --	 12BETSuperVND
					
				)

	END
	
	if @site in ('ALL', 'asiabet88')
	BEGIN
		INSERT INTO @returntable( custid, currency)
		SELECT	custid, currency
		FROM	custinfo ci WITH (NOLOCK)
		WHERE	custid IN(
					932167,--	AB88SuperEURO
					932188,--	AB88SuperGBP
					932209,--	AB88SuperRM
					932253,--	AB88SuperRMB
					1004374,--	AB88SuperSD$
					932181,--	AB88SuperTB
					932063,--	AB88SuperUS$
					925144, --	AB88SuperUUS
					2564717,--	AB88SuperIN
					4833492 --AB88SuperINH
				)
	END
	
	if @site in ('ALL', 'mansion88')
	BEGIN
		INSERT INTO @returntable( custid, currency)
		SELECT	custid, currency
		FROM	custinfo ci WITH (NOLOCK)
		WHERE	custid IN(
					1574016,--	MS88SuperAUD
					1574083,--	MS88SuperBND
					1573960,--	MS88SuperEURO
					1573975,--	MS88SuperGBP
					1574024,--	MS88SuperHK$
					1574102,--	MS88SuperIN
					1574028,--	MS88SuperRM
					1574008,--	MS88SuperRMB
					1574036,--	MS88SuperSD$
					1573967,--	MS88SuperTB
					1573954,--	MS88SuperUS$
					1574095,--	MS88SuperUUS
					2397872,--  MS88SuperJPY
					2397885, --  MS88SuperWON
					3287311 --  MS88SuperVND
				)
	END
	if @site in ('ALL', 'ALog')
	BEGIN
		INSERT INTO @returntable( custid, currency)
		SELECT	custid, currency
		FROM	custinfo ci WITH (NOLOCK)
		WHERE	custid IN(
					2308771, -- ALogSuperGBP
					2308841, -- ALogSuperRMB
					2308796, -- ALogSuperUS$
					2308733, -- ALogSuperUUS
					2747862, -- ALogSuperSD$
					2747736, -- ALogSuperRM
					2747989, -- ALogSuperTB
					3114255, -- AlogSuperEURO	
					3289719, -- AlogSuperJPY
					3289746, -- AlogSuperWON
					3417070, -- ALogSuperVND
					3782799, -- AlogSuperIN 
					3928584  -- AlogSuperRub
				)
	END	
	
	if @site in ('ALL', 'DELA')
	BEGIN
		INSERT INTO @returntable(custid, currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN(
					3229876, --DELASuperUUS
					3319756, --DELASuperUS$
					3319994, --DELASuperGBP
					3320067, --DELASuperEURO
					
					3325726 ,--DELASuperDKK
					3325961 ,--DELASuperSEK
					3326157 ,--DELASuperNOK
					3326312 ,--DELASuperRUB
					3329242 ,--DELASuperPLN
					3329951 ,--DELASuperCZK
					3330152 ,--DELASuperRON
					3330267 ,--DELASuperCHF
					3330403 ,--DELASuperSD$
					3330565 ,--DELASuperRM
					3345920 ,--DELASuperTHB
					3346318 ,--DELASuperHK$
					3347360 ,--DELASuperAUD
					3347644 ,--DELASuperRMB
					3347891 ,--DELASuperIN
					3352069 ,--DELASuperJPY
					3352872 ,--DELASuperWON
					3353211 ,--DELASuperBND
					3353486 ,--DELASuperMXN
					3353831 --DELASuperVND
				)
	END
	
	if @site in ('ALL', 'Spondemo')
	BEGIN
		INSERT INTO @returntable(custid, currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN(
					3233912 --SPONSuperUUS
				)
	END
	
	if @site in ('ALL', 'TLC')
	BEGIN
		INSERT INTO @returntable(custid, currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN(
					3293743, --TLCSuperRMB
					3293760  --TLCSuperUUS
				)
	END
	
	if @site in ('ALL', 'Zzun88')
	BEGIN
		INSERT INTO @returntable(custid,currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN ( 
			3544878, --Z88SuperUUS
			3753528, --Z88SuperRMB 
			3762073 -- Z88SuperUS$
			)
	END
	
	if @site in ('ALL', 'SunCity')
	BEGIN
		INSERT INTO @returntable(custid,currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN (
		3544528, --SCSuperUUS
		3578505, -- SCSuperRM
		3544695, -- SCSuperTB
		3544783 -- SCSuperIN
		)
	END
	
	if @site in ('ALL', 'MayFair')
	BEGIN
		INSERT INTO @returntable(custid,currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN (
		3543918, --MFSuperUUS 
		3544240, -- MFSuperRM
		3544312, -- MFSuperTB
		3544377, -- MFSuperIN
		3752050, -- MFSuperRMB 
		3752544, -- MFSuperUS$ 
		3763288 -- MFSuperJPY 
		
		)
	END
	if @site in ('ALL','Bezbet')
	BEGIN
		INSERT INTO @returntable(custid,currency)
		SELECT custid, currency
		FROM custinfo ci WITH (NOLOCK)
		WHERE custid IN (
		3651355, --BEZBETSuperUUS
		3651422, -- BEZBETSuperEURO 
		3652596, -- BEZBETSuperGBP
		3652650, -- BEZBETSuperRMB  
		3652705, -- BEZBETSuperTB    
		3663671, -- BEZBETSuperUS$   
		3663860, -- BEZBETSuperVND
		3664373, -- BEZBETSuperAUD
		3664636, -- BEZBETSuperHK$ 
		3664957, -- BEZBETSuperRM  
		3670743, -- BEZBETSuperSD$  
		3670780, -- BEZBETSuperIN   
		3670803, -- BEZBETSuperBND    
		3670855, -- BEZBETSuperJPY    
		3670900 -- BEZBETSuperWON    
		)
	END
	
	return
END

GO
GRANT SELECT ON [dbo].[f_DepSuperbyCurrency] TO [vnteam]

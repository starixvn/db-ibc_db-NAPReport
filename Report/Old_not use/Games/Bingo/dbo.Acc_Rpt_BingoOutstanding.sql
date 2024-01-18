ALTER PROCEDURE [dbo].[Acc_Rpt_BingoOutstanding]
	@Username NVARCHAR(50)= '',
	@ExcludeTest BIT = 0,
	@Site VARCHAR(100)='',
	@Currency INT = -1,
	@ErrCode INT = 0,
	@ErrMsg NVARCHAR(4000)= '' OUTPUT 
AS
/*  Created:  Kathy
	Date:  20130826
    Task : Bingo outstanding report
    DB: DBACC/BODB02
   
    Revisions:  
		
	Param's Explanation:  
		+ @Site: -1: IBC group
		+ @Currency: -1: BaseRM, 0: ALL...
		+ @ExcludeTest: 0: exclude test account: currency 20
		+ @Username: empty to search ALL
*/ 
BEGIN
	SET NOCOUNT ON ;
	DECLARE  @tblSite TABLE(
		siteId			INT, 
		site_name		VARCHAR(100)
		)

	DECLARE @listLicensee TABLE(
		licenseeID		INT, 
		licenseename	VARCHAR(30)
		)

	DECLARE @tblTemp TABLE(
		transid			BIGINT, 
		custid			INT ,
		currency		TINYINT ,
		CurrencyName	NVARCHAR(50), 
		Username		NVARCHAR(50), 
		transdate		DATETIME, 
		outstanding		MONEY,
		outstandingRM	MONEY, 
		company			NVARCHAR(50)
		)

	DECLARE @grandTotalRM MONEY
	SET @grandTotalRM = 0

	IF @Site = '' OR @Site is NULL
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'There is no selected site'
		RETURN
	END
	-- check valid username
	IF @Username <> ''
	BEGIN		
		IF (NOT EXISTS (SELECT 1
		FROM	CustInfo WITH (NOLOCK)
		WHERE	Username LIKE @Username + '%' AND RoleID = 1))  
		BEGIN 
			SELECT @ErrCode = 1, @ErrMsg = 'Invalid username.'
			RETURN
		END 
	END

	INSERT INTO @listLicensee (licenseeID, licenseename	)
	SELECT licenseeID, licenseename FROM OPENQUERY(DBEXT, 'bodb_licensee.dbo.Acc_Licensee_Product3rdSel ''BG''')

	IF @Site = '0'
	BEGIN
		INSERT INTO @tblSite
		SELECT l.licenseeID, l.licenseename
		FROM @listLicensee l

		INSERT INTO @tblSite
		SELECT -1, 'IBC'
	END
	ELSE
	BEGIN
		-- get licensee in @Site
		INSERT INTO @tblSite
		SELECT l.licenseeID, l.licenseename
		FROM bodb02.dbo.strSplit(@Site, ',') s
		INNER JOIN @listLicensee l
			ON l.licenseeID = CONVERT(INT,s.val)

		-- get IBC in @Site list
		INSERT INTO @tblSite
		SELECT s.val, 'IBC'
		FROM bodb02.dbo.strSplit(@Site, ',') s
		WHERE s.val = -1
	END

	IF EXISTS (SELECT 1 FROM @tblSite WHERE siteId = -1)
	BEGIN 
		INSERT INTO @tblTemp 
			SELECT b.transid, b.custid, b.currency, b.CurrencyName,
			 b.Username, b.transdate, b.stake,b.stake*b.actualrate, 'IBC'
			FROM bettrans b WITH(NOLOCK)
			INNER JOIN Customer c WITH(NOLOCK) on b.custid = c.custid
 			WHERE c.roleid = 1
			AND b.srecommend NOT IN (SELECT d.CustID FROM Dep_CustSuper d) -- NOT IN licensees
			--AND b.status = 'running'
			AND b.ruben = 0 
			AND b.bettype IN (23202, 23201)
			AND b.currency = CASE WHEN @Currency = -1 OR @Currency = 0 THEN b.currency ELSE @Currency END 
	END
	INSERT INTO @tblTemp 
		SELECT b.transid, b.custid, b.currency, b.CurrencyName,
		 b.Username, b.transdate, b.stake,b.stake*b.actualrate, s.site_name
		FROM bettrans b WITH(NOLOCK)
		INNER JOIN Customer c WITH(NOLOCK) on c.custid = b.custid
		INNER JOIN Customer c2 WITH(NOLOCK) ON c2.custid = c.recommend
		INNER JOIN @tblSite s ON s.site_name = c2.site
		WHERE  c.roleid = 1
		AND b.ruben = 0
		--b.status = 'running'
		AND b.bettype IN (23202, 23201)
		AND b.currency = CASE WHEN @Currency = -1 OR @Currency = 0 THEN b.currency ELSE @Currency END 


		-- exclude account test
	IF @ExcludeTest = 1
	BEGIN
		DELETE FROM @tblTemp WHERE currency = 20 
	END

	IF @Username = ''
	BEGIN 
		IF @Currency = -1
		BEGIN
			;WITH rs(company,currency,Username,date,outstanding)
			AS
			(
				SELECT t.company, t.CurrencyName, t.Username, convert(varchar(10),t.transdate,20), t.outstandingRM  
				FROM @tblTemp t
			)
			SELECT company,currency,Username,date, SUM(ISNULL(outstanding,0)) 'outstanding'
			FROM rs
			GROUP BY company,currency,Username,date
			ORDER BY date


			SELECT t.CurrencyName 'currency', SUM(ISNULL(t.outstandingRM,0)) 'outstanding'
			FROM @tblTemp t
			GROUP BY t.CurrencyName
		END
		ELSE
		BEGIN
			;WITH rs(company,currency,Username,date,outstanding)
			AS
			(
				SELECT t.company, t.CurrencyName, t.Username, convert(varchar(10),t.transdate,20) , t.outstanding 
				FROM @tblTemp t
			)
			SELECT company,currency,Username,date,SUM(ISNULL(outstanding,0))'outstanding'
			FROM rs
			GROUP BY company,currency,Username,date
			ORDER BY date

			SELECT t.CurrencyName 'currency', SUM(ISNULL(t.outstanding,0)) 'outstanding'
			FROM @tblTemp t
			GROUP BY t.CurrencyName
		END

		SELECT @grandTotalRM = SUM(ISNULL(outstandingRM,0))
		FROM @tblTemp

	END
	ELSE
	BEGIN 		
		IF @Currency = -1
		BEGIN
			;WITH rs(company,currency,Username,date,outstanding)
			AS
			(
				SELECT t.company, t.CurrencyName, t.Username, convert(varchar(10),t.transdate,20) , t.outstandingRM  FROM @tblTemp t
				WHERE t.Username LIKE @Username + '%'
			)
			SELECT company,currency,Username,date,SUM(ISNULL(outstanding,0))'outstanding'
			FROM rs
			GROUP BY company,currency,Username,date
			ORDER BY date

			SELECT t.CurrencyName 'currency', SUM(ISNULL(t.outstandingRM,0)) 'outstanding'
			FROM @tblTemp t
			WHERE t.Username LIKE @Username + '%'
			GROUP BY t.CurrencyName
		END
		ELSE
		BEGIN
			;WITH rs(company,currency,Username,date,outstanding)
			AS
			(
				SELECT t.company, t.CurrencyName , t.Username, convert(varchar(10),t.transdate,20) , t.outstanding FROM @tblTemp t
				WHERE t.Username LIKE @Username + '%'
			)
			SELECT company,currency,Username,date,SUM(ISNULL(outstanding,0))'outstanding'
			FROM rs
			GROUP BY company,currency,Username,date
			ORDER BY date

			SELECT t.CurrencyName 'currency', SUM(ISNULL(t.outstanding,0)) 'outstanding'
			FROM @tblTemp t
			WHERE t.Username LIKE @Username + '%'
			GROUP BY t.CurrencyName
		END	
	
		SELECT @grandTotalRM = SUM(ISNULL(outstandingRM,0))
		FROM @tblTemp
		WHERE Username LIKE @Username + '%'
	END

	SELECT ISNULL(@grandTotalRM,0) 'Grand Total RM'
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_BingoOutstanding] TO [bodbAdminNet]
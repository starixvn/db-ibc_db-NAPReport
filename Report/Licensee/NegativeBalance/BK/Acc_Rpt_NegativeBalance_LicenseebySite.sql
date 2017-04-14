ALTER PROCEDURE [dbo].[Acc_Rpt_NegativeBalance_LicenseebySite]
(
	@site NVARCHAR(50)
)
AS
/*
	Created: 20130610@Lukas
	Task: get negative balance licensee customers to notify
	DB: DBTXN/bodb02
	
	Revision:
		- 20130618@Jamie: Always get the negative balance including the values retrieved before 
*/
BEGIN
	
	CREATE TABLE #tmp (custid INT PRIMARY KEY, balance MONEY)
	
	SELECT c.custid INTO #recommend
	FROM custinfo c WITH(NOLOCK)
		INNER JOIN DBLIC.bodb_licensee.dbo.LicenseeCust lc WITH(NOLOCK) ON c.custid = lc.custid
	WHERE srecommend IN (SELECT custid FROM f_depsuper_1(@site))
		AND c.roleid = 2
		
	INSERT INTO #tmp
	SELECT c.custid, c.balance - d.balance
	FROM balanceCredit c WITH(NOLOCK)
		INNER JOIN balanceDebit d WITH(NOLOCK) ON c.custid = d.custid
	WHERE c.custid IN (	SELECT custid 
						FROM custinfo WITH(NOLOCK) 
						WHERE recommend IN (SELECT custid FROM #recommend)
						)
		AND c.balance - d.balance < 0  -- negative balance
	
	
	SELECT	c.username,e.currency, tt.*
	INTO	#result 
	FROM	custinfo c WITH(NOLOCK)
			INNER JOIN (	SELECT	
								COALESCE(br.site,@site) AS site
								,COALESCE(br.custid,t.custid) AS custid
								,COALESCE(t.balance,br.balance) AS balance
								,CASE WHEN br.custid IS NULL OR t.balance  <> br.balance THEN 1 ELSE 0 END isHighlight	-- if balance changed or new negative balance then highlight it							
						FROM	BalanceNegativeRecord br WITH(NOLOCK)
								RIGHT JOIN #tmp t ON br.custid = t.custid AND br.site = @site
						WHERE	br.site = @site OR br.site IS NULL
					) tt ON c.custid = tt.custid
			INNER JOIN exchange e WITH(NOLOCK) ON e.exchangeid = c.currency 
	WHERE	c.currency <> 20
	
	-- update balance record
	UPDATE	br WITH(ROWLOCK,UPDLOCK)
	SET		br.balance	= t.balance
	FROM	BalanceNegativeRecord br 
			INNER JOIN #tmp t ON br.custid = t.custid AND br.site = @site
	WHERE	br.balance <> t.balance
	
	-- insert
	IF EXISTS (SELECT TOP 1 1 FROM #tmp WITH(NOLOCK) 
				WHERE custid NOT IN (SELECT custid FROM BalanceNegativeRecord WITH(NOLOCK) WHERE site = @site))
	BEGIN
		INSERT INTO BalanceNegativeRecord(custid, balance,site)
		SELECT custid, balance, @site
		FROM #tmp
		WHERE custid NOT IN (SELECT custid FROM BalanceNegativeRecord WITH(NOLOCK) WHERE site = @site)
	END

	-- delete
	IF EXISTS (SELECT TOP 1 1 FROM BalanceNegativeRecord WITH(NOLOCK) WHERE site = @site
																AND custid NOT IN (SELECT custid FROM #tmp))
	BEGIN
		DELETE FROM BalanceNegativeRecord WITH(ROWLOCK,UPDLOCK)
		WHERE site = @site
			AND custid NOT IN (SELECT custid FROM #tmp)
		
		
	END
	
	SELECT	*
	FROM	#Result WITH (NOLOCK) 
	ORDER BY Username, currency 
	
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NegativeBalance_LicenseebySite] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NegativeBalance_LicenseebySite] TO [vnteam] AS [dbo]
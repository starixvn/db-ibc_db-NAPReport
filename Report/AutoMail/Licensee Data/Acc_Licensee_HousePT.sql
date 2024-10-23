/*<info serverAlias="DBCUST-CustDB" executers="" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[Acc_Licensee_HousePT]
	@Sites				VARCHAR(MAX)
	,@SiteCurrencies	VARCHAR(MAX)
AS

/*
	Created: 20210129@Percy
	DB: DBCUST-CustDB
	Task: Auto mail - Licensee Sportsbook Data - House PT
	
	Revisions:
		- 20210129@Percy: Initiliaze SP [RedmineID: #148805]
		- 20220928@Danny: Change data source to get House PT [RedmineID: #176077]
		- 20241003@Danny: Move Acc_Licensee_HousePT to DBCUST (#208100)
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @SitesXML XML, @SiteCurrenciesXML XML
	SELECT  @SitesXML = CONVERT(XML, @Sites), @SiteCurrenciesXML = CONVERT(XML, @SiteCurrencies)

	CREATE TABLE #__Site (SiteId INT, PartyId INT, SiteName VARCHAR(50), ExcludedCurrencyId INT)
	INSERT INTO #__Site (SiteId, PartyId, SiteName)
	SELECT DISTINCT t.c.value('@SiteId', 'INT'), t.c.value('@PartyId', 'INT'), t.c.value('@SiteName', 'VARCHAR(50)')
	FROM @SitesXML.nodes('root/r') t(c)
	OPTION (OPTIMIZE FOR (@SitesXML = NULL))

	CREATE TABLE #__SiteCurrency (SiteId INT, PartyId INT, SiteName VARCHAR(50), CurrencyId INT)
	INSERT INTO #__SiteCurrency (SiteId, PartyId, SiteName, CurrencyId)
	SELECT DISTINCT t.c.value('@SiteId', 'INT'), t.c.value('@PartyId', 'INT'), t.c.value('@SiteName', 'VARCHAR(50)'), t.c.value('@CurrencyId', 'INT')
	FROM @SiteCurrenciesXML.nodes('root/r') t(c)
	OPTION (OPTIMIZE FOR (@SiteCurrenciesXML = NULL))

	UPDATE s
	SET s.ExcludedCurrencyId = sc.CurrencyId
	FROM #__Site s
		INNER JOIN #__SiteCurrency sc ON s.SiteId = sc.SiteId

	CREATE TABLE #__member (PartyId INT, CustId INT, CurrencyId INT)
	
	INSERT INTO #__member (PartyId, CustId, CurrencyId)
	SELECT PartyId, CustId, 0
	FROM (
		SELECT s.PartyId, c.CustId, ROW_NUMBER() OVER(PARTITION BY SiteName ORDER BY SiteName) AS RN
		FROM dbo.Dep_CustSuper cs WITH (NOLOCK)
			INNER JOIN dbo.Customer a WITH (NOLOCK) ON cs.custid = a.srecommend AND a.roleid = 2
			INNER JOIN #__Site s ON cs.site = s.SiteName
			CROSS APPLY (
				SELECT TOP 1 c.CustId
				FROM dbo.Customer c WITH (NOLOCK)
				WHERE c.recommend = a.custid
					AND c.username NOT LIKE '%ClearBal' -- balance
					AND c.username NOT LIKE '%CashOut' -- CO
					AND c.roleid = 1
		) c
		WHERE cs.currency <> 20
			AND (s.ExcludedCurrencyId IS NULL OR cs.currency <> s.ExcludedCurrencyId)
			AND a.username NOT LIKE '%ACC%' -- dummy super
	) t
	WHERE RN = 1

	INSERT INTO #__member (PartyId, CustId, CurrencyId)
	SELECT PartyId, CustId, Currency
	FROM (
		SELECT s.PartyId, c.CustId, cs.Currency, ROW_NUMBER() OVER(PARTITION BY SiteName ORDER BY SiteName) AS RN
		FROM dbo.Dep_CustSuper cs WITH (NOLOCK)
			INNER JOIN dbo.Customer a WITH (NOLOCK) ON cs.custid = a.srecommend AND a.roleid = 2
			INNER JOIN #__SiteCurrency s ON cs.site = s.SiteName
			CROSS APPLY (
				SELECT TOP 1 c.CustId
				FROM dbo.Customer c WITH (NOLOCK)
				WHERE c.recommend = a.custid
					AND c.username NOT LIKE '%ClearBal' -- balance
					AND c.username NOT LIKE '%CashOut' -- CO
					AND c.roleid = 1
		) c
		WHERE cs.currency <> 20
			AND cs.currency = s.CurrencyId
			AND a.username NOT LIKE '%ACC%' -- dummy super
	) t
	WHERE RN = 1

	SELECT m.PartyId, m.CurrencyId, CONVERT(FLOAT, 1-AgentPT*1.00/100) AS HousePT
    FROM dbo.Dep_CustPTSetting_Member dcs WITH (NOLOCK)
    INNER JOIN #__member m ON m.CustId = dcs.CustId
    INNER JOIN Dep_CustSettingMode d WITH (NOLOCK) ON dcs.CustID = d.CustId AND d.IsGroupedPT = 0
    WHERE dcs.bettype = 1 AND dcs.sporttype = 1 AND dcs.islive = 0
	UNION ALL
	SELECT m.PartyId, m.CurrencyId, CONVERT(FLOAT, 1-AgentPT*1.00/100) AS HousePT
    FROM #__member m 
    INNER JOIN custInfo ci WITH(NOLOCK) ON ci.custid = m.CustId
    INNER JOIN Dep_CustSettingMode d WITH (NOLOCK) ON m.CustID = d.CustId AND d.IsGroupedPT = 1
    INNER JOIN dbo.Dep_CustPTGroupSetting_Member dcs WITH (NOLOCK) ON ci.recommend = dcs.AgentID
    WHERE dcs.bettype = 1 AND dcs.sporttype = 1 AND dcs.islive = 0

	DROP TABLE #__member
	DROP TABLE #__Site
END
GO
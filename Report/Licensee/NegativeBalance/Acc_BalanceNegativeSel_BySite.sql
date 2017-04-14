ALTER PROCEDURE [dbo].[Acc_BalanceNegativeSel_BySite]
  @Site		VARCHAR(50) = 'Haifa'
 ,@isTest	BIT			= 0

AS
/*
	Created by: Jamie
	Date: 2013-06-26
	Task: Retrieve Negative Balance by Site 
	DB: DBTXN/bodb02 
	
	Revision: 
		- 20131108@Elodie: Splitting bodb02 into CustDB (call custInfo, exchange by link database)
		- 20150120@Jamie: Edit the definition of @isTest 
		- 20150316@Elodie: Support Negative Balance function for all licensee [Red:#30840]
	Param's Explanation: 
		@isTest: 0: Real Currency; 1: UUS Currency 
	
*/
BEGIN 
	SET NOCOUNT ON 
	SELECT	  h.LogID	
			, h.LogDate
			, h.MatchID
			, h.GroupID
			, h.CustID
			, c.Username
			, h.TotalBalance
			, CurrencyName = e.currency 
			, h.Site
			, CASE WHEN bin.CustomInfo1 IS NULL THEN c.username2 ELSE bin.CustomInfo1 END AS CustomInfo1
	FROM	BalanceNegativeHistory h WITH (NOLOCK)
			INNER JOIN CustDB.dbo.Customer c WITH (NOLOCK) ON h.CustID = c.custid
			INNER JOIN CustDB.dbo.exchange e WITH (NOLOCK) ON c.currency = e.exchangeid
			LEFT JOIN DBDEPBBIN.bbin.dbo.Customer bin WITH (NOLOCK) ON h.CustID = bin.IBCCustID
	WHERE	h.StatusID = 0 
			AND h.Site = @Site
			AND 1 = CASE WHEN @isTest = 0 AND e.exchangeID <> 20 THEN 1 
						 WHEN @isTest = 1 AND e.exchangeID = 20 THEN 1 
						 ELSE 0 
						 END  
			
	ORDER BY	  h.LogID ASC
				, h.MatchID ASC
				, c.Username ASC
END

GO
GRANT EXECUTE ON [dbo].[Acc_BalanceNegativeSel_BySite] TO [bodbAdminNet] AS [dbo]
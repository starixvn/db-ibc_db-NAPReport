/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_NegativeBalanceMember_Dep]
	@Site	NVARCHAR(50) = 'All'
AS
/*
	Created: 20110510@Lukas
	Task : get negative balance member in deposit site
	DB: DB052.bodb02
	Original:

	Revisions:
		- 20110525@Jamie: Correct code for getting member's balance
		- 20110530@Kiwi: Get currencyname from exchange for temporary to avoid the mistake from deposit site once inserting 'Q' instead 'INH' for VND
		- 20121116@Henry: change DB from DB06 to DB052 + remove dummy members
		- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
	Param's Explanation:
	• @Site: All - get all
			 12Bet: particular site
*/
BEGIN	
SET NOCOUNT ON	

	DECLARE @MoveBetsDay DATE
	CREATE TABLE #MBUDate (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO #MBUDate (BalanceUpDay, MoveBetsDay)
	  EXEC bodb02.dbo.Age_SelBalanceUpDay
	SELECT @MoveBetsDay = MoveBetsDay FROM #MBUDate

	DECLARE @Super AS TABLE (custid int primary key, currency int,site varchar(50),currencyName nvarchar(50))
	
	CREATE TABLE #Data(site varchar(50),custid int,currencyName nvarchar(50),Balance MONEY)

	IF ISNULL(@Site,'') = ''
		SET @Site = 'ALL'

	INSERT INTO @Super(custid,currency,site,currencyName)  
	SELECT 
		d.CustID,d.currency,d.site ,e.currency
	FROM Dep_CustSuper d WITH (NOLOCK)  
		INNER JOIN 	exchange e ON d.currency = e.exchangeid
	WHERE  
		(@Site='ALL' OR (@Site<>'ALL' AND site = @Site))
		AND d.currency <> 20

	INSERT INTO #Data (site,custid,currencyName,Balance)
	SELECT	s.site, 
			b.custid, 
			s.currencyName, 
			ROUND(SUM(
				CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) 
						OR (b.winlostdate <= @MoveBetsDay and bettype < 19999)
					THEN 0 --skip volatile rows during move bet process
					ELSE winlost-actual_stake + playercomm END 
				)
			,2) AS Balance
	FROM 
			bettrans b WITH(NOLOCK,INDEX=IX_srecommend)
			INNER JOIN @Super s ON b.srecommend = s.custid
			INNER JOIN bodb_licensee.dbo.LicenseeCust lc WITH (NOLOCK) ON b.recommend = lc.custid
	WHERE	
			b.statusID NOT IN (0,1)
	GROUP BY b.custid, s.currencyName, s.site
	HAVING ROUND(SUM(winlost-actual_stake + playercomm),2) < 0
	
		
	SELECT	
		site,
		username,
		currencyname,
		balance
	FROM #Data d
	INNER JOIN Custinfo c WITH (NOLOCK) ON d.custid = c.custid
	WHERE c.roleid =1
	ORDER BY site,username
	
	DROP TABLE #Data
	DROP TABLE #MBUDate
		
END
GO

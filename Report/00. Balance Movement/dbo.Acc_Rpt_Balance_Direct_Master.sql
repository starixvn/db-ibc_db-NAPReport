ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Master]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Jamie
	Date: 2009-07-16
	Task: Direct Master Balance 
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of super instead of get super balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	-- 20121115@Lukas: change query to get only needed data
	- 20130131@Johnson: Filter by username and currency
*/
BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #directMaster (custid INT,username VARCHAR(50), currency INT, srecommend INT)
	
	INSERT INTO #directMaster
	SELECT custid, username, currency,srecommend 
	FROM dbo.f_DirectAgencyList(4)
	WHERE username LIKE '%' + @username + '%'
		AND currency = ISNULL(@currency,currency)
	
	SELECT	m.custid,
			m.username, 
			m.currency,
			IsNull(bal.bal,0) AS Balance,
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	#directMaster m  
			LEFT JOIN (
				SELECT 	srecommend, mrecommend,
						isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
						+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) AS bal, 	
					
						isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
						+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) AS Basebal								
				FROM	bettrans b with (nolock) 	
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')				
				statusID NOT IN (101,102,103)
				AND srecommend IN (SELECT DISTINCT srecommend FROM #directMaster)				
				GROUP BY b.srecommend, b.mrecommend
			) as  bal ON m.custid = bal.mrecommend AND m.srecommend = bal.srecommend 
	ORDER BY m.username
	DROP TABLE #directMaster
END


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Master] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Master] TO [vnteam]
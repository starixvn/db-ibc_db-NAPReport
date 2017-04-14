ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Master_Yesterday]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Master Balance 
	DB: DB06.BODB02
	Revisions:	
	
*/
BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #directMaster (custid INT,username VARCHAR(50), currency INT, srecommend INT)
	DECLARE @currentdate DATETIME
	
	SELECT @currentdate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

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
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
						- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0) AS bal, 	
						
						isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)* actualrate),0)
						+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
						- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0) AS Basebal								
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Master_Yesterday] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Master_Yesterday] TO [vnteam] 
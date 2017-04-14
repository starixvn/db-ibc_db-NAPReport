ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Agent_Yesterday]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Johnson
	Date: 2013-01-31
	Task: Direct Agent Balance
	DB: DB06.BODB02
	Revisions:	
	
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @currentDate datetime 
	SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

	SELECT	a.custid,
			a.username, 
			a.currency, 
			IsNull(bal.bal,0) AS Balance, 
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	f_DirectAgencyList(3) a 
			LEFT JOIN (
				SELECT	recommend, 
						isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) 
						- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end),0) AS bal, 	
						
						isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0)
						- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate then awinlost+comm + winlost-actual_stake else 0 end)*actualrate),0) AS Basebal								
				FROM	bettrans with (nolock) 
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')
				statusID NOT IN (101,102,103)
				GROUP BY recommend 
			)as Bal ON a.custid = Bal.recommend 
	WHERE a.username LIKE '%' + @username +'%'
		AND a.currency = ISNULL(@currency,currency)
	ORDER BY a.username
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Agent_Yesterday] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Agent_Yesterday] TO [vnteam]
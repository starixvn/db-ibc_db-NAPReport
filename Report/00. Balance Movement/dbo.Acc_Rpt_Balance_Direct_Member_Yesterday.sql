ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Member_Yesterday]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Johnson
	Date: 203-01-31
	Task: Direct Member Balance
	DB: DB06.BODB02
		
	Revisions:	
		- 20130531@Johnson: add playercomm for bettype > 19000 to fix data summary bettype(19999)
*/
BEGIN
	SET NOCOUNT ON 
	
	DECLARE @currentDate datetime 
	SELECT @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)	

	SELECT  mem.custid,
			mem.username, 
			mem.currency, 
			IsNull(bal.bal,0) Balance, 
			IsNull(bal.BaseBal,0) BaseBalance
	FROM	f_DirectAgencyList(2) mem
			LEFT JOIN (
				SELECT	custid,
						isnull(SUM(case when bettype < 19001 and winlostdate < @currentdate then winlost - actual_stake + playercomm
										when bettype > 19000 then winlost - actual_stake + playercomm
									else 0 end),0) bal,
								
						isnull(SUM((case when bettype < 19001 and winlostdate < @currentdate then winlost - actual_stake + playercomm
										 when bettype > 19000 then winlost - actual_stake  + playercomm
										else 0 end)* actualrate),0) as Basebal
				FROM	bettrans with (nolock) 
				WHERE	ruben = 1 AND 
				--status NOT IN ('VOID','REJECT','REFUND')				
				statusID NOT IN (101,102,103)				
				GROUP BY custid
			) bal ON mem.custid = bal.custid	
	WHERE mem.username LIKE '%' + @username + '%'
		AND mem.currency = ISNULL(@currency,mem.currency)	
	ORDER BY username
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Member_Yesterday] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Member_Yesterday] TO [vnteam]
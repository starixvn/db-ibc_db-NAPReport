USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Direct_Member]    Script Date: 07/03/2012 01:28:12 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Direct_Member    Script Date: 6/10/2010 1:42:31 PM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Member]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Jamie
	Date: 2009-07-17
	Task: Direct Member Balance
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of agent instead of get agent balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	- 20130131@Johnson: Add filter by username and currency
*/
BEGIN
	SET NOCOUNT ON 
	SELECT  mem.custid,
			mem.username, 
			mem.currency, 
			IsNull(bal.bal,0) Balance, 
			IsNull(bal.BaseBal,0) BaseBalance
	FROM	f_DirectAgencyList(2) mem
			LEFT JOIN (
				SELECT	custid,
						isnull(SUM(winlost - actual_stake + playercomm),0) bal,
						isnull(SUM((winlost - actual_stake + playercomm)* actualrate),0) as Basebal
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Member] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Member] TO [vnteam]
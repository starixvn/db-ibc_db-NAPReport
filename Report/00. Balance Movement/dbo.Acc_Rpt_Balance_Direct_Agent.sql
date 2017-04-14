USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Direct_Agent]    Script Date: 07/03/2012 01:25:52 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Direct_Agent    Script Date: 6/10/2010 1:42:31 PM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Direct_Agent]
	@username	nvarchar(50) = '',
	@currency   int = null
AS
/*	Created: Jamie
	Date: 2009-07-17
	Task: Direct Agent Balance
	DB: DB06.BODB02
	Revisions:	
	- 20090722@Henry: Get downline balance of master instead of get master balance
	- 20100112@Jamie: Get currencyName from Cache 
	-- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
	-- 20120702@Daniel: Get all accounts regardless of data in bettrans
	- 20130131@Johnson: Add filter by username and currency
*/
BEGIN
	SET NOCOUNT ON
	SELECT	a.custid,
			a.username, 
			a.currency, 
			IsNull(bal.bal,0) AS Balance, 
			IsNull(bal.Basebal,0) AS BaseBalance
	FROM	f_DirectAgencyList(3) a 
			LEFT JOIN (
				SELECT	recommend, 
						isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
						+ isnull(sum(case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end),0) AS bal, 	
					
						isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0)
						+ isnull(sum((case when custid <> recommend and custid <> mrecommend then winlost-actual_stake+playercomm else 0 end)* actualrate),0) AS Basebal								
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Direct_Agent] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Direct_Agent] TO [vnteam]
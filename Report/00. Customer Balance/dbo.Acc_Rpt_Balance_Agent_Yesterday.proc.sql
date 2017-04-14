USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Agent_Yesterday]    Script Date: 02/06/2014 00:19:50 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Agent_Yesterday    Script Date: 5/23/2011 6:24:11 PM ******/

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Agent_Yesterday]
	@masterid int = 0
as
/*
Created: 
Task : Get Agent yesterday balance
DB: DB02/DB06.bodb02
Original: 
Revisions:	
	- 20090619@Kiwi: Remove Exchange
	- 20100111@Jamie: Get currencyName from cache 
	- 20110516@Lukas: re-arrange bettype
	- 20131119@Lukas: remove running/void/reject/refund tickets
*/
SET NOCOUNT ON 

DECLARE @currentDate datetime 
SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

SELECT custid, username,c.currency, 
	   IsNull(bal,0) bal,
	   IsNull(BaseBal,0) baseBalance  
FROM custinfo c (nolock)
	LEFT OUTER JOIN 
	(
		SELECT	recommend,
				isnull(sum(case custid 
							WHEN mrecommend then 0
							WHEN recommend then winlost-actual_stake else awinlost+comm-playercomm end),0) 
				+ isnull(sum(case when custid <> recommend AND ruben=1 then winlost-actual_stake+playercomm else 0 end),0) 
				- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate and ruben = 1 then awinlost+comm + winlost-actual_stake else 0 end),0) Bal,
							
				isnull(sum((case custid 
									WHEN mrecommend then 0
									WHEN recommend then winlost-actual_stake else awinlost+comm-playercomm end)* actualrate),0) 
				+ isnull(sum((case when custid <> recommend AND ruben=1 then winlost-actual_stake+playercomm else 0 end)* actualrate),0) 
				- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate and ruben = 1 then awinlost+comm + winlost-actual_stake else 0 end)* actualrate),0) BaseBal
			
		FROM bettrans WITH (nolock)
		WHERE mrecommend = @masterid
			AND ruben = 1 
			AND statusID NOT IN (101,102,103) 
		GROUP BY bettrans.recommend
	) bal ON c.custid = bal.recommend
WHERE c.roleid = 2 AND c.mrecommend = @masterid
order by username


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Agent_Yesterday] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Agent_Yesterday] TO [vnteam] AS [dbo]
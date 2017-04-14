USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Member_Yesterday]    Script Date: 02/06/2014 00:14:08 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Member_Yesterday    Script Date: 5/23/2011 6:24:12 PM ******/

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Member_Yesterday]
	@agentid int
as
/*
Created: 
Task : Get member yesterday balance
DB: DB06.bodb02
Original: 
Revisions:	
	- 20090619@Kiwi: Enhence Performance
	- 20100112@Jamie: Get currencyName from Cache 
	- 20101229@Lukas: Re-arrange bettype
	- 20131118@Lukas: add filter to exclude running tickets
*/

SET NOCOUNT ON

DECLARE @currentDate datetime 
SELECT @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)	

SELECT
	c.custid, 
	c.username, 
	c.currency,
	IsNull(b.bal, 0) Balance,
	IsNull(Basebal,0) AS BaseBalance
FROM
	custinfo c (nolock)
	LEFT OUTER JOIN (
					SELECT
						custid,
						isnull(SUM( case when bettype < 19001 and winlostdate < @currentDate then winlost - actual_stake + playercomm
										 when bettype > 19000 then winlost - actual_stake + playercomm	
									else 0 end ),0) bal,
									
						isnull(SUM(( case when bettype < 19001 and winlostdate < @currentDate then winlost - actual_stake + playercomm
										  when bettype > 19000 then winlost - actual_stake + playercomm	
									 else 0 end )*actualrate),0) Basebal
					FROM bettrans with (nolock)
					WHERE recommend = @agentid 
						AND ruben = 1 
						AND statusID NOT IN (101,102,103)
					GROUP BY custid
					) AS b ON c.custid = b.custid
WHERE
	c.roleid = 1 AND c.recommend = @agentid 
ORDER BY c.username



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Member_Yesterday] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Member_Yesterday] TO [vnteam] AS [dbo]
USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Master_Yesterday]    Script Date: 02/06/2014 00:17:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Master_Yesterday    Script Date: 5/23/2011 6:24:12 PM ******/


ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Master_Yesterday]
	@superid int = 0,
	@Keyword nvarchar(50) = '',
	@FirstChar nvarchar(6)= '',
	@Currency int = NULL	
AS
SET NOCOUNT ON
/*
Created: 
Task : Get Master balance
DB: DB02/DB06.bodb02
Original: 
Revisions:	
		--Balance calculated with the correct transfer date @Phuong20080927
		- 20090619@Kiwi: Remove Exchange
		--20090515@Jamie: Enhance for using right index
		- 20100112@Jamie: Get currencyName from Cache
		- 20110516@Lukas: re-arrange bettype
		- 20131119@Lukas: remove running/void/reject/refund tickets
		- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
*/

DECLARE @currentDate datetime, @srecommend int
SELECT @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

CREATE TABLE #MasterInfo 
(	
	custid int PRIMARY KEY,
	srecommend	int, 
	username nvarchar(50),
	currency int
)  

IF @superid = 0 
BEGIN
	if @keyword <> '' or @FirstChar <> ''
	BEGIN
		INSERT INTO #MasterInfo (custid,username,srecommend, currency)
		SELECT custid, username,srecommend, currency
		FROM customer c with (nolock)
		WHERE c.roleid = 3 and (srecommend < 100 or srecommend in (21278849, 21278858))
			and c.username like '%' + @Keyword + '%'
			AND c.username like @FirstChar + '%'
		
	END
	ELSE 
	BEGIN 
		INSERT INTO #MasterInfo (custid,username,srecommend, currency)
		SELECT custid, username,srecommend, currency
		FROM customer c with (nolock)
		WHERE c.roleid = 3 AND (srecommend < 100 or srecommend in (21278849, 21278858))
	END 
END 
ELSE 
BEGIN
	INSERT INTO #MasterInfo (custid,username,srecommend, currency)
	SELECT custid, username,srecommend, currency
	FROM customer c with (nolock)
	WHERE c.roleid = 3 AND srecommend = @superid 
	 
END

IF @Currency is not null
BEGIN 
	DELETE FROM #MasterInfo WHERE currency <> @currency 
END  

SELECT custid ,username, m.currency, 
	   IsNull(bal,0) AS Balance, 
	   IsNull(Basebal,0) AS BaseBalance
FROM #MasterInfo M 
	LEFT OUTER JOIN (
			 SELECT 
					srecommend, mrecommend, 
					isnull(sum(case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
					+ isnull(sum(case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end),0)
					+ isnull(sum(case when custid <> recommend and custid <> mrecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end),0) 
					- isnull(sum(case when bettype < 19001 and winlostdate >= @currentDate and ruben = 1 then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end ),0)AS bal	,
					
					isnull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*actualrate),0)
					+ isnull(sum((case when custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)*actualrate),0)
					+ isnull(sum((case when custid <> recommend and custid <> mrecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)*actualrate),0) 
					- isnull(sum((case when bettype < 19001 and winlostdate >= @currentDate and ruben = 1 then mwinlost+acomm + awinlost + winlost-actual_stake else 0 end )*actualrate),0)AS Basebal									
			  FROM bettrans with (nolock)
			  WHERE mrecommend in (SELECT custid FROM #MasterInfo WITH (NOLOCK))
					AND srecommend in (SELECT srecommend FROM #MasterInfo WITH (NOLOCK))
					AND ruben = 1 
					AND statusID NOT IN (101,102,103) 
			  GROUP BY mrecommend, srecommend  
			)as Bal ON M.custid = Bal.mrecommend 
order by username 
DROP TABLE #MasterInfo


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Master_Yesterday] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Master_Yesterday] TO [vnteam] AS [dbo]
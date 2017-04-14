USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_Balance_Super_Yesterday]    Script Date: 02/06/2014 00:18:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Super_Yesterday_xtest    Script Date: 7/24/2012 12:29:26 AM ******/
/****** Object:  Stored Procedure dbo.Acc_Rpt_Balance_Super_Yesterday    Script Date: 7/19/2012 10:30:33 AM ******/
ALTER PROC [dbo].[Acc_Rpt_Balance_Super_Yesterday]
	@Keyword nvarchar(50) = '',
	@FirstChar nvarchar(6)= '',
	@Currency int = NULL,
	@IsViewTotalOnly bit = 0,
	@Total money = 0 output
AS
SET NOCOUNT ON
/*
Created: 
Task : Get Yesterday Total Balance of all supers
DB: DBTRANS.bodb02, DB06.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Enhence Performance by using #SuperInfo
	- 20091130@Jamie: Move from DB06 to DB052 (Replication) 
	- 20100112@Jamie: Get currencyName from Cache 
	- 20110516@Lukas: re-arrange bettype
	- 20120717@Elodie:  Add @IsViewTotalOnly and @Total params to show total value when user want to view total only
						Rewrite SP to enhance performance
						Change DBTRANS server instead of DB02 server
	- 20131119@Lukas: remove running/void/reject/refund tickets
	- 20160322@Robert: Moving customers to new lines  [Redmine: #53554]
							
Parameters Explanation:
	- Search keyword: '%keyword%'
	- First char
			A: 'A%'
			B: 'B%'
			0-9: '[0-9]%'
*/
Begin
	DECLARE @currentDate datetime 
	SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

	CREATE TABLE #SuperInfo 
	(	
		custid int PRIMARY KEY,
		username nvarchar(50),
		currency int
	) 

	if @Keyword <> '' OR @FirstChar <> '' OR @Currency is not NULL						
		INSERT INTO #SuperInfo (custid, username, currency)
		SELECT c.custid, c.username, c.currency
		FROM custinfo c with (nolock)
		WHERE c.roleid = 4
			and c.currency = case when @Currency is null then c.currency else @Currency end
			and c.username like '%' + ltrim(rtrim(@Keyword)) + '%' and c.username like ltrim(rtrim(@FirstChar)) + '%'				
	Else
		INSERT INTO #SuperInfo (custid,username, currency)
		SELECT c.custid, c.username, c.currency
		FROM custinfo c with (nolock)
			INNER JOIN Exchange e WITH (NOLOCK) ON e.exchangeid = c.currency  --Filter currency test 
		WHERE c.roleid = 4
		
	IF @IsViewTotalOnly = 0	
		SELECT 
			s.custid,
			s.username, 
			s.currency,
			IsNull(sum(case when b.custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end),0)
			+ IsNull(sum(case when b.custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end),0)
			+ IsNull(sum(case when b.custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end),0)
			+ IsNull(sum(case when b.custid <> recommend and b.custid <> mrecommend and b.custid <> srecommend and b.ruben = 1 then winlost-actual_stake+playercomm else 0 end),0)
			- isNull (sum (case when bettype < 19001 and winlostdate >= @currentDate  and ruben = 1 then  swinlost + scomm + mwinlost + awinlost + winlost-actual_stake else 0 end),0) AS Balance,
			
			IsNull(sum((case when b.custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
			+ IsNull(sum((case when b.custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
			+ IsNull(sum((case when b.custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
			+ IsNull(sum((case when b.custid <> recommend and b.custid <> mrecommend and b.custid <> srecommend and b.ruben = 1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0) 
			- isNull (sum ((case when bettype < 19001 and winlostdate >= @currentDate  and ruben = 1 then  swinlost + scomm + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0) AS BaseBalance
		FROM #SuperInfo s
			INNER JOIN bettrans b with (READPAST) ON b.srecommend = s.custid
		WHERE 
				ruben = 1 
				AND statusID NOT IN (101,102,103) 
		GROUP BY s.custid, s.username, s.currency
		order by CASE when s.custid < 100 or s.custid in (21278849, 21278858) then 0 ELSE 1 END, s.username	
	ELSE	
	Begin
		select @Total = sum(bal.BaseBalance)
		from 
			(SELECT   							
					 b.srecommend,
					 IsNull(sum((case when b.custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
					 + IsNull(sum((case when b.custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
					 + IsNull(sum((case when b.custid=recommend then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
					 + IsNull(sum((case when b.custid <> recommend and b.custid <> mrecommend and b.custid <> srecommend and b.ruben = 1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0)
					 - isNull (sum ((case when bettype < 19001 and winlostdate >= @currentDate  and ruben = 1 then  swinlost + scomm + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0) as BaseBalance
			FROM #SuperInfo s
				INNER JOIN bettrans b with (READPAST) ON b.srecommend = s.custid
			WHERE 
				ruben = 1 
				AND statusID NOT IN (101,102,103) 
			GROUP BY b.srecommend) as bal
	End
	DROP TABLE #SuperInfo
END


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Balance_Super_Yesterday] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Balance_Super_Yesterday] TO [vnteam] AS [dbo]
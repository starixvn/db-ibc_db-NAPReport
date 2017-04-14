DECLARE @currentDate datetime 
SELECT  @currentDate = convert(varchar(10), CURRENT_TIMESTAMP, 120)

CREATE TABLE #SuperInfo 
(	
	custid int PRIMARY KEY,
	username nvarchar(50),
	currency int
) 

INSERT INTO #SuperInfo (custid,username, currency)
SELECT custid, username, currency
FROM custinfo with (nolock)
WHERE roleid = 4
and custid in (2, 608114, 461084, 533951)

SELECT
	custid,username, e.currency,		
	IsNull(Bal1.Balance,0) AS BalanceBeforeYesterday,
	IsNull(Bal2.BettingPosition,0) AS BettingPositionYesterday,
	IsNull(Bal2.Commission,0) AS CommissionYesterday,
	IsNull(Bal2.Transfer,0) AS TransferYesterday,	
	IsNull(Bal2.Balance,0) AS BalanceYesterday,
	IsNull(Bal3.Commission,0) AS CommissionToday,
	IsNull(Bal3.BettingPosition,0) AS BettingPositionToday,
	IsNull(Bal3.Transfer,0) AS TransferToday,	
	IsNull(Bal3.Balance,0) AS BalanceToday
FROM	#SuperInfo s
		INNER JOIN Exchange e with (nolock) ON s.currency = e.exchangeid
		LEFT OUTER JOIN (
						SELECT 
							srecommend,			
						
							IsNull(sum((case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0) 
								AS Balance						
							
						FROM bettrans b with (nolock) 
						where Winlostdate <= dateadd(d, -2, @currentDate) 
						GROUP BY srecommend
						) as  Bal1 ON s.custid = Bal1.srecommend
		
		LEFT OUTER JOIN (
						SELECT 
							srecommend,								
							isNull (sum ((case when bettype < 91 and winlostdate = dateadd(d, -1, @currentDate)  and ruben = 1 then  swinlost + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0)
								AS BettingPosition,
							
							isNull (sum ((case when bettype < 91 and winlostdate = dateadd(d, -1, @currentDate)  and ruben = 1 then  scomm else 0 end)*b.actualrate),0)
								AS Commission,
							
							isNull (sum ((case when bettype >= 91 and winlostdate = dateadd(d, -1, @currentDate)  and ruben = 1 then  swinlost + scomm + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0)
								AS Transfer,

							IsNull(sum((case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0) 
								AS Balance
							
						FROM bettrans b with (nolock) 
						where Winlostdate <= dateadd(d, -1, @currentDate) 
						GROUP BY srecommend
						) as  Bal2 ON s.custid = Bal2.srecommend
		LEFT OUTER JOIN (
						SELECT 
							srecommend,								
							isNull (sum ((case when bettype < 91 and winlostdate = @currentDate  and ruben = 1 then  swinlost + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0)
								AS BettingPosition,
							isNull (sum ((case when bettype < 91 and winlostdate = @currentDate  and ruben = 1 then  scomm else 0 end)*b.actualrate),0)
								AS Commission,
							isNull (sum ((case when bettype >= 91 and winlostdate = @currentDate  and ruben = 1 then  swinlost + scomm + mwinlost + awinlost + winlost-actual_stake else 0 end)*b.actualrate),0)
								AS Transfer,

							IsNull(sum((case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
							+ IsNull(sum((case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
							+ IsNull(sum((case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0) 
								AS Balance
							
						FROM bettrans b with (nolock) 
						where Winlostdate <= @currentDate 
						GROUP BY srecommend
						) as  Bal3 ON s.custid = Bal3.srecommend		
						
order by CASE when custid < 100 then 0 ELSE 1 END, s.username
DROP TABLE #SuperInfo
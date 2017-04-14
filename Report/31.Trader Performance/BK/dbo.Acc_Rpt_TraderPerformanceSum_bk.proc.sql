ALTER PROCEDURE [dbo].[Acc_Rpt_TraderPerformanceSum_bk]
	@fromdate datetime,
	@todate datetime
AS
 
SET NOCOUNT ON		

--Declare @o_x smalldatetime SELECT @o_x = max(winlostdate) FROM bettrans14 with (nolock)

--temp table for operator username and number of matches control by an operator
CREATE TABLE #temp_daao
(
	custid int,
	username varchar(30),	
	matchID int,
	bettype int
	PRIMARY KEY (matchID, bettype,custid)

)
--if @fromdate > @o_x or @todate > @o_x 
--BEGIN
	insert #temp_daao (custid,username,matchID, bettype)
	select a.operatorid, username,  m.matchID,
			case when (a.bettype = 1 and a.operatortype = 1) then 1 
				when (a.bettype = 1 and a.operatortype = 2) then 7 
				when (a.bettype = 2 and a.operatortype = 1) then 3
				when (a.bettype = 2 and a.operatortype = 2) then 8
			end
	from Dot_admin_Assignment_Operator a (nolock)
		inner join customer c with(nolock) on a.operatorid=c.custid
		inner join bodb_archive.dbo.match_bk m with(nolock) on a.matchid=m.matchid
	where
		m.eventdate >= @fromdate and m.eventdate <= @todate
		and m.eventstatus='completed'
		and m.sporttype=1
		and m.matchcode not like '%hedge%'
		and a.operatortype < 3
--END
/*
if @todate <= @o_x or @fromdate <= @o_x 
BEGIN
	insert @temp_daao (custid,username,matchID, bettype)
	select a.operatorid, username, m.matchID,
			case when (a.bettype = 1 and a.operatortype = 1) then 1 
				when (a.bettype = 1 and a.operatortype = 2) then 7 
				when (a.bettype = 2 and a.operatortype = 1) then 3
				when (a.bettype = 2 and a.operatortype = 2) then 8
			end
	from Dot_admin_Assignment_Operator a (nolock)
		inner join customer c with(nolock) on a.operatorid=c.custid
		inner join match14 m with(nolock) on a.matchid=m.matchid
	where
		m.eventdate >= @fromdate and m.eventdate <= @todate
		and m.eventstatus='completed'
		and m.sporttype=1
		and m.matchcode not like '%hedge%'
		and a.operatortype < 3	
END
*/
/*
CREATE TABLE #temp_daao_sum
(
	custid int,	
	qty_hdp int,
	qty_ou int,
	qty_1sthdp int,
	qty_1stou int
)

insert #temp_daao_sum 
select custid,
	sum(case when bettype=1 then 1 else 0 end) as qty_hdp,
	sum(case when bettype=3 then 1 else 0 end) as qty_ou,
	sum(case when bettype=7 then 1 else 0 end) as qty_1sthdp,
	sum(case when bettype=8 then 1 else 0 end) as qty_1stou
from #temp_daao
group by custid

*/

--turn-over, winlost data
CREATE TABLE #temp 
(
	custid int,
	username varchar(30),
	matchno int,	
	stake_hdp money,
	stake_ou money,
	stake_1sthdp money,
	stake_1stou money,
	winlost_hdp money,
	winlost_ou money,
	winlost_1sthdp money,
	winlost_1stou money,
	comm_hdp money,
	comm_ou money,
	comm_1sthdp money,
	comm_1stou money
)
--select * from  @temp_daao

--if @fromdate > @o_x or @todate > @o_x 
--BEGIN
	insert #temp
	--select summary data
	select cm.custid,cm.username,count(distinct cm.matchid) as matchno,	
		
	--turn over
		--hdp, ou, ht hdp, ht ou
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=1 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_hdp,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=3 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_ou,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=7 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_1sthdp,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=8 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_1stou,
		
		--hdp/ou all, total
		--sum((case when b.bettype in (1,7) then case when c.recommend = 52466 then 0 else 1 end else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_allhdp,
		--sum((case when b.bettype in (3,8) then case when c.recommend = 52466 then 0 else 1 end else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_allou,
		--sum((case when c.recommend = 52466 then 0 else 1 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_total,

	--Winlost
		-sum((case when b.bettype=1 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost_hdp,
		-sum((case when b.bettype=3 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost_ou,
		-sum((case when b.bettype=7 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost_1sthdp,
		-sum((case when b.bettype=8 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost_1stou,
	
	--Commission
		sum((case when b.bettype=1 then 1 else 0 end)*scomm*b.virtualrate) as comm_hdp,
		sum((case when b.bettype=3 then 1 else 0 end)*scomm*b.virtualrate) as comm_ou,
		sum((case when b.bettype=7 then 1 else 0 end)*scomm*b.virtualrate) as comm_1sthdp,
		sum((case when b.bettype=8 then 1 else 0 end)*scomm*b.virtualrate) as comm_1stou
		
	from 
		(SELECT * FROM bodb_archive.dbo.bettrans_bk with(nolock) WHERE winlostdate >= @fromdate AND winlostdate <= @todate) b
		inner join #temp_daao cm on b.matchid=cm.matchid and b.bettype = cm.bettype
	where LiveIndicator = 1	
	group by cm.username,cm.custid
--END
/*
if @todate <= @o_x or @fromdate <= @o_x 
BEGIN
	insert @temp	
	select cm.custid,cm.username,
		count(distinct cm.matchid) as matchno,	
		
	--turn over
		--hdp, ou, ht hdp, ht ou
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=1 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_hdp,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=3 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_ou,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=7 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_1sthdp,
		sum((case when b.recommend = 52466 then 0 else 1 end *case when b.bettype=8 then 1 else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_1stou,
		
		--hdp/ou all, total
		--sum((case when b.bettype in (1,7) then case when c.recommend = 52466 then 0 else 1 end else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_allhdp,
		--sum((case when b.bettype in (3,8) then case when c.recommend = 52466 then 0 else 1 end else 0 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_allou,
		--sum((case when c.recommend = 52466 then 0 else 1 end)*b.stake*(1-b.tpositiontaking)*b.virtualrate) as stake_total,

	--Winlost
		-sum((case when b.bettype=1 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.actualrate) as winlost_hdp,
		-sum((case when b.bettype=3 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.actualrate) as winlost_ou,
		-sum((case when b.bettype=7 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.actualrate) as winlost_1sthdp,
		-sum((case when b.bettype=8 then 1 else 0 end)*(winlost-actual_stake + awinlost+mwinlost+swinlost)*b.actualrate) as winlost_1stou
	from bettrans14 b with(nolock) 
		inner join @temp_daao cm  on b.matchid=cm.matchid and b.bettype = cm.bettype
	where LiveIndicator = 1	
	group by cm.username,cm.custid
END
*/
select  custid, username, matchno, stake_hdp, stake_ou, stake_1sthdp, stake_1stou,
	winlost_hdp - comm_hdp as winlost_hdp, 
	winlost_ou - comm_ou as winlost_ou, 
	winlost_1sthdp - comm_1sthdp as winlost_1sthdp, 
	winlost_1stou - comm_1stou as winlost_1stou, 
	comm_hdp, comm_ou, comm_1sthdp, comm_1stou,
	--tds.qty_1sthdp + tds.qty_hdp + tds.qty_1stou + tds.qty_ou as overall_qty,
	stake_1sthdp + stake_hdp + stake_1stou+stake_ou as overall_st,
	winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou - (comm_1sthdp + comm_hdp + comm_1stou + comm_ou) as overall_wl,	
	comm_1sthdp + comm_hdp + comm_1stou + comm_ou as overall_com,
	(winlost_1sthdp - comm_1sthdp)/(case when isnull(stake_1sthdp,0) = 0 then 1 else stake_1sthdp end) as margin_1sthdp,
	(winlost_hdp - comm_hdp)/(case when isnull(stake_hdp,0) = 0 then 1 else stake_hdp end) as margin_hdp,
	(winlost_1stou - comm_1stou)/(case when isnull(stake_1stou,0) = 0 then 1 else stake_1stou end) as margin_1stou,
	(winlost_ou - comm_ou)/(case when isnull(stake_ou,0) = 0 then 1 else stake_ou end) as margin_ou,
	((winlost_1sthdp + winlost_hdp + winlost_1stou + winlost_ou) - (comm_1sthdp + comm_hdp + comm_1stou + comm_ou))/(case when (isnull(stake_1sthdp,0) + isnull(stake_hdp,0) + isnull(stake_1stou,0) + isnull(stake_ou,0)) = 0 then 1 else (isnull(stake_1sthdp,0) + isnull(stake_hdp,0) + isnull(stake_1stou,0) +isnull(stake_ou,0)) end ) as overall_margin
from #temp 
order by username

DROP TABLE #temp_daao
DROP TABLE #temp

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TraderPerformanceSum_bk] TO [bodbAdminNet]
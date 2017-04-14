USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_TraderPerformanceDetail]    Script Date: 07/26/2009 05:19:34 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[Task_rptTraderPerformance] 

AS

/*
Created: 20110320@Amy
Task : Summarize latest 3 days data for table rptTraderPerformance 
DB: DB06.bodb02
Original:

	Revision:
		- 20110516@Lukas: re-arrange bettype

*/

SET NOCOUNT ON

DECLARE @fromdate datetime,	@todate datetime
SET @fromdate= dateadd(dd,-3,CONVERT(varchar(10),getdate(),120))
SET @todate= dateadd(dd,-1,CONVERT(varchar(10),getdate(),120))

--temp table for operator username and number of matches control by an operator
declare @temp_daao table
(
	custid int,
	username varchar(30), 
	leagueid int,
	matchid int,
	sporttype int,
	homeid int,
	awayid int,
	eventdate datetime,
	hthomescore int,
	htawayscore int,
	fthomescore int,
	ftawayscore int,
	bettype smallint,
	IsNeutral bit,
	OUtype tinyint
)

-- Soccer sport --
	insert @temp_daao
	select c.custid, c.username, m.leagueid, m.matchid, 1,
		m.homeid,
		m.awayid,
		m.eventdate,
		m.hthomescore,m.htawayscore,m.finalhomescore,m.finalawayscore,
		case	when operatortype = 1 and bettype = 1 then 1 
				when operatortype = 1 and bettype = 4 then 2
				when operatortype = 1 and bettype = 2 then 3 
				when operatortype = 1 and bettype = 3  then 5
				--when operatortype = 1 and bettype = 4  then 22 -- Next Goal
				when operatortype = 2 and bettype = 1 then 7
				when operatortype = 2 and bettype = 2 then 8
				when operatortype = 2 and bettype = 4 then 12
				when operatortype = 2 and bettype = 3  then 15										
		else 0 end bettype ,	
		m.isNeutral,	--phuong.nguyen
		case 
			when t.teamname LIKE '%No.of Corners%' then 1
			when t.teamname LIKE '%No.of Yellow Cards%' then 3	
			when t.teamname LIKE '%Corner%'  then 4	
			when leaguename LIKE '%SPECIFIC 15 MINS OVER/UNDER%' then 2
			else 0
		end		
	from Dot_admin_Assignment_Operator a (nolock)  
		inner join match m with(nolock) on a.matchid=m.matchid
		inner join team t with(nolock) on m.homeid=t.teamid		
		inner join team ta with(nolock) on m.awayid=ta.teamid		
		inner join customer c with(nolock) on a.operatorid=c.custid
		inner join league l with(nolock) on m.leagueid=l.leagueid		
	where
		m.eventdate between @fromdate and @todate
		and m.eventstatus='completed'
		and m.sporttype= 1
		and a.operatortype < 3
		and m.matchcode not like '%hedge%'
	UNION ALL-- include orphan matches
	select NULL, NULL, m.leagueid, m.matchid,1,
		m.homeid,
		m.awayid,
		m.eventdate,
		m.hthomescore,m.htawayscore,m.finalhomescore,m.finalawayscore,0,
		m.isNeutral,	--phuong.nguyen
		case 
			when t.teamname LIKE '%No.of Corners%' then 1
			when t.teamname LIKE '%No.of Yellow Cards%' then 3	
			when t.teamname LIKE '%Corner%'  then 4			
			when leaguename LIKE '%SPECIFIC 15 MINS OVER/UNDER%' then 2
			else 0
		end
	from 
		Dot_admin_Assignment_Operator a (nolock)
		right join match m with(nolock) on a.matchid = m.matchid
		inner join team t with(nolock) on m.homeid=t.teamid		
		inner join team ta with(nolock) on m.awayid=ta.teamid		
		inner join league l with(nolock) on m.leagueid=l.leagueid
	where
		m.eventdate between @fromdate and @todate
		and m.eventstatus='completed'
		and m.sporttype=1
		and m.matchcode not like '%hedge%'
		and a.matchid is NULL		
-------------------End Soccer---------------------------

-------------Other sports-------------------------
	insert @temp_daao
	select c.custid, c.username, m.leagueid, m.matchid,99,
		m.homeid,
		m.awayid,
		m.eventdate,
		m.hthomescore,m.htawayscore,m.finalhomescore,m.finalawayscore,
		case	when operatortype = 1 and (bettype = 1 or bettype=5) then 1 
				when operatortype = 1 and bettype = 4 then 2
				when operatortype = 1 and bettype = 2 then 3 
				when operatortype = 1 and bettype = 3  then 5
				--when operatortype = 1 and bettype = 4  then 22 -- Next Goal
				when operatortype = 2 and bettype = 1 then 7
				when operatortype = 2 and bettype = 2 then 8
				when operatortype = 2 and bettype = 4 then 12
				when operatortype = 2 and bettype = 3  then 15										
		else 0 end bettype ,	
		m.isNeutral, 0
	from Dot_admin_Assignment_Operator a (nolock)  
		inner join match m with(nolock) on a.matchid=m.matchid
		inner join customer c with(nolock) on a.operatorid=c.custid
		inner join league l with(nolock) on m.leagueid=l.leagueid				
	where
		m.eventdate between @fromdate and @todate
		and m.eventstatus='completed'
		and m.sporttype not in (1,161)-- exclude number game
		and a.operatortype < 3
		and m.matchcode not like '%hedge%'
	UNION ALL
	select NULL, NULL, m.leagueid, m.matchid, 99,
		m.homeid,
		m.awayid,
		m.eventdate,
		m.hthomescore,m.htawayscore,m.finalhomescore,m.finalawayscore,0,
		m.isNeutral, 0
	from 
		Dot_admin_Assignment_Operator a (nolock)
		right join match m with(nolock) on a.matchid = m.matchid
		inner join league l with(nolock) on m.leagueid=l.leagueid
	where
		m.eventdate between @fromdate and @todate
		and m.eventstatus='completed'
		and m.sporttype not in (1,161)
		and m.matchcode not like '%hedge%'
		and a.matchid is NULL
-------------------End Other Sports---------------------------

-----------/*Delete data before inserting*/------
DELETE bodb_report.dbo.rptTraderPerformance WHERE eventdate between @fromdate and @todate
-------------------------------------------------

INSERT INTO bodb_report.dbo.rptTraderPerformance (custid, username, eventdate, leagueid, matchid,sporttype,homeid, awayid, 
		isneutral, hthomescore, htawayscore, fthomescore,ftawayscore,bettype, stake, winlost,comm,betcount)

SELECT om.custid,om.username,om.eventdate, om.leagueid,om.matchid,om.sporttype,om.homeid,om.awayid,
	om.isneutral,om.hthomescore, om.htawayscore, om.fthomescore,om.ftawayscore,
CASE when b.bettype=1 and OUtype = 0 then 1				
	when b.bettype=3 and OUtype = 0 then 3				
	when b.bettype=8 and OUtype = 0 then 8				
	when b.bettype = 8 and OUtype = 1 then 20000
	when b.bettype = 3 and OUtype = 1 then 20001
	when b.bettype = 3 and OUtype = 2 then 20002
	when b.bettype = 8 and OUtype = 3 then 20003
	when b.bettype = 3 and OUtype = 3 then 20004
	when b.bettype =1 and OUtype = 4 then 20005
ELSE b.bettype end as bettype,
--turn over		
	sum(case when b.recommend <> 52466
					then (case when b.modds = 0.25 OR b.modds = -0.25 then b.stake/2 else b.stake end)*(1-b.tpositiontaking)*b.virtualrate else 0 end) as stake,				
--Winlost
	-sum((winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost,		
--Commission
	sum(scomm*b.virtualrate) as comm,			
--Live BetCount				
	sum(1) as bet				
FROM bettrans b with(nolock) 		
	inner join @temp_daao om  on b.matchid=om.matchid and b.bettype = om.bettype and LiveIndicator = 1
WHERE 	
	b.statusID not in (101,102,103,121,111) 
	AND b.ruben =1 
GROUP BY om.custid,om.username,om.eventdate, om.leagueid, om.matchid,b.bettype,sporttype,om.homeid,om.awayid,om.hthomescore,om.htawayscore,om.fthomescore,om.ftawayscore,om.IsNeutral,OUType
UNION ALL
SELECT 0,'(unassigned)',om.eventdate, om.leagueid,om.matchid, om.sporttype,			
	om.homeid,
	om.awayid,
	om.IsNeutral,
	om.hthomescore,om.htawayscore,om.fthomescore,om.ftawayscore,
case when b.bettype=1 and OUtype = 0 then 1				
	when b.bettype=3 and OUtype = 0 then 3				
	when b.bettype=8 and OUtype = 0 then 8				
	when b.bettype = 8 and OUtype = 1 then 20000
	when b.bettype = 3 and OUtype = 1 then 20001
	when b.bettype = 3 and OUtype = 2 then 20002
	when b.bettype = 8 and OUtype = 3 then 20003
	when b.bettype = 3 and OUtype = 3 then 20004
	when b.bettype =1 and OUtype = 4 then 20005
else b.bettype end as bettype,				
--turn over				
	sum(case when b.recommend <> 52466 
					then (case when b.modds = 0.25 OR b.modds = -0.25 then b.stake/2 else b.stake end)*(1-b.tpositiontaking)*b.virtualrate else 0 end) as stake,				
--Winlost
	-sum((winlost-actual_stake + awinlost+mwinlost+swinlost)*b.virtualrate) as winlost,				

--Commission
	sum(scomm*b.virtualrate) as comm,		
--Live BetCount				
	sum(1) as bet					
FROM bettrans b with(nolock) 		
	inner join @temp_daao om  on b.matchid=om.matchid and om.bettype = 0 and LiveIndicator = 1
WHERE 	
	b.statusID not in (101,102,103,121,111) 
	AND b.ruben =1 
GROUP BY om.eventdate, om.leagueid, om.matchid,b.bettype,sporttype,om.homeid,om.awayid,om.hthomescore,om.htawayscore,om.fthomescore,om.ftawayscore,om.IsNeutral,OUType


GO
GRANT VIEW DEFINITION ON [dbo].[Task_rptTraderPerformance]  TO [vnteam]

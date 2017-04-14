USE [MiniCasinoAdmin]
GO
ALTER PROCEDURE [dbo].[Acc_MT_GetMiniGamePT]
	@username	varchar(30)
as
SET NOCOUNT ON
/*
Created: 
Task : Get Customer's MiniGame PT .
DB: CS_MiniBackupDB
Original:

Revisions:
	- 20100413@Shifu: create.

*/

declare @roleid int,@custid int,@sagentid int,@magentid int,@agentid int
declare @susername varchar(30),@musername varchar(30),@ausername varchar(30)
select @roleid = roleid,@custid=custid,
		@sagentid=case roleid when 4 then custid else sagentid end,
		@magentid=case roleid when 3 then custid else magentid end,
		@agentid=case roleid when 2 then custid else agentid end
from customer (nolock) where username=@username and roleid < 5

if @roleid is null
return

select @susername=username from customer(nolock) where custid=@sagentid
select @musername=username from customer(nolock) where custid=@magentid
select @ausername=username from customer(nolock) where custid=@agentid

--select @roleid,@custid,@sagentid,@magentid,@agentid,@susername,@musername,@ausername

declare @minigamept table
(
	roleid		tinyint,
	rolename	varchar(10),
	custid int,
	username varchar(30),
	SPT	money,
	mPT	money,
	aPT	money,
	MinPT	money,
	IsAutoPT	bit,
	AutoPT	money,
	RollingRate	money
)
--SUPER SETTING

insert into @minigamept
select 4,'super', @sagentid,@susername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
		cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.SMAgentRollingRate
from CustGameKind cgd(nolock) 
where cgd.custid=@sagentid 


--MASTER SETTING
if @roleid < 4
begin
	
	insert into @minigamept
	select 3,'master',@magentid,@musername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
			cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.MAgentRollingRate
	from CustGameKind cgd(nolock) 
	where cgd.custid=@magentid 		
	
end

--AGENT SETTING
if @roleid < 3
begin
	insert into @minigamept
	select 2,'agent',@agentid,@ausername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
			cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.AgentRollingRate
	from CustGameKind cgd(nolock) 
	where cgd.custid=@agentid 
	
end


--AGENT SETTING
if @roleid < 2
begin
		insert into @minigamept
		select 1,'player',@custid,@username,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
				cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.MemberRollingRate
		from CustGameKind cgd(nolock) 
		where cgd.custid=@custid 
	
end

select * from @minigamept order by roleid desc

GO
GRANT EXECUTE ON [dbo].[Acc_MT_GetMiniGamePT] TO [Dot_MAgent]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_MT_GetMiniGamePT] TO [Dot_MAgent]
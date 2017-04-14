USE [CasinoAdmin]
GO
/****** Object:  StoredProcedure [dbo].[_DBA_GetCSPT]    Script Date: 03/23/2009 00:51:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create proc [dbo].[Acc_MT_GetCSPT]
	@username	varchar(30),
	@GameKind	int = 1,
	@GameType	int = 0
as

--parameter explanation:
	--@GameKind 0	: by game type
	--			1	: all game kind
	--			>1	: by game kind
	--@GameType 0	: all game type
	--			else: by game type


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

declare @cspt table
(
	roleid		tinyint,
	rolename	varchar(10),
	gamekindid int,
	gamekind nvarchar(50),
	gametypeid int,
	gametype nvarchar(50),
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
if @GameKind <> 0
	insert into @cspt
	select 4,'super',cgd.GameKind,CD.CodeName,0,'',@sagentid,@susername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
			cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.SMAgentRollingRate
	from CustGameKind cgd(nolock) inner join 
			(
				SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
				FROM	Code WITH (NOLOCK) 
				WHERE	CodeTypeNo = '02' AND IsDisabled='0'
			) 
			AS CD ON cgd.GameKind = CD.CodeID

	where cgd.custid=@sagentid 
		and cgd.GameKind = case @GameKind when 1 then cgd.GameKind else @GameKind end
else
	insert into @cspt
	select 4,'super',cgt.GameKind,CD.CodeName,cgt.GameTypeID,gt.GameTypeName,@sagentid,@susername,cgt.SpositionTaking,cgt.MPositionTaking,cgt.APositionTaking,
			cgt.MinPositionTaking,cgt.IsAutoPositiontaking,cgt.AutoPositionTaking,cgt.SMAgentRollingRate
	from CustGameType cgt(nolock) inner join GameType gt(nolock) on cgt.GameTypeID= gt.GameTypeID
		inner join 
			(
				SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
				FROM	Code WITH (NOLOCK) 
				WHERE	CodeTypeNo = '02' AND IsDisabled='0'
			) 
			AS CD ON cgt.GameKind = CD.CodeID
	where cgt.custid=@sagentid
		and gt.GameTypeID = case @GameType when 0 then gt.GameTypeID else @GameType end

--MASTER SETTING
if @roleid < 4
begin
	if @GameKind <> 0
		insert into @cspt
		select 3,'master',cgd.GameKind,CD.CodeName,0,'',@magentid,@musername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
				cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.MAgentRollingRate
		from CustGameKind cgd(nolock) inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgd.GameKind = CD.CodeID

		where cgd.custid=@magentid 
			and cgd.GameKind = case @GameKind when 1 then cgd.GameKind else @GameKind end
	else
		insert into @cspt
		select 3,'master',cgt.GameKind,CD.CodeName,cgt.GameTypeID,gt.GameTypeName,@magentid,@musername,cgt.SpositionTaking,cgt.MPositionTaking,cgt.APositionTaking,
				cgt.MinPositionTaking,cgt.IsAutoPositiontaking,cgt.AutoPositionTaking,cgt.MAgentRollingRate
		from CustGameType cgt(nolock) inner join GameType gt(nolock) on cgt.GameTypeID= gt.GameTypeID
			inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgt.GameKind = CD.CodeID
		where cgt.custid=@magentid
			and gt.GameTypeID = case @GameType when 0 then gt.GameTypeID else @GameType end
end

--AGENT SETTING
if @roleid < 3
begin
	if @GameKind <> 0
		insert into @cspt
		select 2,'agent',cgd.GameKind,CD.CodeName,0,'',@agentid,@ausername,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
				cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.AgentRollingRate
		from CustGameKind cgd(nolock) inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgd.GameKind = CD.CodeID

		where cgd.custid=@agentid 
			and cgd.GameKind = case @GameKind when 1 then cgd.GameKind else @GameKind end
	else
		insert into @cspt
		select 2,'agent',cgt.GameKind,CD.CodeName,cgt.GameTypeID,gt.GameTypeName,@agentid,@ausername,cgt.SpositionTaking,cgt.MPositionTaking,cgt.APositionTaking,
				cgt.MinPositionTaking,cgt.IsAutoPositiontaking,cgt.AutoPositionTaking,cgt.AgentRollingRate
		from CustGameType cgt(nolock) inner join GameType gt(nolock) on cgt.GameTypeID= gt.GameTypeID
			inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgt.GameKind = CD.CodeID
		where cgt.custid=@agentid
			and gt.GameTypeID = case @GameType when 0 then gt.GameTypeID else @GameType end
end


--AGENT SETTING
if @roleid < 2
begin
	if @GameKind <> 0
		insert into @cspt
		select 1,'player',cgd.GameKind,CD.CodeName,0,'',@custid,@username,cgd.SpositionTaking,cgd.MPositionTaking,cgd.APositionTaking,
				cgd.MinPositionTaking,cgd.IsAutoPositiontaking,cgd.AutoPositionTaking,cgd.MemberRollingRate
		from CustGameKind cgd(nolock) inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgd.GameKind = CD.CodeID

		where cgd.custid=@custid 
			and cgd.GameKind = case @GameKind when 1 then cgd.GameKind else @GameKind end
	else
		insert into @cspt
		select 1,'player',cgt.GameKind,CD.CodeName,cgt.GameTypeID,gt.GameTypeName,@custid,@username,cgt.SpositionTaking,cgt.MPositionTaking,cgt.APositionTaking,
				cgt.MinPositionTaking,cgt.IsAutoPositiontaking,cgt.AutoPositionTaking,cgt.MemberRollingRate
		from CustGameType cgt(nolock) inner join GameType gt(nolock) on cgt.GameTypeID= gt.GameTypeID
			inner join 
				(
					SELECT  CodeID, CodeTypeNo, CodeName, CodeSName	
					FROM	Code WITH (NOLOCK) 
					WHERE	CodeTypeNo = '02' AND IsDisabled='0'
				) 
				AS CD ON cgt.GameKind = CD.CodeID
		where cgt.custid=@custid
			and gt.GameTypeID = case @GameType when 0 then gt.GameTypeID else @GameType end
end

select * from @cspt order by gamekind, gametype, roleid desc
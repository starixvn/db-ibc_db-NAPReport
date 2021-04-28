/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetTurnOver]
	@matchid int
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Turnover Report 
	DB: DBACC.bodb_ACC
	
	Revisions:
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20170612@Percy: check bettype of Cash Out [RedmineID: #78160]
		- 20190308@Robert: #109822 - NAP Report - Integrate Bet Builder
		- 20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @EventDate DATETIME
		,@MoveBetsDay DATETIME
	---Get match info---
	;WITH cte_match
	AS (
		SELECT eventdate
		FROM bodb02.dbo.match WITH (NOLOCK)
		WHERE matchid = @matchid
		
		UNION
		
		SELECT eventdate
		FROM bodb02.dbo.match14 WITH (NOLOCK)
		WHERE matchid = @matchid
	)
	SELECT @EventDate = MAX(eventdate)
	FROM cte_match

	---Get MoveBetsDay---
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
	---Get data from bettrans---
	IF @EventDate > @MoveBetsDay
	--SP: Dot_Admin_turnover_detail
	SELECT
		IsNull(TotalA, 0) TotalA, IsNull(SuperA, 0) SuperA, IsNull(MasterA, 0) MasterA, IsNull(AgentA, 0) AgentA,
		IsNull(TotalV, 0) TotalV, IsNull(SuperV, 0) SuperV, IsNull(MasterV, 0) MasterV, IsNull(AgentV, 0) AgentV
	FROM (
		SELECT  
			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate   
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate  
			else b.stake * b.actualrate  
			end) TotalA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.spositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.spositiontaking  
			else b.stake * b.actualrate * b.spositiontaking  
			end) SuperA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.mpositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.mpositiontaking  
			else b.stake * b.actualrate * b.mpositiontaking  
			end) MasterA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.apositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.apositiontaking  
			else b.stake * b.actualrate * b.apositiontaking  
			end) AgentA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate   
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate  
			else b.stake * b.virtualrate  
			end) TotalV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.spositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.spositiontaking  
			else b.stake * b.virtualrate * b.spositiontaking  
			end) SuperV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.mpositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.mpositiontaking  
			else b.stake * b.virtualrate * b.mpositiontaking  
			end) MasterV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.apositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.apositiontaking  
			else b.stake * b.virtualrate * b.apositiontaking  
			end) AgentV
		FROM
			bodb02.dbo.bettrans b (nolock)
		WHERE
			matchid = @matchid
			AND status NOT IN ('void','reject')
			AND b.bettype NOT IN(SELECT bettype FROM bodb02.dbo.f_VSHorseRacingByBettype())
			AND b.bettype NOT IN (901,902,903,904)
			AND b.bettype NOT IN (911,912,913,914, 38)
	) b

	ELSE

	SELECT
		IsNull(TotalA, 0) TotalA, IsNull(SuperA, 0) SuperA, IsNull(MasterA, 0) MasterA, IsNull(AgentA, 0) AgentA,
		IsNull(TotalV, 0) TotalV, IsNull(SuperV, 0) SuperV, IsNull(MasterV, 0) MasterV, IsNull(AgentV, 0) AgentV
	FROM (
		SELECT  
			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate   
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate  
			else b.stake * b.actualrate  
			end) TotalA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.spositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.spositiontaking  
			else b.stake * b.actualrate * b.spositiontaking  
			end) SuperA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.mpositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.mpositiontaking  
			else b.stake * b.actualrate * b.mpositiontaking  
			end) MasterA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.apositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.actualrate * b.apositiontaking  
			else b.stake * b.actualrate * b.apositiontaking  
			end) AgentA,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate   
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate  
			else b.stake * b.virtualrate  
			end) TotalV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.spositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.spositiontaking  
			else b.stake * b.virtualrate * b.spositiontaking  
			end) SuperV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.mpositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.mpositiontaking  
			else b.stake * b.virtualrate * b.mpositiontaking  
			end) MasterV,  

			sum(Case betteam  
			when 'h' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.apositiontaking  
			when 'a' then CASE when abs(odds) > 1 then abs(odds) * b.stake else b.stake END * b.virtualrate * b.apositiontaking  
			else b.stake * b.virtualrate * b.apositiontaking  
			end) AgentV
		FROM
			bodb02.dbo.bettrans14 b (nolock)
		WHERE
			matchid = @matchid
			AND status NOT IN ('void','reject')
			AND b.bettype NOT IN(SELECT bettype FROM bodb02.dbo.f_VSHorseRacingByBettype())
			AND b.bettype NOT IN (901,902,903,904)
			AND b.bettype NOT IN (911,912,913,914, 38)
	) b
END

/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[NAP_SaveBet_GetTB]
	@matchid int,
	@bettype smallint,
	@liveindicator bit
AS

/*
	Created by: Dom
	Date:2014-05-05
	Task: Total Bet Report 
	DB: DBACC.bodb02
	
	Revisions:
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20170612@Percy: check bettype of Cash Out [RedmineID: #78160]
		- 20210329@Jaden: add forecast the result with Real figures (#152290)
		- 20210423@Roy: NAP Report - Move Save bet db & service (#153147)
*/

BEGIN
	SET NOCOUNT ON
	Declare @vScore smallmoney
	SET @vScore = NULL

	Declare @FC TABLE 
		(vScore smallint, liveindicator bit, status nvarchar(20), 
		hdp smallmoney, livehomescore smallint, liveawayscore smallint,
		HomeTotal_V money, AwayTotal_V money, AwayLose_V money, HomeLose_V money, Commission_V money,
		HomeTotal_A money, AwayTotal_A money, AwayLose_A money, HomeLose_A money, Commission_A money,
		BetCount int, 
		FC_pX_V money, FC_p4_V money, FC_p3_V money, FC_p2_V money, FC_p1_V money, FC_p0_V money,
		FC_m1_V money, FC_m2_V money, FC_m3_V money, FC_m4_V money, FC_mX_V money, FC_00_V money, FC_0x_V money,
		FC_pX_A money, FC_p4_A money, FC_p3_A money, FC_p2_A money, FC_p1_A money, FC_p0_A money,
		FC_m1_A money, FC_m2_A money, FC_m3_A money, FC_m4_A money, FC_mX_A money, FC_00_A money, FC_0x_A money)

	Declare @FTHomeScore smallint, @FTAwayScore smallint, @HTHomeScore smallint, @HTAwayScore smallint

	IF @bettype IN (901,902,903,904)
	BEGIN 
		SELECT N'This report does not support bettrade ticket !'
		RETURN
	END

	IF @bettype IN (911,912,913,914)
	BEGIN 
		SELECT N'This report does not support cash out ticket!'
		RETURN
	END 

	DECLARE @EventDate DATETIME
		,@MoveBetsDay DATETIME

	---Get MoveBetsDay---
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
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
	
	---Get data from bettrans---
	IF @EventDate > @MoveBetsDay
	BEGIN

		SELECT
			@FTHomeScore = FinalHomeScore,
			@FTAwayScore = FinalAwayScore,
			@HTHomeScore = HTHomeScore,
			@HTAwayScore = HTAwayScore
		FROM
			bodb02.dbo.match WITH(NOLOCK)
		WHERE
			matchid = @matchid

		IF @bettype IN (1, 7, 20)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, 
				HomeTotal_V, AwayTotal_V, AwayLose_V, HomeLose_V, Commission_V,
				HomeTotal_A, AwayTotal_A, AwayLose_A, HomeLose_A, Commission_A, 
				BetCount)
			SELECT  x.liveindicator, x.status, x.hdp, livehomescore, liveawayscore,
				sum(x.hometotal * x.virtualrate),
				sum(x.awaytotal * x.virtualrate),
				sum((x.homewin - x.awaylose) * x.virtualrate),
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(x.comm * x.virtualrate),
				sum(x.hometotal * x.actualrate),
				sum(x.awaytotal * x.actualrate),
				sum((x.homewin - x.awaylose) * x.actualrate),
				sum((x.awaywin - x.homelose) * x.actualrate) 'hl',
				sum(x.comm * x.actualrate),
				sum(c) c
			FROM 
				(select status, b.currency, hdp1 - hdp2 hdp, livehomescore, liveawayscore, liveindicator,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate, b.actualrate
				from bodb02.dbo.bettrans b with(nolock)
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and b.custid >0 and status NOT IN ('VOID', 'REJECT')
				group by status, b.currency, hdp1 - hdp2, livehomescore, liveawayscore, liveindicator, b.virtualrate, b.actualrate
				)x
		GROUP BY x.status, x.hdp, x.livehomescore, x.liveawayscore, x.liveindicator

		ELSE IF @bettype IN (3, 8)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, 
				HomeTotal_V, AwayTotal_V, AwayLose_V, HomeLose_V, Commission_V,
				HomeTotal_A, AwayTotal_A, AwayLose_A, HomeLose_A, Commission_A, 
				BetCount)
			SELECT x.liveindicator, x.status, x.hdp, x.livehomescore, x.liveawayscore, 
				sum(x.hometotal * x.virtualrate),
				sum(x.awaytotal * x.virtualrate),
				sum((x.homewin - x.awaylose) * x.virtualrate),
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(x.comm * x.virtualrate),
				sum(x.hometotal * x.actualrate),
				sum(x.awaytotal * x.actualrate),
				sum((x.homewin - x.awaylose) * x.actualrate),
				sum((x.awaywin - x.homelose) * x.actualrate) 'hl',
				sum(x.comm * x.actualrate),
				sum(c) c
			FROM 
				(select liveindicator, status, b.currency, hdp1 hdp, livehomescore, liveawayscore,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate, b.actualrate
				from bodb02.dbo.bettrans b with(nolock) 
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and custid > 0 and status NOT IN ('VOID', 'REJECT')
				group by liveindicator, status, b.currency, hdp1, livehomescore, liveawayscore, b.virtualrate, b.actualrate
				)x
			group by x.status, liveindicator, x.hdp, x.livehomescore, x.liveawayscore
		

	END
	ELSE -- get from bettrans14 --
	BEGIN

		SELECT
			@FTHomeScore = FinalHomeScore,
			@FTAwayScore = FinalAwayScore,
			@HTHomeScore = HTHomeScore,
			@HTAwayScore = HTAwayScore
		FROM
			bodb02.dbo.match14 WITH (NOLOCK)
		WHERE
			matchid = @matchid

		IF @bettype IN (1, 7, 20)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, 
				HomeTotal_V, AwayTotal_V, AwayLose_V, HomeLose_V, Commission_V,
				HomeTotal_A, AwayTotal_A, AwayLose_A, HomeLose_A, Commission_A, 
				BetCount)
			SELECT  x.liveindicator, x.status, x.hdp, livehomescore, liveawayscore,
				sum(x.hometotal * x.virtualrate),
				sum(x.awaytotal * x.virtualrate),
				sum((x.homewin - x.awaylose) * x.virtualrate),
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(x.comm * x.virtualrate),
				sum(x.hometotal * x.actualrate),
				sum(x.awaytotal * x.actualrate),
				sum((x.homewin - x.awaylose) * x.actualrate),
				sum((x.awaywin - x.homelose) * x.actualrate) 'hl',
				sum(x.comm * x.actualrate),
				sum(c) c
			FROM 
				(select status, b.currency, hdp1 - hdp2 hdp, livehomescore, liveawayscore, liveindicator,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate, b.actualrate
				from bodb02.dbo.bettrans14 b with(nolock)
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and b.custid >0 and status NOT IN ('VOID', 'REJECT')
				group by status, b.currency, hdp1 - hdp2, livehomescore, liveawayscore, liveindicator, b.virtualrate, b.actualrate
				)x
		GROUP BY x.status, x.hdp, x.livehomescore, x.liveawayscore, x.liveindicator

		ELSE IF @bettype IN (3, 8)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, 
				HomeTotal_V, AwayTotal_V, AwayLose_V, HomeLose_V, Commission_V,
				HomeTotal_A, AwayTotal_A, AwayLose_A, HomeLose_A, Commission_A, 
				BetCount)
			SELECT x.liveindicator, x.status, x.hdp, x.livehomescore, x.liveawayscore, 
				sum(x.hometotal * x.virtualrate),
				sum(x.awaytotal * x.virtualrate),
				sum((x.homewin - x.awaylose) * x.virtualrate),
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(x.comm * x.virtualrate),
				sum(x.hometotal * x.actualrate),
				sum(x.awaytotal * x.actualrate),
				sum((x.homewin - x.awaylose) * x.actualrate),
				sum((x.awaywin - x.homelose) * x.actualrate) 'hl',
				sum(x.comm * x.actualrate),
				sum(c) c
			FROM 
				(select liveindicator, status, b.currency, hdp1 hdp, livehomescore, liveawayscore,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate, b.actualrate
				from bodb02.dbo.bettrans14 b with(nolock) 
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and custid > 0 and status NOT IN ('VOID', 'REJECT')
				group by liveindicator, status, b.currency, hdp1, livehomescore, liveawayscore, b.virtualrate, b.actualrate
				)x
			group by x.status, liveindicator, x.hdp, x.livehomescore, x.liveawayscore

	END

	Declare @LiveHomeScore smallint, @LiveAwayScore smallint,
		@hdp smallmoney, @hdp_p smallmoney, @hdp_m smallmoney
		
	SELECT 
		--@LiveHomeScore = max(livehomescore), @LiveAwayScore = max(liveawayscore), 
		@hdp_p = max(hdp), @hdp_m = min(hdp)
	FROM @FC
	
	IF @bettype IN (7, 8)
		SELECT @LiveHomeScore = @HTHomeScore, @LiveAwayScore = @HTAwayScore
	ELSE
		SELECT @LiveHomeScore = @FTHomeScore, @LiveAwayScore = @FTAwayScore
		
	--SELECT @livehomescore lhs, @liveawayscore lha
	SET @hdp = CASE WHEN -@hdp_m > @hdp_p THEN @hdp_m ELSE @hdp_p END
	--PRINT 'liveHomeScore = ' + CAST(@LiveHomeScore as varchar(20))
	--PRINT 'liveAwayScore = ' + CAST(@LiveAwayScore as varchar(20))
	--PRINT 'handicap = ' + CAST(@hdp as varchar(20))

	IF @vScore IS NULL
	BEGIN
		SET @vScore = CASE
			WHEN @bettype IN (1, 7, 20) THEN @LiveHomeScore - @LiveAwayScore --CASE WHEN ABS(@LiveHomeScore - @LiveAwayScore) > ABS(@hdp) THEN @LiveHomeScore - @LiveAwayScore ELSE FLOOR(@hdp) END
			WHEN @bettype IN (3, 8) THEN @LiveHomeScore + @LiveAwayScore --CASE WHEN (@LiveHomeScore + @LiveAwayScore) > 0 THEN @LiveHomeScore + @LiveAwayScore ELSE FLOOR(@hdp-2) END
			END
		IF @vScore < 0 AND @bettype IN (3, 8) SET @vScore = 0
	END


	Declare @factor smallmoney
	SET @factor = CASE WHEN @bettype IN (1, 7, 20) THEN 1 ELSE 0 END

	--SELECT @vScore vScore

	UPDATE @FC SET vScore = @vScore,
			FC_p4_V = CASE
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_p3_V = CASE
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_p2_V = CASE
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_p1_V = CASE
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_p0_V = CASE
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_m1_V = CASE
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_m2_V = CASE
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_m3_V = CASE
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_m4_V = CASE
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_pX_V = CASE
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_mX_V = CASE
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_V
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_V / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_V / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_00_V = CASE
				WHEN (@livehomescore+@LiveAwayScore) - hdp >  0.25 THEN AwayLose_V
				WHEN (@livehomescore+@LiveAwayScore) - hdp =  0.25 THEN AwayLose_V / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp = -0.25 THEN HomeLose_V / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp < -0.25 THEN HomeLose_V
				ELSE 0 END,
			FC_0x_V = CASE
				WHEN (livehomescore+liveawayscore) - hdp >  0.25 THEN AwayLose_V
				WHEN (livehomescore+liveawayscore) - hdp =  0.25 THEN AwayLose_V / 2
				WHEN (livehomescore+liveawayscore) - hdp = -0.25 THEN HomeLose_V / 2
				WHEN (livehomescore+liveawayscore) - hdp < -0.25 THEN HomeLose_V
				ELSE 0 END,
			--actual
			FC_p4_A = CASE
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_p3_A = CASE
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_p2_A = CASE
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_p1_A = CASE
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_p0_A = CASE
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_m1_A = CASE
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_m2_A = CASE
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_m3_A = CASE
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_m4_A = CASE
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_pX_A = CASE
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_mX_A = CASE
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose_A
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose_A / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose_A / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_00_A = CASE
				WHEN (@livehomescore+@LiveAwayScore) - hdp >  0.25 THEN AwayLose_A
				WHEN (@livehomescore+@LiveAwayScore) - hdp =  0.25 THEN AwayLose_A / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp = -0.25 THEN HomeLose_A / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp < -0.25 THEN HomeLose_A
				ELSE 0 END,
			FC_0x_A = CASE
				WHEN (livehomescore+liveawayscore) - hdp >  0.25 THEN AwayLose_A
				WHEN (livehomescore+liveawayscore) - hdp =  0.25 THEN AwayLose_A / 2
				WHEN (livehomescore+liveawayscore) - hdp = -0.25 THEN HomeLose_A / 2
				WHEN (livehomescore+liveawayscore) - hdp < -0.25 THEN HomeLose_A
				ELSE 0 END
	
	SELECT * FROM @FC
	ORDER BY
		liveindicator,
		livehomescore + liveawayscore,
		ABS(hdp) DESC,
		CASE status WHEN 'LOSE' THEN 1 WHEN 'WON' THEN 2 ELSE 3 END
END

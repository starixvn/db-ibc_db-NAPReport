/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

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
		- 20170612@Percy: check bettype of Cash Out [RedmineID: #73419]
*/

BEGIN
	SET NOCOUNT ON
	Declare @vScore smallmoney
	SET @vScore = NULL

	Declare @FC TABLE 
		(vScore smallint, liveindicator bit, status nvarchar(20), 
		hdp smallmoney, livehomescore smallint, liveawayscore smallint,
		HomeTotal money, AwayTotal money,
		AwayLose money, HomeLose money,
		BetCount int, Commission money, 
		FC_pX money, FC_p4 money, FC_p3 money, FC_p2 money, FC_p1 money, FC_p0 money,
		FC_m1 money, FC_m2 money, FC_m3 money, FC_m4 money, FC_mX money, FC_00 money, FC_0x money)

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

	IF EXISTS (SELECT matchid FROM bodb02.dbo.match WHERE matchid = @matchid)
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
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, HomeTotal, AwayTotal, AwayLose, HomeLose, BetCount, Commission)
			SELECT  x.liveindicator, x.status, x.hdp, livehomescore, liveawayscore,
				sum(x.hometotal * x.virtualrate) 'ht',
				sum(x.awaytotal * x.virtualrate) 'at',
				sum((x.homewin - x.awaylose) * x.virtualrate) 'al',
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(c) c,
				sum(x.comm * x.virtualrate) comm
			FROM 
				(select status, b.currency, hdp1 - hdp2 hdp, livehomescore, liveawayscore, liveindicator,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate
				from bodb02.dbo.bettrans b with(nolock)
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and b.custid >0 and status NOT IN ('VOID', 'REJECT')
				group by status, b.currency, hdp1 - hdp2, livehomescore, liveawayscore, liveindicator, b.virtualrate
				)x
		GROUP BY x.status, x.hdp, x.livehomescore, x.liveawayscore, x.liveindicator

		ELSE IF @bettype IN (3, 8)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, HomeTotal, AwayTotal, AwayLose, HomeLose, BetCount, Commission)
			SELECT x.liveindicator, x.status, x.hdp, x.livehomescore, x.liveawayscore, 
				sum(x.hometotal * x.virtualrate) 'ht',
				sum(x.awaytotal * x.virtualrate) 'at',
				sum((x.homewin - x.awaylose) * x.virtualrate) 'al',
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(c) c,
				sum(x.comm * x.virtualrate) comm
			FROM 
				(select liveindicator, status, b.currency, hdp1 hdp, livehomescore, liveawayscore,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate
				from bodb02.dbo.bettrans b with(nolock) 
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and custid > 0 and status NOT IN ('VOID', 'REJECT')
				group by liveindicator, status, b.currency, hdp1, livehomescore, liveawayscore, b.virtualrate
				)x
			group by x.status, liveindicator, x.hdp, x.livehomescore, x.liveawayscore
		

	END
	ELSE -- get from bettrans14
	BEGIN

		SELECT
			@FTHomeScore = FinalHomeScore,
			@FTAwayScore = FinalAwayScore,
			@HTHomeScore = HTHomeScore,
			@HTAwayScore = HTAwayScore
		FROM
			bodb02.dbo.match14
		WHERE
			matchid = @matchid

		IF @bettype IN (1, 7, 20)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, HomeTotal, AwayTotal, AwayLose, HomeLose, BetCount, Commission)
			SELECT  x.liveindicator, x.status, x.hdp, livehomescore, liveawayscore,
				sum(x.hometotal * x.virtualrate) 'ht',
				sum(x.awaytotal * x.virtualrate) 'at',
				sum((x.homewin - x.awaylose) * x.virtualrate) 'al',
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(c) c,
				sum(x.comm * x.virtualrate) comm
			FROM 
				(select status, b.currency, hdp1 - hdp2 hdp, livehomescore, liveawayscore, liveindicator,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate
				from bodb02.dbo.bettrans14 b with(nolock)
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and b.custid >0 and status NOT IN ('VOID', 'REJECT')
				group by status, b.currency, hdp1 - hdp2, livehomescore, liveawayscore, liveindicator, b.virtualrate
				)x
		GROUP BY x.status, x.hdp, x.livehomescore, x.liveawayscore, x.liveindicator

		ELSE IF @bettype IN (3, 8)
			INSERT INTO @FC (liveindicator, status, hdp, livehomescore, liveawayscore, HomeTotal, AwayTotal, AwayLose, HomeLose, BetCount, Commission)
			SELECT x.liveindicator, x.status, x.hdp, x.livehomescore, x.liveawayscore, 
				sum(x.hometotal * x.virtualrate) 'ht',
				sum(x.awaytotal * x.virtualrate) 'at',
				sum((x.homewin - x.awaylose) * x.virtualrate) 'al',
				sum((x.awaywin - x.homelose) * x.virtualrate) 'hl',
				sum(c) c,
				sum(x.comm * x.virtualrate) comm
			FROM 
				(select liveindicator, status, b.currency, hdp1 hdp, livehomescore, liveawayscore,
					sum(case when betteam='h' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) hometotal,
					sum(case when betteam='a' then case when abs(odds) > 1 then abs(odds) * stake else stake end * (1-b.tpositiontaking) else 0 end) awaytotal,	
					sum(case when betteam='h' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) homewin,
					sum(case when betteam='a' then (case when odds < 0 then 1 else odds end) * stake * (1-b.tpositiontaking) else 0 end) awaywin,
					sum(case when betteam='h' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) homelose,
					sum(case when betteam='a' then (case when odds < 0 then abs(odds) else 1 end)  * stake * (1-b.tpositiontaking) else 0 end) awaylose,
					sum(scomm) comm,
					count(*) c, b.virtualrate
				from bodb02.dbo.bettrans14 b with(nolock) 
				where bettype=@bettype AND liveindicator = @liveindicator
					and matchid = @matchid and custid > 0 and status NOT IN ('VOID', 'REJECT')
				group by liveindicator, status, b.currency, hdp1, livehomescore, liveawayscore, b.virtualrate
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
			FC_p4 = CASE
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore + 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_p3 = CASE
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore + 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_p2 = CASE
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore + 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_p1 = CASE
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore + 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_p0 = CASE
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_m1 = CASE
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - 1 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_m2 = CASE
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - 2 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_m3 = CASE
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - 3 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_m4 = CASE
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - 4 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_pX = CASE
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore + 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_mX = CASE
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) >  0.25 THEN AwayLose
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) =  0.25 THEN AwayLose / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) = -0.25 THEN HomeLose / 2
				WHEN @vScore - 1000 - (hdp + @factor*(livehomescore - liveawayscore)) < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_00 = CASE
				WHEN (@livehomescore+@LiveAwayScore) - hdp >  0.25 THEN AwayLose
				WHEN (@livehomescore+@LiveAwayScore) - hdp =  0.25 THEN AwayLose / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp = -0.25 THEN HomeLose / 2
				WHEN (@livehomescore+@LiveAwayScore) - hdp < -0.25 THEN HomeLose
				ELSE 0 END,
			FC_0x = CASE
				WHEN (livehomescore+liveawayscore) - hdp >  0.25 THEN AwayLose
				WHEN (livehomescore+liveawayscore) - hdp =  0.25 THEN AwayLose / 2
				WHEN (livehomescore+liveawayscore) - hdp = -0.25 THEN HomeLose / 2
				WHEN (livehomescore+liveawayscore) - hdp < -0.25 THEN HomeLose
				ELSE 0 END
	
	SELECT * FROM @FC
	ORDER BY
		liveindicator,
		livehomescore + liveawayscore,
		ABS(hdp) DESC,
		CASE status WHEN 'LOSE' THEN 1 WHEN 'WON' THEN 2 ELSE 3 END
END
GO
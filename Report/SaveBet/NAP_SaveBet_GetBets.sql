/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02;
GO

ALTER PROCEDURE [dbo].[NAP_SaveBet_GetBets] 
	@matchid int,
	@bettype smallint,
	@liveindicator bit,
	@IsDeposit tinyint,
	@Half tinyint
AS

/*
	Created by: Dom
	Date:2014-05-06
	Task: Get Bets Report 
	DB: DBACC.bodb02
	
	Revisions:
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20151001@Jim:support MO (Feature #41935)
		- 20160615@Jim: support to show TEAM statistic figures for Metric Gaming (HotFix #59341)
		- 20160810@Percy: return homeid, awayid [RedmineID: #53523]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20170323@Percy: return betid [RedmineID: #72900]
		- 20170612@Percy: check bettype of Cash Out [RedmineID: #78160]
		- 20180719@Tom:Enhance_the_flow_get_Virtual_Sport(98520)
		- 20190705@Robert - NAP Report - Incorporate new product PHAIO 4 (4a) (#116250)
		- 20201009@Jaden: Add betcheck column (#73598)
		- 20210329@Jaden: Savebet - Support to forecast the result with Real figures & Add some new information (#152290)
		- 20210423@Roy: NAP Report - Move Save bet db & service (#153147)
		- 202109001@Jaden: Add 2 more Dangerous types (#159779)
		- 20220321@Jaden: Cricket phase 2 - Save Bet (#170213)
		- 20221125@Roy: Defer Gen File After Match Complete (#180910)
		- 20221129@Roy: NAP Report - Save Bet Report out of memory (#180701)
		- 20230817@Roy: Exclude TestCurr due to invalid [virtualrate] (#192873)
		- 20230817@Dominic: Tuning performance
	
	Param's Explanation:
		@IsDeposit: seperate IsDeposit only for soccer. 1:Deposit; 0:Credit; 2: All match
		@Half: seperate Half only for soccer. 1:1st half; 2:2nd half; 0: All match
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @1HTime DATETIME
	IF @liveindicator = 0 AND @IsDeposit IN (0,1)--for Non-Live/Credit(Deposit)
	BEGIN
		SET @Half = 0 --ignore half -> get all deadball tickets
	END
	ELSE IF @IsDeposit IN (0,1) AND @Half IN (1,2)
	BEGIN
		SELECT @1HTime = DATEADD(MI, 45, MAX(ISNULL(kickofftime,GlobalShowTime)))
		FROM (
			SELECT kickofftime, GlobalShowTime
			FROM bodb02.dbo.match WITH(NOLOCK)
			WHERE matchid = @matchid
			
			UNION ALL
			
			SELECT kickofftime, GlobalShowTime
			FROM bodb02.dbo.match14 WITH(NOLOCK)
			WHERE matchid = @matchid
		) m
	END
	ELSE
	BEGIN
		SET @IsDeposit = 2
		SET @Half = 0
	END
	
	-- original is Dot_Admin_cteamlist
	DECLARE @isTest BIT= 0
	SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID)
	 
	CREATE TABLE #MetricBettype (bettype INT)
	INSERT INTO #MetricBettype (bettype)
	SELECT  DISTINCT Bettype
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '',@isTest)
	where subproduct='MG-SuperLive'

	CREATE UNIQUE CLUSTERED INDEX CX_Bettype ON #MetricBettype (Bettype)

	IF @bettype IN (901,902,903,904)
	BEGIN 
		SELECT N'This report does not support bettrade ticket!'
		RETURN
	END 

	IF @bettype IN (911,912,913,914)
	BEGIN 
		SELECT N'This report does not support cash out ticket!'
		RETURN
	END 

	DECLARE @homeid INT
	,@awayid INT
	,@EventDate DATETIME
	,@MoveBetsDay DATETIME

	---Get MoveBetsDay---
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC, 'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
	---Get match info---
	;WITH cte_match
	AS (
		SELECT eventdate
			,homeid
			,awayid
		FROM bodb02.dbo.match WITH (NOLOCK)
		WHERE matchid = @matchid
		
		UNION
		
		SELECT eventdate
			,homeid
			,awayid
		FROM bodb02.dbo.match14 WITH (NOLOCK)
		WHERE matchid = @matchid
	)
	SELECT @homeid = MAX(homeid)
		,@awayid = MAX(awayid)
		,@EventDate = MAX(eventdate)
	FROM cte_match
	
	CREATE TABLE #abnormalOrRobotUsers (custid int, [type] varchar(10))

	INSERT INTO #abnormalOrRobotUsers (custid, [type])
	SELECT ISNULL(b.custid, a.custid) custid, 
		RTRIM(LTRIM(ISNULL('(' +b.t+ ')', '') + ' ' + ISNULL('(' +a.t+ ')', ''))) [type]
	FROM (SELECT custid, 'R' t FROM DBONUSER.ON_USER.dbo.robotusers WITH(NOLOCK) WHERE [counter] > 10) a
		FULL OUTER LOOP JOIN (SELECT custid, 'A' t FROM DBONUSER.ON_USER.dbo.AbnormalUsers WITH(NOLOCK) WHERE flags = 4) b
			ON a.custid = b.custid
	WHERE a.custid IS NOT NULL OR b.custid IS NOT NULL

	CREATE UNIQUE CLUSTERED INDEX CX_CustID ON #abnormalOrRobotUsers (CustID)

	---Get data from bettrans---
	IF @EventDate > @MoveBetsDay
	BEGIN
		SELECT
			0 positiontaking, 
			0 comm,
			0 awinlost,
			b.livehomescore, 
			b.liveawayscore,
			CASE
				WHEN b.status = 'reject' THEN '(reject) ' + cr.username
				WHEN b.status = 'void' THEN '(void) ' + cr.username
				WHEN b.custid <> b.creator THEN cr.username
				ELSE '' END creator, 
			b.username,
			b.odds, 
			b.CurrencyName Currency, 
			b.stake,
			b.hdp1,
			b.hdp2, 
			b.transdate, 
			b.transid, 
			betcheck, 
			CASE WHEN ISNULL(t.bettype,0)<> 0 THEN b.transdesc ELSE  b.betteam  END betteam ,
			b.betfrom
			,b.stake * (1- b.tpositiontaking) cpstake
			,CAST(b.actualrate as DECIMAL(9,6)) actualrate
			,CAST(b.virtualrate as DECIMAL(9,6)) virtualrate
			,b.oddsspread
			,@homeid homeid
			,@awayid awayid
			,b.betid
			,b.betcheck

			,CASE WHEN dep.CustID IS NULL THEN 'C' ELSE 'L' END as [site] --credit / lisencee
			,ar.type as [bot]
			,REPLACE(LTRIM(RTRIM(
				CASE WHEN ci.danger > 0 THEN 'Ori@' + cast(ci.danger as varchar(3)) ELSE '' END
				+ CASE WHEN ci.danger2 > 0 THEN ' ABI@' + cast(ci.danger2 as varchar(3)) ELSE '' END
				+ CASE WHEN ci.danger4 > 0 THEN ' Basket@' + cast(ci.danger4 as varchar(3)) ELSE '' END 
				+ CASE WHEN ci.danger5 > 0 THEN ' E-Sport@' + cast(ci.danger5 as varchar(3)) ELSE '' END 
				+ CASE WHEN ci.danger3 > 0 THEN ' O.Sport@' + cast(ci.danger3 as varchar(3)) ELSE '' END 
			)), ' ', ', ') [dgr]
			,ci.CustomerClass as [CC]
			,bi.OriginalOdds as [ori.odds]
			,CASE 
			WHEN ISNULL(b.actualrate, 0) = 0 THEN 0 
			ELSE Round(((b.virtualrate - b.actualrate) / b.actualrate) * 100, 0) END as [var]
			,CASE
			WHEN b.bettype IN (1, 3) and agent.site = '76666B' THEN b.oddsspread
			ELSE NULL END as '%'
			,tm.teamname
		FROM
			bodb02.dbo.bettrans b with (nolock)	
			INNER JOIN bodb02.dbo.customer cr with (nolock) ON b.creator = cr.custid
			LEFT JOIN #MetricBettype t ON b.bettype = t.bettype	
			INNER JOIN bodb02.dbo.customer agent with (nolock) ON b.recommend = agent.custid
			LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) ON cr.srecommend = dep.CustId
			LEFT LOOP JOIN #abnormalOrRobotUsers ar ON b.custid = ar.custid
			INNER JOIN bodb02.dbo.custInfo ci WITH (NOLOCK) ON b.custid = ci.custid
			LEFT JOIN bodb02.dbo.BettransInfo bi WITH (NOLOCK) ON b.transid = bi.transid
			LEFT JOIN bodb02.dbo.team tm WITH (NOLOCK) 
				ON CASE WHEN ISNUMERIC(REPLACE(b.transdesc, ' ', '')) = 1 /*ISNUMERIC('123,456') => 1*/
					THEN
						CASE WHEN CHARINDEX(',', b.transdesc) = 0 THEN b.transdesc
				 			ELSE LEFT(b.transdesc, ISNULL(CHARINDEX(',', b.transdesc) - 1, 0))
				 		END
					ELSE NULL END = tm.teamid
			LEFT JOIN bodb02.dbo.Dep_CustSuper AS d WITH (NOLOCK) ON b.srecommend = d.custid
		WHERE b.matchid = @matchid 
			AND b.bettype = @bettype
			AND b.liveindicator = @liveindicator
			AND (@IsDeposit NOT IN (0,1) OR @IsDeposit = (CASE WHEN d.custid IS NULL THEN 0 ELSE 1 END))
			AND (@Half NOT IN (1,2) OR @Half = (CASE WHEN b.transdate <= @1HTime THEN 1 ELSE 2 END))
			AND b.currency <> 20
		ORDER BY b.betteam, b.transid
		OPTION(RECOMPILE, USE HINT('DISALLOW_BATCH_MODE'))
	END
	ELSE ---Get data from bettrans14---
	BEGIN
		SELECT
			0 positiontaking, 
			0 comm,
			0 awinlost,
			b.livehomescore, 
			b.liveawayscore,
			CASE
				WHEN b.status = 'reject' THEN '(reject) ' + cr.username
				WHEN b.status = 'void' THEN '(void) ' + cr.username
				WHEN b.custid <> b.creator THEN cr.username
				ELSE '' END creator, 
			b.username,
			b.odds, 
			b.currencyname Currency, 
			b.stake,
			b.hdp1,
			b.hdp2, 
			b.transdate, 
			b.transid, 
			betcheck, 
			CASE WHEN ISNULL(t.bettype,0)<> 0 THEN b.transdesc ELSE  b.betteam  END betteam ,
			b.betfrom
			,b.stake * (1- b.tpositiontaking) cpstake
			,CAST(b.actualrate as DECIMAL(9,6)) actualrate
			,CAST(b.virtualrate as DECIMAL(9,6)) virtualrate
			,b.oddsspread
			,@homeid homeid
			,@awayid awayid
			,b.betid
			,b.betcheck

			,CASE WHEN dep.CustID IS NULL THEN 'C' ELSE 'L' END as [site] --credit / lisencee
			,ar.type as [bot]
			,REPLACE(LTRIM(RTRIM(
				CASE WHEN ci.danger > 0 THEN 'Ori@' + cast(ci.danger as varchar(3)) ELSE '' END
				+ CASE WHEN ci.danger2 > 0 THEN ' ABI@' + cast(ci.danger2 as varchar(3)) ELSE '' END
				+ CASE WHEN ci.danger4 > 0 THEN ' Basket@' + cast(ci.danger4 as varchar(3)) ELSE '' END 
				+ CASE WHEN ci.danger5 > 0 THEN ' E-Sport@' + cast(ci.danger5 as varchar(3)) ELSE '' END 
				+ CASE WHEN ci.danger3 > 0 THEN ' O.Sport@' + cast(ci.danger3 as varchar(3)) ELSE '' END 
			)), ' ', ', ') [dgr]
			,ci.CustomerClass as [CC]
			,bi.OriginalOdds as [ori.odds]
			,CASE 
			WHEN ISNULL(b.actualrate, 0) = 0 THEN 0 
			ELSE Round(((b.virtualrate - b.actualrate) / b.actualrate) * 100, 0) END as [var]
			,CASE
			WHEN b.bettype IN (1, 3) and agent.site = '76666B' THEN b.oddsspread
			ELSE NULL END as '%'
			,tm.teamname
		FROM
			bodb02.dbo.bettrans14 b with (nolock)	
			INNER JOIN bodb02.dbo.customer cr with (nolock) ON b.creator = cr.custid
			LEFT JOIN #MetricBettype t ON b.bettype = t.bettype	
			INNER JOIN bodb02.dbo.customer agent with (nolock) ON b.recommend = agent.custid
			LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) ON cr.srecommend = dep.CustId
			LEFT LOOP JOIN #abnormalOrRobotUsers ar ON b.custid = ar.custid
			INNER JOIN bodb02.dbo.custInfo ci WITH (NOLOCK) ON b.custid = ci.custid
			LEFT JOIN bodb02.dbo.BettransInfo14 bi WITH (NOLOCK) ON b.transid = bi.transid
			LEFT JOIN bodb02.dbo.team tm WITH (NOLOCK) 
				ON CASE WHEN ISNUMERIC(REPLACE(b.transdesc, ' ', '')) = 1 /*ISNUMERIC('123,456') => 1*/
					THEN
						CASE WHEN CHARINDEX(',', b.transdesc) = 0 THEN b.transdesc
				 			ELSE LEFT(b.transdesc, ISNULL(CHARINDEX(',', b.transdesc) - 1, 0))
				 		END
					ELSE NULL END = tm.teamid
			LEFT JOIN bodb02.dbo.Dep_CustSuper AS d WITH (NOLOCK) ON b.srecommend = d.custid
		WHERE b.winlostdate = @EventDate
			AND b.matchid = @matchid 
			AND b.bettype = @bettype
			AND b.liveindicator = @liveindicator
			AND (@IsDeposit NOT IN (0,1) OR @IsDeposit = (CASE WHEN d.custid IS NULL THEN 0 ELSE 1 END))
			AND (@Half NOT IN (1,2) OR @Half = (CASE WHEN b.transdate <= @1HTime THEN 1 ELSE 2 END))
			AND b.currency <> 20
		ORDER BY b.betteam, b.transid
		OPTION(RECOMPILE, USE HINT('DISALLOW_BATCH_MODE'))
	END
	DROP TABLE #abnormalOrRobotUsers
	DROP TABLE #MetricBettype
END


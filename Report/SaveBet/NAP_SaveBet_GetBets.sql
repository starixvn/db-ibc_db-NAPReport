/*<info serverAlias="DBACC-bodb_ACC" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_ACC]
GO

ALTER PROCEDURE [dbo].[NAP_SaveBet_GetBets] 
	@matchid int,
	@bettype smallint,
	@liveindicator bit
AS

/*
	Created by: Dom
	Date:2014-05-06
	Task: Get Bets Report 
	DB: DBACC.bodb_ACC
	
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
*/

-- original is Dot_Admin_cteamlist
	DECLARE @isTest BIT= 0;
    SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	 
	DECLARE @MetricBettype AS TABLE (bettype INT)
	INSERT INTO @MetricBettype (bettype)
	SELECT  DISTINCT
         Bettype
	FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '',@isTest)
	where subproduct='MG-SuperLive'

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

DECLARE @homeid INT, @awayid INT,@EventDate SMALLDATETIME
SELECT  @homeid = homeid, @awayid = awayid FROM bodb02.dbo.match WITH(NOLOCK) WHERE matchid = @matchid

IF @homeid IS NOT NULL
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
	FROM 
	bodb02.dbo.bettrans b with (nolock)	
	INNER JOIN bodb02.dbo.customer cr with (nolock) ON b.creator = cr.custid
	LEFT JOIN @MetricBettype t ON b.bettype = t.bettype	
	WHERE
		b.matchid = @matchid 
		AND b.bettype = @bettype
		AND b.liveindicator = @liveindicator
	ORDER BY b.betteam, b.transid
END
ELSE
BEGIN
	SELECT  @homeid = homeid, @awayid = awayid,@EventDate = eventdate FROM bodb02.dbo.match14 WITH(NOLOCK) WHERE matchid = @matchid
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
	FROM 
	bodb02.dbo.bettrans14 b with (nolock)	
	INNER JOIN bodb02.dbo.customer cr with (nolock) ON b.creator = cr.custid
	LEFT JOIN @MetricBettype t ON b.bettype = t.bettype	
	WHERE b.winlostdate = @EventDate
		AND b.matchid = @matchid 
		AND b.bettype = @bettype
		AND b.liveindicator = @liveindicator
	ORDER BY b.betteam, b.transid
END
GO
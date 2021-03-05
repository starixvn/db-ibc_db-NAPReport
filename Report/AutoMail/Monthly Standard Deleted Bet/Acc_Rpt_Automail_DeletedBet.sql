/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_DeletedBet]
	@FromDate    DATE,
	@ToDate      DATE
AS
/*
    Created	: 20210305@Cherry
	Task	: Monthly Standard Deleted Bet (#151160)
	DB		: DBACC/bodb02
	
	Revision:		
		20210305@Cherry: Initial (convert from script adhoc #151160 to SP)


	Param's Explanation:
*/ 
BEGIN
	CREATE table #BU (BalanceUpDay date, MovebetsDay date)
	INSERT INTO #bu(BalanceUpDay, MovebetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	DECLARE @BalanceUpDay DATE, @rptdate DATE
	SELECT @BalanceUpDay =(SELECT BalanceUpDay FROM #BU)

	CREATE TABLE #tmp_data (
		rptdate DATE,
		transid BIGINT,
		liveindicator INT,
		bettype INT,
		betteam NVARCHAR(10),
		custid INT,
		sporttype INT,
		creator INT,
		homeid INT,
		awayid INT,
		transdesc NVARCHAR (200),
		betcount INT,
		memberTO MONEY,
		VirtualTO MONEY,
		VarianceTO MONEY,
		RealTO MONEY)


	--bettrans data-------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO #tmp_data
	SELECT 	winlostdate
		,transid
		,liveindicator
		,bettype
		,betteam
		,mc.custid
		,m.sporttype
		,mc.creator
		,m.homeid
		,m.awayid
		,transdesc
		,1 as [betcount]
		,abs(stake)* mc.virtualrate
		, ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0) ) * mc.virtualrate VirtualTO
		, ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * ABS(virtualrate - actualrate) VarianceTO
		, ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * CASE WHEN mc.virtualrate > actualrate THEN mc.virtualrate ELSE actualrate END RealTO
	FROM bodb02.dbo.bettrans mc WITH (NOLOCK)
		INNER JOIN bodb02.dbo.match m WITH (NOLOCK) ON mc.matchid=m.matchid and m.sporttype>1
	WHERE  winlostdate <= @Todate
		AND mc.statusid = 102--void
		AND mc.currency <> 20

	--Bettrans14 data-------------------------------------------------------------------------------------------------------------------------------------------------

	INSERT INTO #tmp_data
	SELECT 	winlostdate
		,transid
		,liveindicator
		,bettype
		,betteam
		,mc.custid
		,m.sporttype
		,mc.creator
		,m.homeid
		,m.awayid
		,transdesc
		,1 as [betcount]
		,ABS(stake)* mc.virtualrate stake
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * mc.virtualrate VirtualTO
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * ABS(virtualrate - actualrate) VarianceTO
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * CASE WHEN mc.virtualrate > actualrate THEN mc.virtualrate ELSE actualrate END RealTO
	FROM bodb02.dbo.bettrans14 mc WITH (NOLOCK)
		INNER JOIN bodb02.dbo.match14 m WITH (NOLOCK) ON mc.matchid = m.matchid and m.sporttype > 1
	WHERE winlostdate >= @BalanceUpDay
		AND mc.statusid = 102--void
		AND mc.currency <> 20

	-- Bettrans_BK data-------------------------------------------------------------------------------------------------------------------------------------------------

	SELECT matchid,leagueid,homeid,awayid,sporttype 
	INTO #tmpmatch 
	FROM bodb_archive.dbo.match_bk WITH(NOLOCK)
	WHERE eventdate >= @Fromdate AND sporttype > 1

	SELECT @rptdate = @Fromdate

	WHILE @rptdate < @BalanceUpDay
	BEGIN

	INSERT INTO #tmp_data
	SELECT 	winlostdate
		,transid
		,liveindicator
		,bettype
		,betteam
		,mc.custid
		,m.sporttype
		,mc.creator
		,m.homeid
		,m.awayid
		,transdesc
		,1 as [betcount]
		,ABS(stake)* mc.virtualrate stake
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0) ) * mc.virtualrate VirtualTO
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * ABS(virtualrate - actualrate) VarianceTO
		,ABS(Stake) * (1 - tpositiontaking - ISNULL(mc.epositiontaking,0)) * CASE WHEN mc.virtualrate > actualrate THEN mc.virtualrate ELSE actualrate END RealTO
	FROM bodb_archive.dbo.bettrans_bk mc WITH(NOLOCK)
		INNER JOIN #tmpmatch m ON mc.matchid = m.matchid
	WHERE winlostdate = @rptdate
		and mc.statusid = 102--void
		and mc.currency <> 20

	SELECT @rptdate = DATEADD(DAY,1,@rptdate)

	END 

	--Select data------------------------------------------------------------------------------------------------------------------------------
	SELECT CONVERT(VARCHAR(10), Year(rptDate)) + '-' + CONVERT(VARCHAR(10), RIGHT('0' + RTRIM(MONTH(rptDate)), 2)) AS Monthly
		,CAST(rptDate as DATE) 'Winlossdate'
		,s.SportName
		,cu.username 'Customer'
		, bt.typenamee 'Bettype'
		,CASE
				WHEN b.bettype in (1,7,17,20,21) or bt.typenamee like '%Handicap%' or bt.typenamee like '%Moneyline%' or bt.typenamee like '%Cash Out%' THEN 
									   CASE
									   WHEN betteam = 'h' THEN t1.teamname
									   WHEN betteam = 'a' THEN t2.teamname
									   ELSE betteam
									   END
				WHEN b.bettype in (2,12,184) THEN 
									   CASE
									   WHEN betteam = 'h' THEN 'Odd'
									   WHEN betteam = 'a' THEN 'Even'
									   END
				WHEN b.bettype in (3,8,18) THEN 
									   CASE
									   WHEN betteam = 'h' THEN 'Over'
									   WHEN betteam = 'a' THEN 'Under'
									   END
			  
				WHEN b.bettype = 413 THEN 
									   CASE
									   WHEN betteam = 'aos' THEN b.transdesc
									   ELSE betteam
									   END
				WHEN bt.typenamee like '%Over/Under%' THEN 
									   CASE
									   WHEN betteam = 'o' THEN 'Over'
									   WHEN betteam = 'u' THEN 'Under'
									   END
				WHEN b.bettype = 28 THEN betteam
				WHEN betteam = 'h' THEN t1.teamname	
				WHEN betteam = 'a' THEN t2.teamname		   
				ELSE betteam					   	 
		 END [BetChoice]
		,SUM(b.memberTO) AS [TurnoverMember]
		,SUM(realTO) RealTO
		,SUM(virtualTO) VirtualTO
		,SUM(VarianceTO) VarianceTO
		,SUM(b.betcount) BetCount
		,CASE 
			   WHEN liveindicator = 0 THEN 'Non-Live'
			   WHEN liveindicator = 1 THEN 'Live'
			   ELSE 'Live & Non-Live'
			   END [Live]
		,ISNULL(t1.teamname + ' vs ' + t2.teamname,'Combine Parlay Match') [Match]	
		,cu1.username 'creator'	
		,tr.ReasonEnglish
	FROM #tmp_data b WITH (NOLOCK)
		INNER JOIN bodb02.dbo.[TicketVoiding_VoidedTransaction] tv WITH (NOLOCK) ON b.transid = tv.TransId
		LEFT JOIN (SELECT reasonid, replace(ReasonEnglish,char(10),' ') as ReasonEnglish FROM DBTP.bodb02.dbo.TicketVoiding_Reason WITH (NOLOCK)) tr ON tr.ReasonId=tv.ReasonId
		LEFT JOIN bodb02.dbo.Sports s WITH (NOLOCK) ON s.SportType=b.sporttype 
		LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK) ON bt.typeid=b.bettype  
		LEFT JOIN bodb02.dbo.vw_Customer cu WITH (NOLOCK) ON cu.custid=b.custid  
		LEFT JOIN bodb02.dbo.vw_Customer cu1 WITH (NOLOCK) ON cu1.custid=b.creator  
		LEFT JOIN bodb02.dbo.team t1 WITH (NOLOCK)  ON b.homeid = t1.teamid
		LEFT JOIN  bodb02.dbo.team t2 WITH(NOLOCK)  ON b.awayid = t2.teamid
	GROUP BY CONVERT(VARCHAR(10), Year(rptDate)) + '-' + CONVERT(VARCHAR(10), RIGHT('0' + RTRIM(MONTH(rptDate)), 2)) 
		,rptDate
		,s.SportName
		,cu.username 
		, bt.typenamee 
		,CASE
				WHEN b.bettype in (1,7,17,20,21) or bt.typenamee like '%Handicap%' or bt.typenamee like '%Moneyline%' or bt.typenamee like '%Cash Out%' THEN 
									   CASE
									   WHEN betteam = 'h' THEN t1.teamname
									   WHEN betteam = 'a' THEN t2.teamname
									   ELSE betteam
									   END
				WHEN b.bettype in (2,12,184) THEN 
									   CASE
									   WHEN betteam = 'h' THEN 'Odd'
									   WHEN betteam = 'a' THEN 'Even'
									   END
				WHEN b.bettype in (3,8,18) THEN 
									   CASE
									   WHEN betteam = 'h' THEN 'Over'
									   WHEN betteam = 'a' THEN 'Under'
									   END
			  
				WHEN b.bettype=413 THEN 
									   CASE
									   WHEN betteam = 'aos' THEN b.transdesc
									   ELSE betteam
									   END
				WHEN bt.typenamee like '%Over/Under%' THEN 
									   CASE
									   WHEN betteam = 'o' THEN 'Over'
									   WHEN betteam = 'u' THEN 'Under'
									   END
				WHEN b.bettype = 28 THEN betteam	
				WHEN betteam = 'h' THEN t1.teamname	
				WHEN betteam = 'a' THEN t2.teamname					   
				ELSE betteam
				END
		,CASE 
			   WHEN liveindicator = 0 THEN 'Non-Live'
			   WHEN liveindicator = 1 THEN 'Live'
			   ELSE 'Live & Non-Live'
			   END 
		,ISNULL(t1.teamname + ' vs ' + t2.teamname,'Combine Parlay Match') 
		,cu1.username 
		,tr.ReasonEnglish

	DROP TABLE #BU
	DROP TABLE #tmp_data
	DROP TABLE #tmpmatch
	
END  
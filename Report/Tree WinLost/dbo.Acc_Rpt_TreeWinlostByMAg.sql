USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_TreeWinlostByMAg]
	@FromDate   DATETIME,
	@ToDate   DATETIME,  
	@mrecommend INT,	
	@Products VARCHAR(4000) -- instead of all @showXXX parameters

AS

/*  
Created by: Scott  
Date: 2012-12-14 
Task : Report Tree Win Lost  
DB: DBACC.bodb02  
Original SP:   
Revisions:  
	-20130115@Scott : fix bug sum total of poker sporttype
	-20130418@Scott : Update formula turnover of Racing
	-20130702@Dom.Cao: Add Vanriance (+\-)
	-20140304@TomVo: 
		Change Name Server (DB06) to Alias Server (DBACC)
		Add Keno Sport (202) -Bettype : 1501 - 1599
	- 20151226@Johnson: Separate virtual rate by sporttype, bettype [Redmine: #25840]	
	- 20150529@Jim: add more parameter @ShowGD,@ShowMGSL and apply sport-bettype matrix 	
	- 20150710@Jim: Super Balance fix and Microgaming integration (Feature #38168)	
	- 20150723@Jim: Apply Bettrade [#38815]			
	- 20150828@Jim: support Colossus Bet (#42608)
	- 20151110@Billy : Change to new Virtual Rate structure - [Redmine: #47355]
	- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	- 20151214@Percy: 1. Add new product: Cockfighting [Redmine: #49027]
					  2. Change input parameters
	- 20160118@Percy: Calculate turnover for RNG Casino [Redmine: #49134]
	- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
	- 20160615@Sophia: Change READPAST to ROWLOCK because of the Deadlock [Redmind: #59254]
	- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
*/  

SET NOCOUNT ON

--DECLARE @TmpCondBettype TABLE(bettype INT , isVirtual BIT) 
DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)  
DECLARE @CommSetting TABLE (MatchID int, IBCFee bit, ToteCommWin smallmoney, ToteCommPlace smallmoney, ToteCommWP smallmoney, ToteFee smallmoney )


CREATE TABLE #TmpResult (recommend INT ,
						actualrate FLOAT,
						Turnover MONEY, 
						Winloss MONEY,
						Commission MONEY)
CREATE TABLE #TmpResultAll (recommend INT ,
							VirtualRateType INT,
							Turnover MONEY, 
							Winloss MONEY,
							Commission MONEY,
							Total MONEY,
							TurnoverRM MONEY,
							TurnoverIBCVirtual MONEY,
							TotalRM MONEY,
							Virtual_Total MONEY)

DECLARE @isTest BIT= 0;
SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
DECLARE @SportBettype TABLE(ProductID INT,Bettype INT,EventType INT,SubProduct VARCHAR(200))
INSERT INTO @SportBettype
    SELECT ProductID,
              Bettype,
              EventType,
              SubProduct
    FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);

IF OBJECT_ID('tempdb..#Product') IS NOT NULL
BEGIN
	DROP TABLE #Product
END

CREATE TABLE #Product (ProductID INT,IsNoTurnover BIT,IsNoVirtual BIT)
	
DECLARE @DocHandler INT

BEGIN TRY
	EXEC sp_xml_preparedocument @DocHandler OUTPUT
		,@Products

	INSERT INTO #Product (
		ProductID
		,IsNoTurnover
		,IsNoVirtual
		)
	SELECT ProductID
		,IsNoTurnover
		,IsNoVirtual
	FROM OPENXML(@DocHandler, '/ROOT/Product', 1) WITH (ProductID [int], IsNoTurnover BIT, IsNoVirtual BIT) AS Data

	EXEC sp_xml_removedocument @DocHandler
END TRY

BEGIN CATCH
	SELECT ErrCode = 100
		,ErrMsg = N'Paramter invalid.'

	RETURN
END CATCH;

IF OBJECT_ID('tempdb..#tmpBettype') IS NOT NULL
BEGIN
	DROP TABLE #tmpBettype
END

CREATE TABLE #tmpBettype (ProductID int, bettype int, IsNoTurnover bit, IsNoVirtual bit)

IF EXISTS (SELECT TOP 1 1 FROM #Product P WHERE p.ProductID = - 1)
BEGIN
	;WITH tblP (ProductID,IsNoTurnover,IsNoVirtual)
	AS (
		SELECT 1 ProductID,IsNoTurnover,IsNoVirtual
		FROM #Product tblP
		WHERE tblP.ProductID = - 1
		)
	INSERT INTO #tmpBettype (
		ProductID
		,bettype
		,IsNoTurnover
		,IsNoVirtual
		)
	SELECT  tblS.ProductID
		,tblS.bettype
		,tblP.IsNoTurnover
		,tblP.IsNoVirtual
	FROM tblP
		,@SportBettype tblS
	WHERE tblS.ProductID = 1
		AND tblS.SubProduct IN ('MG-SuperLive')
END

IF EXISTS (SELECT TOP 1 1 FROM #Product P WHERE p.ProductID = 1)
BEGIN
	INSERT INTO #tmpBettype (ProductID,bettype,IsNoTurnover,IsNoVirtual)
	SELECT  tblP.ProductID,tblS.bettype
		,tblP.IsNoTurnover
		,tblP.IsNoVirtual
	FROM @SportBettype tblS
		INNER JOIN #Product tblP ON tblS.ProductID = tblP.ProductID
	WHERE tblP.ProductID = 1
		AND tblS.SubProduct NOT IN ('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss')
END

INSERT INTO #tmpBettype (
	ProductID
	,bettype
	,IsNoTurnover
	,IsNoVirtual
	)
SELECT  tblP.ProductID
	,tblS.bettype
	,tblP.IsNoTurnover
	,tblP.IsNoVirtual
FROM @SportBettype tblS
	INNER JOIN #Product tblP ON tblS.ProductID = tblP.ProductID
WHERE tblP.ProductID <> 1
		
CREATE CLUSTERED INDEX IDX_Bettype_bettype_ProductID ON #tmpBettype(bettype,ProductID)	
	
--IF @winlostdate > @MoveBetDays
--BEGIN

--get result for Horse Racing
	IF EXISTS (SELECT TOP 1 1 FROM #tmpBettype WHERE ProductID = 2)
	--IF @ShowRB=1
	BEGIN
	
		INSERT INTO @tmpIBCFee (partnerID, IBCFee)  
		SELECT 1,1 --RACE-PHU
	UNION ALL
		SELECT 2,0 --RACE-ATRUK
	UNION ALL
		SELECT 3,0 --RACE-ATRIRL
	UNION ALL
		SELECT 4,0 --RACE-RUK
	UNION ALL
		SELECT 5,1 --RACE-TABCORP
	UNION ALL
		SELECT 6,1 --RACE-TABCORPNSW
	UNION ALL
		SELECT 101,1 --GREY-DTOTEUK
	UNION ALL
		SELECT 102,1 --GREY-DTOTEIRL
	UNION ALL
		SELECT 103,1 --GREY-TABCORP
	UNION ALL
		SELECT 104,1 --GREY-TABCORPNSW
	UNION ALL
		SELECT 201,1 --HAR-TABCORP
	UNION ALL
		SELECT 202,1 --HAR-TABCORPNSW

		INSERT INTO @CommSetting (MatchID, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)  
		SELECT DISTINCT o.orid as matchid, t.IBCFee, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee   
		FROM outright o WITH (NOLOCK)  
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.leagueID and p.programDate = o.programDate  
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid  
			INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID  
		WHERE o.eventdate BETWEEN @FromDate AND @ToDate
		
		INSERT INTO #TmpResult
		SELECT b.recommend,
			b.actualrate,  
			-- SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,  
			sum(case when bettype = 33 then bm.TOIBC else b.actual_stake*isnull(oddsspread,0) end) Turnover,
			-(  
			sum((case when bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)) -- PTWLIBC,   
			- sum(case when cs.IBCFee = 0 then 0 else  
			(case when b.bettype = 33 then bm.TOPhum   
			when b.bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(oddsspread,0)) else 0 end)*cs.ToteFee end) -- FeeDue2 ,  
			+ sum((case bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))  
			when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))  
			when 33 then bm.TOPhum*cs.ToteCommWP   
			else 0 end))-- commIncomeIBC  
			) Winloss,  
			SUM(scomm) Commission	
		FROM bettrans b with (NOLOCK)  
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
			--INNER JOIN custinfo cii WITH(NOLOCK) ON b.recommend = cii.custid   
			LEFT JOIN ( select refno,
							sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,    
							-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,  
							sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore<>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum  
						from bettransm with (nolock)  
						group by refno  
					)bm on b.transid = bm.refno   
		WHERE b.ruben =1   
			and b.bettype in (SELECT bettype FROM @SportBettype WHERE ProductID = 2)    
			and b.matchid >0  
			and b.winlostdate BETWEEN @FromDate AND @ToDate
			and b.statusID not in (101,102,103,121) 
			and b.currency <> 20
			and b.mrecommend = @mrecommend
		GROUP BY b.recommend,
				b.actualrate
				
 
 
		INSERT INTO #TmpResultAll
		SELECT recommend,
			0 VirtualRateType,
			SUM(Turnover), 
			SUM(Winloss),
			SUM(Commission),
			SUM(Winloss+Commission) Total,
			SUM(Turnover*actualrate) TurnoverRM,
			SUM(Turnover*actualrate) TurnoverIBCVirtual,
			SUM( (Winloss+Commission)*actualrate ) TotalRM,
			SUM( (Winloss+Commission)*actualrate ) Virtual_Total 
			
		FROM #TmpResult
		GROUP BY recommend
	END
	
---get result for PORKER	
	IF EXISTS (SELECT TOP 1 1 FROM #tmpBettype WHERE ProductID = 9)	
	--IF @showP2P = 1   
	BEGIN
		
		DELETE #TmpResult
		
		INSERT INTO	#TmpResult
		SELECT b.recommend,
			b.actualrate,
			0 Turnover,
			isnull(sum(-1*(odds)),0)  Winlost,   
			SUM(scomm) commission
		from bettrans b with (NOLOCK)  
			--INNER JOIN custinfo cs WITH(NOLOCK) ON b.recommend = cs.custid   
		where b.bettype IN( SELECT bettype FROM @SportBettype WHERE ProductID = 9)
			and b.matchid = 1000   
			and b.ruben=1    
			and b.winlostdate BETWEEN @FromDate AND @ToDate
			and statusID NOT in (101,102,103,121)  
			and b.currency <> 20
			and b.mrecommend = @mrecommend
		GROUP BY b.recommend,
			b.actualrate
			
		
		
		INSERT INTO #TmpResultAll
		SELECT recommend,
			0 VirtualRateType,  
			0  Turnover, 
			SUM(Winloss),
			SUM(Commission),
			SUM(Winloss+Commission) Total,
			0 TurnoverRM,
			0 TurnoverIBCVirtual,
			SUM( (Winloss+Commission)*actualrate ) TotalRM,
			SUM( (Winloss+Commission)*actualrate ) Virtual_Total 
		FROM #TmpResult
		GROUP BY recommend
	END

---get data from bettransRNG	
	BEGIN
		INSERT INTO #TmpResultAll
		SELECT b.recommend,
			 CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
			 SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
			 SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,
			 SUM(scomm) commission,  
			 SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total, 
			 SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
			 SUM(ABS(stake)*(1 - tpositiontaking)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) TurnoverIBCVirtual,
			 SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM	,
			 SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) Virtual_Total
		FROM bettransRNG b WITH(ROWLOCK) 
			INNER JOIN #tmpBettype t ON t.bettype = b.gameID 
		WHERE winlostdate BETWEEN @FromDate AND @ToDate
		AND t.ProductID IN (6, 17, 22, 24)
		   AND b.statusID NOT IN (0, 1, 101, 102, 103)   
		   and b.currency <> 20
		   and b.mrecommend = @mrecommend
		GROUP BY b.recommend ,
			CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END  

	END
------------------------------


INSERT INTO #TmpResultAll
SELECT b.recommend,
	CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
	SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
	SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,
	SUM(scomm) commission,  
	SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total, 
	SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
	SUM(ABS(stake)*(1 - tpositiontaking)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) TurnoverIBCVirtual,
	SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM	,
	SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) Virtual_Total
FROM bettrans b WITH(ROWLOCK) 
	INNER JOIN #tmpBettype t ON t.bettype = b.bettype 	
WHERE winlostdate BETWEEN @FromDate AND @ToDate
    AND t.ProductID NOT IN (2, 6, 9, 17, 21, 22, 24)
    and b.ruben = 1  
    AND b.statusID NOT IN (101, 102, 103)   
    and b.currency <> 20
    and b.mrecommend = @mrecommend
GROUP BY b.recommend ,
	CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END  

UNION ALL -- AllBet

SELECT b.recommend,
	CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
	SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
	SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,
	SUM(scomm) commission,  
	SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total, 
	SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
	SUM(ABS(stake)*(1 - tpositiontaking)*b.virtualrate) TurnoverIBCVirtual,
	SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM	,
	SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*b.virtualrate) Virtual_Total
FROM bettransLC b WITH(ROWLOCK) 
	INNER JOIN #tmpBettype t ON t.bettype = b.gameID 
WHERE winlostdate BETWEEN @FromDate AND @ToDate   
    AND t.ProductID = 21	
    AND b.statusID NOT IN (0, 1, 101, 102, 103)   
    and b.currency <> 20
    and b.mrecommend = @mrecommend
GROUP BY b.recommend ,
	CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END  

SELECT b.recommend,
		ca.username, 
		SUM(Turnover) Turnover,
		SUM(Winloss) Winloss, 
		SUM(Commission) Commission, 
		SUM(total) total,
		SUM(TurnoverRM) TurnoverRM,
		SUM(TurnoverIBCVirtual) Virtual_Turnover,
		SUM (TotalRM) TotalRM,
		SUM(Virtual_Total) Virtual_Total,
		SUM(CASE WHEN virtualratetype=1 THEN totalrm-virtual_total ELSE 0 END) [WLVariance+],
		SUM(CASE WHEN virtualratetype=-1 THEN totalrm-virtual_total ELSE 0 END) [WLVariance-],
		SUM(CASE WHEN virtualratetype=1 THEN TurnoverRM-TurnoverIBCVirtual ELSE 0 END) [TOVariance+],
		SUM(CASE WHEN virtualratetype=-1 THEN TurnoverRM-TurnoverIBCVirtual ELSE 0 END) [TOVariance-],
		ISNULL(ca.virtualmultiplier,1) EnableVirtualrate
	FROM #TmpResultAll b
	INNER JOIN custinfo ca WITH(NOLOCK) ON b.recommend = ca.custid
	GROUP BY b.recommend,ca.username,ISNULL(ca.virtualmultiplier,1)
ORDER BY username	

SELECT	ci.username,
		cvs.custid,
		pvs.sporttype,
		pvs.bettype,
		pvs.islive,
		dbo.f_GetVirtualSetting(cvs.bitmapVirtual, pvs.profileID) AS virtualMultiplier
FROM		custinfo				AS ci  WITH(NOLOCK) 
INNER JOIN	CustVirtualSetting		AS cvs WITH(NOLOCK) 
		ON	ci.custid = cvs.custid
INNER JOIN	ProfileVirtualSetting	AS pvs WITH(NOLOCK)
		ON	cvs.seqNo = pvs.seqNo
WHERE	ci.custid IN (SELECT DISTINCT recommend FROM #TmpResultAll)
	AND ci.virtualMultiplier = 1
	AND pvs.isActive = 1
ORDER BY username, sporttype, islive DESC, bettype
	
DROP TABLE #TmpResult
DROP TABLE #TmpResultAll

/*

[Acc_Rpt_TreeWinlostBySAg_xtest]
	@FromDate   = '20130618',
	@ToDate   = '20160630',  
	@srecommend =394310,	
	
	@showSB =1,  
	@showNG =1,  
	@ShowRB =1,  
	@showLiveCasino = 1,  
	@showCasino =1,  
	@showP2P =1,  
	@showBI =1,  
	@showVS = 1,
	@showKeno=1

[Acc_Rpt_TreeWinlostByMAg_xtest]
	@FromDate   = '20130618',
	@ToDate   = '20160630',  
	@mrecommend =395840,	
	
	@showSB =1,  
	@showNG =1,  
	@ShowRB =1,  
	@showLiveCasino = 1,  
	@showCasino =1,  
	@showP2P =1,  
	@showBI =1,  
	@showVS = 1
*/
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TreeWinlostByMAg] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_TreeWinlostByMAg] TO [bodbAdminNet]
GO
USE [bodb02]
GO 

ALTER PROCEDURE [dbo].[Acc_Rpt_TreeWinlostByProduct]  
	@FromDate   DATETIME,
	@ToDate		DATETIME,	
	@Products	VARCHAR(4000),
	-- 8RM account
	@TurnOver_8RM		MONEY = 0 OUTPUT,    
	@Total_8RM			MONEY = 0 OUTPUT,    
	@VirtualTotal_8RM	MONEY = 0 OUTPUT,    	
	-- BARM account
	@TurnOver_BARM		MONEY = 0 OUTPUT, 
	@Total_BARM			MONEY = 0 OUTPUT,    
	@VirtualTotal_BARM  MONEY = 0 OUTPUT    
AS  
  
/*    
Created by: Scott    
Date: 2012-12-14   
Task : Report Tree Win Lost    
DB: DBACC.bodb02    
Original SP:     
Revisions:    
	- 20130115@Scott : fix bug sum total of poker sporttype
	- 20130122@Scott : Does not use #bettrans14,query data direct bettrans14
	- 20130418@Scott : Update formula turnover of Racing
	- 20130702@Dom.Cao: Add Vanriance (+\-)
	- 20140304@TomVo: 
		Change Name Server (DB06) to Alias Server (DBACC)
		Add Keno Sport (202) -Bettype : 1501 - 1599
	- 20150529@Jim: add more parameter @ShowGD,@ShowMGSL and apply sport-bettype matrix 	
	- 20150710@Jim: Super Balance fix and Microgaming integration (Feature #38168)
	- 20150723@Jim: Apply Bettrade [#38815]
	- 20150828@Jim: support Colossus Bet (#42608)
	- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	- 20151214@Percy: 1. Add new product: Cockfighting [Redmine: #49027]
					  2. Change input parameters
	- 20160118@Percy: Calculate turnover for RNG Casino [Redmine: #49134]
	- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
	- 20160615@Sophia: Change READPAST to ROWLOCK because of the Deadlock [Redmind: #59254]
	- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	- 20160916@Robert: Integrate new product NG2 [RedmindID: #63460]
	- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
*/    
  
  
SET NOCOUNT ON

DECLARE @FDate DATETIME, @TDate DATETIME
SELECT  @FDate = @FromDate, @TDate = @ToDate
  
DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)  
DECLARE @CommSetting TABLE (MatchID int, IBCFee bit, ToteCommWin smallmoney, ToteCommPlace smallmoney, ToteCommWP smallmoney, ToteFee smallmoney )

CREATE TABLE #TmpResult (Currency TINYINT,
						actualrate FLOAT,
						Turnover MONEY, 
						Winloss MONEY,
						Commission MONEY)
						
CREATE TABLE #TmpResultAll (Currency TINYINT,
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

---get result for Horse Racing
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
			WHERE o.eventdate BETWEEN @FDate AND @TDate	
		
		INSERT INTO #TmpResult
			SELECT b.currency,
					b.actualrate,
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
				LEFT JOIN ( select refno,
								sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,  
								-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,  
								sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore<>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum  
							from bettransm with (nolock)  
							group by refno  
						)bm on b.transid = bm.refno   
			WHERE b.ruben =1   
				and b.bettype IN (SELECT bettype FROM @SportBettype WHERE ProductID = 2)  
				and b.matchid >0  
				and b.winlostdate BETWEEN @FDate AND @TDate
				and b.statusID not in (101,102,103,121)  
				and b.currency <> 20
			GROUP BY b.currency,
					b.actualrate


		INSERT INTO #TmpResultAll
		SELECT Currency, 
			0 virtualratetype,
			SUM(Turnover), 
			SUM(Winloss),
			SUM(Commission),
			SUM(Winloss+Commission) Total,
			SUM(Turnover*actualrate) TurnoverRM,
			SUM(Turnover*actualrate) TurnoverIBCVirtual,
			SUM((Winloss+Commission)*actualrate) TotalRM,
			SUM((Winloss+Commission)*actualrate ) Virtual_Total
		FROM #TmpResult
		GROUP BY Currency
	
	END --------END Racing-----------
		
---get result for PORKER
	IF EXISTS (SELECT TOP 1 1 FROM #tmpBettype WHERE ProductID = 9)	
	--IF @showP2P = 1  
	BEGIN
		TRUNCATE TABLE #TmpResult
	
		INSERT INTO	#TmpResult
			SELECT b.currency,
				b.actualrate,
				0 Turnover,
				isnull(sum(-1*(odds)),0)  Winlost,   
				SUM(scomm) commission
			from bettrans b with (NOLOCK)  
			where b.bettype IN( SELECT bettype FROM @SportBettype WHERE ProductID = 9)
				and b.matchid = 1000   
				and b.ruben=1    
				and b.winlostdate BETWEEN @FDate AND @TDate
				and statusID NOT in (101,102,103,121)  
				and b.currency <> 20
			group by  b.currency,b.actualrate
		
		
		INSERT INTO #TmpResultAll
		SELECT Currency, 
			0 virtualratetype,
			0  Turnover, 
			SUM(Winloss),
			SUM(Commission),
			SUM(Winloss+Commission) Total,
			0 TurnoverRM,
			0 TurnoverIBCVirtual,
			SUM( (Winloss+Commission)*actualrate ) TotalRM,
			SUM( (Winloss+Commission)*actualrate ) Virtual_Total
		FROM #TmpResult
		GROUP BY Currency	
	END

	---get data from bettransRNG
	INSERT INTO #TmpResultAll  
	   SELECT b.currency,
		  CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
		  SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
		  SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,  
		  SUM(scomm) commission,    
		  SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total,   
		  SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
		  SUM(ABS(stake)*(1 - tpositiontaking)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) TurnoverIBCVirtual,  
		  SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM ,  
		  SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) Virtual_Total
	   FROM bettransRNG b WITH(ROWLOCK)   
		  INNER JOIN #tmpBettype t on t.bettype = b.gameID 
	   WHERE winlostdate BETWEEN @FDate AND @TDate  
		  AND t.ProductID in (6, 17, 22, 24)
		  AND b.statusID NOT IN (0, 1, 101, 102, 103,121)     
		  and b.currency <> 20
	   GROUP BY b.currency,
		  CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END
	
	---get data from bettransLC
	INSERT INTO #TmpResultAll 
	
	SELECT b.currency,
		CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
		SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
		SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,  
		SUM(scomm) commission,    
		SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total,   
		SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
		SUM(ABS(stake)*(1 - tpositiontaking)*b.virtualrate) TurnoverIBCVirtual,  
		SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM ,  
		SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*b.virtualrate) Virtual_Total
	FROM bettransLC b WITH(ROWLOCK)   
		INNER JOIN #tmpBettype t on t.bettype = b.gameID 
	WHERE winlostdate BETWEEN @FDate AND @TDate	
	     AND t.ProductID = 21	
		AND b.statusID NOT IN (0, 1, 101, 102, 103,121)     
		and b.currency <> 20
	GROUP BY b.currency,
		CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END	
	
	---get data from bettrans
	INSERT INTO #TmpResultAll  
	SELECT b.currency,
		CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END VirtualRateType,  
		SUM(ABS(stake)*(1 - tpositiontaking)) Turnover,
		SUM(swinlost + mwinlost + awinlost + winlost-actual_stake) Winloss,  
		SUM(scomm) commission,    
		SUM(swinlost + mwinlost + awinlost + winlost-actual_stake+scomm) total,   
		SUM(ABS(stake)*(1 - tpositiontaking)*actualrate) TurnoverRM,
		SUM(ABS(stake)*(1 - tpositiontaking)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) TurnoverIBCVirtual,  
		SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate)  TotalRM ,  
		SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END)) Virtual_Total
	FROM bettrans b WITH(ROWLOCK)   
		INNER JOIN #tmpBettype t on t.bettype = b.bettype
	WHERE winlostdate BETWEEN @FDate AND @TDate
	     AND t.ProductID NOT IN (2, 6, 9, 17, 21, 22, 24)
		AND b.ruben = 1    
		AND b.statusID NOT IN (101, 102, 103,121)     
		and b.currency <> 20
	GROUP BY b.currency,
		CASE WHEN t.IsNoVirtual = 1 THEN 0 ELSE CASE WHEN b.virtualrate-b.actualrate < 0 THEN -1 WHEN b.virtualrate-b.actualrate > 0 THEN 1 ELSE 0 END END

SELECT	@TurnOver_8RM     = -SUM(ABS(stake)*(1 - tpositiontaking)*actualrate),
		@Total_8RM        = -SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate),    
		@VirtualTotal_8RM = -SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END))  		
FROM bettrans b WITH(NOLOCK)    
	INNER JOIN #tmpBettype t on t.bettype = b.bettype
WHERE recommend = 52466 AND    
	ruben=1 AND    
	winlostdate  between @FDate and @TDate   AND   
	b.statusID NOT IN (101, 102, 103,121)

SELECT	@TurnOver_BARM = -SUM(ABS(stake)*(1 - tpositiontaking)*actualrate),
		@Total_BARM = -SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*actualrate),    
		@VirtualTotal_BARM = -SUM((swinlost + mwinlost + awinlost + winlost-actual_stake+scomm)*(CASE WHEN t.IsNoVirtual = 0 THEN b.virtualrate ELSE actualrate END))		
FROM bettrans b WITH(NOLOCK)   
	INNER JOIN #tmpBettype t on t.bettype = b.bettype   
WHERE recommend = 5707545 AND    
	ruben=1 AND    
	winlostdate  between @FDate and @TDate  AND  
	b.statusID NOT IN (101, 102, 103,121)
		
---record set main data
	SELECT currency, 
		SUM(Turnover) Turnover,
		SUM(Winloss) Winloss, 
		SUM(Commission) Commission, 
		SUM(total) total,
		SUM(TurnoverRM) TurnoverRM,
		SUM(turnoveribcvirtual) Virtual_Turnover,
		SUM (TotalRM) TotalRM,
		SUM(Virtual_Total) Virtual_Total,
		SUM(CASE WHEN virtualratetype=1 THEN totalrm-virtual_total ELSE 0 END) [WLVariance+],
		SUM(CASE WHEN virtualratetype=-1 THEN totalrm-virtual_total ELSE 0 END) [WLVariance-],
		SUM(CASE WHEN virtualratetype=1 THEN TurnoverRM-TurnoverIBCVirtual ELSE 0 END) [TOVariance+],
		SUM(CASE WHEN virtualratetype=-1 THEN TurnoverRM-TurnoverIBCVirtual ELSE 0 END) [TOVariance-]
	FROM #TmpResultAll
	GROUP BY currency

DROP TABLE #TmpResult
DROP TABLE #TmpResultAll

GO 
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TreeWinlostByProduct] TO [vnteam]
GO 
GRANT EXECUTE ON [dbo].[Acc_Rpt_TreeWinlostByProduct] TO [bodbAdminNet]
GO
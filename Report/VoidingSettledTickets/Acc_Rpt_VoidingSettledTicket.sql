/*<info serverAlias="DBBAH-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_VoidingSettledTicket
	@WinlostDate DATE
   , @VoidTime   DATETIME = ''
   , @MatchId    INT = -1
AS
/*  
Created by: Cherry  
Date: 2020-10-10 
Task : Voiding Settled Tickets
DB: DBBAH.bodb02  
Original SP:   
Revisions:  
	20201010@Cherry : Voiding Settled Tickets (#142454)		

*/

BEGIN
    SET NOCOUNT ON
    CREATE TABLE #Bettype (Bettype INT, SubProduct VARCHAR(50))
    CREATE TABLE #Recommend (Recommend INT)
    CREATE TABLE #VoidTrans 
		(TransID BIGINT, 
		CustID INT, 
		VoidDate DATETIME, 
		Bettype INT, 
		Matchid INT, 
		Recommend INT,
		liveindicator BIT,
		ActualRate FLOAT, 
		tpositiontaking SMALLMONEY, 
		epositiontaking SMALLMONEY)
	CREATE TABLE #BalanceRecord 
		(TransID BIGINT, 
		CustID INT, 
		ActionDate DATETIME)
	CREATE TABLE #BalanceRecordBK 
		(TransID BIGINT, 
		CustID INT, 
		ActionDate DATETIME)
	CREATE TABLE #VoidRecord 
		(TransID BIGINT, 
		CustID INT, 
		ActionDate DATETIME)
	CREATE TABLE #tmpSettle
		(TransID BIGINT, 
		CustID INT, 
		ActionDate DATETIME)
	CREATE TABLE #tmpSettleBK
		(TransID BIGINT, 
		CustID INT, 
		ActionDate DATETIME)
	CREATE TABLE #SettledBalance
		(TransID BIGINT, 
		CustID INT, 
		winlost MONEY, 
		actual_stake MONEY, 
		awinlost MONEY, 
		mwinlost MONEY, 
		swinlost MONEY, 
		scomm MONEY,
		ActionDate DATETIME)
	CREATE TABLE #SettledBalanceBK
		(TransID BIGINT, 
		CustID INT, 
		winlost MONEY, 
		actual_stake MONEY, 
		awinlost MONEY, 
		mwinlost MONEY, 
		swinlost MONEY, 
		scomm MONEY,
		ActionDate DATETIME)
	CREATE TABLE #SettledRecord 
		(TransID BIGINT, 
		CustID INT, 
		winlost MONEY, 
		actual_stake MONEY, 
		awinlost MONEY, 
		mwinlost MONEY, 
		swinlost MONEY, 
		scomm MONEY)
	CREATE TABLE #Result 
		(ProductGroupId INT,
		ProductGroup VARCHAR(50),	
		HouseIncomeBeforeExtraPT MONEY,	
		HouseIncomeAfterExtraPT MONEY)

	INSERT INTO #Bettype (Bettype, SubProduct)
	SELECT DISTINCT Bettype, SubProduct
	FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
	WHERE IsTest = 0
		AND ProductID IN (1, 25)
		AND BetType NOT IN (901,902,903,904,911,912)
		
	INSERT INTO #Recommend (Recommend)
	SELECT c.recommend
	FROM bodb02.dbo.Customer c WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Site ss WITH (NOLOCK) ON ss.Site = c.site
	WHERE c.roleid = 2 AND ss.Site = 'CN88'
	
	INSERT INTO #VoidTrans (TransID, CustID, VoidDate, Bettype, Matchid, Recommend, liveindicator, ActualRate, tpositiontaking, epositiontaking)
	SELECT z.transid, z.custid, z.transdate, b.Bettype, b.Matchid, b.Recommend, b.liveindicator, b.ActualRate, b.tpositiontaking, b.epositiontaking
	FROM bodb02.dbo.zzzbettrans z (NOLOCK)
		INNER JOIN bodb02.dbo.bettrans b (NOLOCK) ON z.custid = b.custid AND z.transid = b.transid 
	WHERE b.Bettype in (SELECT Bettype FROM #Bettype)
		  AND z.status in ('WON','LOSE','DRAW')
		  AND b.winlostdate = @WinlostDate
		  AND (@VoidTime = '' OR z.transdate >= @VoidTime)
		  AND b.currency <> 20
		  AND (@MatchId = -1 OR b.matchid = @MatchId)
  
	INSERT INTO #BalanceRecord (TransID, CustID, ActionDate)
	SELECT b.TransID, b.CustID, MAX(b.ActionDate)
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #VoidTrans v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
		AND ActionID = 50 --latest void ticket in BalanceRecord
	GROUP BY b.TransID, b.CustID
	
	INSERT INTO #BalanceRecordBK (TransID, CustID, ActionDate)
	SELECT b.TransID, b.CustID, MAX(b.ActionDate)
	FROM BalanceRecord.dbo.BalanceRecord_bk b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #VoidTrans v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
		AND ActionID = 50 --latest void ticket in BalanceRecord_bk
	GROUP BY b.TransID, b.CustID
	
	INSERT INTO #VoidRecord (TransID, CustID, ActionDate)
	SELECT a.TransID, a.CustID, 
		CASE WHEN a.ActionDate > b.ActionDate THEN a.ActionDate ELSE b.ActionDate END
	FROM #BalanceRecord a INNER JOIN #BalanceRecordBK b ON a.TransID = b.TransID
	
	INSERT INTO #VoidRecord (TransID, CustID, ActionDate)
	SELECT a.TransID, a.CustID, a.ActionDate
	FROM #BalanceRecord a LEFT JOIN #BalanceRecordBK b ON a.TransID = b.TransID
	WHERE b.TransID IS NULL
	
	INSERT INTO #VoidRecord (TransID, CustID, ActionDate)
	SELECT a.TransID, a.CustID, a.ActionDate
	FROM #BalanceRecordBK a LEFT JOIN #BalanceRecord b ON a.TransID = b.TransID
	WHERE b.TransID IS NULL
	
	INSERT INTO #tmpSettle (TransID, CustID, ActionDate)
	SELECT b.transid, b.custid, MAX(b.ActionDate)
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE b.ActionID = 30 -- latest settled ticket in BalanceRecord
		AND b.CustID IN (SELECT CustID FROM #VoidRecord)
		AND EXISTS(SELECT TOP 1 1 FROM #VoidRecord v WHERE b.TransID = v.TransID AND b.CustID = v.CustID AND b.ActionDate < v.ActionDate)
	GROUP BY b.transid, b.custid

	INSERT INTO #SettledBalance (TransID, CustID, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, ActionDate)
	SELECT b.transid, b.custid, b.winlost, b.actual_stake, b.awinlost, b.mwinlost, b.swinlost, b.scomm, b.ActionDate
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #tmpSettle v WHERE b.TransID = v.TransID AND b.CustID = v.CustID AND b.ActionDate = v.ActionDate)
	
	INSERT INTO #tmpSettleBK (TransID, CustID, ActionDate)
	SELECT b.transid, b.custid, MAX(b.ActionDate)
	FROM BalanceRecord.dbo.BalanceRecord_bk b (NOLOCK)
	WHERE b.ActionID = 30 -- latest settled ticket in BalanceRecord_bk
		AND b.CustID IN (SELECT CustID FROM #VoidRecord)
		AND EXISTS(SELECT TOP 1 1 FROM #VoidRecord v WHERE b.TransID = v.TransID AND b.CustID = v.CustID AND b.ActionDate < v.ActionDate)
	GROUP BY b.transid, b.custid
		
	INSERT INTO #SettledBalanceBK (TransID, CustID, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm, ActionDate)
	SELECT b.transid, b.custid, b.winlost, b.actual_stake, b.awinlost, b.mwinlost, b.swinlost, b.scomm, b.ActionDate
	FROM BalanceRecord.dbo.BalanceRecord_bk b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #tmpSettleBK v WHERE b.TransID = v.TransID AND b.CustID = v.CustID AND b.ActionDate = v.ActionDate)
		
	INSERT INTO #SettledRecord (TransID, CustID, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm)
	SELECT a.TransID, a.CustID,
		CASE WHEN a.ActionDate > b.ActionDate THEN a.winlost ELSE b.winlost END,
		CASE WHEN a.ActionDate > b.ActionDate THEN a.actual_stake ELSE b.actual_stake END,
		CASE WHEN a.ActionDate > b.ActionDate THEN a.awinlost ELSE b.awinlost END,		
		CASE WHEN a.ActionDate > b.ActionDate THEN a.mwinlost ELSE b.mwinlost END,
		CASE WHEN a.ActionDate > b.ActionDate THEN a.swinlost ELSE b.swinlost END,
		CASE WHEN a.ActionDate > b.ActionDate THEN a.scomm ELSE b.scomm END
	FROM #SettledBalance a INNER JOIN #SettledBalanceBK b ON a.TransID = b.TransID
	
	INSERT INTO #SettledRecord (TransID, CustID, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm)
	SELECT a.TransID, a.CustID, a.winlost, a.actual_stake, a.awinlost, a.mwinlost, a.swinlost, a.scomm
	FROM #SettledBalance a LEFT JOIN #SettledBalanceBK b ON a.TransID = b.TransID
	WHERE b.TransID IS NULL
	
	INSERT INTO #SettledRecord (TransID, CustID, winlost, actual_stake, awinlost, mwinlost, swinlost, scomm)
	SELECT a.TransID, a.CustID, a.winlost, a.actual_stake, a.awinlost, a.mwinlost, a.swinlost, a.scomm
	FROM #SettledBalanceBK a LEFT JOIN #SettledBalance b ON a.TransID = b.TransID
	WHERE b.TransID IS NULL
	
	INSERT INTO #Result 
		(ProductGroupId,
		ProductGroup,	
		HouseIncomeBeforeExtraPT,	
		HouseIncomeAfterExtraPT)
	SELECT
		CASE WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 1 AND c.Recommend IS NULL THEN 1
			WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 0 AND c.Recommend IS NULL THEN 2
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NULL THEN 3
			WHEN t.Bettype = 10 AND c.Recommend IS NULL THEN 4
			WHEN b.SubProduct = 'Bet Builder' AND c.Recommend IS NULL THEN 5
			WHEN b.SubProduct = 'MG-SuperLive' AND c.Recommend IS NULL THEN 6
			WHEN m.sporttype IS NOT NULL AND c.Recommend IS NULL THEN 7
			WHEN t.Bettype IN (913, 914) AND c.Recommend IS NULL THEN 8
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 1 AND c.Recommend IS NOT NULL THEN 9
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 0 AND c.Recommend IS NOT NULL THEN 10
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NOT NULL THEN 11
			WHEN t.Bettype = 10 AND c.Recommend IS NOT NULL THEN 12
		END ProductGroupId,
		CASE WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 1 AND c.Recommend IS NULL THEN 'SPL'
			WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 0 AND c.Recommend IS NULL THEN 'SPNL'
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NULL THEN 'Parlay'
			WHEN t.Bettype = 10 AND c.Recommend IS NULL THEN 'Outright'
			WHEN b.SubProduct = 'Bet Builder' AND c.Recommend IS NULL THEN 'Bet Builder'
			WHEN b.SubProduct = 'MG-SuperLive' AND c.Recommend IS NULL THEN 'Metric Gaming - Super Live'
			WHEN m.sporttype IS NOT NULL AND c.Recommend IS NULL THEN 'Muay Thai'
			WHEN t.Bettype IN (913, 914) AND c.Recommend IS NULL THEN 'Cash Out'
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 1 AND c.Recommend IS NOT NULL THEN 'CN88 SPL'
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 0 AND c.Recommend IS NOT NULL THEN 'CN88 SPNL'
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NOT NULL THEN 'CN88 Parlay'
			WHEN t.Bettype = 10 AND c.Recommend IS NOT NULL THEN 'CN88 Outright'
		END ProductGroup,
		SUM((s.winlost - s.actual_stake + s.swinlost + s.mwinlost + s.awinlost + s.scomm) * t.ActualRate) HouseIncomeBeforeExtraPT,
		SUM((s.winlost - s.actual_stake + s.swinlost + s.mwinlost + s.awinlost + s.scomm 
				- (CASE WHEN t.tpositiontaking = 1 THEN 0
					ELSE s.winlost - s.actual_stake + s.scomm / (1 - t.tpositiontaking) END)* t.epositiontaking) * t.ActualRate) HouseIncomeAfterExtraPT
	FROM #VoidTrans t 
		INNER JOIN #SettledRecord s ON t.TransID = s.TransID
		INNER JOIN #Bettype b ON t.Bettype = b.Bettype
		LEFT JOIN bodb02.dbo.match m (NOLOCK) ON t.Matchid = m.matchid AND m.sporttype = 44
		LEFT JOIN #Recommend c ON t.Recommend = c.Recommend
	GROUP BY 
		CASE WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 1 AND c.Recommend IS NULL THEN 1
			WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 0 AND c.Recommend IS NULL THEN 2
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NULL THEN 3
			WHEN t.Bettype = 10 AND c.Recommend IS NULL THEN 4
			WHEN b.SubProduct = 'Bet Builder' AND c.Recommend IS NULL THEN 5
			WHEN b.SubProduct = 'MG-SuperLive' AND c.Recommend IS NULL THEN 6
			WHEN m.sporttype IS NOT NULL AND c.Recommend IS NULL THEN 7
			WHEN t.Bettype IN (913, 914) AND c.Recommend IS NULL THEN 8
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 1 AND c.Recommend IS NOT NULL THEN 9
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 0 AND c.Recommend IS NOT NULL THEN 10
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NOT NULL THEN 11
			WHEN t.Bettype = 10 AND c.Recommend IS NOT NULL THEN 12
		END,
		CASE WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 1 AND c.Recommend IS NULL THEN 'SPL'
			WHEN t.Bettype NOT IN (9,29,10) AND b.SubProduct NOT IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder') 
				AND m.sporttype IS NULL AND t.liveindicator = 0 AND c.Recommend IS NULL THEN 'SPNL'
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NULL THEN 'Parlay'
			WHEN t.Bettype = 10 AND c.Recommend IS NULL THEN 'Outright'
			WHEN b.SubProduct = 'Bet Builder' AND c.Recommend IS NULL THEN 'Bet Builder'
			WHEN b.SubProduct = 'MG-SuperLive' AND c.Recommend IS NULL THEN 'Metric Gaming - Super Live'
			WHEN m.sporttype IS NOT NULL AND c.Recommend IS NULL THEN 'Muay Thai'
			WHEN t.Bettype IN (913, 914) AND c.Recommend IS NULL THEN 'Cash Out'
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 1 AND c.Recommend IS NOT NULL THEN 'CN88 SPL'
			WHEN t.Bettype NOT IN (9,29,10) AND t.liveindicator = 0 AND c.Recommend IS NOT NULL THEN 'CN88 SPNL'
			WHEN t.Bettype IN (9,29) AND c.Recommend IS NOT NULL THEN 'CN88 Parlay'
			WHEN t.Bettype = 10 AND c.Recommend IS NOT NULL THEN 'CN88 Outright'
		END     
	
	SELECT ProductGroupId,
		ProductGroup,	
		HouseIncomeBeforeExtraPT,	
		HouseIncomeAfterExtraPT
	FROM #Result
	
	DROP TABLE #VoidTrans
	DROP TABLE #BalanceRecord
	DROP TABLE #BalanceRecordBK
	DROP TABLE #VoidRecord
	DROP TABLE #tmpSettle
	DROP TABLE #tmpSettleBK
	DROP TABLE #SettledBalance
	DROP TABLE #SettledBalanceBK
	DROP TABLE #SettledRecord
	DROP TABLE #Result
	DROP TABLE #Bettype
	DROP TABLE #Recommend
	
END

GO

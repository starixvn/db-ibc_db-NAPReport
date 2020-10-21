/*<info serverAlias="DBBAH-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_VoidingSettledTicket_Product
	@WinlostDate DATE,
    @VoidTime   DATETIME = '',
    @MatchId    INT = -1,
    @ProductGroupID INT,
    @PageSize INT,
	@PageIndex INT
   
AS
/*  
Created by: Cherry  
Date: 2020-10-10 
Task : Voiding Settled Tickets
DB: DBBAH.bodb02  
Original SP:   
Revisions:  
	20201010@Cherry : Voiding Settled Tickets (#142454)	
	
Param's Explanation:
	@ProductGroupID: 
		1 : SPL
		2 : SPNL
		3 : Parlay
		4 : Outright
		5 : Bet Builder
		6 : Metric Gaming
		7 : Muay Thai
		8 : Cash Out
		9 : CN88 SPL
		10: CN88 SPNL
		11: CN88 Parlay
		12: CN88 Outright

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
		(TransID BIGINT,
		Username VARCHAR(50),	
		MatchID INT,
		VoidedTime DATETIME,
		HouseIncomeBeforeExtraPT MONEY,	
		HouseIncomeAfterExtraPT MONEY)
	CREATE TABLE #tmpTrans (
		RN INT IDENTITY(1, 1)
		,TransID BIGINT
		)

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
		
	IF @ProductGroupID = 1 -- SPL
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE liveindicator = 0 
			OR Bettype IN (9,29,10)
			OR Matchid IN (SELECT matchid FROM bodb02.dbo.match (NOLOCK) WHERE sporttype = 44)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
			OR Bettype IN (SELECT Bettype FROM #Bettype WHERE SubProduct IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder'))
	END
	
	IF @ProductGroupID = 2 -- SPNL
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE liveindicator = 1 
			OR Bettype IN (9,29,10)
			OR Matchid IN (SELECT matchid FROM bodb02.dbo.match (NOLOCK) WHERE sporttype = 44)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
			OR Bettype IN (SELECT Bettype FROM #Bettype WHERE SubProduct IN ('MG-SuperLive','CO-Comm','CO-Winloss','Bet Builder'))
	END
	
	IF @ProductGroupID = 3 -- Parlay
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (9,29)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 4 -- Outright
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (10)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 5 -- Bet Builder
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (SELECT Bettype FROM #Bettype WHERE SubProduct = 'Bet Builder')
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 6 -- Metric Gaming - Super Live
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (SELECT Bettype FROM #Bettype WHERE SubProduct = 'MG-SuperLive')
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 7 -- Muay Thai
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Matchid NOT IN (SELECT matchid FROM bodb02.dbo.match (NOLOCK) WHERE sporttype = 44)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 8 -- Cash Out
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (913, 914)
			OR Recommend IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 9 -- CN88 SPL
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype IN (9,29,10)
			OR liveindicator = 0
			OR Recommend NOT IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 10 -- CN88 SPNL
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype IN (9,29,10)
			OR liveindicator = 1
			OR Recommend NOT IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 11 -- CN88 Parlay
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (9,29)
			OR Recommend NOT IN (SELECT Recommend FROM #Recommend)
	END
	
	IF @ProductGroupID = 12 -- CN88 Outright
	BEGIN
		DELETE
		FROM #VoidTrans 
		WHERE Bettype NOT IN (10)
			OR Recommend NOT IN (SELECT Recommend FROM #Recommend)
	END
  
	INSERT INTO #BalanceRecord (TransID, CustID, ActionDate)
	SELECT b.TransID, b.CustID, MAX(b.ActionDate)
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #VoidTrans v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
		AND ActionID = 50  --latest void ticket in BalanceRecord
	GROUP BY b.TransID, b.CustID
	
	INSERT INTO #BalanceRecordBK (TransID, CustID, ActionDate)
	SELECT b.TransID, b.CustID, MAX(b.ActionDate)
	FROM BalanceRecord.dbo.BalanceRecord_bk b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #VoidTrans v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
		AND ActionID = 50  --latest void ticket in BalanceRecord_bk
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
	WHERE b.ActionID = 30  -- latest settled ticket in BalanceRecord
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
	WHERE b.ActionID = 30  -- latest settled ticket in BalanceRecord_bk
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
		(TransID,
		Username,	
		MatchID,
		VoidedTime,
		HouseIncomeBeforeExtraPT,	
		HouseIncomeAfterExtraPT)
	SELECT t.TransID,
		c.username,
		t.Matchid,
		t.VoidDate,
		(s.winlost - s.actual_stake + s.swinlost + s.mwinlost + s.awinlost + s.scomm) * t.ActualRate HouseIncomeBeforeExtraPT,
		(s.swinlost + s.mwinlost + s.awinlost + scomm 
				- CASE WHEN t.tpositiontaking = 1 THEN 0
					ELSE s.winlost - s.actual_stake + s.scomm / (1 - t.tpositiontaking) * t.epositiontaking END) * t.ActualRate HouseIncomeAfterExtraPT
	FROM #VoidTrans t
		INNER JOIN #SettledRecord s ON t.TransID = s.TransID
		INNER JOIN bodb02.dbo.Customer c ON t.CustID = c.custid
	
	CREATE CLUSTERED INDEX [CIX_TransID] ON #Result(TransID)
	
	INSERT INTO #tmpTrans (TransID)
	SELECT TransID
	FROM #Result
	GROUP BY TransID
	ORDER BY TransID
	
	CREATE CLUSTERED INDEX [CIX_RN] ON #tmpTrans( RN )
	
	DECLARE @FromTrans INT, @ToTrans INT
	
	IF ( @PageIndex = 0 AND @PageSize = 0 ) ---All data---
	BEGIN
		SET @FromTrans = 1
		SELECT @ToTrans = ISNULL(MAX(RN),0)
		FROM #tmpTrans
	END
	ELSE  ---Pagination---
	BEGIN
		SET @FromTrans = 1 + (@PageIndex - 1) * @PageSize
		SELECT @ToTrans = MIN(val)
		FROM (
			SELECT MAX(u.RN) AS val
			FROM #tmpTrans AS u			
			UNION			
			SELECT (@PageIndex * @PageSize) AS val
			) AS tmp
	END
	
	SELECT TransID,
		Username,	
		MatchID,
		VoidedTime,
		HouseIncomeBeforeExtraPT,	
		HouseIncomeAfterExtraPT
	FROM #Result
	WHERE TransID BETWEEN ( SELECT TransID FROM #tmpTrans WHERE RN = @FromTrans )
					AND ( SELECT TransID FROM #tmpTrans WHERE RN = @ToTrans )
	ORDER BY TransID
	
	SELECT ISNULL(MAX(RN),0) TotalItems
	FROM #tmpTrans
	
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
	DROP TABLE #tmpTrans
	
END

GO

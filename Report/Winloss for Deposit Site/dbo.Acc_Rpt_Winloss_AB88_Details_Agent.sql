ALTER PROCEDURE [dbo].[Acc_Rpt_Winloss_AB88_Details_Agent]
	@Custid INT = 0,
	@FromDate SMALLDATETIME,
	@ToDate SMALLDATETIME,
	@ShowSB Bit = 1,
	@ShowHR Bit = 0,
	@BalanceUpDay SMALLDATETIME
AS
/*
	Created: Johnson
	Date: 2010-10-13
	Task: Winloss Report for AB88 (Agent)
	DB : DB052.BODB02

	Revisions:
Param's Explanation:
	- @Custid : super ID
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #SAgWinLoss(
		winlostdate DATETIME,
		Custid		INT, -- recommend
		SRecommend	INT,
		TurnOver	MONEY,
		GrossComm	MONEY,
		Winlost		MONEY,
		Comm		MONEY,
		AWinlost	MONEY,
		AComm		MONEY,
		Company		MONEY)

	DECLARE @TmpCond		TABLE(sporttype INT, bettype INT)
	DECLARE @TmpCondSumWL	TABLE(sporttype INT, bettype INT)
	DECLARE @TmpAB88SAg		TABLE(custID INT PRIMARY KEY)

	IF @custid = 0
	BEGIN
		INSERT INTO @TmpAB88SAg(custid) SELECT custid FROM dbo.f_DepSuperByCurrency('asiabet88')
	END
	ELSE
	BEGIN
		INSERT INTO @TmpAB88SAg(custid) VALUES(@custid)
	END
	
	IF @showSB = 1
	BEGIN
		-- bettrans
		INSERT INTO @TmpCond(sporttype,bettype)
		SELECT 0 AS sporttype, typeid 
		FROM bettype (NOLOCK)
		WHERE typeid < 31
		-- sum_winloss
		INSERT INTO @TmpCondSumWL(sporttype,bettype)
		VALUES(0,0)
	END

	IF @showHR = 1
	BEGIN
		--bettrans
		INSERT INTO @TmpCond(sporttype,bettype)
		SELECT 151,31 UNION ALL SELECT 151,32 UNION ALL SELECT 151,33 UNION ALL
		SELECT 152,41 UNION ALL SELECT 152,42 UNION ALL SELECT 152,43
		
		--sum_winloss
		INSERT INTO @TmpCondSumWL(sporttype, bettype)
		VALUES(151,0)
	END

	IF @ToDate >= @BalanceUpDay
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT 
			b.winlostdate,
			b.recommend,
			b.srecommend,
			SUM(CASE WHEN b.liveawayscore = 0 and b.bettype in (33,43) THEN b.stake/2 ELSE b.stake END) AS turnover,
			SUM(acomm/(1-apositiontaking-mpositiontaking)) AS GrossComm,
			SUM(b.winlost - b.actual_stake) AS Winlost,
			SUM(b.playercomm) Comm,
			SUM(b.swinlost + b.mwinlost + b.awinlost) AWinlost,
			SUM(b.scomm - b.playercomm) AComm,
			-SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost - b.actual_stake + b.scomm) Company
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN @TmpCond t ON b.bettype = t.bettype
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate AND
			b.bettype < 99 AND
			b.ruben = 1 AND
			b.statusID NOT IN (101,102,103) AND
			SRecommend IN (SELECT custid FROM @TmpAB88SAg)
		GROUP BY b.winlostdate, b.recommend, b.srecommend	

		IF @BalanceUpDay < @FromDate
			SELECT @BalanceUpDay = @FromDate
		
		INSERT INTO #SAgWinloss
		SELECT b.winlostdate,
			b.recommend,
			b.srecommend,
			SUM(b.turnover),
			SUM(b.grosscomm) AS GrossComm,
			SUM(b.winlost),
			SUM(b.playercomm),
			SUM(b.swinlost + b.mwinlost + b.awinlost),
			SUM(b.scomm - b.playercomm),
			-SUM(b.winlost + b.mwinlost + b.awinlost + b.scomm)
		FROM dbo.sum_winloss b WITH(NOLOCK)
			INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0
		WHERE b.winlostdate BETWEEN @BalanceUpDay AND @ToDate	
			AND b.roleid = 2
			AND b.srecommend IN (SELECT custid FROM @TmpAB88SAg)
		GROUP BY b.winlostdate,b.recommend,b.srecommend
	END

	IF @FromDate < @BalanceUpDay
	BEGIN
		IF @ToDate >= DATEADD(dd,-1,@BalanceUpDay)
			SELECT @ToDate = DATEADD(dd,-1,@BalanceUpDay)
		
		INSERT INTO #SAgWinLoss		
		SELECT b.winlostdate,
			b.recommend,
			b.srecommend,
			SUM(b.turnover),
			SUM(b.grosscomm) AS GrossComm,
			SUM(b.winlost),
			SUM(b.playercomm),
			SUM(b.swinlost + b.mwinlost + b.awinlost),
			SUM(b.scomm - b.playercomm),
			- SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm)
		FROM bodb_Summary.dbo.Sum_Winloss_Old b WITH(NOLOCK)
			INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype and b.bettype = 0
		WHERE
			b.winlostdate BETWEEN @FromDate AND @ToDate
			AND b.roleid = 2
			AND b.srecommend in (SELECT custid FROM @TmpAB88SAg)
		GROUP BY b.winlostdate, b.recommend, b.srecommend
	END 

	SELECT 
		c.username,
		w.custid,
		SUM(TurnOver)			AS TurnOver,
		SUM(GrossComm)			AS GrossComm,
		SUM(Winlost)			AS Winlost,
		SUM(Comm)				AS Comm,
		SUM(AWinlost)			AS AWinlost,
		SUM(AComm)				AS AComm,
		SUM(Company)			AS Company,
		--BaseUSD
		SUM(TurnOver*h.USDRate)	AS TurnOverUSD,
		SUM(GrossComm*h.USDRate) AS GrossCommUSD,
		SUM(Winlost*h.USDRate)	AS WinlostUSD,
		SUM(Comm*h.USDRate)		AS CommUSD,
		SUM(AWinlost*h.USDRate)	AS AWinlostUSD,
		SUM(AComm*h.USDRate)	AS ACommUSD,
		SUM(Company*h.USDRate)	AS CompanyUSD,
		--BaseRM
		SUM(TurnOver*h.actualrate)	AS TurnOverRM,
		SUM(GrossComm*h.actualrate) AS GrossCommRM,
		SUM(Winlost*h.actualrate)	AS WinlostRM,
		SUM(Comm*h.actualrate)		AS CommRM,
		SUM(AWinlost*h.actualrate)	AS AWinlostRM,
		SUM(AComm*h.actualrate)	AS ACommRM,
		SUM(Company*h.actualrate)	AS CompanyRM
	FROM #SAgWinloss w
		INNER JOIN Exchange_History h WITH(NOLOCK) ON w.winlostdate = h.winlostdate AND w.srecommend = h.srecommendAB88
		INNER JOIN customer c WITH(NOLOCK) ON w.custid =c.custid
	GROUP BY w.custid, c.username

DROP TABLE #SAgWinloss
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_AB88_Details_Agent] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_AB88_Details_Agent] TO [vnteam]
GO


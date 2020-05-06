/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_ExtraSuperComm]
	@FromDate		DATETIME
	,@ToDate		DATETIME
AS

/*
	Created: 20200505@Percy
	DB: DBAGE-bodb02
	Task: NAP Report - Auto mail - Extra Super Commission

	Revisions:
		- 20200505@Percy: Initialize SP [RedmineID: #133413]
*/

BEGIN
	SET NOCOUNT ON

	-- winlostdate range
	BEGIN
		DECLARE @tmpMBBU TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
		INSERT INTO @tmpMBBU (BalanceUpDay, MoveBetsDay)
		EXEC dbo.Age_SelBalanceUpDay

		DECLARE @BalanceUpDay DATETIME, @MoveBetsDay DATETIME
		SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @tmpMBBU

		DECLARE @tmpWinlostDate TABLE (winlostdate DATETIME, daterange TINYINT) -- 0:bettrans, 1:sum_winloss, 2:sum_winloss_old
		;WITH CTE_WinlostDate AS
		(
			SELECT @FromDate AS winlostdate
			UNION ALL
			SELECT DATEADD(DAY, 1, winlostdate)
			FROM CTE_WinlostDate
			WHERE winlostdate < @ToDate
		)
		INSERT INTO @tmpWinlostDate (winlostdate)
		SELECT winlostdate
		FROM CTE_WinlostDate
		OPTION (MAXRECURSION 0)

		UPDATE @tmpWinlostDate
		SET daterange = CASE
						WHEN winlostdate > @MoveBetsDay THEN 0
						WHEN winlostdate >= @BalanceUpDay THEN 1
						ELSE 2 END
	END

	-- super list
	BEGIN
		CREATE TABLE #__tmpSuper
		(
			custid			INT
			,username		VARCHAR(30)
			,currency		INT
			,winlostdate	DATETIME
			,daterange		TINYINT -- 0:bettrans, 1:sum_winloss, 2:sum_winloss_old
			,roleid			INT
			,productid		SMALLINT
			,sporttype		SMALLINT
			,bettype		SMALLINT
			,discount		FLOAT
			,extradiscount	FLOAT
		)
		INSERT INTO #__tmpSuper (CustId, UserName, currency, winlostdate, daterange, roleid, productid, sporttype, bettype, discount, extradiscount)
		SELECT f.CustId, f.UserName, f.currency, w.winlostdate, w.daterange, 4, f.ProductId, f.SportType, f.BetType, f.Discount, f.ExtraDiscount
		FROM dbo.f_ExtraSuperDiscount() f
			CROSS APPLY @tmpWinlostDate w
		WHERE w.winlostdate BETWEEN f.FromDate AND f.ToDate
	END

	-- exchange rate
	BEGIN
		CREATE TABLE #__tmpExchange (ExchangeDate SMALLDATETIME, ExchangeId INT, Rate FLOAT)
		INSERT INTO #__tmpExchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'MYR')
		WHERE ExchangeId IN (SELECT currency FROM #__tmpSuper)
	END

	-- get data from bettrans, sum_winloss and sum_winloss_old
	BEGIN
		CREATE TABLE #__tmpData
		(
			CustId			INT
			,UserName		VARCHAR(30)
			,ProductId		SMALLINT
			,Turnover		MONEY
			,NetTurnover	MONEY
			,MemberWinloss	MONEY
			,SuperComm		MONEY
			,ExtraSuperComm	MONEY
		)

		-- bettrans
		IF EXISTS (SELECT 1 FROM @tmpWinlostDate WHERE daterange = 0)
		BEGIN
			CREATE TABLE #__btSuper (custid INT, username VARCHAR(30), winlostdate SMALLDATETIME, productid SMALLINT, discount FLOAT, extradiscount	FLOAT)
			INSERT INTO #__btSuper (custid, username, winlostdate, productid, discount, extradiscount)
			SELECT DISTINCT custid, username, winlostdate, productid, discount, extradiscount FROM #__tmpSuper WHERE daterange = 0

			CREATE TABLE #__btBettype (productid SMALLINT, bettype SMALLINT)
			INSERT INTO #__btBettype (productid, bettype)
			SELECT DISTINCT s.ProductId, s.BetType FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
			WHERE EXISTS (SELECT 1 FROM #__tmpSuper t WHERE s.ProductID = t.productid)

			INSERT INTO #__tmpData (CustId, UserName, ProductId, Turnover, NetTurnover, MemberWinloss, SuperComm, ExtraSuperComm)
			SELECT t.custid, t.username, t.productid, SUM(ABS(b.stake) * b.actualrate), SUM(ABS(stake * spositiontaking) * b.actualrate), SUM((b.winlost - b.actual_stake) * b.actualrate), SUM(b.scomm * b.actualrate), SUM(b.scomm * (t.extradiscount / t.discount) * b.actualrate)
			FROM dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #__btSuper t ON t.custid = b.srecommend AND t.winlostdate = b.winlostdate
				INNER JOIN #__btBettype bt ON b.bettype = bt.bettype AND t.productid = bt.productid
			GROUP BY t.custid, t.username, t.productid

			DROP TABLE #__btBettype
			DROP TABLE #__btSuper
		END

		-- sum_winloss
		IF EXISTS (SELECT 1 FROM @tmpWinlostDate WHERE daterange = 1)
		BEGIN
			INSERT INTO #__tmpData (CustId, UserName, ProductId, Turnover, NetTurnover, MemberWinloss, SuperComm, ExtraSuperComm)
			SELECT t.custid, t.username, t.productid, SUM(s.turnover * e.Rate), SUM(s.netTurnover * e.Rate), SUM(s.winlost * e.Rate), SUM(s.scomm * e.Rate), SUM(s.scomm * (t.extradiscount / t.discount) * e.Rate)
			FROM dbo.sum_winloss s WITH (NOLOCK)
				INNER JOIN #__tmpSuper t
					ON		t.custid		= s.srecommend
						AND t.winlostdate	= s.winlostdate
						AND t.roleid		= s.roleid
						AND t.sporttype		= s.sporttype
						AND t.bettype		= s.bettype
						AND t.daterange		= 1
				INNER JOIN #__tmpExchange e
					ON		t.winlostdate	= e.exchangedate
						AND t.currency		= e.exchangeid
			GROUP BY t.custid, t.username, t.productid
		END

		-- sum_winloss_old
		IF EXISTS (SELECT 1 FROM @tmpWinlostDate WHERE daterange = 2)
		BEGIN
			INSERT INTO #__tmpData (CustId, UserName, ProductId, Turnover, NetTurnover, MemberWinloss, SuperComm, ExtraSuperComm)
			SELECT t.custid, t.username, t.productid, SUM(s.turnover * e.Rate), SUM(s.netTurnover * e.Rate), SUM(s.winlost * e.Rate), SUM(s.scomm * e.Rate), SUM(s.scomm * (t.extradiscount / t.discount) * e.Rate)
			FROM bodb_Summary.dbo.sum_winloss_old s WITH (NOLOCK)
				INNER JOIN #__tmpSuper t
					ON		t.custid		= s.srecommend
						AND t.winlostdate	= s.winlostdate
						AND t.roleid		= s.roleid
						AND t.sporttype		= s.sporttype
						AND t.bettype		= s.bettype
						AND t.daterange		= 2
				INNER JOIN #__tmpExchange e
					ON		t.winlostdate	= e.exchangedate
						AND t.currency		= e.exchangeid
			GROUP BY t.custid, t.username, t.productid
		END
	END

	-- return data
	BEGIN
		SELECT
			t.UserName
			,p.ProductName
			,SUM(t.Turnover)		AS Turnover
			,SUM(t.NetTurnover)		AS NetTurnover
			,SUM(t.MemberWinloss)	AS NetTurnover
			,SUM(t.SuperComm)		AS SuperComm
			,SUM(t.ExtraSuperComm)	AS ExtraSuperComm
			,SUM(t.SuperComm + t.ExtraSuperComm)	AS TotalSuperComm
		FROM #__tmpData t
			INNER JOIN dbo.Products p WITH (NOLOCK) ON t.ProductId = p.ProductID
		GROUP BY
			t.UserName
			,p.ProductName
		ORDER BY
			t.UserName
			,p.ProductName
	END

	DROP TABLE #__tmpData
	DROP TABLE #__tmpSuper
END
GO